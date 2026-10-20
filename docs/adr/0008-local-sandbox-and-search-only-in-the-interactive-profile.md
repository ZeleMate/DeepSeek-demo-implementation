# Jobs run on the local sandbox; web search exists only in the Interactive profile

**Sandbox.** gitleaks and later job tools run under dsh's `sandbox-local` in read-only mode, behind our policy plugin (ADR 0003). Each job tool calls its binary with fixed arguments and no shell. There is no Docker or cloud backend in v1.

**Search.** dsh's default web search (`web-search-deepseek`) is turned off in every profile, because it sends queries to DeepSeek's API with `DEEPSEEK_API_KEY`. We write a Tavily provider for dsh's `web` service (`@zelemate/dsh-web-search-tavily`). It is enabled only in a third bundle, `bundles/interactive`: the **Interactive profile** runs the job profile's models and all defences, plus Tavily and `web_fetch`, and you use it by hand. The job profile has neither search nor fetch. The red-team profile gets a **fixture search provider** that serves our attack pages from 127.0.0.1, so red-team runs never reach Tavily.

## Considered options

- **Docker per scan.** It is stronger, because it also limits reads and network, but it means writing a sandbox plugin before any job runs. Deferred to [#39](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/39).
- **Daytona.** Rejected: it would copy your repos, secrets included, off the machine (ADR 0004).
- **No search in v1.** Rejected: web search is a required category in the brief, and the provider seam is worth learning.
- **Tavily as a disabled row in the job bundle that you switch on per machine.** Rejected: one hand-edited row would quietly change the job profile's attack surface. A separate bundle is reviewed in PRs and scored like the others.

## Consequences

- dsh's sandbox limits writes only, so in v1 the read allowlist and the egress allowlist in the policy plugin are the only limits on reads and network (ADR 0003).
- The Interactive profile is the only one with `web_fetch` on a real network, so it is the one most exposed to indirect injection. It runs the same defences and is scored against the same attack set.
- The Tavily key follows ADR 0007 (Keychain, launcher, per-key monthly limit). Tavily's terms allow it to train on queries and results, so it never searches for anything taken from a scanned repo.

Decided in [Pick sandbox and search provider](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/13). Research: research/sandbox.md, research/web-search.md.
