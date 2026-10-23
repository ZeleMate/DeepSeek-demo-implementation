#!/usr/bin/env bash
# Requires a conventional-commit subject: type(scope): summary
# Usage: commit-message.sh <message-file>   (commit-msg hook; CI pipes the PR title, which becomes the squash commit)
set -euo pipefail

types='feat|fix|docs|chore|ci|test|refactor|perf|build|style|research|prototype'
subject=$(head -1 "${1:-/dev/stdin}")
if ! printf '%s\n' "$subject" | grep -qE "^(Merge |Revert )|^($types)(\([a-z0-9-]+\))?!?: .+"; then
  echo "must start with type(scope): summary, e.g. 'docs: ADR 0013' (types: ${types//|/, })"
  echo "got: $subject"
  exit 1
fi
