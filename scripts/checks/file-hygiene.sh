#!/usr/bin/env bash
# Refuses merge-conflict markers and files over 1 MB.
# Eval fixtures and datasets don't belong in git (ADR 0011 keeps only summaries).
# Usage: file-hygiene.sh <file>...
set -euo pipefail

status=0
for f in "$@"; do
  [ -f "$f" ] || continue
  if grep -nE '^(<<<<<<<|>>>>>>>)( |$)' "$f"; then
    echo "^ conflict marker in $f"; status=1
  fi
  if [ "$(wc -c <"$f")" -gt 1048576 ]; then
    echo "too large: $f (over 1 MB)"; status=1
  fi
done
exit "$status"
