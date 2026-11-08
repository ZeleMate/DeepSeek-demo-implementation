#!/usr/bin/env bash
# Refuses commands the ADRs forbid anywhere in the repo.
# Usage: forbidden-patterns.sh <file>...
set -euo pipefail

# Docs and this script describe the rules, so they are not checked.
files=()
for f in "$@"; do
  case "$f" in
    *.md | scripts/checks/forbidden-patterns.sh) ;;
    *) [[ -f "$f" ]] && files+=("$f") ;;
  esac
done
[[ "${#files[@]}" -eq 0 ]] && exit 0

status=0
check() {
  local pattern=$1 reason=$2
  if grep -inE -- "$pattern" "${files[@]}"; then
    echo "^ forbidden: $reason"; status=1
  fi
}

q="[\"']?" # optional quote before an assignment

# A one-off runner (npx, bunx, yarn dlx, pnpm dlx, npm exec/x, flags allowed) that names the
# package in the same command fetches npm's latest tag. The match stops at ; | & and #.
check "(^|[^a-z0-9_-])(npx|bunx|yarn[[:space:]]+dlx|pnpm([[:space:]]+-[^[:space:]]+)*[[:space:]]+dlx|npm([[:space:]]+-[^[:space:]]+)*[[:space:]]+(exec|x))[[:space:]][^;|&#]*@deepseek-ai/dsh([^a-z0-9_-]|$)" "npm's latest tag is a prerelease; use pnpm exec dsh (ADR 0001)"
check '--from-default-profile' 'deletes the existing profile (ADR 0001)'
# A secret-named assignment among env's own arguments: flags (with values) and other
# assignments may come first; the first other word is the command, and the match stops there.
# Lines are checked one at a time, so a command continued with a trailing \ is not seen whole.
check "(^|[^a-z0-9_.-])env([[:space:]]+(-[a-z]*[ucs]([[:space:]]+[^[:space:]]+)?|-[a-z]+|--(unset|chdir|split-string)[[:space:]]+[^[:space:]]+|--([a-z-]+(=[^[:space:]]*)?)?|${q}[a-z_][a-z0-9_]*=[^[:space:]]*))*[[:space:]]+${q}[a-z0-9_]*(key|token|secret|password)[a-z0-9_]*=" 'keys passed as arguments show up in ps; export them inside the launcher (ADR 0007)'
exit "$status"
