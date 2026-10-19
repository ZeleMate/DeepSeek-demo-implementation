# Security purpose: a hardened harness running defensive jobs, never offensive work

The harness's purpose is security, in two layers. First, a **hardened harness**: our dsh profile with five simple defences (network egress allowlist, injection filter on tool results, MCP pinning guard, canary secret, and dsh's session log as the audit trail), scored by **attack success rate** before and after against a fixed attack set. Second, **security jobs** that run on it against the user's own material. The first job is a secrets false-positive filter (gitleaks finds candidates, the Decisions API judges them, the user confirms); a security reviewer for the user's own PRs comes second.

Offensive agents (pentest, exploitation, CTF solving) and any third-party target are excluded. Red-team runs attack only our own harness, local labs bound to `127.0.0.1`, and a **victim model** that runs locally (Ollama, within this Mac's limits) or sits behind an API whose terms allow testing your own app. OpenRouter is not one of them without its approval.

## Why

- Cheap open-weight models do poorly on long offensive tasks but well on narrow defensive gates (research on issues #19 and #20).
- OpenRouter's terms ban prompt-injection and jailbreak testing against its models without written approval, and several model licences and CTF platforms forbid attack use. Unauthorised access is a crime under EU Directive 2013/40/EU and Hungary's Btk. §423–424 (issue #21).
- Every later security job needs a harness that can't be hijacked, so hardening comes first.

## Consequences

- Authorisation and scope are enforced in code (sandbox and egress policy), not in the prompt.
- Every version must have a Promptfoo number: attack success rate for the hardening, F1 on a labelled set (CredData) for each job.
- Asking OpenRouter's safety team for approval stays a later option, not a dependency.

Decided in [What security problem does the harness solve?](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/22).

_Amended 2026-10-19:_ the Mac (M5, 16 GB) can't run 7–14B local models alongside the harness. The usable local model size will be **measured**, with ≤4B assumed until then, and red-team-friendly APIs are being researched.
