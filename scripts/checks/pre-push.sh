#!/usr/bin/env bash
# Refuses pushes to main, runs gitleaks over the commits each pushed ref adds, and refuses
# commits whose author or committer email isn't a GitHub noreply address.
# Usage: pre-push.sh < refs   (lefthook pre-push, use_stdin; git sends one
#        "<local ref> <local sha> <remote ref> <remote sha>" line per ref)
set -euo pipefail

null_sha=0000000000000000000000000000000000000000
status=0
while read -r local_ref local_sha remote_ref remote_sha; do
  [[ -z "$local_ref" ]] && continue
  if [[ "$remote_ref" = "refs/heads/main" ]]; then
    echo "push to main refused: open a PR instead"; status=1; continue
  fi
  [[ "$local_sha" = "$null_sha" ]] && continue # branch deletion: nothing to scan
  if [[ "$remote_sha" = "$null_sha" ]] || ! git cat-file -e "$remote_sha^{commit}" 2>/dev/null; then
    log_opts="$local_sha --not --remotes" # new branch, or remote tip not fetched: commits no remote branch has yet
  else
    log_opts="$remote_sha..$local_sha"
  fi
  echo "gitleaks: $remote_ref ($log_opts)"
  gitleaks git --redact --no-banner --log-opts="$log_opts" || status=1
  # The repo is public, so every pushed commit must carry a GitHub noreply address, not a personal
  # email or a machine's hostname (docs/THREAT_MODEL.md T9). Set it with
  # git config user.email <id>+<login>@users.noreply.github.com.
  read -r -a range <<<"$log_opts"
  bad=$(git log --format='%ae%n%ce' "${range[@]}" | grep -vE '@users\.noreply\.github\.com$|^noreply@github\.com$' | sort -u || true)
  if [[ -n "$bad" ]]; then
    echo "push refused: $remote_ref has commits by an address that isn't a GitHub noreply one:"
    printf '  %s\n' "$bad"
    echo "  Rewrite them with: git rebase -r --exec 'git commit --amend --no-edit --reset-author' <base>"
    status=1
  fi
done
exit "$status"
