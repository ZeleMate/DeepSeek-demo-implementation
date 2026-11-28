#!/usr/bin/env bash
# The $0 upgrade check (ADR 0001): every dsh upgrade PR must pass it. No remote model is reachable.
# Usage: pnpm check:upgrade [--update]
#   --update rewrites the config snapshots; review their diff in the upgrade PR.
# Needs Ollama running locally with qwen3.5:2b pulled, plus the red-team victim base qwen3.5:4b
# for bin/dsh-redteam, which the enabled-rows step runs.
# scripts/checks/upgrade-check.sh tests every branch offline, against stub launchers and tools.
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

failed=()
step() { printf '\n== %s\n' "$1"; }
fail() { echo "FAIL: $1"; failed+=("$1"); }

step "Frozen install (fails if the pi-ai patch no longer applies)"
(cd "$repo" && pnpm install --frozen-lockfile) || fail "frozen install"

step "pi-ai: exactly one version, installed patched"
# Read from the lockfile's snapshots, which the frozen install above just installed. A local
# node_modules/.pnpm keeps folders of versions it no longer uses, so it can list an old pi-ai.
pi_ai=$(awk '/^snapshots:/{s=1; next} s && /^  '"'"'?@earendil-works\/pi-ai@/{print $1}' "$repo/pnpm-lock.yaml")
echo "$pi_ai"
if [[ "$(printf '%s\n' "$pi_ai" | grep -c .)" -ne 1 ]] || [[ $pi_ai != *patch_hash=* ]]; then
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

# The bundles turn base rows off one by one, so a row a dsh upgrade adds starts on (AgentTeam in
# 0.2.2-rc.2 did). --update rewrites the snapshots above but never these lists: a new row needs a
# hand edit, here or in the bundle (ADR 0003).
step "Enabled rows match enabled-rows/ (ADR 0003)"
for profile in job redteam; do
  expected=$here/enabled-rows/$profile.txt
  actual=$root/enabled-rows.$profile.txt
  if ! "$repo/bin/dsh-$profile" --dump-config >"$root/dump.$profile.yml" 2>"$root/dump.$profile.err"; then
    tail -n 5 "$root/dump.$profile.err"
    fail "$profile: --dump-config exited non-zero"
    continue
  fi
  awk -f "$here/enabled-rows.awk" "$root/dump.$profile.yml" | sort >"$actual"
  if diff -u <(grep -v '^#' "$expected" | sort) "$actual"; then
    echo "matches enabled-rows/$profile.txt ($(grep -c . "$actual") rows)"
  else
    fail "$profile: enabled rows differ from enabled-rows/$profile.txt (+ is on now; disable it in the bundle or add it by hand)"
  fi
done

# Checks dsh's plumbing, not the model: a 2B model's answer is too noisy to gate an upgrade on.
step "Headless smoke turn on local Ollama"
# The overlay's default model is the tag built from smoke.Modelfile.
smoke_tag=$(sed -n 's/^ *model: //p' "$here/ollama.patch.yml")
smoke_base=$(sed -n 's/^FROM //p' "$here/smoke.Modelfile")
if ! curl -sf http://127.0.0.1:11434/api/tags >/dev/null; then
  fail "Ollama is not running on 127.0.0.1:11434"
elif ! command -v ollama >/dev/null 2>&1; then
  fail "the ollama CLI is not on PATH"
elif ! ollama show "$smoke_base" >/dev/null 2>&1; then
  # Checked first so `ollama create` never downloads the base.
  fail "$smoke_base is missing; run 'ollama pull $smoke_base'"
elif ! ollama create "$smoke_tag" -f "$here/smoke.Modelfile" >/dev/null 2>&1; then
  # Recreated every run, so a changed Modelfile always takes effect.
  fail "could not create the smoke model from smoke.Modelfile"
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

step "A wider --permission-mode is refused (ADR 0003)"
# Since dsh 0.2.2, headless applies --permission-mode over the sandbox row. The bundle keeps
# read-only as the only preset, so this must fail before any model call. The Ollama overlay keeps
# a regression on the local model instead of the profile's remote route.
if "$job" --patch "$here/ollama.patch.yml" --permission-mode danger-full-access --json "Reply with only OK." \
  >"$root/permission.out" 2>"$root/permission.err"; then
  fail "--permission-mode danger-full-access was accepted"
elif ! grep -q 'unknown preset "danger-full-access"' "$root/permission.err"; then
  tail -n 5 "$root/permission.err"
  fail "--permission-mode danger-full-access failed, but not as an unknown preset"
else
  grep 'unknown preset' "$root/permission.err"
fi

step "An inactive row stops the launch (ADR 0003)"
# dsh only warns about a row that did not activate, then runs the session. The launcher's startup
# check must refuse first, before any model call, and dsh's warning must keep the header and row
# line that bin/lib/launcher.sh and eval/lib/activation.ts read.
if "$job" --patch "$here/ollama.patch.yml" --patch "$here/inactive-row.patch.yml" --json "Reply with only OK." \
  >"$root/inactive.out" 2>"$root/inactive.err"; then
  fail "a launch with an inactive row started"
elif ! grep -q 'refusing to start an undefended job run' "$root/inactive.err"; then
  tail -n 5 "$root/inactive.err"
  fail "a launch with an inactive row failed, but not at the startup check"
elif ! grep -qx 'dsh: warning: 1 entry did not activate' "$root/inactive.err" ||
  ! grep -q '^upgrade-check-missing (@zelemate/dsh-upgrade-check-missing): ' "$root/inactive.err"; then
  cat "$root/inactive.err"
  fail "dsh's did-not-activate warning changed its text; update bin/lib/launcher.sh and eval/lib/activation.ts"
else
  grep 'did not activate' "$root/inactive.err"
fi

step "Resume a session from the previous dsh version"
# resume/<version>/<id>.v4.jsonl is one session the previous pin wrote. It is synthetic: one
# prompt to the local smoke model, with the throwaway root replaced by <root>. It lives outside a
# sessions/ folder because .gitignore and forbidden-paths.sh keep real session logs out of git.
# On each upgrade, replace it with a session written by the pin being left.
# dsh files sessions under a folder named after the workspace, which the smoke turn just created.
# `|| true`: a missing folder must reach the fail branches below, not end the script under set -e.
fixture=$(find "$here/resume" -name '*.v4.jsonl' 2>/dev/null || true)
sessions_dir=$(find "$root/home/sessions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)
sessions_dir=${sessions_dir%%$'\n'*}
if [[ "$(printf '%s' "$fixture" | grep -c .)" -ne 1 ]]; then
  fail "resume/ must hold exactly one session fixture, from the pin being left"
elif [[ -z $sessions_dir ]]; then
  fail "the smoke turn left no sessions folder to resume into"
else
  session_id=$(basename "$fixture" .v4.jsonl)
  echo "resuming $session_id from $(basename "$(dirname "$fixture")")"
  mkdir -p "$sessions_dir/$session_id"
  resumed=$sessions_dir/$session_id/session.v4.jsonl
  # dsh checks the log's cwd against the resolved path (on macOS /var is a link to /private/var).
  # The path is escaped for sed's replacement, where \, & and the # delimiter are special.
  real_root=$(cd "$root" && pwd -P | sed 's/[\\&#]/\\&/g')
  sed "s#<root>#$real_root#g" "$fixture" >"$resumed"
  if "$job" --patch "$here/ollama.patch.yml" --session-id "$session_id" --json \
    "Which word did I ask you to remember? Reply with only the word." \
    >"$root/resume.out" 2>"$root/resume.err"; then
    tail -n 1 "$root/resume.out" | cut -c1-200
    grep -q '"type":"final"' "$root/resume.out" || fail "resumed turn ended without a final answer"
    grep -q '"type":"turn/start","seq":[0-9]*,"time":[0-9]*,"data":{"turn":2}' "$resumed" ||
      fail "the resumed turn wasn't appended to the old session log"
  else
    tail -n 5 "$root/resume.err"
    fail "resumed turn exited non-zero"
  fi
fi

echo
if [[ "${#failed[@]}" -eq 0 ]]; then
  echo "upgrade check passed"
else
  printf 'upgrade check failed:\n'
  printf '  - %s\n' "${failed[@]}"
  exit 1
fi
