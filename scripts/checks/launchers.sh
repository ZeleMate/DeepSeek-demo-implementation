#!/usr/bin/env bash
# Tests what the launchers in bin/ hand to dsh, with a stub dsh: no model, no key, no Keychain.
# Usage: launchers.sh
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A copy of the launchers next to a stub dsh that prints the environment it was started with.
mkdir -p "$tmp/repo/bin/lib" "$tmp/repo/bundles/redteam" "$tmp/repo/node_modules/.bin" "$tmp/stubs"
cp "$repo/bin/dsh-job" "$repo/bin/dsh-redteam" "$tmp/repo/bin/"
cp "$repo/bin/lib/launcher.sh" "$tmp/repo/bin/lib/"
cp "$repo"/bundles/redteam/*.Modelfile "$tmp/repo/bundles/redteam/"
printf '#!/bin/sh\nenv\n' >"$tmp/repo/node_modules/.bin/dsh"
# The stub ollama has every model except the ones named in stubs/missing, one per line.
: >"$tmp/stubs/missing"
# shellcheck disable=SC2016 # $1 and $2 are the stub's own arguments
printf '#!/bin/sh\n[ "$1" = show ] && grep -qxF -- "$2" "%s" && exit 1\nexit 0\n' "$tmp/stubs/missing" >"$tmp/stubs/ollama"
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
      AUDIT_PLAIN=leak OPENROUTER_API_KEY=leak OPENAI_API_KEY=leak DEEPSEEK_API_KEY=leak \
      DEEPSEEK_BASE_URL=leak \
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

# Checks one launcher. keyed says whether its profile reads Keychain keys; models lists the
# local model tags it must build.
check() {
  local launcher=$1 profile=$2 home=$3 bundle=$4 workspace=$5 keyed=$6 models=$7 root out tag
  root=$(fresh_root "$profile" "$home" "$bundle")

  if ! out=$(launch "$launcher" "$root" 2>&1); then
    fail "$launcher did not start: $out"
  elif grep -q 'leak\|danger-full-access' <<<"$out"; then
    fail "$launcher passed the calling shell's environment to dsh: $(grep 'leak\|danger-full-access' <<<"$out" | cut -d= -f1 | tr '\n' ' ')"
  elif ! grep -q '^DSH_TELEMETRY_DISABLED=1$' <<<"$out"; then
    fail "$launcher did not turn telemetry off"
  fi

  # DSH_DEMO_NO_KEYS only means something to a profile with keys, so only that one passes it on.
  if $keyed && ! grep -q '^DSH_DEMO_NO_KEYS=1$' <<<"$out"; then
    fail "$launcher dropped DSH_DEMO_NO_KEYS, so it would read the Keychain"
  elif ! $keyed && grep -q '^DSH_DEMO_NO_KEYS=' <<<"$out"; then
    fail "$launcher passed DSH_DEMO_NO_KEYS to a profile with no keys"
  fi

  for tag in $models; do
    [[ -s "$root/$profile/models/$tag.sha256" ]] || fail "$launcher did not build $tag"
  done

  # dsh's instruction and skill rows fall back to ~/.agents, so each profile gets its own (#110).
  if ! grep -qxF "DSH_AGENTS_HOME=$root/$profile/agents-home" <<<"$out"; then
    fail "$launcher did not point DSH_AGENTS_HOME at its own directory"
  fi
  root=$(fresh_root "$profile" "$home" "$bundle")
  mkdir -p "$root/$profile/agents-home/skills"
  refuses "$launcher" "$root" "agents-home must be empty" "a non-empty agents home"

  # Setting the re-run marker by hand must not skip the cleanup.
  root=$(fresh_root "$profile" "$home" "$bundle")
  refuses "$launcher" "$root" "is set; start $launcher without" "a forged DSH_LAUNCHER_CLEAN_ENV" DSH_LAUNCHER_CLEAN_ENV=1

  # In an otherwise clean environment, DSH_DEMO_NO_KEYS is allowed only for a profile with keys.
  # The flag is not a secret; it sits in a variable because forbidden-patterns.sh flags any
  # key-named assignment written out after env.
  root=$(fresh_root "$profile" "$home" "$bundle")
  local no_keys=DSH_DEMO_NO_KEYS=1
  if out=$(env -i HOME="$HOME" PATH="$tmp/stubs:$PATH" DSH_DEMO_ROOT="$root" "$no_keys" \
    DSH_LAUNCHER_CLEAN_ENV=1 "$tmp/repo/bin/$launcher" 2>&1); then
    $keyed || fail "$launcher started with DSH_DEMO_NO_KEYS in a profile with no keys"
  elif $keyed; then
    fail "$launcher refused DSH_DEMO_NO_KEYS: $out"
  elif ! grep -q "DSH_DEMO_NO_KEYS is set" <<<"$out"; then
    fail "$launcher stopped with DSH_DEMO_NO_KEYS, but not at its guard: $out"
  fi

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

check dsh-job job home @zelemate/dsh-bundle-job workspace/job true ""
check dsh-redteam redteam redteam/home @zelemate/dsh-bundle-redteam workspace/redteam false \
  "redteam-qwen3.5-4b-16k redteam-granite4.2-3b-16k"

# Where dsh starts: the job profile always in its one workspace, the red-team profile in a new
# run directory per launch, so a file one attempt writes never reaches the next (#110).
start_dir() { sed -n 's/^PWD=//p' <<<"$1"; }
root=$(fresh_root job home @zelemate/dsh-bundle-job)
first=$(start_dir "$(launch dsh-job "$root" 2>&1)")
second=$(start_dir "$(launch dsh-job "$root" 2>&1)")
[[ "$first" == "$root/workspace/job" && "$second" == "$first" ]] ||
  fail "dsh-job did not start in its shared workspace: $first, then $second"

root=$(fresh_root redteam redteam/home @zelemate/dsh-bundle-redteam)
first=$(start_dir "$(launch dsh-redteam "$root" 2>&1)")
: >"$first/left-by-attempt-1"
second=$(start_dir "$(launch dsh-redteam "$root" 2>&1)")
if [[ "$first" != "$root/workspace/redteam/run."* || "$second" != "$root/workspace/redteam/run."* ]]; then
  fail "dsh-redteam did not start in a run directory: $first, then $second"
elif [[ "$first" == "$second" || -n "$(ls -A "$second")" ]]; then
  fail "dsh-redteam reused a run directory: $first, then $second"
fi

# A refused launch leaves no run directory behind, so each one there is an attempt that ran.
root=$(fresh_root redteam redteam/home @zelemate/dsh-bundle-redteam)
mkdir -p "$root/redteam/agents-home/skills"
launch dsh-redteam "$root" >/dev/null 2>&1 && fail "dsh-redteam started with a non-empty agents home"
if compgen -G "$root/workspace/redteam/run.*" >/dev/null; then
  fail "a refused dsh-redteam launch left a run directory behind"
fi

# A launcher that sets fresh_workspace to anything else stops before dsh starts.
sed 's/^fresh_workspace=true$/fresh_workspace=yes/' "$tmp/repo/bin/dsh-redteam" >"$tmp/repo/bin/dsh-redteam-bad"
chmod +x "$tmp/repo/bin/dsh-redteam-bad"
refuses dsh-redteam-bad "$(fresh_root redteam redteam/home @zelemate/dsh-bundle-redteam)" \
  "fresh_workspace must be true or false" "fresh_workspace=yes"

# The red-team models: a missing required base stops the launch, a missing optional one only
# warns, and a changed Modelfile rebuilds its tag.
modelfiles=$tmp/repo/bundles/redteam
victim_base=$(sed -n 's/^FROM //p' "$modelfiles/victim.Modelfile")
grader_base=$(sed -n 's/^FROM //p' "$modelfiles/grader.Modelfile")
redteam_root() { fresh_root redteam redteam/home @zelemate/dsh-bundle-redteam; }

printf '%s\n' "$victim_base" >"$tmp/stubs/missing"
refuses dsh-redteam "$(redteam_root)" "the victim base $victim_base is missing" "no victim base"

printf '%s\n' "$grader_base" >"$tmp/stubs/missing"
if ! out=$(launch dsh-redteam "$(redteam_root)" 2>&1); then
  fail "dsh-redteam did not start without the optional grader base: $out"
elif ! grep -q "warning: the grader base $grader_base is missing" <<<"$out"; then
  fail "dsh-redteam started without the grader base but did not warn"
fi
: >"$tmp/stubs/missing"

root=$(redteam_root)
stamp=$root/redteam/models/redteam-qwen3.5-4b-16k.sha256
launch dsh-redteam "$root" >/dev/null 2>&1 || fail "dsh-redteam did not start for the rebuild check"
cp "$modelfiles/victim.Modelfile" "$tmp/victim.Modelfile.orig"
printf '# changed\n' >>"$modelfiles/victim.Modelfile"
launch dsh-redteam "$root" >/dev/null 2>&1 || fail "dsh-redteam did not start after a Modelfile change"
if [[ "$(cat "$stamp")" != "$(shasum -a 256 "$modelfiles/victim.Modelfile" | cut -d' ' -f1)" ]]; then
  fail "dsh-redteam did not rebuild the victim tag after its Modelfile changed"
fi
cp "$tmp/victim.Modelfile.orig" "$modelfiles/victim.Modelfile"

if [[ "$status" -eq 0 ]]; then echo "launchers ok"; fi
exit "$status"
