#!/usr/bin/env bash
# Tests the $0 upgrade check's every pass and fail branch offline, with no dsh, model or Ollama.
# check.sh finds the repo from its own path, so a copy of it in a fake repo runs against stub
# launchers there, plus stub pnpm, curl and ollama on PATH. The real launchers and Ollama are
# the other adapter at the same seam, used by `pnpm check:upgrade` on an upgrade PR.
# Usage: upgrade-check.sh
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The fake repo: the real check and its committed inputs, a lockfile with one patched pi-ai,
# and dump fixtures the stub launchers print.
base=$tmp/base
mkdir -p "$base/scripts" "$base/bin" "$base/fixtures" "$tmp/stubs"
cp -R "$repo/scripts/upgrade-check" "$base/scripts/"
printf 'lockfileVersion: 9.0\n\nsnapshots:\n\n  %s:\n    dependencies: {}\n' \
  "'@earendil-works/pi-ai@1.3.0(patch_hash=abc)(ws@8.22.0)'" >"$base/pnpm-lock.yaml"
cp "$repo/scripts/upgrade-check/snapshots/config.yml" "$base/fixtures/job.yml"
cp "$repo/scripts/upgrade-check/snapshots/config-schema.json" "$base/fixtures/config-schema.json"
# The red-team dump is rebuilt from its enabled-rows list, one row per line.
grep -v '^#' "$repo/scripts/upgrade-check/enabled-rows/redteam.txt" | awk '{
  id = $1; rest = substr($0, length(id) + 2); dis = ""
  if ((i = index(rest, " (disabled: ")) > 0) { dis = substr(rest, i + 12); sub(/\)$/, "", dis); rest = substr(rest, 1, i - 1) }
  print "- id: " id; print "  name: " rest; if (dis != "") print "  disabled: " dis
}' >"$base/fixtures/redteam.yml"

# The stub job launcher answers each way check.sh starts it. STUB_* variables pick a failure.
cat >"$base/bin/dsh-job" <<'EOF'
#!/bin/sh
fixtures=$(dirname "$0")/../fixtures
sessions=$DSH_DEMO_ROOT/home/sessions
session_id=
mode=smoke
while [ "$#" -gt 0 ]; do
  case $1 in
    --dump-config-schema) cat "$fixtures/config-schema.json"; exit 0 ;;
    --dump-config) cat "$fixtures/job.yml"; exit 0 ;;
    --permission-mode) mode=permission ;;
    --session-id) mode=resume; session_id=$2 ;;
  esac
  shift
done
case $mode in
  permission)
    case ${STUB_PERMISSION:-} in
      accept) echo '{"type":"final","text":"OK"}'; exit 0 ;;
      other) echo 'dsh: something else went wrong' >&2; exit 1 ;;
      *) echo 'dsh: permission: unknown preset "danger-full-access" (known: read-only)' >&2; exit 1 ;;
    esac ;;
  resume)
    log=$(find "$sessions" -path "*/$session_id/session.v4.jsonl" | head -n 1)
    [ -n "$log" ] || { echo "no session $session_id" >&2; exit 1; }
    [ "${STUB_RESUME:-}" = noappend ] ||
      echo '{"type":"turn/start","seq":9,"time":1,"data":{"turn":2}}' >>"$log"
    echo '{"type":"final","text":"walnut"}' ;;
  smoke)
    [ "${STUB_SMOKE:-}" = fail ] && { echo 'dsh: smoke failed' >&2; exit 1; }
    [ "${STUB_SMOKE:-}" = noplugin ] || echo '[zelemate-hello] loaded' >&2
    if [ "${STUB_SMOKE:-}" != nosession ]; then
      mkdir -p "$sessions/workspace-job/session-new"
      echo '{"type":"step","data":{"provider":"ollama"}}' >"$sessions/workspace-job/session-new/session.v4.jsonl"
    fi
    [ "${STUB_SMOKE:-}" = nofinal ] || echo '{"type":"final","text":"42"}' ;;
esac
EOF
cat >"$base/bin/dsh-redteam" <<'EOF'
#!/bin/sh
[ "${STUB_REDTEAM:-}" = fail ] && { echo 'dsh: redteam failed' >&2; exit 1; }
cat "$(dirname "$0")/../fixtures/redteam.yml"
EOF
cat >"$tmp/stubs/pnpm" <<'EOF'
#!/bin/sh
case $1 in
  install) [ "${STUB_PNPM:-}" != install ] ;;
  *) [ "${STUB_PNPM:-}" != tests ] ;;
esac
EOF
cat >"$tmp/stubs/curl" <<'EOF'
#!/bin/sh
[ "${STUB_OLLAMA:-}" != down ]
EOF
cat >"$tmp/stubs/ollama" <<'EOF'
#!/bin/sh
[ "$1" = show ] && [ "${STUB_OLLAMA:-}" = nobase ] && exit 1
exit 0
EOF
chmod +x "$base/bin/dsh-job" "$base/bin/dsh-redteam" "$tmp/stubs/"*

# A PATH with the stubs and the tools check.sh uses, but no ollama at all.
mkdir -p "$tmp/no-ollama"
cp "$tmp/stubs/pnpm" "$tmp/stubs/curl" "$tmp/no-ollama/"
for tool in bash env awk sed grep diff sort cp mkdir mktemp rm find cut tail basename dirname cat cmp; do
  ln -s "$(command -v "$tool")" "$tmp/no-ollama/$tool"
done

status=0
cases=0
fail() { echo "FAIL: $1"; status=1; }

# Runs the check in a fresh copy of the fake repo. setup is a shell snippet run there first
# (to break an input), the rest are NAME=value stub settings. Prints the run's output and sets
# code to its exit status.
run() {
  local setup=$1 dir
  shift
  dir=$(mktemp -d "$tmp/case.XXXXXX")
  cp -R "$base/." "$dir/"
  (cd "$dir" && eval "$setup")
  code=0
  path=$tmp/stubs:$PATH
  [[ -n "${no_ollama:-}" ]] && path=$tmp/no-ollama
  out=$(cd "$dir" && env PATH="$path" "$@" scripts/upgrade-check/check.sh ${update:+--update} 2>&1) || code=$?
  last_dir=$dir
}

# Expects the check to fail with exactly the listed failures, in order.
expect_fail() {
  local label=$1 setup=$2 want=$3 got
  shift 3
  cases=$((cases + 1))
  run "$setup" "$@"
  got=$(sed -n 's/^  - //p' <<<"$out")
  if [[ "$code" -eq 0 ]]; then
    fail "$label: the check passed"
  elif [[ "$got" != "$want" ]]; then
    fail "$label: expected failures:"$'\n'"$want"$'\n'"got:"$'\n'"$got"
  fi
}

cases=$((cases + 1))
run :
if [[ "$code" -ne 0 ]] || ! grep -q '^upgrade check passed$' <<<"$out"; then
  fail "a clean run did not pass: $out"
fi

expect_fail "frozen install" : "frozen install" STUB_PNPM=install
expect_fail "unpatched pi-ai" "sed -i.bak 's/(patch_hash=abc)//' pnpm-lock.yaml" \
  "pi-ai is not a single patched copy"
expect_fail "two pi-ai versions" "printf '  %s:\n' \"'@earendil-works/pi-ai@1.4.0(patch_hash=abc)'\" >>pnpm-lock.yaml" \
  "pi-ai is not a single patched copy"
expect_fail "typecheck or tests" : "typecheck or tests" STUB_PNPM=tests
expect_fail "config dump drift" "echo '# drift' >>scripts/upgrade-check/snapshots/config.yml" \
  "config.yml differs from its snapshot (rerun with --update and review the diff)"
expect_fail "schema drift" "echo ' ' >>scripts/upgrade-check/snapshots/config-schema.json" \
  "config-schema.json differs from its snapshot (rerun with --update and review the diff)"

rows="redteam: enabled rows differ from enabled-rows/redteam.txt (+ is on now; disable it in the bundle or add it by hand)"
expect_fail "a new row" "printf -- '- id: agent-team\n  name: x\n' >>fixtures/redteam.yml" "$rows"
expect_fail "a row with no id" "printf -- \"- name: '@x/y'\n\" >>fixtures/redteam.yml" "$rows"
grep -q "^+(no-id) '@x/y'$" <<<"$out" || fail "a row with no id was not listed as (no-id): $out"
expect_fail "a row disabled by expression" "printf -- '- id: z\n  name: z\n  disabled: !!js false\n' >>fixtures/redteam.yml" "$rows"
expect_fail "red-team dump fails" : "redteam: --dump-config exited non-zero" STUB_REDTEAM=fail

expect_fail "Ollama down" : "Ollama is not running on 127.0.0.1:11434
the smoke turn left no sessions folder to resume into" STUB_OLLAMA=down
smoke_base=$(sed -n 's/^FROM //p' "$base/scripts/upgrade-check/smoke.Modelfile")
expect_fail "smoke base missing" : "$smoke_base is missing; run 'ollama pull $smoke_base'
the smoke turn left no sessions folder to resume into" STUB_OLLAMA=nobase
no_ollama=1
expect_fail "no ollama CLI" : "the ollama CLI is not on PATH
the smoke turn left no sessions folder to resume into"
unset no_ollama
expect_fail "smoke turn fails" : "smoke turn exited non-zero
the smoke turn left no sessions folder to resume into" STUB_SMOKE=fail
expect_fail "no final answer" : "smoke turn ended without a final answer" STUB_SMOKE=nofinal
expect_fail "plugin not loaded" : "our plugin didn't load" STUB_SMOKE=noplugin
expect_fail "no ollama route" : "the session log doesn't show the ollama route answering
the smoke turn left no sessions folder to resume into" STUB_SMOKE=nosession

expect_fail "wider permission accepted" : "--permission-mode danger-full-access was accepted" STUB_PERMISSION=accept
expect_fail "permission fails otherwise" : \
  "--permission-mode danger-full-access failed, but not as an unknown preset" STUB_PERMISSION=other

expect_fail "no resume fixture" "rm -r scripts/upgrade-check/resume/*" \
  "resume/ must hold exactly one session fixture, from the pin being left"
expect_fail "two resume fixtures" "mkdir -p scripts/upgrade-check/resume/old && cp scripts/upgrade-check/resume/*/*.jsonl scripts/upgrade-check/resume/old/" \
  "resume/ must hold exactly one session fixture, from the pin being left"
expect_fail "resume not appended" : "the resumed turn wasn't appended to the old session log" STUB_RESUME=noappend

# --update rewrites the config snapshots, but never the enabled-rows lists.
update=1
cases=$((cases + 1))
run "echo '# drift' >>scripts/upgrade-check/snapshots/config.yml"
if [[ "$code" -ne 0 ]]; then
  fail "--update did not pass after rewriting a drifted snapshot: $out"
elif ! cmp -s "$last_dir/scripts/upgrade-check/snapshots/config.yml" "$base/fixtures/job.yml"; then
  fail "--update did not rewrite the config snapshot"
fi
expect_fail "--update with a new row" "printf -- '- id: agent-team\n  name: x\n' >>fixtures/redteam.yml" "$rows"
cmp -s "$last_dir/scripts/upgrade-check/enabled-rows/redteam.txt" "$repo/scripts/upgrade-check/enabled-rows/redteam.txt" ||
  fail "--update rewrote enabled-rows/redteam.txt"
unset update

if [[ "$status" -eq 0 ]]; then echo "upgrade check ok ($cases cases)"; fi
exit "$status"
