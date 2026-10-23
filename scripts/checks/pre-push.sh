#!/usr/bin/env bash
# pre-push: refuses pushes to main, then runs gitleaks over the commits each pushed ref adds.
# Git passes one line per ref on stdin: <local ref> <local sha> <remote ref> <remote sha>.
set -euo pipefail

zero=0000000000000000000000000000000000000000
status=0
while read -r local_ref local_sha remote_ref remote_sha; do
  [ -z "${local_ref:-}" ] && continue
  if [ "$remote_ref" = "refs/heads/main" ]; then
    echo "push to main refused: open a PR instead"; status=1; continue
  fi
  [ "$local_sha" = "$zero" ] && continue # branch deletion: nothing to scan
  if [ "$remote_sha" = "$zero" ] || ! git cat-file -e "$remote_sha^{commit}" 2>/dev/null; then
    range="$local_sha --not --remotes" # new branch, or remote tip not fetched: commits no remote branch has yet
  else
    range="$remote_sha..$local_sha"
  fi
  echo "gitleaks: $remote_ref ($range)"
  gitleaks git --redact --no-banner --log-opts="$range" || status=1
done
exit "$status"
