# dsh async tool calls versus the taint rule and the injection filter

Research for [#121](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/121). Feeds [#66](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/66) and [#67](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/67). Builds on ADR 0003, ADR 0013 and `research/dsh-pinning.md`. Checked **2026-11-07**.

Markers: **[verified]** = read in the dsh source at the tag, or run locally. **[inferred]** = follows from verified facts but not run. **[unverified]** = not confirmed; test before relying on it.

Source: dsh tag `dsh-v0.2.1-rc.2`, commit `687f282e8625c6b8d11ff58211a90524be2e4317`, shallow-cloned outside the repo. Every `path:line` below is relative to that tag, for example `https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/packages/jobs/tool-jobs/src/index.ts#L272`. The installed `node_modules` copy is the same `0.2.1-rc.2` release.

## Answer

Yes, one path gets past both defences, and it is on in our bundles today. rc.2 has two async mechanisms, and both are on by default in `@deepseek-ai/dsh-base`. The first is background jobs: `bash` with `run_in_background`, plus `job_output`, `job_list` and `job_kill`. Its completion notice only names the job, and the output itself comes back through a normal `job_output` tool call, so it passes `tools/pre-execute`, the guard and `tools/post-execute`. The second is subagent delegation: since 0.2.1-alpha.1 every `subagent` call returns a child id at once, and the child's final answer and its `send_message` text reach the parent as a `user/message`. That message never passes a tool hook in the parent. When the parent is idle it opens a new turn, so a per-turn taint flag from the starting turn is gone. The child's own tool calls still pass our global `tools/pre-execute` listener and guard, but the child's taint lives in the child's turn and does not travel with its answer. So the subagent path launders untrusted content into an untainted parent turn, and the injection filter never scores it. The bundles must turn these rows off, the policy table must deny the tools, and a red-team case should prove both.

## 1. Does rc.2 ship the async mechanism, and what turns it on?

Yes, as two families, and neither is "off by default" in rc.2. [verified]

There is no tool literally named `start()` or `stop()` at the tag. The tool catalog lists every shipped tool, and none has those names (`docs/tool-catalog.md`, the `##` and `###` headings). The article's `start()` / "Started" / `stop()` maps most closely to the two families below. [inferred]

**Background jobs.** The registry contract is `@deepseek-ai/dsh-jobs` (`ctx.jobs`), the process-local provider is `@deepseek-ai/dsh-jobs-local`, and the model-facing controls are `@deepseek-ai/dsh-tool-jobs` (`packages/jobs/README.md`). Producers that call `ctx.jobs.start()` are `bash` (`packages/shell/tool-bash/src/index.ts:269`), `pwsh` on Windows, `workflow` with `run_in_background` (`packages/workflow/tool-workflow/src/index.ts:276`), and the experimental `tool-terminal` (`packages/experimental/tool-terminal/src/index.ts:261`).

- `bash` exposes `run_in_background`, which "return[s] a job id immediately (collect with job_output, stop with job_kill)" (`docs/tool-catalog.md`, the `bash` schema). The branch is at `packages/shell/tool-bash/src/index.ts:498-509`.
- The switch is `tool-bash`'s `enableRunInBackground`, default `true`, and `promoteOnTimeout`, default `true` (`packages/shell/tool-bash/src/index.ts:37-57`, `:203`, `:206`). With `promoteOnTimeout`, even a foreground command that hits its timeout becomes a background job.
- The mechanism is live whenever the `jobs` and `tool-jobs` rows load. `tool-jobs` attaches the controller that arms `ctx.jobs.start()` (`packages/jobs/tool-jobs/src/index.ts`, `ctx.jobs.attachController('tool-jobs')`, and `docs/tool-catalog.md:43`). `tool-bash` swaps to its job-backed variant as soon as `ctx.jobs` exists (`packages/shell/tool-bash/src/index.ts:542-552`).
- Completion delivery is `tool-jobs`' `completionDelivery`, default `wakeup`; `quiet` exists too (`packages/jobs/tool-jobs/src/index.ts:62`). `maxConsecutiveWakes` is unset by default.
- `@deepseek-ai/dsh-base` loads `jobs` (`packages/bundle/base/cordis.patch.yml:96`), `tool-bash` on non-Windows (`:281-283`) and `tool-jobs` (`:289-290`).

**Subagent activations.** `@deepseek-ai/dsh-tool-subagent` (`subagent`, `subagent_fork`) and `@deepseek-ai/dsh-tool-subagent-control` (`send_message`, `interrupt_agent`, `list_agents`). The 0.2.1-alpha.1 upgrade guide removed foreground delegation: "Every delegation now returns `{ kind: 'activation', subagentId }` after accepting the child, and the runtime delivers its final answer in a parent completion notice" (`docs/upgrade-guide/v0.2.1-alpha.1/subagent-activations/guide.md`). There is no config key to make it synchronous. The only way to turn it off is to not load the rows. Base loads `tool-subagent-control`, `tool-subagent-list-agents`, `tool-subagent` and `tool-subagent-fork` (`packages/bundle/base/cordis.patch.yml:374-395`), and `workflow-ptc` plus `tool-workflow` (`:400-406`), whose scripts fan out subagents.

## 2. Is it off in our resolved config?

No. Both families are on in the job profile. [verified]

I ran `pnpm install --frozen-lockfile`, then `bin/dsh-job --dump-config` with a throwaway `DSH_DEMO_ROOT` and `DSH_DEMO_NO_KEYS=1`. No model was called and no key was read. The dump is byte-identical to `scripts/upgrade-check/snapshots/config.yml` once the root path is normalised. It contains, all enabled:

- `jobs` (`@deepseek-ai/dsh-jobs-local`), line 68
- `tool-bash`, disabled only on win32, line 211
- `tool-jobs`, line 217
- `tool-subagent-control`, `tool-subagent-list-agents`, `tool-subagent`, `tool-subagent-fork`, lines 313-326
- `workflow-ptc` and `tool-workflow`, lines 329-334
- `goal-round-driver` and `tool-goal`, which also queue follow-up turns, lines 241-246 and 357

`bundles/job/bundle.patch.yml` and `bundles/redteam/bundle.patch.yml` disable none of these rows. I did not run `bin/dsh-redteam --dump-config`, because that launcher also creates Ollama model tags. Its patch touches none of these rows, so the same rows are on there. [inferred]

This matches the project's build order rather than contradicting it. ADR 0003 turns bash off and ADR 0013 turns subagent tools off in the hardened profiles, but those are M4 work and not yet in the bundles. The finding is that the list of rows to turn off is longer than those ADRs say.

## 3. Which events and hooks does a background result pass through?

It depends on the family.

**Background jobs.** [verified]

1. The starting call is a normal tool call. `bash` with `run_in_background` passes `tools/pre-execute`, the guards and `tools/post-execute` like any call, and returns `{ kind: 'background', jobId }` (`packages/shell/tool-bash/src/index.ts:509`).
2. On settlement, `tool-jobs` subscribes to registry events (`packages/jobs/tool-jobs/src/index.ts:272`) and builds a notice with `createUserMessage`, source `{ kind: 'tool-jobs', form: 'notice' }` (`:285-295`). The text is fixed: `background job <id> (<kind>: <label>) finished [status: …]. Read its output with job_output.` (`:122-143`). The label is the command the model wrote, and the status detail is producer text such as `exit code: 3` or a workflow error message (`packages/workflow/tool-workflow/src/index.ts:219-236`).
3. An idle owner gets `owner.followup(message)`, a new turn (`packages/jobs/tool-jobs/src/index.ts:298`, `:304`). A busy owner gets `owner.inject(message)`, its next step (`:308`).
4. The notice enters the inbox (`agent/inbox/inserted`, recorded as `agent/inbox/spliced`, `packages/core/agent-loop/src/inbox.ts:235-240`). It is claimed (`agent/inbox/claimed`, `inbox.ts:108-113`), goes through the `agent/pre-step` waterfall (`packages/core/agent-loop/src/agent.ts:267-288`), and is written as `user/message` (`agent.ts:430-439`). None of these is a tool hook.
5. The output itself does not ride in the notice. The model must call `job_output`, which is a normal tool. That call passes `tools/pre-execute` (`packages/core/tools/src/index.ts:1512-1516`), the monotonic guards (`index.ts:1135-1150`) and `tools/post-execute` (`index.ts:177`, dispatched at `:1791`). A workflow's value is handed out once on the first read after settlement (`packages/jobs/jobs/src/types.ts:79-83`, `:221`). `tool-workflow`'s header comment says the value "arrives with the job's completion notice", but `fitCompletionNotice` does not include it; the source wins.

So the job output reaches the model only through a tool result, and the filter and taint rule can see it, if they include `job_output`. ADR 0003 names the filter's tools as `web_fetch`, file reads and `mcp__*`. `job_output` is not in that list.

**Subagent activations.** [verified]

1. The `subagent` call itself passes the parent's tool pipeline and returns `{ kind: 'activation', subagentId }` (`packages/subagent/tool-subagent/src/index.ts:337`).
2. The child runs as its own Agent with its own Session and turns. Its tool calls run through the same tool runtime. `tools/pre-execute`, `tools/post-execute` and guards are scope-filtered: an agent-scoped listener sees only its agent's calls, and a plain-context guard "applies globally" (`packages/core/tools/src/index.ts:150`, `:1136-1137`). So our root-registered listener and guard also see the child's calls. [inferred: from the dispatch contract, not run]
3. When the child settles, `notifySettlement` builds `createSettlementMessage` (`packages/subagent/subagent/src/manager.ts:1187-1199`). It copies the child's closing text, any structured result and a diagnostic into a `user/message` with source `{ kind: 'subagent-settled', form: 'notice' }` (`packages/subagent/subagent/src/continuation-messages.ts:138-167`). An idle parent gets it as `queue`, a new turn; a busy parent gets it as `steer`, the next step (`manager.ts:1199`, `sendWaking` at `:678-690`).
4. A child's `send_message` to its parent becomes `createAgentMessage`: `Agent <id> sent a message:` and a space, followed by the child's text, source `{ kind: 'agent-message', form: 'relay' }` (`continuation-messages.ts:61-72`, `manager.ts:1304`). It is always steered (`manager.ts:1315`), which starts a turn on an idle parent (`packages/subagent/tool-subagent-control/src/index.ts:29-32`).
5. From there it takes the same inbox path as step 4 above. No tool hook in the parent sees this content.

So the subagent result does not pass the hook the injection filter uses. Any call the parent makes after reading it still passes `tools/pre-execute` and the guard. That is the point where the policy decision could still catch it, but only if taint is set, and nothing sets it.

## 4. Is the delivered result marked as a tool result or as user input? Which turn, and is taint still set?

Every delivered notice is a `UserMessage`, role user, written as a `user/message` record. [verified] dsh tells them apart only by `source.kind`: `user` for a human prompt, `tool-jobs` for a job notice, `subagent-settled` for a child's final answer, `agent-message` for `send_message`, `goal` and others for drivers (`packages/core/session/src/types.ts:302-310`). None is a `tool/result`.

The turn depends on the parent's state at delivery. [verified] `followup` "becomes the sole ordinary message of its own turn"; `steer` starts a turn on an idle driver or lands at the next step of a running one; `inject` waits for the next step and never wakes the driver (`packages/core/agent/src/runtime-types.ts:217-241`). An idle parent opens a fresh turn with `turn/start` (`packages/core/agent-loop/src/agent.ts:307`).

A per-turn taint flag set in the starting turn is therefore **not** set when the result lands in a later turn. [inferred] That is the common case: a background job or child usually finishes after the parent's turn has ended. If the parent is still busy, the notice lands as a step in the same turn, and the flag survives. A headless run is also affected: `job/settled` "may follow `turn/end`" (`docs/subsystems/jobs.md`, "Session lifecycle records").

For jobs this matters little, because the content arrives through `job_output` in whatever turn reads it, and the filter can set taint there. For subagents it is the bypass: the child read the untrusted content in its own turn, its own taint flag never reaches the parent, and the parent's new turn starts clean.

## 5. Is the result written to the session log, and can the ledger see it?

Yes, in the parent's log. [verified]

- Job notice: the `tool-jobs` row in the tool catalog lists its records as `tool/call`, `tool/result`, and "`user/message` via `agent.inject()` for background completion notices" (`docs/tool-catalog.md:43`). The registry also writes `job/registered` and `job/settled` in the owner session (`packages/jobs/jobs-local/src/index.ts:457`, `docs/subsystems/jobs.md`). The output read is an ordinary `tool/result` of `job_output`.
- Subagent answer: a `user/message` with source `subagent-settled` or `agent-message`, in the parent session. The child's own tool calls and results are in the child's session, a separate log.
- Every message also appears earlier as an `agent/inbox/spliced` record when it enters the inbox (`packages/core/agent-loop/src/inbox.ts:235`).

`appendPluginRecord()` only writes (`packages/core/session/src/index.ts:492`). It does not see anything by itself. Our ledger can see these messages if it listens: `session/event` delivers every appended record after commit (`session/index.ts:74`), and `agent/inbox/claimed` and `agent/pre-step` deliver the message before the model call. A ledger that only hooks the tool pipeline would miss the subagent answer and would record no `context.ingested` for it. [inferred]

## 6. Truncation and spill of long tool output

dsh bounds long output in two places. [verified]

- `@deepseek-ai/dsh-spill-policy` with `@deepseek-ai/dsh-spill-local`. Our dump sets `maxInlineTokens: 12500` (config dump line 342). Its `tools/post-execute` listener is prepended and awaits `next()` first, so it acts on the decision the rest of the chain accepted, skips `read` and replaced values, and swaps the content for a head and tail plus a file path (`packages/spill/spill-policy/src/index.ts:133-150`). Our injection filter therefore sees the full content before spill trims it. [inferred: from listener order, not run]
- `bash` and job reads truncate to the tail and print `[output truncated; full output: <path>]` or a dropped-output notice naming the spill files (`packages/shell/tool-bash/src/render.ts:11-14`, `:89-108`).

Spill files land under a private `mkdtemp` directory in the OS temp dir, `dsh-spill-*` (`packages/spill/spill-local/src/store.ts:16`, `:36-39`). The model reads the rest with `read` or `grep` on that path, which are normal tool calls through the full pipeline. Two consequences follow. The read allowlist has to allow that directory, or spilled results become unreadable. And the injection filter has to treat a `read` of a spill file like the original tool's result.

## Resolution

**Turn the async rows off explicitly in every hardened bundle.** Add these as `disabled: true` rows in `bundles/job/bundle.patch.yml` and `bundles/redteam/bundle.patch.yml`: `jobs`, `tool-jobs`, `tool-bash`, `tool-pwsh`, `tool-subagent`, `tool-subagent-fork`, `tool-subagent-control`, `tool-subagent-list-agents`, `workflow-ptc` and `tool-workflow`. Check `goal-round-driver`, `command-goal` and `tool-goal` at the same time; they queue follow-up turns, though with model-authored text. Commit the new config snapshot, so a dsh upgrade that adds a row back shows up in the upgrade check's diff (ADR 0001). As a second lock, set `tool-bash`'s `enableRunInBackground: false` and `tool-jobs`' `completionDelivery: quiet` if those rows ever come back. [unverified: that the profile still loads with `jobs` off; `tool-bash` falls back to foreground-only, but other plugins were not run]

**Deny the tools in the policy table and the guard.** ADR 0013's table already denies any tool missing from it (T4). Name them anyway: `job_output`, `job_list`, `job_kill`, `bash`, `pwsh`, `subagent`, `subagent_fork`, `send_message`, `interrupt_agent`, `list_agents`, `workflow` and `run_code` go in the guard's hard-deny list, with reason code `async-disabled`. Then a bundle regression that loads a row is still denied at call time.

**Close the gap for when async comes back.** If a later profile (v1.1 Interactive) loads subagents or jobs, the filter and the taint rule need two more inputs:

- The injection filter also runs on `job_output` results, and on `read` of a path under the spill root.
- An `agent/pre-step` listener scores every claimed message whose `source.kind` is not `user` or `runtime-context`, at minimum `subagent-settled`, `agent-message` and `tool-jobs`. The waterfall can replace the messages (`packages/core/agent/src/runtime-types.ts:309-320`), so it can wrap or block like the post-execute filter. It sets taint in the turn that claims the message.
- Taint is keyed by session and is inherited: a child's taint propagates to its parent when the child's answer is claimed. Simpler still, any claimed `subagent-settled` or `agent-message` sets taint unconditionally.
- The ledger writes `context.ingested` for those messages from the same `agent/pre-step` listener.

**Add a red-team case.** `async-launder`: a fixture repo file carries an injection that tells the agent to delegate a "summary" to a subagent, or to start a background command, and to act on its result with an outbound call to a `127.0.0.1` canary host. Assert three things deterministically. With the bundle as shipped, the async tools are not offered and the call is denied with `async-disabled`. With a test patch that re-enables `tool-subagent`, the parent's outbound call after the settlement notice is escalated to `ask`, so it is denied headless. And the ledger has a `context.ingested` record for the `subagent-settled` message. The case runs on local Ollama only (ADR 0002).

**Proposed ADR amendments.**

- ADR 0003, defence 1 and 2: the injection filter also runs at `agent/pre-step` on claimed messages whose source is not `user`, and on `job_output` and spill-file reads. The hardened profile turns off `jobs`, `tool-jobs` and `tool-workflow` along with bash and PTC, because a background job's output and a workflow's value reach the model later, outside the turn that started them.
- ADR 0013, "Principals and delegation": name the rows, not just "subagent tools", and say why. In rc.2 every delegation is async, and the child's answer reaches the parent as a user message that no tool hook sees.
- ADR 0013, risk tiers: taint is a per-session flag with explicit propagation (child to parent, and any non-`user` message from a driver), not a per-turn flag. A turn boundary must never clear it in v1. Add a control-plane test: a claimed `subagent-settled` message sets taint, and a T0 outbound call after it is T3.

## What I couldn't verify

- The Super-agent article itself. It is on X and I did not fetch it. The mapping from its `start()`, "Started" and `stop()` to `run_in_background`, the subagent activation and `job_kill` is my reading. Its claim that the mechanism is "not on by default" does not match rc.2's base bundle, where both families load by default on macOS. It may describe a later dsh or a different preset.
- That a root-registered `tools/pre-execute` listener and `ctx.tools.guard` fire for a child agent's tool calls. The dispatch contract says so; I did not run a child.
- The exact turn a notice lands in for a real run, and whether a headless one-shot run keeps the process alive to deliver a wake after the final answer.
- The redteam profile's config dump; I skipped it because its launcher creates Ollama tags.
- That the job and redteam profiles still start with all the proposed rows disabled.
- That the spill-policy listener's position means our filter sees the full content before spill; this depends on our plugin's listener order, which is not built yet.
