#!/usr/bin/env bash
# Refuses files that must never be committed: secrets, dsh state, session logs.
# Usage: forbidden-paths.sh <file>...   (pre-commit passes staged files; CI passes `git ls-files`)
set -euo pipefail

status=0
for f in "$@"; do
  case "$f" in
    .env.example | */.env.example) ;;
    # Keep in step with the .env lines in .gitignore.
    .env | .env[._-]* | .envrc | */.env | */.env[._-]* | */.envrc)
      echo "forbidden: $f (keys live in the Keychain, ADR 0007)"; status=1 ;;
    *.pem | *.key | *.p12 | *.credentials.yaml)
      echo "forbidden: $f (credential file)"; status=1 ;;
    *dsh-home/* | *.jsonl.zstd | *session.lock)
      echo "forbidden: $f (dsh state belongs in \$DSH_HOME, outside the repo)"; status=1 ;;
    cordis.patch.yml | */cordis.patch.yml)
      echo "forbidden: $f (user-owned profile layer, ADR 0007)"; status=1 ;;
    eval/embargoed/*)
      echo "forbidden: $f (embargoed upstream bug, ADR 0015)"; status=1 ;;
    prototypes/*/out/*)
      echo "forbidden: $f (prototype run output)"; status=1 ;;
  esac
done
exit "$status"
