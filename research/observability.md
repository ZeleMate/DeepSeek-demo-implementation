# Observability: what dsh already records, and what we should add

Research for [#35](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/35). Builds on `research/deepseek-harness.md` (#2) and `research/redteam-setup.md` (#25), and on ADRs 0003, 0004 and 0006. Checked **2026-10-19**.

Markers: **[verified]** = read in a primary source (source code, official docs, registry) on the check date. **[inferred]** = follows from verified facts but not run. **[unverified]** = not confirmed; test before relying on it.

Versions read:

| Thing | Version / commit | How |
|---|---|---|
| dsh | tag `dsh-v0.2.1-rc.2`, commit `687f282` | git clone at tag |
| pi-ai (`@earendil-works/pi-ai`, used by `llm-pi-ai`) | 1.1.0 (dsh lockfile, patched), MIT | npm tarball |
| pi-telemetry (`@earendil-works/pi-telemetry`, a pi-ai dependency) | 1.1.0, MIT | npm tarball |
| OpenTelemetry GenAI semantic conventions | `open-telemetry/semantic-conventions-genai` `main` @ `547934a` (2026-10-18) | git clone |
| OpenTelemetry JS exporters | docs on opentelemetry.io | docs |
| LangSmith | docs on docs.langchain.com | docs |
| Promptfoo | docs on promptfoo.dev (tracing, assertions, custom provider) | docs |
| OpenRouter | docs on openrouter.ai (usage accounting, get-a-generation) | docs |

Nothing was installed or run. Paths below are relative to the dsh repo root unless they name another package. Every config and plugin sketch is a **plan**, not a tested recipe.

---

## TL;DR

1. **The session log already records almost everything an eval needs.** Every tool call and result, every approval ask and its outcome, per-step token usage, the requested model, and (for `llm-pi-ai` routes) the model the provider says actually answered plus the provider's response id. It is local JSONL under `$DSH_HOME/sessions`, **zstd-compressed by default**. Set `compression: none` if you want to grep it.
2. **dsh has no cost accounting at all.** `llm-pi-ai` zeroes pi-ai's cost fields, and the code says "no consumer reports spend". pi-ai also ignores OpenRouter's own `usage.cost`. Per-run cost has to come from OpenRouter: its `GET /api/v1/generation?id=gen-…` returns `total_cost`, `model` and `provider_name`, and the `gen-…` id is already in our session log as `responseId`.
3. **Our own defence decisions are not recorded by dsh.** Denials show up as error tool results and `ask` shows up as `approval/*` events. But an injection-filter score, a "wrap as untrusted" rewrite, the taint flag and a canary seen in the model stream leave no trace. A native plugin writes no `hook/*` records. ADR 0003's "audit = session log, nothing new built" is therefore **not quite enough**. The fix is small: dsh's `appendPluginRecord()` lets our plugins write `plugin:…` records into the same log.
4. **dsh's built-in telemetry is OpenTelemetry *logs*, gated by feedback, sent to DeepSeek.** The `session-telemetry-otel` row exports the whole session prefix to `dsh-otel-collector.deepseeksvc.com` only after you give explicit feedback. `FULL` mode does not exist, so it can't be pointed at a local collector for normal runs. Turn it off with `DSH_TELEMETRY_DISABLED=1`, which removes the row. A second, separate path, `session-log-deepseek`, uploads the log inside requests to the **official DeepSeek adapter only**. Our `llm-pi-ai` routes never send it, but disable it anyway.
5. **No OpenTelemetry traces and no LangSmith anywhere.** dsh ships only the OTel logs SDK. pi-ai 1.1.0 has a `telemetryContext` option typed by pi-telemetry, but no code in pi-ai creates a span, and `llm-pi-ai` doesn't pass one. LangSmith is cloud-only unless you buy Enterprise (self-hosting is an Enterprise add-on on Kubernetes), so it conflicts with ADR 0004's local-first rule.
6. **Recommendation: no tracing stack in v1.** Use the session log as the audit trail. Add one small plugin, `@zelemate/dsh-audit`, that (a) writes `plugin:zelemate-audit/*` records for every defence decision and canary hit and (b) writes a per-run JSON summary file for Promptfoo. Disable `session-telemetry-otel`, `session-log-deepseek` and the title LLM call in both profiles. Look up cost from OpenRouter after the run. An OTel trace exporter that sends spans to **Promptfoo's own local OTLP receiver** (127.0.0.1:4318) is a good stretch goal for learning. It is not needed for any v1 number.

---

## 1. What dsh already records

### 1a. The session log (the source of truth)

- The base bundle mounts `session-persistence-jsonl` with `root: dshHomePath('sessions')` (`packages/bundle/base/cordis.patch.yml:138-141`) [verified]. Each session gets its own directory, `<root>/--<normalized-cwd>--/<encoded-id>/session.vN.jsonl[.zstd]` (`packages/session/session-persistence-jsonl/README.md:55-70`) [verified].
- **Compression is `zstd` by default.** `compression: 'none'` gives plain newline-delimited UTF-8 (`packages/session/session-persistence-jsonl/README.md:44-48`) [verified]. A patch row replaces the whole `config`, so an override must repeat `root` (`apps/cli/reference/README.md`, as cited in `research/redteam-setup.md` §2) [verified there].
- Each append is `fsync`ed before it resolves (`session-persistence-jsonl/README.md`, "Durability and crash semantics") [verified]. So the log is complete when a headless run exits [inferred].
- The on-disk rows are a storage encoding with versioned formats and migrations (`README.md:57`, "lossless source-event representation") [verified]. **Parsing them from outside dsh ties us to the storage format** [inferred]. Read events in-process instead (section 4).

The event types that matter for us (`packages/core/session/src/types.ts`, `packages/core/session/src/known-event-types.ts:23-84`) [verified]:

| Event | What it carries | Source |
|---|---|---|
| `turn/start`, `turn/end` | Turn number; end reason `completed`, `aborted`, `blocked`, `error` (with `LlmFailure`), `max-tokens`, `interrupted`, `forked` | `types.ts:202-230`, `289-298` |
| `step/start`, `step/end` | One model call plus its tool calls | `types.ts:300-302` |
| `request/header` | The request config: `provider`, `model`, reasoning effort, sampling, tool schemas. No API keys | `types.ts:391-397`; `LlmCallConfig` in `packages/llm/llm/src/call-config.ts:31-34` |
| `request/context` | Route metadata (`provider`, `model`, `contextWindow`) when the route changes | `types.ts` (`RequestContext`) |
| `assistant/message` | The assembled message, the **exact timed stream**, and `usage?: TokenUsage` | `types.ts:342-350` |
| `assistant/attempt` | A failed or retried attempt's stream (its tokens were still billed) | `types.ts` (after 350) |
| `tool/call` | Tool name and the raw argument JSON, logged **before** execution | `types.ts:362` |
| `tool/result` | The model-facing result, `isError`, and optional `error: {name, code, reason}` | `types.ts:376-389` |
| `approval/asked`, `approval/decided` | Every approval question and its outcome, including the fail-closed `unavailable` | `packages/interaction/user-approval/src/types.ts:44-58` |
| `llm/retry`, `llm/retry-started` | Retries | `known-event-types.ts:47-48` |
| `hook/invoked`, `hook/result` | Only for Claude Code or Codex `hooks.json` bridges | `packages/experimental/hook-protocol/src/types.ts:19-41` |
| `session/title-llm-request` | The auxiliary title request (no usage) | `packages/session/session-title-llm/src/index.ts:267-275` |

**Which model answered (ADR 0006).** An `assistant/message` carries `message.source = { kind: 'model', provider, model, replayState }` (`packages/llm/llm/src/message.ts:10-26`) [verified]. For `llm-pi-ai` routes, `replayState.response` holds `api`, `provider`, the requested `model`, an optional **`responseModel`**, and an optional **`responseId`** (`packages/llm/llm-pi-ai/src/replay.ts:22-35`, `76-86`) [verified]. pi-ai sets `responseId` from the chunk `id`. It sets `responseModel` from the chunk `model` **only when it differs from the requested id** (`pi-ai dist/api/openai-completions.js:358-362`) [verified]. So:

- `responseModel` absent → the provider reported the requested model [verified].
- With an OpenRouter preset or Switchyard (ADR 0006), the served model id should appear as `responseModel` [inferred; depends on what OpenRouter puts in the chunk `model` field, not checked].
- `responseId` is OpenRouter's generation id, which is the key for the cost lookup in section 3 [inferred from the `gen-…` pattern in OpenRouter's docs].
- Replay state exists only for **successful** responses (`replay.ts:68-76`, "Project a successful pi-ai response") [verified]. Failed attempts don't record the served model.
- The upstream provider (for example which host served DeepSeek V4.1 Flash) is **not** captured. pi-ai doesn't read it from the stream [verified, no `chunk.provider` in `openai-completions.js`].

### 1b. Token usage, timing and cost

- `TokenUsage` has `inputTokens`, `outputTokens`, optional `totalTokens`, `cacheReadTokens`, `cacheWriteTokens` and `reasoningTokens` (`packages/llm/llm/src/types.ts:175-189`) [verified]. **There is no cost field.**
- `llm-pi-ai` maps pi-ai usage but **drops `reasoningTokens`** (pi-ai folds reasoning into output) (`packages/llm/llm-pi-ai/src/stream.ts:19-32`) [verified].
- **dsh never computes spend.** `catalog.ts` says "The harness never reads pi-ai's cost metadata — `replay.ts` zeroes it and no consumer reports spend" (`packages/llm/llm-pi-ai/src/catalog.ts:33-38`) [verified]. pi-ai computes cost from its own catalog (`calculateCost`) and **ignores the `usage.cost` that OpenRouter returns** (`openai-completions.js:1163-1192`) [verified]. OpenRouter now includes `usage.cost` in every response automatically ([usage accounting](https://openrouter.ai/docs/use-cases/usage-accounting)) [verified].
- pi-ai has an `onProviderStreamEvent` hook that would see the raw chunk (and so `usage.cost`) (`pi-ai dist/types.d.ts:113-118`, called at `openai-completions.js:354`) [verified]. **`llm-pi-ai` doesn't pass it, nor `onPayload` or `onResponse`** [verified, no match in `packages/llm/llm-pi-ai/src/`]. Reaching it needs a dsh patch, which ADR 0001 avoids.
- `token-meter` measures **context pressure** for compaction, not spend (`docs/subsystems/token-meter.md`) [verified].
- `session-stats` folds the whole log into turn and step counts, `llmMs`, `toolMs`, first-token latency and decode tokens (`packages/session/session-stats/README.md`, "What the figures mean") [verified]. It feeds the web UI. Headless doesn't print it [inferred].
- **Headless `--json`** emits `status` events with `phase: step_end` carrying the step's summed `usage`, **including retried attempts**. It omits `usage` when any attempt didn't report one, rather than print a partial sum (`packages/bundle/headless/src/json-stream.ts:266-290`) [verified]. It does **not** print the model or `responseId` [verified].
- **Hidden extra call.** The base mounts `session-title-first-prompt-llm` (`cordis.patch.yml:67-77`) [verified]. It makes one auxiliary model call per fresh session, on the main route unless configured otherwise (`packages/session/session-title-first-prompt-llm/README.md:32-36`) [verified]. Its request is logged but **its usage is not** (`session-title-llm/src/index.ts:267-275`; no `usage` anywhere in that package) [verified]. When the main route is Opus 5.5, this call costs Opus prices and is invisible in the log's token sums [inferred].

### 1c. Telemetry that leaves the machine

Two independent paths, both on by default in the base bundle.

**Path 1: `session-telemetry-otel` (OpenTelemetry logs to DeepSeek).**

- Rows `otel` and `session-telemetry-otel` in `cordis.patch.yml:202-232` [verified]. The endpoint is `DSH_TELEMETRY_OTLP_URL` or `https://dsh-otel-collector.deepseeksvc.com/v1/logs`. The mode is `DSH_TELEMETRY_MODE` or `FEEDBACK_ONLY` [verified].
- Only two modes exist: `FEEDBACK_ONLY` and `DISABLED`. "`FULL` is rejected, not an alias" (`packages/session/session-telemetry-otel/src/index.ts:31-34`, `52-63`; README "Modes") [verified].
- In `FEEDBACK_ONLY`, nothing is sent until you submit feedback (`feedback/record`, message ratings, edits). Then the **whole canonical prefix** of that session is uploaded, including message text, tool arguments, tool results and workspace paths (`src/index.ts:42-50`, `220-232`; `apps/cli/reference/README.md:139`) [verified]. It carries an anonymous user id from `$DSH_HOME/.anonymous-user-id` (`cordis.patch.yml:210-212`) [verified].
- The package ships **no redaction rules**: "records leave the process exactly as captured, including any credentials embedded in file contents or command output" (`packages/session/session-telemetry/README.md`, Known Limitations) [verified].
- **Off switch:** any non-empty `DSH_TELEMETRY_DISABLED` (even `0`) patches the row `disabled: true` at boot (`packages/boot/app-boot/src/profile-context.ts:39-55`) [verified]. That is stronger than `DSH_TELEMETRY_MODE=DISABLED`, which still mounts the plugin but builds no transport (`src/index.ts:156-162`) [verified]. Our bundles can also simply leave the row disabled.
- The OTLP exporter posts through `node:http` and bypasses dsh's HTTP proxy (`packages/util/http-proxy/README.md:110`) [verified]. So an egress proxy would not catch it. One more reason to remove the row.

**Path 2: `session-log-deepseek` (log suffix inside DeepSeek API requests).**

- Mounted in the base (`cordis.patch.yml:43-44`), `enabled: true` by default (`packages/session/session-log-deepseek/README.md`, Configuration) [verified]. It adds a `dsh_session_log` field with the unaccepted log suffix (up to 8 MiB) to each request [verified].
- Only the official DeepSeek adapter uses it: `llm-deepseek` calls `deepseekLlmApiExtensions.prepare()` (`packages/llm/llm-deepseek/src/host.ts:52`). `llm-pi-ai` never references it [verified by grep]. So our OpenRouter and Ollama routes don't send it [inferred].
- The base default model is still `deepseek-official` (`research/redteam-setup.md` §2) [verified there]. If a profile ever fell back to it, the log would go to DeepSeek. Set `session-log-deepseek` to `enabled: false` (or disable the row) in both profiles as belt and braces.

**Product analytics** (`product-analytics`, `desktop-product-telemetry`) only mount when the profile name is `desktop` (`packages/bundle/web-app/cordis.patch.yml:44-62`) [verified]. Headless never loads them.

---

## 2. Where a plugin can observe model calls, tool calls and defences

All events below come from the generated table in `docs/event-producer-consumer.md` (lines cited) [verified].

| Hook | Mode | What a plugin sees | Use for us |
|---|---|---|---|
| `session/event` | emit | **Every** appended event, in order (`:67`) | The audit plugin's main input. Everything in section 1a |
| `llm/stream` | waterfall | Every streaming model call, including auxiliary ones (title), with the full request and all chunks, `usage` included (`:57`; `packages/llm/llm/src/index.ts:63-74`) | Canary scan of the model stream (ADR 0003 #5); counting title-call tokens |
| `agent/request` | waterfall | The prepared request per step (`:21`) | Not needed |
| `agent/assistant-stream` | emit | Live stream frames (`:13`) | Not needed; the log has the same stream |
| `tools/pre-execute` | waterfall | Each call before dispatch; can `allow`, `deny` (with `{name, code}`), `cancel` or `ask` (`:80`; `packages/core/tools/src/index.ts:600-612`) | Policy plugin, and the place to record *why* it denied |
| `ctx.tools.guard()` | monotonic guard | Can only deny, returning a reason string (`index.ts:725-732`, `1135-1148`) | MCP pinning guard |
| `tools/post-execute` | waterfall | The result; can `accept` with new `content`/`value` or `block` (`:79`; `index.ts:614-622`) | Injection filter; the place to record score and action |
| `tools/result` | emit | The final, immutable outcome (`:82`) | Observing results without changing them |
| `agent/error` | emit | Step or turn errors (`:16`) | Error counting |

What already lands in the log from these hooks, and what does not:

- A `deny` from `tools/pre-execute` or a guard becomes an error `tool/result`. Its `error.code` is whatever `info` the plugin supplied [verified, `index.ts:600-612`; `types.ts:376-389`]. **Give every defence denial a stable `code`** (for example `ZM_EGRESS_DENIED`, `ZM_PIN_MISMATCH`) so assertions can count them.
- An `ask` produces `approval/asked` and `approval/decided`. Headless has no answerer, so the outcome is `unavailable`, which denies [verified, `user-approval/src/types.ts:44-58`; ADR 0003].
- A `post-execute` rewrite is **only visible as the final content**. The original content and the filter's score are not logged [inferred from "model-visible means logged" and the `PostToolDecision` shape].
- A canary match in `llm/stream` (ADR 0003 says "turn flagged") has **no log representation** unless we write one [inferred].
- Native plugins write **no** `hook/*` records; only the Claude Code and Codex bridges do (`hook-protocol/src/types.ts:44-48`) [verified].
- Decisions API calls made by our injection filter and secrets judge are **plain HTTP calls from our plugin**, not dsh model calls. Their model, cost and latency appear nowhere unless we record them [inferred].

**How to record them: plugin records.** `appendPluginRecord(session, 'plugin:<name>/<event>', data)` appends an event marked `ignorable: true`. It never enters the model's view, survives fork and resume, and older or newer readers skip it safely (`packages/core/session/src/index.ts:466-498`; `pluginRecordOf()` at `:508-512`) [verified]. The grammar is `plugin:` plus lowercase slash-separated segments (`index.ts:439`) [verified]. Limits:

- dsh calls it "experimental", and its in-repo lint gate allows only `packages/experimental/` to call it (`index.ts:479-481`) [verified]. That gate is a dsh-repo check, not a runtime check. The function is exported from the package root, since `@deepseek-ai/dsh-session` maps `.` to the built `index.js` (`packages/core/session/package.json:16-20`) [verified]. So our out-of-repo plugin can call it [inferred, not run]. The API may change between releases [inferred; check at each upgrade].
- Format migrations keep plugin records only on a best-effort basis (`index.ts:474-476`) [verified]. Fine for audit within one dsh version.
- A plugin could instead declare a real `SessionEventMap` type. But the reader refuses unknown required types, and out-of-repo types are always unknown to dsh (`known-event-types.ts:8-21`) [verified]. **Use plugin records, not custom event types.**

Data that must never enter the log: ADR 0004's secret values. The log stores tool results verbatim (`types.ts:376-389`) [verified], and both telemetry paths would upload it if enabled. **The gitleaks tool must mask values before it returns a result**, not only before the Decisions call [inferred from ADR 0004 plus "model-visible means logged"].

---

## 3. OpenTelemetry and LangSmith

### 3a. What exists today

- dsh's `otel` package depends only on the **logs** side of the OTel JS SDK (`@opentelemetry/api-logs`, `sdk-logs`, `otlp-exporter-base`, `otlp-transformer`, `resources`, `core`) (`packages/telemetry/otel/package.json:32-38`) [verified]. No package in the repo depends on `sdk-trace` [verified by grep]. **There are no spans.**
- `ctx.otel` offers `createEventReporter()` and `createSessionLogReporter()` channels (`docs/subsystems/otel.md`, Cordis API) [verified]. A plugin could reuse them to send OTLP **logs** to a local endpoint without new dependencies [inferred].
- The `sessionTelemetry` service allows one backend per context; a second load throws (`packages/session/session-telemetry/src/index.ts:142-151`) [verified]. Its coordinator supports a `live` capture mode (`coordinator.ts:30`) that the shipped backend doesn't use (`session-telemetry-otel/src/index.ts:220`) [verified]. So a custom backend could stream every event live to a **local** collector, but only by replacing the shipped row [inferred].
- **pi-ai 1.1.0** declares `telemetryContext?: TelemetryContext` on request options (`pi-ai dist/types.d.ts:1`, `61-62`) and forwards it (`dist/api/simple-options.js:25`) [verified]. No file in pi-ai's `dist` calls `startSpan` [verified by grep]. pi-telemetry is "vendor-neutral telemetry contracts … no exporter" (`pi-telemetry README.md`) [verified]. `llm-pi-ai` passes no `telemetryContext` [verified]. Newer pi-telemetry versions exist (1.2.0, 1.3.0 on npm) [verified]; whether newer pi-ai emits spans is **[unverified]** and irrelevant while dsh pins 1.1.0.
- **LangSmith:** nothing in dsh or pi-ai mentions it [verified by grep].

### 3b. What a minimal OTel trace plugin would need

- **Spans to emit**, following the GenAI conventions (all still **Development** status, `docs/gen-ai/gen-ai-spans.md:7`) [verified]:
  - one `invoke_agent` span per turn,
  - one `chat {gen_ai.request.model}` span per step with `gen_ai.operation.name=chat`, `gen_ai.provider.name`, `gen_ai.request.model`, `gen_ai.response.model`, `gen_ai.response.id` and `gen_ai.usage.*` (`gen-ai-spans.md:37`, `54`, `64-75`),
  - one `execute_tool` span per tool call with `gen_ai.tool.name` and `gen_ai.tool.call.id` (`gen-ai-spans.md:739`; `reference/reports/execute-tool-span.md:10-18`).
  - Message content is **Opt-In** and marked sensitive (`gen-ai-spans.md:390-392`, `656`) [verified]. Leave it off.
- **Source of data:** the `session/event` stream. Turn, step, tool call and result times, usage, requested and response model and response id are all there (section 1a) [inferred].
- **Packages:** `@opentelemetry/api`, `@opentelemetry/sdk-trace-base` (or `-node`) and `@opentelemetry/exporter-trace-otlp-http`. The default endpoint is `http://localhost:4318/v1/traces` ([OTel JS exporters](https://opentelemetry.io/docs/languages/js/exporters/)) [verified]. Our plugin would ship them as its own dependencies [inferred].
- **A local receiver:** either Jaeger (OTLP on 4317/4318, UI on 16686; the docs' `docker run -p 4318:4318 …` binds all interfaces, so use `-p 127.0.0.1:4318:4318`) [verified ports; loopback binding is my advice], or **Promptfoo itself** (next point).
- **Promptfoo has a built-in OTLP receiver.** `tracing.enabled: true` plus a `tracing.otlp.http` block starts it on `127.0.0.1:4318` by default. It stores spans in local SQLite. It passes a W3C `traceparent` to JS custom providers on the context object. It offers `trace-span-count`, `trace-span-duration`, `trace-error-spans` and `trajectory:tool-used` / `tool-sequence` / `tool-args-match` assertions. Trajectory assertions read `tool.name` and `tool.arguments` ([Promptfoo tracing](https://www.promptfoo.dev/docs/tracing/)) [verified]. So a trace plugin should set both `gen_ai.tool.name` and `tool.name` [inferred].
- **Passing the parent trace:** our JS custom provider would read `context.traceparent` and hand it to `dsh` through an env var that our plugin reads as the root span's parent [inferred design; dsh has no such variable].

Size: roughly one plugin file that maps about six event types to spans, plus SDK setup and shutdown flush on disposal [inferred, not written].

### 3c. LangSmith

- OTLP ingest is `https://api.smith.langchain.com/otel/v1/traces` with header `x-api-key` and optional `Langsmith-Project`. It maps `gen_ai.*` attributes, including `gen_ai.request.model` and `gen_ai.usage.input_tokens` ([LangSmith OTel](https://docs.langchain.com/langsmith/trace-with-opentelemetry)) [verified]. So the same trace plugin could point at LangSmith with no code change [inferred].
- But that sends prompts, tool data and timing to LangChain's cloud. "Self-hosted LangSmith is an add-on to the Enterprise plan", installed on Kubernetes with Helm ([self-hosted](https://docs.langchain.com/langsmith/self-hosted)) [verified]. **It doesn't fit a local-first, one-person, no-budget project**, and it would be one more place secret-shaped data could leak (ADR 0004).

---

## 4. What the hardened harness and the Promptfoo evals need

| Need | Already in dsh? | Gap | Smallest fix |
|---|---|---|---|
| Egress or read denied (policy plugin) | Error `tool/result` with our `error.code` | None, if we set codes | Stable `ZM_*` codes on every `deny` |
| Taint escalated to `ask`, then denied | `approval/asked` + `approval/decided: unavailable` | Doesn't say *taint* caused it | Put a tag in the ask `reason`; also a plugin record |
| Injection filter score, wrap or block | Only the final content | Score, action and model are lost | `plugin:zelemate-audit/injection` record with score, action, tool, callId, Decisions model, **no content** |
| MCP pin mismatch | Error `tool/result` (guard reason) | No code (guards return a string only) | Prefix the reason, plus a plugin record |
| Canary in outbound args | Error `tool/result` | None, if coded | `ZM_CANARY_EGRESS` |
| Canary in model stream | Nothing | Not recorded | `plugin:zelemate-audit/canary` record from the `llm/stream` listener |
| Canary in the audit log (ADR 0003 #5) | The log is local | Needs the per-run canary value to search | Audit plugin knows the value; it counts hits but **never writes the value** |
| Per-run tokens | `--json` `step_end.usage`; `assistant/message.usage` | Title call missing; reasoning tokens dropped | Disable `session-title-llm`; accept the reasoning gap |
| Per-run cost | Nothing | No cost anywhere | After the run, `GET https://openrouter.ai/api/v1/generation?id=<responseId>` per step: `total_cost`, `model`, `provider_name` ([get-a-generation](https://openrouter.ai/docs/api-reference/get-a-generation)) [verified]. Local Ollama runs cost 0. Decisions calls: the filter records `usage` from OpenAI's response |
| Which model answered (ADR 0006) | `request/header.model` + `replayState.response.responseModel` | Not in `--json`; no upstream provider | Audit plugin copies both into the summary; the generation lookup adds `provider_name` and `router` |
| Attack success rate inputs | Tool results, approvals, turn end reason | Spread over many events | Per-run summary file (below) |

Promptfoo can use these directly. A JS custom provider returns `output`, `tokenUsage`, `cost` and `metadata` ([custom provider](https://www.promptfoo.dev/docs/providers/custom-api/)) [verified]. The built-in `cost` assertion checks that reported cost is under a threshold ([deterministic assertions](https://www.promptfoo.dev/docs/configuration/expected-outputs/deterministic/)) [verified]. So the provider should fill `cost` from the OpenRouter lookup and `metadata` from the summary [inferred].

**Per-run summary file.** The audit plugin keeps a small fold over `session/event` (and its own records). At `turn/end` it writes `$AUDIT_DIR/<sessionId>.json`:

```json
{
  "sessionId": "session-…",
  "profile": "redteam",
  "turnEnd": "completed",
  "models": [{ "step": 1, "requested": "qwen3.5:4b", "responseModel": null, "responseId": "chatcmpl-…" }],
  "usage": { "input": 0, "output": 0, "cacheRead": 0, "complete": true },
  "toolCalls": 3,
  "denials": { "ZM_EGRESS_DENIED": 1 },
  "approvals": { "unavailable": 1 },
  "injection": [{ "callId": "…", "score": 0.93, "action": "block", "judge": "gpt-6-luna" }],
  "canaryHits": { "stream": 0, "outboundArgs": 1, "toolResults": 0 },
  "decisionsCalls": { "count": 2, "inputTokens": 0, "outputTokens": 0 }
}
```

Field names are a sketch [unverified design]. The file holds **no message text, no tool content and no canary value**, so it is safe to keep next to eval results. Reading events in-process through dsh's typed `session/event` keeps us off the storage format (section 1a) [inferred]. Subagent sessions are separate sub-sessions in the session tree (`packages/session-query/session-log-export/README.md`, Summary) [verified], so the fold must follow child session ids if subagents are ever enabled [inferred]. Both profiles turn them off today (ADR 0003 keeps the tool set narrow) [inferred].

---

## 5. Recommendation

**v1 (needed for the first attack-success-rate and F1 numbers):**

1. **Turn off everything that leaves the machine** in both bundles: disable the `session-telemetry-otel` row, set `session-log-deepseek` to `enabled: false`, and export `DSH_TELEMETRY_DISABLED=1` in the Promptfoo wrapper as a second lock. Keep the `otel` row; mounting it alone opens no connection (`docs/subsystems/otel.md`) [verified].
2. **Disable `session-title-llm`** in both bundles. It adds an unlogged model call per run, and on Opus it costs real money. The fallback title still works [inferred from `session-title` fallback config at `cordis.patch.yml:60-65`].
3. **Keep the session log as the audit trail** (ADR 0003 #6), but set `session-persistence-jsonl` to `compression: none` with the same `root`, so a human can `grep` it.
4. **Write one plugin, `@zelemate/dsh-audit`.** It (a) gives the defence plugins a tiny `ctx.audit.record(kind, data)` service that calls `appendPluginRecord()` with `plugin:zelemate-audit/<kind>`, (b) watches `llm/stream` for the canary, and (c) writes the per-run summary file. Every defence denial uses a stable `ZM_*` code.
5. **Cost after the run, outside dsh.** The Promptfoo provider reads `responseId`s from the summary and calls OpenRouter's generation endpoint with the same key (openrouter.ai is already allowlisted in ADR 0003). Ollama runs report 0. Keep the provider dashboards as the budget truth (ADR 0005/0006).

This amends ADR 0003's "audit: nothing new built" into "audit: the session log, plus plugin records for defence decisions". That needs a short ADR update.

**Later (learning, optional):** an OTel trace plugin that maps `session/event` to GenAI spans and exports OTLP/HTTP to **Promptfoo's local receiver on 127.0.0.1:4318**, so `trajectory:*` and `trace-*` assertions work. Jaeger on loopback is the alternative viewer. **Don't adopt LangSmith**; its cloud endpoint conflicts with ADR 0004 and self-hosting needs Enterprise.

**Check before relying on this:**

- What OpenRouter puts in the stream chunk `model` field for presets and Switchyard, and so whether `responseModel` really names the served model [unverified].
- That the title row can be disabled without breaking headless startup [unverified].
- That `compression: none` plus the same `root` boots with `--dump-config` [unverified].

## Corrections to earlier research and ADRs

- **ADR 0005** says spend is tracked on dashboards "because dsh's price table is out of date". The real reason is stronger: **dsh never reads any price table**. `llm-pi-ai` zeroes cost and no consumer reports spend (`catalog.ts:33-38`).
- **`research/redteam-setup.md` §2** describes telemetry as "triggered only by explicit feedback events" and suggests `DSH_TELEMETRY_MODE=DISABLED`. That is right, but `DSH_TELEMETRY_DISABLED=1` is stronger (it removes the row), and the upload, once triggered, is the **whole session prefix** with no redaction.
- **`research/redteam-setup.md` §3d** refers to "our harness's `audit` plugin" and an "audit JSONL" as the source of truth, while **ADR 0003 #6** says nothing new is built. Both are partly right: the session log is the trail, and a small audit plugin is needed to record defence decisions in it.

## Sources

- dsh `dsh-v0.2.1-rc.2`: `packages/bundle/base/cordis.patch.yml`, `packages/bundle/headless/{cordis.patch.yml,README.md,src/json-stream.ts}`, `packages/bundle/web-app/cordis.patch.yml`, `packages/core/session/src/{types.ts,index.ts,known-event-types.ts}`, `packages/core/tools/src/index.ts`, `packages/llm/llm/src/{types.ts,message.ts,call-config.ts,index.ts}`, `packages/llm/llm-pi-ai/src/{stream.ts,catalog.ts,replay.ts}`, `packages/llm/llm-deepseek/src/host.ts`, `packages/session/session-telemetry/{README.md,src/index.ts,src/coordinator.ts}`, `packages/session/session-telemetry-otel/{README.md,src/index.ts}`, `packages/session/session-log-deepseek/README.md`, `packages/session/session-persistence-jsonl/README.md`, `packages/session/session-stats/README.md`, `packages/session/session-title-llm/src/index.ts`, `packages/session/session-title-first-prompt-llm/README.md`, `packages/telemetry/{README.md,otel/package.json}`, `packages/interaction/user-approval/src/types.ts`, `packages/experimental/hook-protocol/{README.md,src/types.ts}`, `packages/boot/app-boot/src/profile-context.ts`, `packages/util/http-proxy/README.md`, `apps/cli/reference/README.md`, `docs/{event-producer-consumer.md,tool-execution-pipeline.md}`, `docs/subsystems/{otel.md,product-telemetry.md,session.md,token-meter.md}`
- pi-ai 1.1.0 (npm `@earendil-works/pi-ai`): `package.json`, `dist/types.d.ts`, `dist/api/openai-completions.js`, `dist/api/simple-options.js`
- pi-telemetry 1.1.0 (npm `@earendil-works/pi-telemetry`): `README.md`, `dist/index.d.ts`
- OpenTelemetry: [GenAI semantic conventions repo](https://github.com/open-telemetry/semantic-conventions-genai) @ `547934a` (`docs/gen-ai/gen-ai-spans.md`, `reference/reports/execute-tool-span.md`); [JS exporters](https://opentelemetry.io/docs/languages/js/exporters/)
- LangSmith: [trace with OpenTelemetry](https://docs.langchain.com/langsmith/trace-with-opentelemetry), [self-hosted](https://docs.langchain.com/langsmith/self-hosted)
- Promptfoo: [tracing](https://www.promptfoo.dev/docs/tracing/), [custom API provider](https://www.promptfoo.dev/docs/providers/custom-api/), [deterministic assertions](https://www.promptfoo.dev/docs/configuration/expected-outputs/deterministic/)
- OpenRouter: [usage accounting](https://openrouter.ai/docs/use-cases/usage-accounting), [get a generation](https://openrouter.ai/docs/api-reference/get-a-generation)
