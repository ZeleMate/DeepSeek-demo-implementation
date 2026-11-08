#!/usr/bin/env bash
# Refuses pushes to main and runs gitleaks over the commits each pushed ref adds.
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
done
exit "$status"
