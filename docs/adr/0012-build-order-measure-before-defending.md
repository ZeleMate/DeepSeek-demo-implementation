# v1 is built skeleton first, measured before it is defended, and loads only our own plugins

v1 is built in seven milestones, each a vertical slice tracked as a GitHub milestone with one issue per slice:

| Milestone | Contents | Ends with |
|---|---|---|
| **M1 Walking skeleton** | pnpm workspace, exact dsh pin plus the pi-ai patch (ADR 0001), `bundles/job`, launcher `bin/dsh-job` (ADR 0007), one trivial plugin, the $0 upgrade check | A task answered on DeepSeek V4.1 Flash; tag `v0.1` |
| **M2 Red-team baseline** | `bundles/redteam` on local Ollama, Promptfoo, the first attack set (ADR 0011), fixture search and fetch providers; **no defences** | `eval/results/v0.2.json` |
| **M3 Canary and ledger** | Per-run canary, the hash-chained ledger (ADR 0013) | Results file with the delta |
| **M4 Policy decision** | Risk-tier table, the `pre-execute` policy decision and its guard, egress allowlist, read allowlist, taint, per-turn tool-call cap, subagents off, the control-plane tests in CI | Results file with the delta |
| **M5 Injection filter** | Regex rules, then the `ctx.decisions` seam with its local backend | Results file with the delta |
| **M6 MCP pinning guard** | Lockfile, call-time guard, prompt filter (ADR 0003) | Results file with the delta |
| **M7 Secrets filter** | gitleaks tool, masking, judge, thresholds, `.gitleaksignore` and report writes with effect verification (ADR 0013), CredData F1 (ADR 0004) | Both scores committed; tag `v1.0` |

**v1 is done** when the secrets filter runs on the hardened harness and both scores are committed. After v1: the Interactive profile with Tavily (v1.1, ADR 0008), then the PR security reviewer (v1.2). The `later` issues stay outside.

The repo is tagged at the end of each milestone (`v0.1` … `v0.6`, then `v1.0`), and the tag is the `<version>` in `eval/results/<version>.json` (ADR 0011).

**Packaging.** v1 loads only plugins and skills from our own bundles. dsh's plugin manager, plugin market and filesystem skill rows are disabled in every profile, and the only MCP servers are the ones under test, pinned (ADR 0003).

**Jev and Laya** become backends to try behind the `ctx.decisions` seam later, in a judge bake-off the eval scores ([#51](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/51)). They are not in v1.

## Why

- **Skeleton first:** every later slice depends on the riskiest plumbing (npm pinning, the pi-ai patch, Keychain keys, bundle loading), so it is proven before anything else is built on it.
- **Measure before defending:** ADR 0011 scores each defence by its before/after change in attack success rate. That needs a baseline with no defences, and a working attack set is also the best test bed while each defence is built.
- **Defence order:** the canary and audit plugin come first because most deterministic checks read them. The policy plugin is next because it is the cheapest and strongest defence. The pinning guard comes last because only the MCP attacks exercise it.
- **The secrets filter comes last** because jobs run on the hardened harness (ADR 0002). Its F1 work doesn't depend on the defences, so nothing is lost by waiting.
- **No third-party plugins:** every Cordis plugin runs with full harness privileges, so one installed plugin would undo the hardening. This is revisited after v1, with its own threat model.

## Considered options

- **Secrets filter right after the skeleton**, as the motivating use case. Rejected: it would run on an unhardened harness first.
- **Build every defence, then measure.** Rejected: there would be no per-defence deltas.
- **Swap Jev in for the Decisions API now**, since it is cheaper. Rejected: the bake-off lets the eval choose instead of a guess.

_Amended 2026-10-23 by ADR 0013 ([#90](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/90)):_ M3 builds the ledger instead of a plain audit plugin, and M4 builds the control plane's policy decision instead of a standalone policy plugin. M5 and M6 deliver defences that feed that policy decision. The order is unchanged.

Decided in [Build order and milestones](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/50).
