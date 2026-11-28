<!-- markdownlint-disable-next-line MD041 -->
@AGENTS.md

## Claude Code specifics

- Before opening a PR, run the `spec-review` skill (diff vs. the linked issue/ADR) and `/code-review`.
- Hard limits are enforced in `.claude/settings.json` (deny rules), lefthook and CI, not in this file.
- Path-specific rules live in `.claude/rules/`.
- Put personal preferences in `CLAUDE.local.md` only if you also keep the `@AGENTS.md` import here; Claude Code otherwise skips AGENTS.md.

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues, reached with the `gh` CLI. See [docs/agents/issue-tracker.md](docs/agents/issue-tracker.md).

### Triage labels

The five default triage labels, each named after its role. See [docs/agents/triage-labels.md](docs/agents/triage-labels.md).

### Domain docs

Single-context: one root `CONTEXT.md` and `docs/adr/`. See [docs/agents/domain.md](docs/agents/domain.md).
