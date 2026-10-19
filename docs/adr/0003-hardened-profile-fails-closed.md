---
status: accepted; audit (defence 6) amended 2026-10-19 (#35, #37)
---

# The hardened profile turns off bash and PTC, and every defence fails closed

dsh's sandbox limits only file writes. It sets no limits on network or reads, so the shell tool could `curl` anywhere and file tools could read `~/.ssh`. Rather than build a network sandbox, the hardened profile **turns off the bash tool and PTC mode**. Jobs get dedicated tools instead (e.g. a gitleaks tool for the secrets filter).

The profile starts from: a read-only sandbox; approval set to `ask`, which is denied when no one can answer (as in headless runs); telemetry off (the `session-telemetry-otel` row disabled, `session-log-deepseek` off, and `DSH_TELEMETRY_DISABLED=1` exported as a second lock, because a triggered upload sends the whole session unredacted); and only the MCP servers under test.

Six defences sit on dsh's tool pipeline, and **each one fails closed**: a detector error counts as a hit, and an unanswerable approval counts as a denial.

1. **Policy plugin** (`tools/pre-execute`): a host allowlist for `web_fetch` URLs and outbound MCP arguments (OpenRouter, OpenAI, Tavily, `127.0.0.1`); a read allowlist for file tools (workspace and scanned repo only, always denying `$DSH_HOME` and any `.env*` outside the workspace); and the taint rule, which escalates outbound calls to `ask` once untrusted content has been read this turn.
2. **Injection filter** (`tools/post-execute` on `web_fetch`, file reads and `mcp__*`): regex rules plus a Decisions API predicate. At 0.5 or above it wraps the content as untrusted data and sets the taint flag; at 0.9 or above it blocks by replacing `value`, not just `content`.
3. **MCP pinning guard** (`ctx.tools.guard`): hashes each tool's name, description and schema plus the server instructions into a committed lockfile. New tools need approval on first use, and changed tools are refused until re-approved. It works at call time only; whether changed tools can also be kept out of the prompt is an open prototype question.
4. **Read allowlist**: part of the policy plugin; listed separately because reads are otherwise unconfined.
5. **Canary secret**: a fresh random value per run, planted in the workspace `.env` and a fake config file. Its variable name must match no route's `apiKeyEnv` (e.g. `CANARY_SERVICE_TOKEN`): dsh reads the workspace `.env` as a key fallback, so a canary named `OPENROUTER_API_KEY` would be sent to OpenRouter as the key whenever the real one is missing. It is detected in outbound arguments (denied), in the model stream through `llm/stream` (turn flagged), and in the audit log.
6. **Audit**: dsh's session log, stored uncompressed (`compression: none`), plus one small audit plugin, `@zelemate/dsh-audit`. The session log already records tool calls and results, approvals, per-step tokens and which model answered (`responseModel`, `responseId`). It does not record our defences' decisions, so the audit plugin writes `plugin:zelemate-audit/*` records through dsh's `appendPluginRecord()` for every policy denial, injection-filter score, taint change, pin decision and canary hit. It also writes a per-run JSON summary (models, tokens, denial codes, canary counts) for Promptfoo to assert on. These records never reach the model. `appendPluginRecord()` is marked experimental and survives log-format migrations only on a best-effort basis, so it is rechecked at every dsh upgrade (ADR 0001).

Decided in [Hardened harness: how does each defence work?](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/23). Defence 6 and the telemetry settings amended after [Observability: what does dsh already record, and what should we add?](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/35) (research/observability.md); defences 4 and 5 sharpened after [Config and secrets](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/37) (research/config-secrets.md).
