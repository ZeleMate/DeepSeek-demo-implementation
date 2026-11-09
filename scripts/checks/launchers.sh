#!/usr/bin/env bash
# Tests what the launchers in bin/ hand to dsh, with a stub dsh: no model, no key, no Keychain.
# Usage: launchers.sh
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A copy of the launchers next to a stub dsh that prints the environment it was started with.
mkdir -p "$tmp/repo/bin" "$tmp/repo/bundles/redteam" "$tmp/repo/node_modules/.bin" "$tmp/stubs"
cp "$repo/bin/dsh-job" "$repo/bin/dsh-redteam" "$tmp/repo/bin/"
cp "$repo"/bundles/redteam/*.Modelfile "$tmp/repo/bundles/redteam/"
printf '#!/bin/sh\nenv\n' >"$tmp/repo/node_modules/.bin/dsh"
printf '#!/bin/sh\nexit 0\n' >"$tmp/stubs/ollama"
chmod +x "$tmp/repo/node_modules/.bin/dsh" "$tmp/stubs/ollama"

status=0
fail() { echo "FAIL: $1"; status=1; }

# A fresh root whose profile already lists the launcher's bundle, so the stub never has to add it.
fresh_root() {
  local profile=$1 home=$2 bundle=$3 root
  root=$(mktemp -d "$tmp/root.XXXXXX")
  mkdir -p "$root/$home/profiles/$profile"
  printf '{"dsh":{"profile":{"bundles":["%s"]}}}\n' "$bundle" >"$root/$home/profiles/$profile/package.json"
  printf '%s\n' "$root"
}

# Starts a launcher with a shell full of things that must not reach dsh, plus any extra
# NAME=value assignments given after the root, exported in a subshell.
launch() {
  local launcher=$1 root=$2
  shift 2
  (
    for assignment in "$@"; do export "${assignment?}"; done
    PATH="$tmp/stubs:$PATH" DSH_DEMO_ROOT="$root" DSH_DEMO_NO_KEYS=1 \
      AUDIT_PLAIN=leak OPENAI_API_KEY=leak DEEPSEEK_API_KEY=leak DEEPSEEK_BASE_URL=leak \
      DSH_PERMISSION_MODE=danger-full-access DSH_TOOLS_MODE=leak DSH_TELEMETRY_OTLP_URL=leak \
      HTTPS_PROXY=leak NODE_OPTIONS=leak "$tmp/repo/bin/$launcher"
  )
}

# Expects the launcher to stop before dsh starts, with a message matching the pattern, so a
# failure for some other reason doesn't count as the guard working.
refuses() {
  local launcher=$1 root=$2 pattern=$3 label=$4 out
  shift 4
  if out=$(launch "$launcher" "$root" "$@" 2>&1); then
    fail "$launcher started with $label"
  elif ! grep -q -- "$pattern" <<<"$out"; then
    fail "$launcher stopped with $label, but not at its guard: $out"
  fi
}

check() {
  local launcher=$1 profile=$2 home=$3 bundle=$4 workspace=$5 sentinel=$6 root out
  root=$(fresh_root "$profile" "$home" "$bundle")

  if ! out=$(launch "$launcher" "$root" 2>&1); then
    fail "$launcher did not start: $out"
  elif grep -q 'leak\|danger-full-access' <<<"$out"; then
    fail "$launcher passed the calling shell's environment to dsh: $(grep 'leak\|danger-full-access' <<<"$out" | cut -d= -f1 | tr '\n' ' ')"
  elif ! grep -q '^DSH_TELEMETRY_DISABLED=1$' <<<"$out"; then
    fail "$launcher did not turn telemetry off"
  fi

  # Setting the re-run marker by hand must not skip the cleanup.
  root=$(fresh_root "$profile" "$home" "$bundle")
  refuses "$launcher" "$root" "is set; start $launcher without" "a forged $sentinel" "$sentinel=1"

  for stray in "$workspace/.env" "$home/.env" "$home/.credentials.yaml"; do
    root=$(fresh_root "$profile" "$home" "$bundle")
    mkdir -p "$root/$(dirname "$stray")"
    : >"$root/$stray"
    refuses "$launcher" "$root" "$stray exists" "a stray $stray"
  done

  for stray in AGENTS.md CLAUDE.local.md .agents; do
    root=$(fresh_root "$profile" "$home" "$bundle")
    mkdir -p "$root/$workspace"
    : >"$root/$workspace/$stray"
    refuses "$launcher" "$root" "$workspace/$stray exists" "a stray $workspace/$stray"
  done

  root=$(fresh_root "$profile" "$home" "$bundle")
  printf -- '- id: x\n' >"$root/$home/cordis.patch.yml"
  refuses "$launcher" "$root" "must be exactly \[\]" "a non-empty home patch"

  root=$(fresh_root "$profile" "$home" "not-our-bundle")
  refuses "$launcher" "$root" "refusing to start" "no bundle"
}

check dsh-job job home @zelemate/dsh-bundle-job workspace/job DSH_JOB_CLEAN_ENV
check dsh-redteam redteam redteam/home @zelemate/dsh-bundle-redteam workspace/redteam DSH_REDTEAM_CLEAN_ENV

if [[ "$status" -eq 0 ]]; then echo "launchers ok"; fi
exit "$status"
