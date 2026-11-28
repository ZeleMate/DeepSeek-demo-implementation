# shellcheck shell=sh
# The launcher module (ADR 0007): every guard a bin/dsh-<profile> runs before it starts dsh.
# A launcher sets these, sources this file and calls `launch "$@"`:
#   profile  the dsh profile, e.g. job; the bundle is bundles/<profile>, @zelemate/dsh-bundle-<profile>
#   home     DSH_HOME under the root, e.g. home or redteam/home
#   keys     Keychain key names to export, space-separated; empty for a profile with no keys
#   models   local models as role:tag:required|optional, space-separated; built from
#            bundles/<profile>/<role>.Modelfile; empty for a profile with no local models
#   fresh_workspace  true: each launch gets a new run directory under the workspace, so no file
#            one attempt writes reaches the next (ADR 0011); false: one shared workspace
#   pass_env names from the calling shell that may reach dsh, space-separated; empty for none.
#            Each value must be letters, digits, dots, dashes or underscores (#58)

refuse() {
  echo "$me: $1" >&2
  exit 1
}

# Each value is reassigned from itself, so a launcher that forgets one stops here.
read_descriptor() {
  me=${0##*/}
  profile=${profile:?}
  home=${home:?}
  keys=${keys?}
  models=${models?}
  fresh_workspace=${fresh_workspace:?}
  case $fresh_workspace in
    true | false) ;;
    *) refuse "fresh_workspace must be true or false" ;;
  esac
  pass_env=${pass_env?}
  for name in $pass_env; do
    case $name in
      DSH_REDTEAM_*[!A-Z0-9_]*) refuse "pass_env names must be letters, digits and underscores, not $name" ;;
      DSH_REDTEAM_*) ;;
      # Only names of our own pass, so a launcher can't let a dsh setting or a key through.
      *) refuse "pass_env may name only DSH_REDTEAM_* variables, not $name" ;;
    esac
  done
}

# dsh's template flag deletes the profile and boots a fresh copy of a shipped template in its
# place, such as plain headless: no bundle of ours, so DeepSeek's API, search and fetch are on. Every
# check here looks at the profile on disk, so the flag would pass them all and then swap the
# profile out (ADR 0001, 0003). It is refused wherever it sits, before anything else runs. The [i]
# keeps forbidden-patterns.sh, which bans the flag outside docs, from flagging this refusal.
check_args() {
  for arg in "$@"; do
    case $arg in
      --from-default-prof[i]le | --from-default-prof[i]le=*)
        refuse "dsh's template flag replaces the $profile profile with one that has no bundle of ours; refusing to start (ADR 0001, 0003)"
        ;;
    esac
  done
}

is_passed() {
  for passed in $pass_env; do [ "$passed" = "$1" ] && return 0; done
  return 1
}

# A passed value is a plain word, so it can't smuggle a path, a flag or a second assignment.
check_passed_value() {
  case $2 in
    "" | *[!A-Za-z0-9._-]*) refuse "$1 must be letters, digits, dots, dashes or underscores" ;;
  esac
}

# The script re-runs itself with an empty environment plus a fixed allowlist, so nothing exported
# in the calling shell reaches dsh: no other key, no proxy, no endpoint, no DSH_* setting.
# DSH_DEMO_NO_KEYS is allowlisted only for a profile that has keys to skip.
clean_env() {
  if [ "${DSH_LAUNCHER_CLEAN_ENV:-}" != 1 ]; then
    no_keys=
    [ -n "$keys" ] && no_keys="DSH_DEMO_NO_KEYS=${DSH_DEMO_NO_KEYS:-}"
    passed_env=
    for name in $pass_env; do
      eval "value=\${$name-}"
      [ -n "$value" ] || continue
      check_passed_value "$name" "$value"
      passed_env="$passed_env $name=$value"
    done
    # passed_env is split on purpose: each entry is NAME=word, checked above.
    # shellcheck disable=SC2086
    exec env -i \
      HOME="$HOME" USER="${USER:-}" PATH="$PATH" LANG="${LANG:-en_US.UTF-8}" \
      TERM="${TERM:-dumb}" TMPDIR="${TMPDIR:-/tmp}" \
      DSH_DEMO_ROOT="$root" ${no_keys:+"$no_keys"} $passed_env DSH_LAUNCHER_CLEAN_ENV=1 \
      "$0" "$@"
  fi
  # DSH_LAUNCHER_CLEAN_ENV can be set by hand, so the re-run also checks that only allowlisted
  # names are left. PWD, OLDPWD, SHLVL and _ are the shell's own.
  for name in $(env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p'); do
    case $name in
      HOME | USER | PATH | LANG | TERM | TMPDIR | DSH_DEMO_ROOT | DSH_LAUNCHER_CLEAN_ENV) ;;
      PWD | OLDPWD | SHLVL | _) ;;
      DSH_DEMO_NO_KEYS) [ -n "$keys" ] || refuse "$name is set; start $me without DSH_LAUNCHER_CLEAN_ENV so it clears the environment" ;;
      *)
        is_passed "$name" || refuse "$name is set; start $me without DSH_LAUNCHER_CLEAN_ENV so it clears the environment"
        eval "value=\${$name}"
        check_passed_value "$name" "$value"
        ;;
    esac
  done
}

# Stops on anything left on disk that dsh would read as config, a key or instructions.
check_disk() {
  # The home patch outranks every profile, so it stays exactly [] (ADR 0007).
  home_patch=$DSH_HOME/cordis.patch.yml
  [ -e "$home_patch" ] || printf '[]\n' >"$home_patch"
  if [ "$(cat "$home_patch")" != "[]" ]; then
    refuse "$home_patch must be exactly [] (ADR 0007)"
  fi

  # dsh falls back to these files for keys and settings. Keys reach dsh only from the Keychain,
  # through this launcher, so none may exist: one left by an earlier run would apply (ADR 0007).
  for file in "$DSH_HOME/.env" "$DSH_HOME/.credentials.yaml" "$workspace_root/.env" "$workspace/.env"; do
    [ -e "$file" ] && refuse "$file exists; keys reach dsh only from the Keychain, through $me (ADR 0007)"
  done

  # The bundles turn off dsh's instruction and skill rows, but a file one run leaves here would
  # steer every later run if a row came back, so none may exist (ADR 0009, 0010, 0011). A run
  # directory sits inside the workspace, and instruction lookups can walk up, so both are checked.
  for dir in "$workspace_root" "$workspace"; do
    for file in AGENTS.md AGENTS.local.md CLAUDE.md CLAUDE.local.md .agents .dsh; do
      [ -e "$dir/$file" ] && refuse "$dir/$file exists; the $profile workspace holds no instructions (ADR 0009)"
    done
  done

  # dsh's instruction and skill rows fall back to ~/.agents. The launcher points them at an
  # empty directory of its own instead, a second lock behind those rows being off (ADR 0012).
  if [ -n "$(ls -A "$DSH_AGENTS_HOME")" ]; then
    refuse "$DSH_AGENTS_HOME must be empty; only our own bundles' skills load (ADR 0012)"
  fi
  return 0
}

# Builds each local model's tag from its Modelfile, which fixes a 16k context (#26). Only an
# installed base is used: this never downloads a model. A required model's missing base stops
# the launch; an optional one only warns. A tag is rebuilt whenever its Modelfile changes, so an
# old tag never keeps an old context.
build_models() {
  [ -n "$models" ] || return 0
  command -v ollama >/dev/null 2>&1 || refuse "ollama is not installed"
  built=$root/$profile/models
  mkdir -p "$built"
  for entry in $models; do
    role=${entry%%:*}
    rest=${entry#*:}
    tag=${rest%%:*}
    need=${rest#*:}
    case $need in
      required | optional) ;;
      *) refuse "model entry $entry must end in :required or :optional" ;;
    esac
    modelfile=$bundle/$role.Modelfile
    stamp=$built/$tag.sha256
    hash=$(shasum -a 256 "$modelfile" | cut -d' ' -f1)
    if ollama show "$tag" >/dev/null 2>&1 && [ "$(cat "$stamp" 2>/dev/null)" = "$hash" ]; then
      continue
    fi
    base=$(sed -n 's/^FROM //p' "$modelfile")
    if ollama show "$base" >/dev/null 2>&1; then
      rm -f "$stamp"
      ollama create "$tag" -f "$modelfile" >/dev/null 2>&1 || refuse "could not create $tag from $role.Modelfile"
      printf '%s\n' "$hash" >"$stamp"
    elif [ "$need" = required ]; then
      refuse "the $role base $base is missing; run 'ollama pull $base'"
    else
      echo "$me: warning: the $role base $base is missing; run 'ollama pull $base'" >&2
    fi
  done
}

# First run: the profile is dsh-base, then dsh-headless, then our bundle (#53). The manifest is
# written here instead of using dsh's template flag, which deletes an existing profile (ADR 0001).
# Without our bundle the profile is plain headless: DeepSeek's API as the default model, search
# and fetch on. So a first run that wrote the manifest but failed to add the bundle is retried
# here, and the launcher refuses to start if the bundle is still missing (ADR 0003).
ensure_profile() {
  profile_dir=$DSH_HOME/profiles/$profile
  if [ ! -e "$profile_dir/package.json" ]; then
    mkdir -p "$profile_dir"
    cat >"$profile_dir/package.json" <<EOF
{
  "name": "dsh-profile-$profile",
  "private": true,
  "dependencies": {},
  "dsh": { "profile": { "bundles": ["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-headless"] } }
}
EOF
  fi
  has_bundle || "$dsh" plugin --profile "$profile" add "$bundle" >/dev/null || true
  has_bundle || refuse "the $profile profile in $profile_dir is missing bundles/$profile; refusing to start"
}

has_bundle() {
  node -e '
    const bundles = require(process.argv[1]).dsh?.profile?.bundles ?? []
    process.exit(bundles.includes(process.argv[2]) ? 0 : 1)
  ' "$profile_dir/package.json" "@zelemate/dsh-bundle-$profile" 2>/dev/null
}

# Keys are exported here, never passed as arguments, which anyone can see in `ps`. A missing item
# leaves the variable unset, and dsh fails the request with MISSING_CREDENTIAL. DSH_DEMO_NO_KEYS=1
# skips the Keychain entirely (the upgrade check runs keyless).
export_keys() {
  for name in $keys; do
    unset "$name"
    [ "${DSH_DEMO_NO_KEYS:-}" = 1 ] && continue
    if value=$(/usr/bin/security find-generic-password -a "$USER" -s "dsh-demo.$name" -w 2>/dev/null); then
      export "$name=$value"
    fi
  done
  unset value
}

# dsh stops at startup only for its own required rows. A bundle row that fails to import, throws
# or waits on a missing service gets `dsh: warning: N entries did not activate`, and the session
# runs anyway, so a missing defence would pass as a defended run (ADR 0003, #104). There is no
# setting to make that warning fatal. So the launcher boots the profile once first with an empty
# task: headless refuses an empty task after the startup audit and before any model call. Any row
# that did not activate stops the launch, and so does a boot that never reached that refusal.
# The boot takes the same --patch overlays as the real run, and is skipped for the --dump-* flags,
# which only print config. eval/lib/activation.ts matches the same text in each attempt's stderr,
# which also catches a row that activated here but not in the real run.
check_rows() {
  for arg; do
    case $arg in
      --dump-config | --dump-config-schema | --dump-default-config) return 0 ;;
    esac
  done
  # Keeps only the --patch overlays in this function's own arguments, in order.
  left=$#
  while [ "$left" -gt 0 ]; do
    arg=$1
    shift
    left=$((left - 1))
    case $arg in
      --patch)
        if [ "$left" -gt 0 ]; then
          set -- "$@" --patch "$1"
          shift
          left=$((left - 1))
        fi
        ;;
      --patch=*) set -- "$@" "$arg" ;;
    esac
  done
  rows_err=$(mktemp "$root/$profile/rows.XXXXXX") || refuse "could not create a file for the startup check"
  # Exits 1 by design: the empty task is refused.
  rows_out=$("$dsh" --profile "$profile" "$@" --json - </dev/null 2>"$rows_err") || :
  if grep -q 'did not activate' "$rows_err"; then
    # From the warning on, without stack frames or the empty-task refusal: the row lines say which
    # row and why.
    sed -n '/did not activate/,$p' "$rows_err" | grep -v -e '^    at ' -e 'a task is required' >&2
    rm -f "$rows_err"
    refuse "a bundle row did not activate; refusing to start an undefended $profile run (ADR 0003)"
  fi
  case $rows_out in
    *'"type":"error"'*'a task is required'*) rm -f "$rows_err" ;;
    *)
      tail -n 5 "$rows_err" >&2
      rm -f "$rows_err"
      refuse "the startup check did not reach the headless runner; refusing to start (ADR 0003)"
      ;;
  esac
}

launch() {
  read_descriptor
  check_args "$@"
  root=${DSH_DEMO_ROOT:-$HOME/.dsh-demo}
  clean_env "$@"

  repo=$(cd "$(dirname "$0")/.." && pwd)
  bundle=$repo/bundles/$profile
  DSH_HOME=$root/$home
  DSH_AGENTS_HOME=$root/$profile/agents-home
  workspace_root=$root/workspace/$profile
  workspace=$workspace_root
  # Called by path, not through `pnpm exec`, which would run dsh in the repo instead of the workspace.
  dsh=$repo/node_modules/.bin/dsh
  [ -x "$dsh" ] || refuse "run 'pnpm install --frozen-lockfile' in $repo first"

  mkdir -p "$DSH_HOME" "$DSH_AGENTS_HOME" "$workspace_root"
  check_disk

  # dsh reads ./.env as a key fallback and ./AGENTS.md as instructions, so it never starts inside
  # a repo. A scanned repo reaches a job as a tool argument (ADR 0007, ADR 0009).
  cd "$workspace" || exit 1
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    refuse "$workspace is inside a git repo; the $profile workspace must not be one"
  fi

  build_models

  # Ollama needs no key, but pi-ai's OpenAI-compatible transport requires one. The red-team
  # bundle and the upgrade check's overlay name this dummy, which is not a secret (ADR 0007).
  export DSH_HOME DSH_AGENTS_HOME DSH_TELEMETRY_DISABLED=1 OLLAMA_DUMMY_KEY=ollama
  # Bundle rows that start our own programs, such as the red-team MCP test server, find them here.
  export DSH_DEMO_REPO="$repo"

  ensure_profile
  export_keys
  check_rows "$@"

  # The run directory is made last, after every check that can refuse, so each one left behind
  # is a launch that reached dsh. Run directories are kept, not deleted, as an attempt's evidence.
  if [ "$fresh_workspace" = true ]; then
    workspace=$(mktemp -d "$workspace_root/run.XXXXXX") || refuse "could not create a run directory in $workspace_root"
    cd "$workspace" || exit 1
  fi

  exec "$dsh" --profile "$profile" "$@"
}
