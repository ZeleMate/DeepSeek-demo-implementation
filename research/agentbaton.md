# AgentBaton: should the job profile hand off once instead of routing per turn?

Research for [#106](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/106). Read on 2026-11-01 from the paper's arXiv HTML version, [arXiv 2610.35959v1](https://arxiv.org/abs/2610.35959) (25 Oct 2026, CC BY 4.0). Section numbers below refer to that version.

## Answer

The paper's idea fits the job profile's model routing (ADR 0006), not the defences. It is a `later` item for the PR security reviewer, because that is our first long, multi-step job. It gets measured against Switchyard before any ADR changes. There is no tooling to adopt: the paper links no code and no detector weights, and a Hugging Face search on 2026-11-01 found none. We bring in the idea only.

## What the paper finds

The paper studies one-time **handoffs** inside a single agent task. A source model works for some steps, then a receiving model inherits the workspace and continues until the end, never switching back (§2). It runs mini-SWE-agent on Terminal-Bench 2.1 and DeepSWE v1.1, with GPT-5.6 Sol, Kimi K3, GLM-5.3, Claude Opus 5 and Gemini 3.8 Flash as capable models and Qwen 3.8 27B and GPT-5.6 Luna as efficient ones (§2, §4.3).

- **Direction matters.** Efficient-to-capable handoffs lose accuracy or save little. GPT-5.6 Sol taking over from Qwen at 30% saves only 6.1% (§3.2). Capable-to-efficient handoffs at the right stage keep accuracy and cut cost. Kimi K3 handing off at 45% keeps 72.6% against 73.5% at 61.5% lower cost (§3.2).
- **Once is enough.** A learned one-time handoff costs 46.7–86.6% less than MTRouter, a per-turn router, with equal or better accuracy (§4.4, Table 4). The paper reads this as a sign that frequent switching piles up errors the capable model must keep recovering from (§3.2).
- **Readiness has a shape.** A handoff works once three things hold: a substantive implementation or artifact exists, running or inspecting it has produced task-relevant feedback, and the remaining work is local diagnosis, repair, validation or finishing (§3.3). Failed feedback counts if it narrows the problem.
- **The capable model won't reliably hand off when prompted.** Kimi K3 handed off on 0 of 113 tasks and GLM-5.3 on 6 of 113. GPT-5.6 Sol always did, but still cost $3.75 against $5.32 (§4.1, Table 2).
- **A small detector decides.** AgentBaton is Qwen 3.5 2B fine-tuned on 4,000 SWE-rebench V2 trajectories labelled by Codex against the three readiness signs. After each step it outputs `{"judgement":"HANDOFF_READY"}` or `{"judgement":"HANDOFF_NOT_READY"}`, and the first ready hands off (§4.2). Past its context limit it drops the oldest half of the history, keeping the system prompt and the task. Median latency is 338 ms on one H100.
- **Results.** Across 11 model pairs and two benchmarks it cuts API cost by 65.9% on average. 12 of 22 settings improve or lose less than 5% relative accuracy. Opus 5 handing off to GPT-5.6 Luna rises from 67.3% to 76.1% on DeepSWE at 70.5% lower cost (§4.3, Table 3). A fixed-turn handoff at the same mean turn is consistently less accurate (§4.4).
- **Two ways to pass history.** In-context transfer replays the conversation in the receiving model's format. Log-file transfer writes one `.jsonl` record per source step (response, commands, return codes, stdout, stderr) that the receiving model reads with shell tools (§2). Log files suit efficient-to-capable handoffs. For capable-to-efficient ones the better method depends on the source model; models that hide their reasoning do better with the log file (§3.1).

Caveats: the benchmarks are coding and terminal tasks, not security review. The detector was trained on coding trajectories with an expensive model labelling them. Cost counts local models as free.

## How it maps to this repo

| Paper | Here |
|---|---|
| Turn | **Step** (CONTEXT.md) |
| Capable model | Opus 5.5 via OpenRouter (ADR 0006) |
| Efficient model | DeepSeek V4.1 Flash via OpenRouter. The paper's Qwen 3.8 27B doesn't fit the 16 GB Mac (ADR 0002 amendment) |
| Handoff detector | A `handoff_ready` **Decision** behind the `ctx.decisions` seam ([#68](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/68)) |
| In-context transfer | dsh's replay of the **session log**, which survived model switches in the Switchyard prototype ([#33](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/33)) |
| Log-file transfer | A `.jsonl` export of the session log |

ADR 0006 does what the paper finds weakest. The job profile runs cheap by default and Switchyard escalates to Opus turn by turn. That is efficient-first and per-turn. The paper's evidence comes from coding benchmarks with other model pairs, so it is a reason to measure, not to switch.

## Decisions

These were agreed on 2026-11-01 while placing the paper.

- **Timing.** A `later` issue and this note. No ADR changes now, and the M2–M7 order of ADR 0012 stands.
- **Job.** The PR security reviewer (v1.2). The secrets filter is out of scope: it makes one Decision per finding, so there is nothing to hand off.
- **Switchyard.** Kept. The handoff is measured against it, and ADR 0006 is amended only if the handoff wins on both cost and accuracy.
- **Decider.** A `handoff_ready` Decision behind `ctx.decisions`. A fixed-turn handoff is the baseline to beat. Prompting the capable model to hand off is rejected (§4.1). A decider error keeps the task on the capable model.
- **Backend.** Local `qwen3.5:2b` first, with the paper's rule of dropping the oldest half of the history. It is free and nothing leaves the machine. The Decisions API is a second backend in the [#51](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/51) comparison, and only ever sees masked findings (ADR 0004).
- **Context transfer.** In context by default. The log file is the option tested against it, recorded as `context.ingested` with an untrusted trust class (ADR 0013).
- **Security.** The handoff is a boundary. Taint carries over. After a handoff the policy can only stay the same or get stricter: same tiers, never more authority. The ledger records `handoff.decided` with the step, the probability, the decider backend and both model ids, and the principals name the acting model (ADR 0013).
- **Attack cases.** An injection planted before the handoff, aimed at the weaker model that inherits it. A planted file that tries to make the decider hand off early.
- **Measurement.** A fixed set of PR-review tasks on our own repos with planted flaws. A deterministic check decides whether each flaw was found, and cost per task comes from OpenRouter's generation endpoint (ADR 0005). Five setups: Flash only, Opus only, Switchyard, fixed-turn handoff, Decision handoff. Spend cap about $2–5, as in #33.
- **Vocabulary.** The terms below stay here until code uses them, then move into CONTEXT.md.

## Proposed terms

**Handoff**: the one-time switch, within a task, from the capable model to the efficient model, which inherits the workspace and history and finishes the task. _Avoid_: escalation, routing, switch.

**Capable model**: the stronger, more expensive model that starts a task. _Avoid_: big model, premium model.

**Efficient model**: the cheaper model that finishes a task after a handoff. _Avoid_: small model, fallback.
