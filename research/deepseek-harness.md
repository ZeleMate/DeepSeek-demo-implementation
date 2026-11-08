# DeepSeek Harness

Research for issue #2. Checked 2026-10-18 against the repo at commit `687f282e` (release `dsh-v0.2.1-rc.2`).

## Answer

**Yes, the link is real.** <https://github.com/deepseek-ai/deepseek-harness> is a public repo in DeepSeek's own GitHub org. It is an open-source agent harness called `dsh`. Its tagline is "Everything is a Plugin." It is written in TypeScript on Node.js, uses the MIT license, and is a fast-moving **developer preview**. Its loop is a replaceable plugin built on the Cordis plugin framework. It is much bigger than what own-harness needs, so treat it as a design reference, not something to depend on.

## Facts

| Item | Value | Source |
|---|---|---|
| Owner | `deepseek-ai` org (the official DeepSeek GitHub org) | GitHub API `repos/deepseek-ai/deepseek-harness` |
| Description | "DeepSeek Harness: Everything is a Plugin." | GitHub API |
| Language / runtime | TypeScript, Node `^22.19.0 \|\| >=24.0.0`, pnpm monorepo. There is also a Python SDK (`python/`) | GitHub API `language`; root `package.json` `engines` |
| License | MIT, "Copyright (c) 2026 DeepSeek" | `LICENSE`; GitHub API |
| Created / last push | 2026-08-13 / 2026-10-17 | GitHub API |
| Maturity | 31 releases, **all marked prerelease**. The latest is `dsh-v0.2.1-rc.2` (2026-10-17). The README calls it a "developer preview" and warns of breaking changes. `SAFETY.md` says it has had no security audit and is not production-ready | Releases API; `README.md`; `SAFETY.md` |
| Popularity | About 252k stars and 30k forks, as the API reported on 2026-10-18. Issues are off; feedback goes through Discussions | GitHub API |
| How to run | `npx @deepseek-ai/dsh web` starts a Web UI on `127.0.0.1:3080`. Other profiles are `headless`, `sdk`, `sdk-minimal`, and `acp`. There is also an Electron desktop app | `README.md`; `docs/architecture.md` |

## Architecture (from `docs/architecture.md`)

- **Cordis underneath.** Cordis is a vendored plugin framework. In Cordis a context holds services (`ctx.tools`, `ctx.llm`, `ctx.sessions`). A plugin declares the services it needs with `inject`. Plugins talk through typed events, each with a fixed dispatch mode (`emit`, `waterfall`, `parallel`, `serial`, `bail`). Every registration is a reversible effect, so it is undone when its plugin unloads. Sources: `docs/cordis-primer.md`, and the paper the README links (arXiv 2608.25512).
- **No privileged core.** The model adapter, tool registry, session log, and agent loop are all plugins and can be swapped through configuration. The core packages are `core/session` (append-only `SessionEvent` log), `core/system-prompt`, `core/tools` (scoped registry plus guarded execution), `core/agent` (the `Agent` interface and registry), `core/agent-loop` (the default driver), and `llm/llm` (message and stream vocabulary plus the adapter seam).
- **Composition.** At startup a *profile* stacks ordered *bundles*. On top of those come YAML patch layers (`cordis.patch.yml`, the home patch, and `--patch`). Each patch replaces or inserts config rows by id. `dsh --profile web --dump-config` prints the resulting plugin tree.
- **Agent loop.** A *step* is one model request plus the tools it calls. A *turn* is zero or more steps. The flow is: `turn/start`, then claim input, then assemble prompt sections and tool schemas, then `agent/pre-step` (may rewrite or reject the input), then `step/start`, then `agent/request` and `prepareCall`, then freeze the model history derived from the log. Next the model call streams (`llm/stream`, `agent/assistant-stream`) and ends as `assistant/message`, or as `assistant/attempt` if it fails. Then come `tool/call`, the three tool hooks, and `tool/result`, then `step/end`. The loop takes another step while tool results are still owed to the model. Last come `agent/turn-stopping` and `turn/end`.
- **Session log is the source of truth.** "Model-visible means logged": every model request must be reconstructable from durable session events. `deriveMessages()` rebuilds the model history from the log. Fork, resume, transcripts, and telemetry also come from the log. Sessions are stored as versioned JSONL with migrations between versions.
- **Tool model.** Tools register on `ctx.tools`, and their schemas go into prompt assembly. Each call is logged as `tool/call` before it runs. It then goes through the `tools/pre-execute` waterfall (hooks, permission, sandbox, possibly an approval prompt), then guards that can only deny, then the `tools/execute` waterfall (timeouts, retries, metrics around the call), then `tools/post-execute`, then `finalizeContent`. Anything thrown along the way becomes an `isError` result. The model sees exactly one `tool/result` per call (`docs/tool-execution-pipeline.md`).
- **Extension points.** Events are the extension mechanism, in three groups. Session events are durable facts. `agent/*` events let plugins watch or intercept a live agent. Capability events (`fs/*`, `tools/*`, `telemetry/*`) attach policy without importing the loop. A "seam" is a service definition plus a provider plus a consumer. For example, swapping the fs/subprocess provider for a remote sandbox moves Bash, PTY, and LSP with it.
- **Models.** `llm/llm` defines streams that are provider-neutral and always end with a terminal result. Adapters include `llm-deepseek` and `llm-pi-ai`. `llm-pi-ai` supports multiple providers and any OpenAI-compatible gateway, and reads credentials per request from env references. Retries live in a separate plugin, `llm-retry` (`packages/llm/*/README.md`).

## What own-harness should borrow or compare against

Ideas worth borrowing in a thin, hand-written loop:

1. **Use the turn/step vocabulary.** A step is one model call plus its tool calls. A turn loops steps until no tool result is still owed to the model. This is the same core loop, with clean names.
2. **Make the log the source of truth.** Use an append-only event log (`user/message`, `assistant/message`, `tool/call`, `tool/result`) and rebuild model messages from it with one pure `deriveMessages()` function. Resume, fork, and transcripts then come almost for free. Persisting the log as JSONL fits a research assistant whose sessions should be reviewable.
3. **Give every tool call exactly one result.** Log the call before running it. Turn any thrown error into an `isError` result. When a step fails, record the missing results so the history stays valid for the next request.
4. **Run tools through a small middleware pipeline.** A before/around/after chain (`pre-execute` / `execute` / `post-execute`) gives you a place for approvals, timeouts, and output truncation without putting that logic in each tool.
5. **Keep a narrow model adapter seam.** Provider-neutral stream events, one attempt per call, and retries kept outside the adapter. This maps directly to one OpenRouter adapter.
6. **Freeze the request.** Build the request, freeze it, then stream it, so nothing can change it mid-call.

Things to compare against but not copy now:

- **The Cordis DI/plugin framework**, profiles and bundles, YAML patch layers, and HMR. These cost a lot of complexity to make *everything* swappable, which works against a learning-first, hand-written core. Plain TypeScript interfaces and a few hook arrays can get the same seams.
- **The full set of `agent/*` waterfall events**, request series, system-prompt surface nodes, and session-format migrations. These are production concerns for a multi-surface product (Web, desktop, SDK, ACP).
- **Using it as a dependency.** It is a breaking-change developer preview, so do not depend on it.

## Primary sources

- Repo metadata: `gh api repos/deepseek-ai/deepseek-harness` and `/releases`
- `README.md`, `SAFETY.md`, `LICENSE`, root `package.json`
- `docs/architecture.md`, `docs/cordis-primer.md`, `docs/tool-execution-pipeline.md`
- `packages/llm/llm/README.md`, `packages/llm/llm-pi-ai/README.md`
- Docs site (not read here): <https://deepseek-harness.github.io/deepseek-harness/>
