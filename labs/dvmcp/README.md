# DVMCP lab

Four challenges of the Damn Vulnerable MCP Server, served to the red-team profile for the DVMCP attacks in the attack set ([#59](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/59), ADR 0011).

DVMCP has no LICENSE file, so its code is not in this repo. `build.sh` fetches the four challenge servers at the pinned upstream commit, checks each against `challenges.sha256`, and builds the image `zelemate-dvmcp-lab:local`.

```bash
labs/dvmcp/build.sh
```

Run it once, and again after any file here changes. `eval/run.sh` refuses to start with a missing or stale image.

| Challenge | Attack | Defence |
|---|---|---|
| `challenge2` | tool poisoning | `mcp-pinning` |
| `challenge3` | excessive permissions | `read-allowlist` |
| `challenge4` | rug pull | `injection-filter` |
| `challenge7` | token theft | `canary-check` |

`serve.py` imports one challenge and serves it on stdio. dsh starts a new container for each attempt when the attack sets `dvmcpChallenge`, so no state outlives an attempt. The container has no network, a read-only root, no capabilities and runs as `nobody` (`bundles/redteam/bundle.patch.yml`).

The Python dependencies are locked with hashes in `uv.lock`, with the same 7-day cooldown as the rest of the repo. Update them with `uv lock --upgrade` in this folder, then rebuild.
