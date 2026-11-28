#!/usr/bin/env bash
# Runs the red-team attack set and writes eval/results/<tag>.json (ADR 0011, #57).
# Usage: eval/run.sh <tag>, e.g. eval/run.sh v0.2
#
# - Promptfoo and everything it starts run under eval/loopback.sb: no outbound network except
#   loopback, whatever Promptfoo's own flags do.
# - The environment is cleared and rebuilt from a fixed list, as in bin/lib/launcher.sh, so no
#   provider key in the calling shell can make Promptfoo grade or generate remotely.
# - Promptfoo's local store and the raw output stay under the demo root, outside the repo. Only
#   the summary is committed.
set -euo pipefail

me=${0##*/}
refuse() {
  echo "$me: $1" >&2
  exit 1
}

tag=${1:-}
[[ "$tag" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || refuse "usage: eval/run.sh <tag>, tag like v0.2"

repo=$(cd "$(dirname "$0")/.." && pwd)
root=${DSH_DEMO_ROOT:-$HOME/.dsh-demo}
results=$repo/eval/results/$tag.json
[[ -e "$results" ]] && refuse "$results exists; results files are not overwritten"
[[ -x /usr/bin/sandbox-exec ]] || refuse "/usr/bin/sandbox-exec is missing; refusing to run without the network sandbox"
promptfoo=$repo/node_modules/.bin/promptfoo
[[ -x "$promptfoo" ]] || refuse "run 'pnpm install --frozen-lockfile' in $repo first"
# The DVMCP attacks start the lab image; a missing or stale one would make them all check errors
# (#59). The build needs the network, so it is never run from here.
"$repo/labs/dvmcp/build.sh" --check || refuse "the DVMCP attacks need a current lab image"

if [[ "${DSH_EVAL_CLEAN_ENV:-}" != 1 ]]; then
  exec env -i HOME="$HOME" USER="${USER:-}" PATH="$PATH" LANG="${LANG:-en_US.UTF-8}" \
    TERM="${TERM:-dumb}" TMPDIR="${TMPDIR:-/tmp}" DSH_DEMO_ROOT="$root" DSH_EVAL_CLEAN_ENV=1 \
    /usr/bin/sandbox-exec -f "$repo/eval/loopback.sb" "$0" "$@"
fi
# DSH_EVAL_CLEAN_ENV can be set by hand, which would skip the sandbox too, so the re-run checks
# that only the names it passed are left. PWD, OLDPWD, SHLVL and _ are the shell's own.
for name in $(env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p'); do
  case $name in
    HOME | USER | PATH | LANG | TERM | TMPDIR | DSH_DEMO_ROOT | DSH_EVAL_CLEAN_ENV | PWD | OLDPWD | SHLVL | _) ;;
    *) refuse "$name is set; start $me without DSH_EVAL_CLEAN_ENV so it clears the environment and sandboxes the run" ;;
  esac
done

store=$root/promptfoo
runs=$root/eval-runs
mkdir -p "$store" "$runs"
raw=$runs/$tag-$(date -u +%Y%m%dT%H%M%SZ).json

export PROMPTFOO_CONFIG_DIR=$store
export PROMPTFOO_DISABLE_REMOTE_GENERATION=true
export PROMPTFOO_DISABLE_TELEMETRY=1 PROMPTFOO_DISABLE_SHARING=1 PROMPTFOO_DISABLE_UPDATE=1
export OLLAMA_BASE_URL=http://127.0.0.1:11434
# A hit fails an assertion, which is a result to record, not a failed run. A provider or config
# error still exits non-zero.
export PROMPTFOO_FAILED_TEST_EXIT_CODE=0

cd "$repo/eval"
"$promptfoo" eval -c promptfooconfig.yaml --no-cache --no-progress-bar -o "$raw"
node "$repo/eval/summarize.ts" "$raw" "$tag"
echo "$me: raw output in $raw"
