# Secret values never leave the machine; models judge masked findings

The secrets filter runs gitleaks over the full git history plus the files on disk (merged by fingerprint). A model then judges each finding. Those findings are candidate **real** secrets from your own repos, and the judge is a remote API (OpenAI's Decisions API, falling back to a small open-weight model through OpenRouter). So **the secret value never leaves the machine**.

Each finding is sent as a **masked finding**: the value is replaced by a shape token (length, charset, entropy, and a known vendor prefix such as `ghp_`, `sk-` or `AKIA`), alongside the surrounding lines with any other candidates masked, the variable name and the file path. A per-repo switch keeps everything local and judges with a small local model instead.

## Why

- Sending live credentials to a third party would itself be a leak, and it would defeat the canary rule (ADR 0003). With masking, any real secret value seen in an outbound call is always a violation, and the egress policy can block it.
- The judgement needed ("is this a real, working credential?") depends on shape and context, not on the value itself.

## Consequences

- Decisions: one call per finding, with a predicate `is_real_credential` and a choice `kind` (live / test-fixture / placeholder / public-by-design / not-a-secret). At 0.8 or above it is flagged likely real and shown first; at 0.2 or below it is auto-dismissed but kept reviewable; anything in between is up to you.
- Fallback order: Decisions API → small OpenRouter model (same masked input) → you. Everything fails closed.
- Dismissed findings go into `.gitleaksignore` by fingerprint. Confirmed ones go into a local report with rotation steps. Verdicts stay in the session log for threshold tuning. The secret value is stored nowhere.

Decided in [Secrets filter: pipeline, questions and thresholds](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/24).
