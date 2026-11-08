---
status: reversed 2026-11-08 (#126); reviews read only trusted authors' text 2026-11-07 (https://github.com/ZeleMate/DeepSeek-demo-implementation/pull/120)
---

# CI fixes the Claude review findings and pushes them to the PR branch

## Reversed

We removed the fixer on 2026-11-08 in #126. CI no longer fixes findings or pushes to any branch. The reviews stay as advisory comments, and local Claude sessions take over the fixes.

- **Bot commits don't start CI.** A push with the job's own token starts no workflow until someone approves it, so a fix commit stalled its PR without required checks.
- **Most runs fixed nothing.** Workflows and other protected files are off limits to the fixer, so it had to leave those findings. Patches were also refused whole when they created, deleted or renamed a file.
- **It was the only job with write access.** Removing it means no CI job holds `contents: write`, which matters more now that the repo is going public.

What replaces it:

- The two reviews live in `.github/workflows/claude-review.yml`. They run once per PR, on `opened`, `ready_for_review` and `reopened`, and on demand with `workflow_dispatch`, not on every push.
- The limits below on what the reviews can read still hold: no git, one exact `gh pr comment`, only trusted authors' text, and no `/proc`.
- A local session reads the review comment, makes the fix and pushes it as the owner, so CI runs on it.

The rest of this ADR records the flow as it was.

Every PR gets two Claude reviews in CI: a code review and a security review. Until now they only commented. Now a fixer acts on their findings, and CI pushes its fix to the PR branch as one commit. Whatever it doesn't fix becomes a check on the head commit, which goes back to the PR's owner.

This puts model-written code on our branches without a human writing it first. So the flow follows ADR 0013's split: the model proposes a patch, and a plain step with no model decides what of it lands.

## The flow

- **claude-gate** looks at the head commit. If it carries a `Claude-Fix:` trailer and the bot is its author, the code review and the fixer skip it, so Claude never fixes its own fix. The security review still runs on that commit. Dependabot PRs skip the whole flow.
- **claude-code-review** and **claude-security** return structured findings and never fail on them.
- **claude-fix** gives both reviews' findings to Claude with a read-only token. It packages the result as a patch and a list of the findings it skipped. It never commits or pushes.
- **claude-push** applies the patch to a fresh checkout. Claude doesn't run in this job. It keeps only edits to files the PR already changes, minus protected files. It refuses outright a patch that creates, deletes or renames a file, or changes a mode. It commits once, with a `Claude-Fix:` trailer, and pushes. It never pushes to the default branch.
- **claude-leftovers** turns every finding that wasn't fixed into annotations on the head commit. That covers skipped findings, dropped edits, and every finding when the fix or the push fails (ADR 0003). Medium and high findings fail the check, which wakes the Claude session that owns the PR. Low ones only show as notices.

## Limits on the fixer

- **No git and no shell.** A prep step hands Claude the diff and commit log as files. The reviews may run only one exact `gh pr comment`.
- **Only trusted authors reach the model.** The repo is public, so anyone can write an issue or a comment, and an injected finding there would reach the fixer and then the PR branch. So no review can run `gh pr view` or `gh issue view`. A plain step fetches the PR text and the issues it references, with their comments, and keeps only what the owner, members and collaborators wrote.
- **File tools stay in the checkout.** Reading `/proc`, `/sys`, `~/.claude` and `~/.config` is denied, which keeps `CLAUDE_CODE_OAUTH_TOKEN` out of reach. Writes to `.git/` are denied, and a hash of git's hooks and settings taken before and after Claude runs is the second line of defence.
- **Protected files never take a fix.** These are files that run code on a developer's machine, decide what CI checks, or steer an agent. That means workflows, hook and package config, dev-machine config (`.envrc`, `Makefile`, `.vscode/`, `.devcontainer/`, Dockerfiles), `scripts/`, `bin/` (ADR 0007), `patches/`, `eval/` (ADR 0011), `plugins/` and `bundles/` (dsh runs them, and the defences live there), `prototypes/`, tests, `AGENTS.md`, `CLAUDE.md` and `.claude/`. A finding there goes to the PR's owner. So a defence never changes after its score was measured without a human making the change (ADR 0011). This leaves the fixer mostly docs to fix, which is the price of that rule.
- **Inputs are data.** The prompt tells Claude to treat the findings, the diff and the repo's files as data, never as instructions. Annotation text from the model is kept to one line, and its `@mentions` are broken before the fixer's summary is posted.
- **Each token sits in one step.** The push token is only in the push step's environment.

## Tokens

All three Claude jobs run on the owner's Claude subscription through `CLAUDE_CODE_OAUTH_TOKEN`. They share its usage limits with local Claude Code use.

`CLAUDE_FIX_TOKEN`, if set, is a fine-grained token with contents: write on this repo and without the Workflows permission, so GitHub refuses any workflow change it pushes. Without it, the push uses the job's own token. GitHub then holds the fix commit's runs as `action_required` until someone clicks "Approve and run", as seen on [ZeleMate/forge-lab#61](https://github.com/ZeleMate/forge-lab/issues/61). Until someone does, the findings the fixer left wait in the fix commit's `Claude-Fix-Left:` trailer and its PR comment, and no check shows them.

## Considered options

- **Reviews that only comment.** This was the flow before. Rejected: every finding waited for a human, even a one-line fix.
- **One job where Claude fixes, commits and pushes.** Rejected: Claude would hold a write token, and a prompt injection in the diff could use it.
- **Let the fixer touch any file.** Rejected: a fix to a hook, a workflow or a check script would run code or change what CI trusts, with no human review.

## Consequences

- Model-written commits can land on a PR branch. The squash-merge into `development` still needs a human, and the reviews can't block a merge.
- The trailer check can be faked by anyone who can push. A faked trailer only skips the code review and the fixer. The security review still runs.
- Each push starts a new round of reviews, and each round can raise new judgement calls. So the loop doesn't always settle on its own, and the PR's owner decides when a PR is done.
- PR diffs go to Anthropic's API. They are our own code, and gitleaks runs on every PR, so no secret value goes with them (ADR 0004).

Decided in [ZeleMate/DeepSeek-demo-implementation#94](https://github.com/ZeleMate/DeepSeek-demo-implementation/pull/94), after trials on [ZeleMate/forge-lab#59](https://github.com/ZeleMate/forge-lab/issues/59), [#60](https://github.com/ZeleMate/forge-lab/issues/60) and [#61](https://github.com/ZeleMate/forge-lab/issues/61).
