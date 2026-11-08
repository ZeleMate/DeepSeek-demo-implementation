#!/usr/bin/env bash
# The $0 upgrade check (ADR 0001): every dsh upgrade PR must pass it. No remote model is reachable.
# Usage: pnpm check:upgrade [--update]
#   --update rewrites the config snapshots; review their diff in the upgrade PR.
# Needs Ollama running locally with qwen3.5:2b pulled.
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
here=$repo/scripts/upgrade-check
snapshots=$here/snapshots
job=$repo/bin/dsh-job
update=false
[[ "${1:-}" = --update ]] && update=true

# A throwaway DSH_DEMO_ROOT: a fresh profile, no Keychain reads, nothing left behind.
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export DSH_DEMO_ROOT=$root DSH_DEMO_NO_KEYS=1
# Ollama ignores the key; pi-ai needs one set. Not a secret.
export OLLAMA_API_KEY=ollama

failed=()
step() { printf '\n== %s\n' "$1"; }
fail() { echo "FAIL: $1"; failed+=("$1"); }

step "Frozen install (fails if the pi-ai patch no longer applies)"
(cd "$repo" && pnpm install --frozen-lockfile) || fail "frozen install"

step "pi-ai: exactly one version, installed patched"
pi_ai=$(cd "$repo/node_modules/.pnpm" && find . -maxdepth 1 -name '@earendil-works+pi-ai@*' | sed 's#^\./##')
echo "$pi_ai"
if [[ "$(printf '%s\n' "$pi_ai" | grep -c .)" -ne 1 ]] || [[ $pi_ai != *_patch_hash=* ]]; then
  fail "pi-ai is not a single patched copy"
fi

step "Typecheck and tests"
(cd "$repo" && pnpm -r --if-present run typecheck && pnpm -r --if-present test) || fail "typecheck or tests"

# Compares one dump with its committed snapshot, or rewrites the snapshot with --update.
snapshot() {
  local name=$1 file=$snapshots/$1 actual=$root/$1
  shift
  # The schema embeds the working directory as a default; drop the throwaway root from it.
  if ! "$job" "$@" 2>/dev/null | sed "s#$root#<root>#g" >"$actual"; then
    fail "$name: dsh exited non-zero"
    return
  fi
  if $update; then
    cp "$actual" "$file"
    echo "updated $name"
  elif diff -u "$file" "$actual"; then
    echo "matches $name"
  else
    fail "$name differs from its snapshot (rerun with --update and review the diff)"
  fi
}

step "Config dump against its snapshot"
snapshot config.yml --dump-config

step "Config schema against its snapshot"
snapshot config-schema.json --dump-config-schema

# Checks dsh's plumbing, not the model: a 2B model's answer is too noisy to gate an upgrade on.
step "Headless smoke turn on local Ollama"
if ! curl -sf http://127.0.0.1:11434/api/tags >/dev/null; then
  fail "Ollama is not running on 127.0.0.1:11434"
else
  if "$job" --patch "$here/ollama.patch.yml" --json "What is 17+25? Reply with only the number." \
    >"$root/smoke.out" 2>"$root/smoke.err"; then
    tail -n 1 "$root/smoke.out" | cut -c1-200
    grep -q '"type":"final"' "$root/smoke.out" || fail "smoke turn ended without a final answer"
    grep -q '\[zelemate-hello\] loaded' "$root/smoke.err" || fail "our plugin didn't load"
    find "$root/home/sessions" -name '*.jsonl' -exec grep -l '"provider":"ollama"' {} + >/dev/null ||
      fail "the session log doesn't show the ollama route answering"
  else
    tail -n 5 "$root/smoke.err"
    fail "smoke turn exited non-zero"
  fi
fi

step "Resume a session from the previous dsh version"
# Added with the first upgrade: commit a session written by the old pin, resume it with --session-id.
echo "skipped: no previous dsh version yet"

echo
if [[ "${#failed[@]}" -eq 0 ]]; then
  echo "upgrade check passed"
else
  printf 'upgrade check failed:\n'
  printf '  - %s\n' "${failed[@]}"
  exit 1
fi
