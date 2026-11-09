---
status: accepted; both launchers clear the environment and refuse key files 2026-11-08 (https://github.com/ZeleMate/DeepSeek-demo-implementation/pull/132)
---

# API keys live in the macOS Keychain and reach dsh only through a launcher

Every provider key (OpenRouter, OpenAI for the Decisions API, Tavily, and Daytona if it is ever added) is a **macOS login Keychain item** named `dsh-demo.<NAME>`, e.g. `dsh-demo.OPENROUTER_API_KEY`. A committed launcher script per profile (`bin/dsh-job`, `bin/dsh-redteam`) reads the keys with `security find-generic-password -w`, exports them inside the script, and `exec`s `pnpm exec dsh`. The keys exist only in that one dsh process and its environment. dsh reads them through config that names a key and never holds it (`apiKeyEnv: OPENROUTER_API_KEY`). A missing key fails the request with `MISSING_CREDENTIAL`.

- **No keys in plaintext files:** none in any `.env`, in `$DSH_HOME/.credentials.yaml`, in `~/.zshrc`, or in a committed file. `.env.example` lists the Keychain item names instead of `KEY=` lines.
- **Settings live in our bundles:** routes, defences and disabled rows go in the committed `dsh.bundle.patch` files. `$DSH_HOME/cordis.patch.yml` is exactly `[]`, because it outranks every profile and would leak settings into the red-team profile. An empty or comment-only file fails boot. There is no `$DSH_HOME/.env`.
- **Bootstrap variables come from the launcher:** `DSH_HOME` and `DSH_TELEMETRY_DISABLED=1`. dsh refuses `DSH_*` variables from `.env` files. Both launchers re-run themselves with an empty environment plus a fixed allowlist, so a key, proxy, endpoint or `DSH_*` setting in the calling shell never reaches dsh. A proxy therefore can't be set from the shell.
- **Both launchers refuse key files.** They stop if `$DSH_HOME/.env`, `$DSH_HOME/.credentials.yaml` or the workspace `.env` exists. `scripts/checks/launchers.sh` tests this and the environment with a stub dsh, in the hooks and in CI.
- **The red-team launcher uses its own `DSH_HOME` and sets no provider keys at all.** It sets only the dummy Ollama key, which is not a secret. So a red-team run can't reach a remote model even through a misconfigured route.
- **The job launcher refuses to start inside a scanned repo.** It `cd`s into a dedicated job workspace and gets the repo as a tool argument.
- **Spending is capped by each provider:**
  - OpenRouter: a key credit limit of $30 with a monthly reset (ADR 0006).
  - OpenAI: a dedicated project for the Decisions API, with a $5 monthly spend limit and "Enforce a hard limit" on.
  - Tavily: a per-key monthly credit limit set when the key is created.

## Why

dsh looks for a key in `$DSH_HOME/.credentials.yaml`, then the environment it was started with, then `<cwd>/.env`, then `$DSH_HOME/.env`. Headless profiles turn the credentials file off. dsh has no Keychain or secret-store support; upstream lists it as deferred. Each of the file sources is a plaintext key on disk that a file-read tool could open. The `<cwd>/.env` source also means a scanned repo's `.env` would become a key source if dsh started inside it. Keeping keys in the Keychain and putting them only into the launched process's environment leaves no key on disk at all.

## Considered options

- **`.env` files or `~/.zshrc` exports.** This is dsh's default path. Rejected: plaintext on disk, readable by any file tool and by every program you run.
- **dsh's own `.credentials.yaml` (mode 0600).** Rejected: still plaintext, and headless profiles ignore it.
- **1Password CLI (`op run` with secret references).** It works as well as the Keychain and is a fine swap if you already use 1Password. It wasn't chosen because it adds a dependency the Keychain doesn't need.
- **direnv.** Rejected: it loads the keys into your interactive shell, so every command you run there sees them.

## Consequences

- Child processes get a filtered environment: dsh drops names matching `/KEY|PASSWORD|SECRET|TOKEN/i` for bash and MCP stdio servers, and PTC programs start empty. Keys also stay out of the session log, error messages and `--dump-config`. **But reads are not confined.** Bash could still run `security find-generic-password -w` and read any Keychain item you have unlocked: the sandbox allows it, and an item created with `security` trusts that tool without a prompt. So this key is out of the model's reach only while bash and PTC are off, which both bundles enforce (ADR 0003). The profile also has to deny reads of `$DSH_HOME` and stray `.env*` files once file tools return (M4).
- The launcher must `export` the keys inside the script, not pass them as `env KEY=… dsh` arguments, because process arguments show up in `ps` for anyone on the machine.
- The first Keychain read per item may show a macOS access prompt; choose "Always Allow" for `security` only.
- Tested: `scripts/checks/launchers.sh` checks that neither launcher passes the calling shell's environment to dsh and that both refuse key files, and the upgrade check's `--dump-config` snapshot runs keyless. Still untested: that a missing key gives `MISSING_CREDENTIAL`, and that `--dump-config` with the real key loaded shows no key value. Bash's environment no longer matters while both bundles keep bash off.

Decided in [Config and secrets: where do API keys and profile settings live?](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/37). Research: research/config-secrets.md.
