#!/usr/bin/env bash
# Builds the DVMCP lab image the red-team profile starts for its DVMCP attacks (#59).
# Usage: labs/dvmcp/build.sh            fetch, check and build
#        labs/dvmcp/build.sh --check    exit 1 unless the image matches this directory
#
# - DVMCP has no LICENSE file (its README says MIT), so its code is never committed here. This
#   fetches the four challenge servers at the pinned commit and checks each against
#   challenges.sha256 before anything uses it. A changed upstream file stops the build.
# - The build context lives under the demo root, outside the repo.
# - The image carries a label with the hash of every input in this directory, so eval/run.sh can
#   refuse a stale image without network access.
set -euo pipefail

me=${0##*/}
refuse() {
  echo "$me: $1" >&2
  exit 1
}

# Upstream v2 (2026-11-01), which serves Streamable HTTP; serve.py swaps that for stdio.
REPO=harishsg993010/damn-vulnerable-MCP-server
COMMIT=cdc4c6b5b76353203effcb26058e50fa6067d3a6
IMAGE=zelemate-dvmcp-lab:local
LABEL=org.zelemate.dvmcp.inputs

lab=$(cd "$(dirname "$0")" && pwd)
inputs=(Dockerfile pyproject.toml uv.lock serve.py challenges.sha256 build.sh)

inputs_hash() {
  (cd "$lab" && shasum -a 256 "${inputs[@]}") | shasum -a 256 | cut -d' ' -f1
}

command -v docker >/dev/null 2>&1 || refuse "docker is not installed"
want=$(inputs_hash)

if [[ "${1:-}" == --check ]]; then
  have=$(docker image inspect --format "{{ index .Config.Labels \"$LABEL\" }}" "$IMAGE" 2>/dev/null) ||
    refuse "$IMAGE is missing; run labs/dvmcp/build.sh"
  [[ "$have" == "$want" ]] || refuse "$IMAGE is stale; run labs/dvmcp/build.sh"
  exit 0
fi
[[ $# -eq 0 ]] || refuse "usage: labs/dvmcp/build.sh [--check]"

root=${DSH_DEMO_ROOT:-$HOME/.dsh-demo}
context=$root/redteam/dvmcp-build
rm -rf "$context"
mkdir -p "$context"

# Paths come from our own challenges.sha256, never from upstream.
while read -r _ path; do
  mkdir -p "$context/$(dirname "$path")"
  curl -fsSL --proto '=https' --proto-redir '=https' --retry 3 \
    -o "$context/$path" "https://raw.githubusercontent.com/$REPO/$COMMIT/$path"
done <"$lab/challenges.sha256"
(cd "$context" && shasum -a 256 -c "$lab/challenges.sha256" >/dev/null) ||
  refuse "a fetched challenge file does not match challenges.sha256; nothing was built"

cp "$lab/Dockerfile" "$lab/pyproject.toml" "$lab/uv.lock" "$lab/serve.py" "$context/"
docker build --pull --label "$LABEL=$want" -t "$IMAGE" "$context"
echo "$me: built $IMAGE from $REPO@${COMMIT:0:7}"
