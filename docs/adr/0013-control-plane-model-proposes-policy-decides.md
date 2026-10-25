---
status: accepted
---

# The model proposes, a control plane decides, an executor acts

The hardened harness follows the three-plane split from [How to Build a Control Plane for AI Agents](https://towardsdatascience.com/how-to-build-a-control-plane-for-ai-agents/) and NIST SP 800-207's split between deciding and enforcing, read alongside OWASP's [Top 10 for Agentic Applications 2026](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/) and [AI Agent Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/AI_Agent_Security_Cheat_Sheet.html) (research/control-plane-zero-trust.md).

- **Planning:** the model in dsh's agent loop. Every tool call it makes is an **action proposal**, never permission.
- **Control plane:** our plugins. One **policy decision** (allow, deny or ask) per proposal, reached deterministically from the proposal, its context and the policy version, outside the model. The defences of ADR 0003 become inputs to that policy decision instead of separate gates.
- **Execution:** an **executor** seam that performs allowed actions with only the authority each needs. In v1 its provider is in-process.

This reshapes v1, not a later version: nothing is built yet, and ADR 0012's milestones keep their order. M3 becomes the ledger, M4 the policy decision and its enforcement, and M5 and M6 stay as defences feeding it. Each defence is still scored by its before/after change in attack success rate (ADR 0011).

## Risk tiers

Every tool has a **risk tier**, assigned in the policy table of each bundle's `dsh.bundle.patch`. Our own tools may declare a side-effect class as a hint, but the table wins. An MCP server never chooses its own tier.

| Tier | v1 actions | Policy decision |
|---|---|---|
| T0 observe | gitleaks scan, allowlisted file reads, `web_fetch` to an allowlisted host | allow |
| T1 draft | writing the local findings report | allow, with effect verification |
| T2 reversible | writing `.gitleaksignore`; an MCP tool under test whose pin matches the lockfile and whose arguments pass the egress allowlist | allow; `.gitleaksignore` with effect verification |
| T3 approve | an MCP tool not yet in the lockfile; any T0–T2 action once taint is set | ask (headless: `unavailable`, so denied) |
| T4 critical | an MCP tool whose pin changed; any tool missing from the table | deny |

The MCP rows follow ADR 0003's pinning guard: a pinned tool runs, a new tool needs approval on first use, and a changed tool is refused until it is re-approved into the lockfile. So headless red-team and job runs can still call the pinned MCP servers under test, and the pinning guard's attack cases measure the guard rather than a blanket denial.

Escalations stack, and a tier is never lowered, least of all because the model sounds confident.

## Enforcement on dsh's hooks

- One `tools/pre-execute` listener makes the policy decision (allow, deny or ask) with a reason code and the policy version. The defences report into it instead of each returning its own `deny`.
- A monotonic `ctx.tools.guard` enforces the hard denials (T4, unknown tool, failed policy lookup, failed ledger write). Guards can only deny, so listener order can never undo them.
- A dsh approval is `allowed-once` and tied to that call's `callId`, so it can't be replayed for another call. Whether dsh freezes a call's arguments before policy runs is not yet checked. So we record a SHA-256 over the canonical action (tool name, pin hash or, for a tool without a pin, its executor version, normalised arguments, tier, policy version) with each approval. The executor dispatches only an action whose hash matches. The hash is also the key an out-of-process executor would check.

## Ledger

ADR 0003's audit plugin becomes the **ledger**. It writes `plugin:zelemate-audit/*` records through dsh's `appendPluginRecord()`:

- `run.started`, with the principals (below)
- `context.ingested`: source, trust class and content hash, never the raw content
- `action.proposed`
- `policy.decided`: tier, reason code, policy version, canonical hash, principals
- `approval.linked`: refers to dsh's own `approval/asked` and `approval/decided` by id instead of copying them
- `execution.dispatched`
- `effect.verified`, `effect.failed` or `effect.unknown`

Each record carries the hash of the one before it, and the per-run JSON summary carries the head hash. A failed ledger write is a hard denial at the guard. The chain makes edits detectable, not impossible: `$DSH_HOME` belongs to the same macOS user as dsh.

## Effects

An action is done only when its **effect** is verified. Appends to `.gitleaksignore` are keyed by fingerprint, so repeating one changes nothing, and the executor reads the file back to confirm every intended fingerprint. The findings report is written to a temporary file, renamed into place, read back and hash-checked. The model is told `verified`, `failed` or `unknown`, never a bare "done".

## Principals and delegation

`run.started` and every `policy.decided` name the user (macOS account), profile, session id, agent id and executor (tool name plus version or pin hash). The hardened profiles turn off dsh's subagent tools, so v1 has no delegation: a child agent would otherwise act on its parent's authority without a policy decision of its own (OWASP ASI03, ASI07, ASI08). Subagents come back with a rule that a child's policy can only narrow its parent's.

## Limits

The policy decision denies any tool call past a per-turn cap, with reason `budget`. Token spend stays capped by the providers (ADR 0006, ADR 0007), because dsh only learns a run's cost afterwards from OpenRouter's generation endpoint (ADR 0005).

## Control-plane tests

A deterministic suite with no model in it runs in CI (`ci.yml`) on every PR and must pass in full: an unknown tool is denied; an MCP tool with a changed pin is denied; taint raises T0–T2 to T3; a headless T3 is denied; the hash recorded with an approval equals the hash of what was dispatched; a failed ledger write denies the call; the chain verifies and breaks when any record is edited; a `.gitleaksignore` write whose read-back fails is recorded `effect.failed`. Attack success rate stays Promptfoo's number (ADR 0011). A PR that touches the policy table and these tests together is reviewed with that in mind, because weakening a test in the same change is a known attack.

## Trust boundary

Every Cordis plugin runs with full harness privileges, and provider keys live in the dsh process's environment (ADR 0007). So in v1 the control plane shares a trust domain with the agent it controls. That is an accepted residual risk, held down by bash and PTC being off (ADR 0003) and by loading only our own plugins (ADR 0012). The executor is a seam so that an out-of-process provider, one that holds the credentials while dsh only proposes, can replace the in-process one without touching the callers.

## Considered options

- **Keep v1 as decided and add the control plane later.** Rejected: the defences would be built once as separate gates and then rebuilt around one policy decision.
- **Use the control plane only as vocabulary.** Rejected: the gaps it exposes (no tiers, no approval evidence, a ledger that isn't tamper-evident) are structural.
- **An out-of-process executor in v1.** Deferred: v1's only side effects are local file writes and outbound fetches, so a second process buys little yet. The seam keeps it cheap later.
- **Tools declare their own tier.** Rejected: a malicious MCP server would mark itself harmless (OWASP ASI02, ASI04).
- **Quarantine extraction in v1** (a no-tool, no-secret model that turns untrusted content into a typed summary). Deferred: it arrives as its own measured defence, most likely with the Interactive profile (v1.1), which is the most exposed to injection.

## Consequences

- ADR 0003, ADR 0011 and ADR 0012 are amended to match.
- "Defence" now means a detector or rule feeding a policy decision (CONTEXT.md).
- **v1 has no per-run token cap.** dsh can't count tokens live, so a long run is stopped only by the per-turn tool-call cap and the provider spending caps.

Decided in [Control plane: model proposes, policy decides](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/90). Research: research/control-plane-zero-trust.md.
