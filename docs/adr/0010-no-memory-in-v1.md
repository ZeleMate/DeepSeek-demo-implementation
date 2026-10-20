# v1 has no memory across sessions

Neither v1 job needs to remember anything between sessions. The secrets filter's lasting state is already `.gitleaksignore` (dismissals) and the session log (verdicts for threshold tuning, ADR 0004). So v1 ships no memory plugin.

Memory arrives with the PR security reviewer, as our own TypeScript re-implementation of OptMem's idea: an append-only log of one-line notes, a binary summary tree, decay-with-age wake, and regex recall ([#40](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/40)). OptMem has no license, so no code is copied. The memory-poisoning lab follows it ([#41](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/41)). A WikiSkill-style loop that improves a job's `SKILL.md` comes only after the eval produces a stable score to gate edits with ([#42](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/42)).

## Why

Memory is an attack surface: anything the agent writes down can carry an injected instruction into a later session. Adding it after the defences exist and are scored means it can be measured from the first day.

## Considered options

- **Memory in v1 for the secrets filter** (past verdicts per repo). Rejected: `.gitleaksignore` already does that job deterministically.
- **No memory at all.** Rejected: memory is a required category in the brief, and the PR reviewer benefits from it.

Decided in [Memory design](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/11). Research: research/optmem.md, research/wikiskill.md.
