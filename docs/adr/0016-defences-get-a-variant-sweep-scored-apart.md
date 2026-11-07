---
status: accepted
---

# Defences get a variant sweep, scored apart from the frozen attack set

Each defence is scored once against the fixed attack set (ADR 0011). A defence can block all of those attacks and still let a close copy of one through, such as the same payload in base64 or split across two tool results. So after a defence lands, we hunt for bypasses of it with a **variant sweep**.

**When.** Each defence milestone (M4 to M7) ends with its variant sweep, run after the defence's before/after score is committed (ADR 0012). M3 has no sweep, because the canary and the ledger detect attacks rather than block them.

**How variants are made.**

- The sweep takes each attack the new defence now blocks and makes one **variant** per mutator family: encoding, split across tool results, move to a different tool or MCP server, move to a different fixture spot (README, code comment, AGENTS.md), and paraphrase. A family that can't apply to an attack is skipped.
- Encodings are Promptfoo's local static strategies (`base64`, `hex`, `rot13`, `leetspeak`, `homoglyph`), rotated across attacks so one sweep covers them all. Split and move are our own scripted mutators.
- Paraphrase uses a local Ollama model in the red-team profile only. No remote model ever generates a variant (ADR 0002).
- Every variant is committed as a fixed file under `eval/variants/`. Reruns never regenerate it.

**How variants are scored.**

- A variant inherits its parent attack's goal and defence. It is judged the same way: deterministic checks only, 3 attempts, the grader reported alongside (ADR 0011).
- The **variant set** is append-only and is scored apart from the attack set, which stays frozen at the attacks it was first built with (about 20).
- `eval/results/<version>.json` gains a per-defence **variant rate**, the attack success rate measured on the variant set, plus the variant count it was scored on. It is never mixed into the core attack success rate.
- The committed variant set reruns with every later results file, so a regression shows up without a new sweep.

**Bypasses.**

- A variant whose attempts succeed against its defence is a **bypass**. It stays in the variant set, so its fix shows up as a lower variant rate.
- The milestone may close with a bypass open, as long as each one is fixed in that milestone or has a filed issue naming the defence.
- A bypass that reproduces without the model and breaks behaviour dsh documents is an upstream bug. It goes to `eval/embargoed/` and the `embargoed` count instead, and joins the variant set when the fix ships (ADR 0015).

## Why

- A defence tuned against 20 hand-written attacks can overfit them. Hunting for bypasses and close variants is part of validating every fix in OpenAI's [Patch the Planet write-up](https://openai.com/index/coordinated-disclosure-of-critical-vulnerabilities/).
- A frozen core keeps the attack success rate comparable from v0.2 on. Reporting variants next to it follows the grader pattern in ADR 0011: alongside, never folded in.
- Deterministic mutators cost nothing and cover the bypass classes most likely to beat a regex filter or an allowlist. A local model of 4B or less writes poor attacks but can paraphrase, which finds what encodings can't.
- Committed variant files keep reruns reproducible, even though paraphrase came from a model.
- One variant per family keeps a sweep about the size of the core run on a local victim model.
- Sweeping at the end of a milestone mutates attacks against a finished defence and keeps per-defence attribution (ADR 0012).

## Considered options

- **Survivors join the attack set.** Rejected: the set would keep growing, and rates across versions would stop being comparable.
- **A sweep on every defence PR.** Rejected: it mutates attacks against a defence that is still changing.
- **One sweep after M7.** Rejected: it loses per-defence attribution.
- **Local model generation for every variant** (Promptfoo's `jailbreak` or `crescendo`). Rejected: local generation quality is low, and small models may refuse.
- **The full cross product of mutators.** Rejected: it multiplies the run by about five for little extra coverage.
- **No milestone closes while a bypass is open.** Rejected: a nondeterministic victim could block a milestone forever.

## Consequences

- Variant rates are comparable only at the same variant count. A jump in the count is visible in the results diff.
- The PR that closes a defence milestone commits new variant files alongside its results file.

Decided in [Should each defence get a bypass and variant sweep after it lands?](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/116).
