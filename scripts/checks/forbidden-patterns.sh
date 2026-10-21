#!/usr/bin/env bash
# Refuses commands the ADRs forbid anywhere in the repo.
# Usage: forbidden-patterns.sh <file>...
set -euo pipefail

# Docs and this script describe the rules, so they are not checked.
files=()
for f in "$@"; do
  case "$f" in
    *.md | scripts/checks/forbidden-patterns.sh) ;;
    *) [ -f "$f" ] && files+=("$f") ;;
  esac
done
[ "${#files[@]}" -eq 0 ] && exit 0

status=0
check() {
  local pattern=$1 reason=$2
  if grep -nE -- "$pattern" "${files[@]}"; then
    echo "^ forbidden: $reason"; status=1
  fi
}

check 'npx +@deepseek-ai/dsh' "npm's latest tag is a prerelease; use pnpm exec dsh (ADR 0001)"
check '--from-default-profile' 'deletes the existing profile (ADR 0001)'
check '(^|[^A-Za-z_])env +[A-Z_]*(KEY|TOKEN|SECRET)=' 'keys passed as arguments show up in ps; export them inside the launcher (ADR 0007)'
exit "$status"
