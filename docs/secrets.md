# Secrets

Following the OWASP Secrets Management Cheat Sheet: centralise, prefer short-lived credentials, inject at runtime, rotate. In this repo, keys live in the macOS Keychain (ADR 0007) and secret values never reach a remote model (ADR 0004).

## Where secrets live

| Secret | Store | Used by | Rotation |
|---|---|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | GitHub Actions secret | `claude-review.yml` (ADR 0014) | yearly (the token expires after 1 year) or on leak |
| Model API keys | macOS Keychain, exported by the launchers in `bin/` | dsh, through `apiKeyEnv` | 90 days |

No package is published, so there are no registry tokens.

## Local development

Keys stay in the Keychain. `.env` files are gitignored and refused by `scripts/checks/forbidden-paths.sh`; only `.env.example` is tracked. Never put secrets in prompts, Docker `ENV`/`ARG`, or `$DSH_HOME/cordis.patch.yml`, which stays exactly `[]`.

## If a secret leaks

1. Revoke/rotate it at the provider first.
2. Check provider logs for use since the leak.
3. Remove it from the code; history rewriting is optional once the secret is dead.
4. If the leak came from an upstream bug, follow ADR 0015.
