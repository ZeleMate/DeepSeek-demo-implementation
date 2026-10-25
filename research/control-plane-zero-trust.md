# Control plane and zero trust for the hardened harness

Sources:

- Ari Joury, [How to Build a Control Plane for AI Agents](https://towardsdatascience.com/how-to-build-a-control-plane-for-ai-agents/), Towards Data Science, 2026-10-02.
- OWASP, [Top 10 for Agentic Applications for 2026](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/) (ASI01–ASI10).
- OWASP, [AI Agent Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/AI_Agent_Security_Cheat_Sheet.html).
- NIST SP 800-207, Zero Trust Architecture (policy decision point / policy enforcement point split), as cited by both.

OWASP has no standalone "zero trust framework" for agents. Its zero-trust content is spread across the agentic Top 10 and the cheat sheet; the zero-trust backbone both rely on is NIST 800-207.

## The article in one paragraph

A valid tool call can still be the wrong action. A model that can pick a tool and fill its arguments has **capability**; it has **authority** only when a separately enforced policy allows a bounded action for an identified principal in the current context. Treat every model tool call as a **proposal**. Split the system into three planes: **planning** (the model proposes typed actions, holds no credentials, decides no policy), **control** (canonicalise, validate, decide allow / deny / approval-required, bind approvals, issue narrow authority, record evidence), and **execution and observation** (a broker runs a constrained adapter with narrow credentials, a verifier checks the effect really happened, and a ledger records decisions and effects). "Let the model plan. Let policy decide. Let a constrained executor act. Let an independent verifier state what happened."

## The nine steps

| # | Step | Core rule |
|---|---|---|
| 1 | Narrow, typed action contracts | Business verbs, not `http_request` / `run_shell`. Each contract states `action_id`, `schema_version`, `side_effect_class` (read_only, draft, reversible_write, external, irreversible), required scopes, risk tier, approval mode, idempotency, verification method, outbound-data rules. A schema is an interface, not an authorisation. |
| 2 | Separate authentication, delegation and approval | No ambient authority from a borrowed user token. Agent identity, human identity and delegation are distinct, attributable concepts. |
| 3 | Deterministic authorisation | Model → `ActionProposal` → gateway validates → PDP returns allow / deny / approval_required → broker (not the planner) executes. The check is outside the LLM; approval is checked against the same canonical digest that is dispatched; HTTP 200 is not success. |
| 4 | Classify actions, not agents | Tiers T0 observe, T1 draft, T2 reversible internal, T3 high impact (exact-action approval, short-lived authority), T4 critical (default deny, human runbook). Escalate when the target was inferred, when untrusted content influenced the action, when there is no idempotency or verification path, or when scope turns bulk / external / irreversible. Never demote on model confidence. |
| 5 | Bind approval to a canonical action | The approver sees the canonical effect, not the model's intent. The record holds action and schema version, principals, resolved target and parameters, tier, policy version, digest, approver, expiry, one-time nonce. Any change invalidates it. |
| 6 | Prompt injection | Provenance-label every context item; never concatenate untrusted content into instructions; **quarantine extraction** (a no-tool, no-secret model turns external content into a narrow typed summary); re-check at the execution boundary; short-lived narrow credentials; test direct, indirect, encoded, tool-output and RAG attacks. No secret in model-visible context when a secret reference will do. |
| 7 | Uncertainty, retries, compensation | Action state machine: pending / unknown / failed / verified. Persist intent and idempotency key before dispatch; verify by authoritative read-back; surface unknown instead of "done". Retry, rollback, compensation and reconciliation are different things. |
| 8 | Decision/effect record | Protected events: `run.started`, `context.ingested` (source, trust class, hash), `action.proposed`, `policy.decided` (with policy version), `approval.requested/decided`, `execution.dispatched/acknowledged`, `effect.verified/unknown/failed`, `compensation`. The audit ledger is not the chat transcript; it is tamper-evident. |
| 9 | Evaluate the control plane | Deterministic gates at 100% for contracts, authZ, approval binding; attack success rate plus blast radius for injection; canary tests for egress; duplicate-effect target 0; HTTP 200 without postcondition never reads as verified. A model judge never proves an authorisation control worked. |

## OWASP agentic Top 10 (2026)

ASI01 Agent goal hijack · ASI02 Tool misuse and exploitation · ASI03 Identity and privilege abuse · ASI04 Agentic supply chain · ASI05 Unexpected code execution · ASI06 Memory and context poisoning · ASI07 Insecure inter-agent communication · ASI08 Cascading failures · ASI09 Human–agent trust exploitation · ASI10 Rogue agents. The guiding principle is **least agency**: no more autonomy, tools or privilege than the task needs.

Zero-trust rules from the cheat sheet that go beyond the article:

- Enforce authorisation in the execution component, outside the agent's context. Fail closed for unknown tools, missing approval requirements, and failed policy lookup, risk classification or audit logging.
- Check and **consume** an approval atomically, right before execution, so concurrent or repeated calls can't reuse it.
- Only explicitly low-risk tools skip review; unmapped tools need it. Classification never grants permission on its own.
- Recursion, retry, token and cost limits (denial of wallet).
- Release gates: rerun adversarial suites when prompts, tool policies or credential scopes change; review test changes closely, because an attacker can weaken a test in the same change.

## Mapping onto what we already decided

| Concept | Already have | Gap |
|---|---|---|
| Narrow contracts (1) | Bash and PTC off; job tools call fixed binaries with fixed args (ADR 0003, 0008) | No per-tool contract metadata (side-effect class, tier, verification) |
| Identity and delegation (2) | One user, keys only in the launched process (ADR 0007) | Provider keys are ambient authority inside the dsh process; no named agent or executor identity in records |
| PDP / PEP (3) | Policy plugin at `tools/pre-execute`, every defence fails closed (ADR 0003) | Decision and enforcement are one plugin; no explicit proposal object or policy version |
| Tiers and escalation (4) | Taint escalates outbound calls to `ask` (ADR 0003) — this is the article's "untrusted content influenced the action" rule | No tier table; unmapped MCP tools have no default tier |
| Approval binding (5) | dsh approvals are `allowed-once`, tied to the tool call's `callId`, and fail closed when unanswerable | No digest of canonical arguments, no expiry, no policy version in `approval/asked` |
| Injection (6) | Injection filter fences untrusted data and sets taint; AGENTS.md of scanned repos is data (ADR 0009); masked findings (ADR 0004) | No quarantine extractor; no provenance label beyond untrusted / not |
| Effects (7) | — | No state machine or read-back for the few writes (`.gitleaksignore`, report) |
| Ledger (8) | Session log plus `plugin:zelemate-audit/*` records (ADR 0003) | Not tamper-evident; no `context.ingested` hashes |
| Eval (9) | Deterministic attack success rate, canaries, grader never mixed in (ADR 0011) | No deterministic approval-binding or contract-conformance tests |
| Supply chain (ASI04) | Own plugins only, pinned MCP tools, pinned dsh (ADR 0001, 0012) | — |

## Facts checked in dsh (`dsh-v0.2.1-rc.2`, `@deepseek-ai/dsh-user-approval`)

- `ApprovalOutcome` is `'allowed-once' | 'rejected' | 'cancelled' | 'unavailable'`. Grants apply only to the requested action; there is no "always allow".
- `approval/asked` records `toolName`, optional `callId` and `reason`. It records no argument digest, expiry or policy version.
- Session policy is `ask` (answerer chain, `unavailable` with none) or `never` (every ask rejected).
- Every Cordis plugin runs with full harness privileges, so a PDP inside the dsh process shares the agent's trust domain.
- Not yet checked: whether a tool call's arguments are frozen before `tools/pre-execute` runs. `dsh-llm` deep-freezes messages (`lib/types/message.js`), but nothing found ties that to the arguments a listener sees. ADR 0013 does not rely on it.
