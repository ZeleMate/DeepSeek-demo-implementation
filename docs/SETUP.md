# Setup checklist — DeepSeek demo implementation

Adapted from the repo template (v0.3.0) for a **public** repo on GitHub **Free** with this repo's branch flow: PRs squash-merge into `development`, and `main` moves only by a merge commit from `development` (ADR 0016).

## Automated

`./scripts/bootstrap-github.sh` (run with `--dry-run` first) does:

- [ ] Squash merges for PRs, merge commits for `development` into `main`, PR title as commit message, auto-delete branches
- [ ] Read-only default `GITHUB_TOKEN`; Actions must be pinned to full SHAs
- [ ] Dependabot alerts and security updates
- [ ] Secret scanning + push protection, private vulnerability reporting, CodeQL default setup, approval before fork PR workflows run for every outside contributor
- [ ] Ruleset `Protect main` from `.github/rulesets/main.json`: PR required, merge commits only, `ci-ok` required, review threads resolved, no force-push/delete

Run the script only after `ci-ok` has run once on `main`, because the ruleset requires that check.

The `Protect development`, `Protect version tags` and `Copilot review on every PR` rulesets are managed by hand in the GitHub UI.

## Manual steps

1. **Account security (once per account):** passkey or security key on GitHub.
1. **Hooks:** `brew bundle`, then `lefthook install` (see [README.md](../README.md)).
1. **Commit email:** `git config user.email <id>+<login>@users.noreply.github.com`. The pre-push hook refuses any other author or committer address, because the repo is public. Rewrite older commits on a branch with `git rebase -r --exec 'git commit --amend --no-edit --reset-author' <base>`.
1. **Dependabot malware alerts:** Settings → Advanced Security → enable "Malware alerts" (UI only).
1. **Claude reviews:** run `claude setup-token` and copy the token. The token often wraps onto two lines, and a copied line break breaks it, so check the length (about 108) and store it without whitespace:
   `pbpaste | tr -d '[:space:]' | wc -c`, then `pbpaste | tr -d '[:space:]' | gh secret set CLAUDE_CODE_OAUTH_TOKEN`. Copy something else afterwards to clear the clipboard. The reviews run once per PR, or by hand from the Actions tab (ADR 0014).
1. **Model API keys:** in the macOS Keychain, read by the launchers in `bin/` (ADR 0007). Never in `.env` files or GitHub secrets.
1. **Optional:** register at bestpractices.dev for the OpenSSF Best Practices Badge (passing level is reachable).
1. **Fill in** `docs/THREAT_MODEL.md` §5 and `docs/agent-policy.md` from the bundles and ADRs.
