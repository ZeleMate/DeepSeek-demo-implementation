---
status: accepted
---

# Adopt the repo template and keep this repo's stricter choices

The owner keeps a shared baseline in [ZeleMate/repo-template](https://github.com/ZeleMate/repo-template): security scanning, Dependabot cooldowns, agent instructions, a threat model and setup docs. This repo predates it and already has its own, stricter CI. We adopt the template at v0.3.0 and record the answers in `.copier-answers.yml`, so `copier update` can bring later versions in as a 3-way merge.

## What we take

- `security.yml`: Semgrep CE and OSV-Scanner on every PR and weekly, behind a new `ci-ok` job in `ci.yml`.
- The template update check, the CI tools lock in `.github/tools/`, and Dependabot for it.
- A 7-day supply-chain cooldown for pnpm (`minimumReleaseAge`) and npm Dependabot updates, plus pnpm's `trustPolicy: no-downgrade`.
- `.claude/` settings, review agent and `spec-review` skill, `CLAUDE.md`, `REVIEW.md`, `CONTRIBUTING.md`, issue and PR templates, `.editorconfig`.
- The threat model, agent policy, secrets, dependency and setup docs, adapted to the ADRs here.
- `scripts/bootstrap-github.sh` and `.github/rulesets/main.json`, adapted to our branch flow.
- The MIT licence: `LICENSE`, `LICENSES/MIT.txt` and `REUSE.toml`. `REUSE.toml` also credits the pi-ai patch and the dsh config snapshots, which are MIT too.

## What we keep

- **Lefthook, not pre-commit.** The hooks and `scripts/checks/` are mirrored in CI job by job, and `ci-ok` sums those jobs up for the rulesets.
- **Our Claude reviews (ADR 0014).** They read only trusted authors' text and deny `/proc`, which the template's `claude-review.yml` doesn't do.
- **The branch flow.** PRs squash-merge into `development`, and `main` takes only merge commits from `development`. The template assumes squash-only on `main`, so the bootstrap script and ruleset are changed to match.
- **Our ADRs in `docs/adr/`.** The template's `docs/decisions/` and its first two ADRs are not copied. Its solo-maintainer review exception is this ADR's last section.
- **Our `SECURITY.md` and ADR 0015.** They are stricter on embargo and response time.
- **Our eval approach (ADR 0011).** The template's Inspect AI `evals/` and its nightly workflow are left out.

## Left for later

- TypeScript lint, type check, tests and coverage (the template's `typescript` job). The repo has one JavaScript plugin so far, so the tooling comes with the first TypeScript code.
- Releases. release-please assumes squash commits on `main`, which our flow doesn't make.

## Solo maintainer: no non-author review

OpenSSF OSPS Baseline QA-07.01, the Scorecard Code-Review check and the Best Practices Badge expect someone other than the author to approve changes. This repo has one maintainer, so we accept the gap. Every change still goes through a PR under a ruleset, the required checks must pass, review threads must be resolved, and the Claude reviews run on every PR. AI review is a mitigation, not a substitute for human review. Revisit when a second maintainer joins.
