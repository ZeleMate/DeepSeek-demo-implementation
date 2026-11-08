# WikiSkill (arXiv 2608.27454): what it proposes

Research for issue #4. Read on 2026-10-18.

**Source.** Tang, Rashtchian, Ferng, Tomkins, Juan, Vu (Google Research, plus Virginia Tech). *WikiSkill: Compiling Agent Experience into Persistent Knowledge for Skill Evolution.* arXiv:2608.27454v1, 27 Aug 2026, CC BY 4.0. Abstract: <https://arxiv.org/abs/2608.27454>. I read the full text from the arXiv HTML rendering: <https://arxiv.org/html/2608.27454v1>.

The arXiv id resolves to the WikiSkill paper. Citations below use the form "§x" and point to sections of that paper. Anything marked **(analysis)** is my own inference for own-harness and does not come from the paper.

## TL;DR

- WikiSkill is an **offline skill-evolution loop**, not a runtime memory system. An agent runs on training tasks. A "Wiki Maintainer" LLM compiles the traces into a persistent markdown wiki of failure and success patterns. A "Skill Proposer" LLM reads that wiki and proposes one edit to a `SKILL.md`. The edit is kept only if the validation score goes up. Skills can be rolled back. **The wiki is never rolled back** (§1, §3.2.4).
- The key ablation: giving the proposer the persistent wiki raises Gemini-3.5-Flash from 48.7% to 63.7% on average. Letting the *executing* agent read the wiki during training lowers the result, from 63.7% to 60.9% (§5.1, Table 3).
- **There is no official code.** The paper links no repository. Several third-party GitHub repos claim to implement it. I did not review them.
- A minimal version fits a small TypeScript harness, but it needs labeled tasks with a scoring function. A personal research assistant mostly lacks those, so it needs a substitute signal **(analysis)**.

## Core idea

Prior skill-evolution methods (EvoSkill, Trace2Skill, SkillOpt) keep their lessons inside proposal histories or in the skill text itself. They "do not maintain what has been learned as a separate, evolving knowledge representation" (§1, §6). WikiSkill takes its inspiration from Karpathy's "LLM Wiki" gist (<https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f>; cited in §1). It adds a knowledge layer between raw experience and executable skills. Skills are the distilled, gated output. The wiki is the compounding knowledge that later skill edits build on.

## Data structures: a three-layer workspace (§3.1)

```text
raw/            immutable execution traces (reasoning, tool calls, outputs, answers)
  traces/<task_id>
wiki/           persistent, never reset or rolled back
  index.md        one line per pattern: "[name](wiki/patterns/name.md): PROBLEM + ROOT CAUSE + FIX"
  log.md          chronological evolution log (the paper's prose says logs.md, its prompt says log.md)
  skill-impact.md audit trail: proposal metadata, target skill, unified diff, val score, accept/reject
  patterns/*.md   one page per failure or success pattern, 10-30 lines, with workarounds
skills/<name>/  active skill set S_t
  SKILL.md        YAML frontmatter (name, description) + When to Apply / When NOT to Apply / Instructions
  PURPOSE.md      Origin + wiki patterns addressed + evolution history
```

- The outer harness writes `skill-impact.md` **programmatically** after each gating decision. No LLM writes it (§3.1, §3.2.4).
- Wiki and skill edits are **patch ops** expressed as JSON: `append`, `replace{target,content}`, and `insert_after{target,content}`, where `target` must be an exact substring. A new pattern or skill is written as full content (Appendix E.2, E.3).
- The Maintainer's output is JSON with the keys `create_patterns`, `update_patterns`, `update_index` (the full index, required), and `append_log` (required) (E.2).
- The Proposer's output is `finish({action: "create"|"patch"|"no_action", name, skill_md, purpose_md | edits})` (E.3).

## The loop (§3.2, Algorithm 1 in Appendix A.1)

```text
S = {} ; W = empty wiki
tau = score(agent+S, val)                      # baseline threshold
for t in 0..T-1:
  if tau == max: break                          # early stop
  traces = rollout(agent + S, train)            # skills injected into system prompt; NO wiki access
  sample = up to 5 failing + 3 passing traces, each capped at 15k chars   (App. C)
  W' = WikiMaintainer(W, sample)                # one LLM call: root-cause failures, extract successes
  p  = SkillProposer(index, skill-impact, outcome summary)  # ReAct, tools: read_file, finish
                                                 # must read >= 4 traces; one atomic change to ONE skill
  S' = apply(S, p)
  s  = score(agent+S', val)
  if s > tau: S, tau = S', s                    # strict improvement only
  else:       keep S                             # roll back skills only
  W = W' + append(skill-impact.md, {p, diff, s, accepted})
```

- Skills are **fully injected** into the inference agent's system prompt. There is no retrieval or triggering step. The authors chose this deliberately to remove retrieval as a confound, and they list it as a limitation (§3.2.1, Limitations).
- Cost per iteration is one Maintainer call plus K ReAct turns for the Proposer. With the full training split in one batch, that cost does not depend on the training-set size (App. D.2).
- The training, validation, and test splits are small, e.g. 16/10/85 for SealQA (Table 6).
- Results: WikiSkill has the best average score for all 5 models across 5 benchmarks (Table 1). Skills transfer across models, and sometimes the transferred skill beats the self-evolved one (Table 2).
- Limitations the authors state: there is no automated pruning of the wiki, gating is strictly greedy, retrieval is not evaluated, and very long-horizon tasks are not covered (Limitations).

## Reference code

- **Official:** none. The paper and its HTML rendering link no code repository. The only external GitHub link is Karpathy's gist. The paper does include the full Maintainer and Proposer system prompts (Appendix E), and that is most of what a re-implementation needs.
- **Unofficial:** `gh search repos wikiskill` (run on 2026-10-18) returns several third-party repos that say they implement the paper. Examples: kenhuangus/wikiskill ("Reference implementation…"), ashutoshsinghpr7/wikiskill (Hermes Agent), ranjithrajv/wikiskill (OpenCode, Claude Code, Codex CLI), poweredbyGEN/wikiskill, and siyu1231/wikiskill. None of them is by the paper's authors as far as their descriptions show. I did not review any of them.

## Could own-harness implement a minimal version? (analysis)

Yes. The mechanics are small: a few directories of markdown, two extra LLM roles with fixed prompts, a JSON patch applier (exact-substring replace, insert_after, append), and an outer loop with an accept/reject gate. None of this needs a framework. A thin TypeScript loop handles it, and the cost is a few cheap OpenRouter calls per iteration.

The hard part is the **scoring function**. WikiSkill gates every edit on a validation score over labeled tasks. A personal research assistant has no ground truth by default. Options, from simplest to most faithful:

1. **No gating.** Keep the Maintainer, so traces are compiled into `wiki/patterns`. The human approves or rejects a proposed skill patch, and the decision is still logged to `skill-impact.md`. This drops the paper's main safety mechanism, so it is a WikiSkill-inspired design and not WikiSkill itself.
2. **Gate on an eval suite.** Write a small set of research questions with checkable answers or rubric criteria, and gate edits on that score. This matches the eval tool in the brief (Promptfoo). It is the closest to the paper.
3. Run evolution as an explicit offline command (e.g. `harness evolve`) and keep it out of the chat loop. This mirrors the paper's training/validation phase split.

Design rules taken directly from the paper's results:

- Keep the wiki out of the executing agent's context during evolution runs (§5.1).
- Put one atomic change per iteration on one skill (§3.2.3).
- Never roll back the wiki, and do roll back skills (§3.2.4).
- Plan for wiki pruning, which the paper leaves unsolved (Limitations).

## Relation to agent memory (analysis, grounded where noted)

- WikiSkill is **procedural, offline, cross-task learning**. The paper itself treats harness-level "memory" optimization as complementary and out of scope (§6).
- The paper's own wiki is **not** a user-facing knowledge base. It records the *agent's own failure and success patterns* on a task family, and the paper finds the executing agent does better without reading it during evolution (§5.1).
- own-harness wants a "wiki of skills and notes" plus memory of past questions. That is a different store: declarative and user-facing. **Do not conflate the two.** Possible mapping:
  - `raw/traces` maps to the session/episode log, which can also serve as "what was I asked before".
  - `wiki/patterns` maps to a meta-knowledge store about how the agent itself performs.
  - `skills/` maps to procedural memory.
  - The user's research notes would be a fourth store, for the memory component (OptMem in the brief) to own.

## Relation to Skill / AGENTS.md conventions

- **Skills:** WikiSkill's skill format is the Agent Skills convention. It is a directory containing a `SKILL.md` with YAML frontmatter (unique name plus concise description) and full instructions (§2). The paper cites Anthropic's skills writing as the origin of the format (Zhang et al., 2025; Anthropic, 2026; §1, §6). It adds a sibling `PURPOSE.md` for provenance (§3.1). That file is a WikiSkill addition and not part of the convention as cited.
- **Progressive disclosure:** the paper credits this as a benefit of the convention (§1). Its own experiments, however, inject all skills in full (§3.2.1). A harness that loads skills by description would face the retrieval and triggering problem the paper explicitly does not evaluate.
- **AGENTS.md:** the paper does **not** mention AGENTS.md. **(analysis)** The natural analogue is that AGENTS.md is always-loaded, hand-written project guidance, close to the paper's "full injection" setting. Evolved `SKILL.md`s are machine-maintained and gated. Keeping evolved content out of AGENTS.md preserves the human/agent boundary.
