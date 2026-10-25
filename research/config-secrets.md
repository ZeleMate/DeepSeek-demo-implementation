# Config and secrets: where API keys and profile settings live

Research for [#37](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/37) (map #1). Builds on `research/deepseek-harness.md` (#2), `research/openrouter-models.md` (#15), `research/redteam-setup.md` (#25), ADR 0003 and ADR 0004. Checked **2026-10-19**.

Markers: **[verified]** = read in a primary source (source code, official docs, man page) on the check date. **[inferred]** = follows from verified facts but not run. **[unverified]** = not confirmed; test before relying on it.

Versions read:

| Thing | Version / commit | How |
|---|---|---|
| dsh | tag `dsh-v0.2.1-rc.2`, commit `687f282e` | git clone at tag (read, not run) |
| pi-ai (`@earendil-works/pi-ai`, used by `llm-pi-ai`) | 1.1.0 (pinned in dsh `pnpm-lock.yaml:13`), MIT | npm tarball (read, not run) |
| macOS `security` | man page on macOS 27.0.1 (build 26A434) | `man security` |
| 1Password CLI `op run` | docs page, current | [1password.dev](https://www.1password.dev/cli/reference/commands/run/) |
| direnv | docs, current | [direnv.net](https://direnv.net/), [stdlib](https://direnv.net/man/direnv-stdlib.1.html) |
| OpenRouter, OpenAI, Tavily limits | docs, current | links in section 6 |

All dsh paths below are relative to the repo root at the tag, e.g. `https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/<path>`. pi-ai paths are relative to the tarball's `package/`. No real keys were used and no money was spent. Every command below is a **plan**, not a tested recipe.

---

## TL;DR

1. **dsh has two credential planes, and the headless profile uses only one.** The managed store `$DSH_HOME/.credentials.yaml` ranks first, then the inherited process env, then `<cwd>/.env`, then `$DSH_HOME/.env`. The shipped **headless** profile disables the store, so keys come only from the **launch environment and the two `.env` files**. There is **no Keychain or secret-manager provider**; upstream lists one as deferred work.
2. **Config names keys; it never holds them.** `llm-pi-ai` takes `apiKeyEnv: OPENROUTER_API_KEY` and resolves it on every request. If the reference doesn't resolve, the request fails with `MISSING_CREDENTIAL` (fail closed). Profile settings are YAML patch layers: bundle → profile `cordis.patch.yml` → **home `$DSH_HOME/cordis.patch.yml` (applies to every profile)** → `--patch`.
3. **Where keys can leak at runtime.** `.env` values are **copied into `process.env`**. Child processes (bash, MCP stdio servers, subagents) get a scrubbed env that drops names matching `/KEY|PASSWORD|SECRET|TOKEN/i`. PTC children start with an empty env. Keys are **not** in the session log, error messages or `--dump-config`. **But reads are unconfined.** A file-read tool can read `.env`, `$DSH_HOME/.env` or `$DSH_HOME/.credentials.yaml`, and bash could also run `security find-generic-password -w`. This is why ADR 0003 turns off bash and PTC and adds a read allowlist.
4. **The launch directory is a credential source.** In headless runs the workspace is the cwd, and dsh loads `<cwd>/.env` as a key fallback. So **never launch dsh inside a repo you scan**, and don't give the canary `.env` a real provider key name.
5. **Recommendation.** Keep keys in the **macOS login Keychain**. A small committed launcher script reads them with `security find-generic-password -w` and `exec`s `dsh` with the keys set **only for that process**. Keep no keys in any `.env` and don't use the web Models page. The red-team profile gets **its own `DSH_HOME` and no provider keys at all**. `op run` is an equal alternative if you already use 1Password. direnv is not recommended.
6. **Spending caps are per provider.** OpenRouter: key credit limit with a monthly reset (402/403 `openrouter_key_limit`). OpenAI: project monthly spend limit with **"Enforce a hard limit"** (429 `project_spend_limit_exceeded`; can overshoot slightly). Tavily: a per-key monthly limit set when the key is created, inside a 1,000-credit free plan. Daytona isn't needed in v1.

---

## 1. How dsh loads configuration and credentials

### Settings (non-secret)

- A profile lives at `$DSH_HOME/profiles/<name>`. `DSH_HOME` defaults to `~/.dsh` (`packages/util/home-paths/src/index.ts:12,71`) [verified].
- The effective plugin tree is built in this order: each bundle patch from the profile manifest, then the profile's `cordis.patch.yml`, then **the home-level `$DSH_HOME/cordis.patch.yml`, which "outranks the per-profile layer"**, then each `--patch <path>` overlay in argv order. A patch replaces a row's whole `config` and doesn't deep-merge (`apps/cli/reference/README.md:11`) [verified].
- Patches may interpolate `!!js` expressions such as `!!js process.env.X` at boot (`packages/boot/app-boot/README.md:61`). `--dump-config` prints those expressions **verbatim**, not their values (`packages/boot/app-boot/README.md:73`) [verified].
- **Consequence:** anything in the home patch applies to *every* profile, the red-team profile included. A remote model route written there would reach the red-team profile and break ADR 0005 [inferred].

### `.env` files and the launch environment

- The CLI calls `loadLayeredEnv('dsh')` at startup (`apps/cli/src/bin.ts:36`). It reads `<cwd>/.env` and `$DSH_HOME/.env`, then **writes their values into `process.env` without replacing inherited names** (`packages/boot/app-boot/src/index.ts:238-259`) [verified].
- The ranking is inherited env > `<cwd>/.env` > `$DSH_HOME/.env`. The frozen snapshot remembers which layer gave each value (`packages/util/launch-environment/README.md:12`) [verified].
- `.env` files **may not set bootstrap names**: `PATH`, `HOME`, `NODE_OPTIONS`, `DEEPSEEK_BASE_URL`, CA and TLS variables, anything starting `DSH_`, `XDG_` or `DYLD_`, and more. Proxy names are allowed only in `$DSH_HOME/.env` (`packages/boot/app-boot/src/index.ts:136-169`) [verified]. So **`DSH_TELEMETRY_MODE` and `DSH_HOME` must be exported** by whatever launches dsh. They can't go in a `.env` [verified].

### Credentials

- `credentials-local` resolves a reference in this order: **`$DSH_HOME/.credentials.yaml`**, then the inherited process env, then `<cwd>/.env`, then `$DSH_HOME/.env` (`packages/credentials/credentials-local/src/index.ts:1-16`, `resolve()` at `:624`) [verified].
- The file must be mode `0600`. A group- or world-readable file stops startup (`:127-146`) [verified]. Parse errors never quote values (`:153-164`) [verified].
- The base bundle mounts `credentials-local` (`packages/bundle/base/cordis.patch.yml:113-126`). The web Models page writes to that file [verified].
- **The headless bundle disables `credentials` and `authorization`**: "One-shot jobs use launch-time credentials instead of the interactive store" (`packages/bundle/headless/cordis.patch.yml:35-40`). Its README says API-key routes then use "the launch environment, then `<invocation cwd>/.env`, then `$DSH_HOME/.env`" (`packages/bundle/headless/README.md:55`) [verified].
- **Doc drift:** `apps/cli/reference/README.md:137` lists the inherited env *before* `.credentials.yaml`. The code and the `credentials-local` comment say the file wins (a 2026-10-09 decision note). Trust the code [verified].
- **No OS secret store.** "An OS-keychain provider is deferred". The seam "leaves room for helper-command- and KMS-backed providers; none is shipped" (`packages/credentials/credentials-local/README.md:199,211`) [verified]. `CredentialProvider` is an abstract Cordis service (`resolve`, `describe`, `set`, `unset`, record methods) (`packages/credentials/credentials/src/index.ts:171-256`). So we could write a Keychain provider ourselves later [inferred].

### How `llm-pi-ai` reads a key

- `apiKeyEnv` is a credential reference, not a value (`packages/llm/llm-pi-ai/src/config.ts:93,327`) [verified].
- Each request calls `resolveApiKey`. It uses `ctx.credentials` when that service is mounted, and otherwise `launchEnvironmentOf(ctx).get(ref)`, meaning all three env layers. A miss throws `MISSING_CREDENTIAL`. An **omitted** `apiKeyEnv` falls back to pi-ai's own env discovery, and the code warns that this "would let it pick up an unrelated ambient key" (`packages/llm/llm-pi-ai/src/index.ts:188-212`) [verified].
- pi-ai's discovery maps `openrouter → OPENROUTER_API_KEY` and `openai → OPENAI_API_KEY` (`dist/env-api-keys.js:82,93`; `dist/providers/openrouter.js:15`). It reads from dsh's auth context first and then from `process.env` (`dist/utils/provider-env.js:38-43`; dsh `packages/llm/llm-pi-ai/src/auth.ts:204-215`) [verified].
- pi-ai reads **no** `OPENROUTER_BASE_URL`-style env var. A grep of `dist` finds only Azure and Cloudflare `*_BASE_URL` names [verified]. So a stray `.env` can't redirect OpenRouter traffic.
- Error messages name the reference, never the value (`packages/llm/llm/src/index.ts:151-166`). pi-ai's `No API key for provider: …` messages carry only the provider id (grep of `dist`) [verified].

### Plugins that read keys differently

- The MCP client takes `env:` (stdio) and `headers:` (HTTP) as config, usually filled with `!!js process.env.X` (`packages/mcp/mcp-client/README.md:34-53`) [verified].
- `web-search-exa` falls back to `launchEnvironmentOf(ctx).get('EXA_API_KEY')` (`packages/web/web-search-exa/src/index.ts:61`) [verified]. dsh ships **no Tavily provider**. A "Firecrawl/Tavily-style `web_extract`" is listed as deferred (`packages/web/web/README.md:154`) [verified]. Our Tavily plugin will be our own code.

---

## 2. Where keys end up at runtime

| Place | Can a key get there? | Source |
|---|---|---|
| dsh's own `process.env` | **Yes.** Inherited vars, plus every `.env` value copied in | `app-boot/src/index.ts:249-252`; `launch-environment/README.md:102` [verified] |
| Bash / `ctx.subprocess` children | Only if named explicitly. `scrubbedParentEnv()` drops names matching `/KEY\|PASSWORD\|SECRET\|TOKEN/i` and all `DSH_*` | `packages/subprocess/subprocess/src/index.ts:47,66-70`; `subprocess-local/src/spawn.ts:45` [verified] |
| MCP stdio servers | The same scrub, **plus whatever the row's `env:` hands over** | `packages/mcp/mcp-client/src/transport.ts:21-23,37` [verified] |
| PTC programs | No. "process.env starts empty" | `packages/ptc-runtime/ptc-runtime-node/src/index.ts:48,224-226` [verified] |
| macOS Seatbelt sandbox | It doesn't filter env. The profile is `(allow default)` plus `(deny file-write*)`, so **reads and network stay open** | `packages/sandbox/sandbox-local/src/profiles.ts:52`; `apps/cli/reference/README.md:131` [verified] |
| File-read tools | **Yes, if pointed at a file holding keys.** Reads are unconfined in every mode | `packages/fs/fs-sandbox/README.md:12,50` [verified] |
| `.credentials.yaml` | Same-UID readable: "the file-effect sandbox modes do not deny reads" | `credentials-local/README.md:199` [verified] |
| Session log | Not the key itself. `apiKey` is a request option, and no session or core package has an `apiKey` field. **Tool results are logged**, so a key a tool read *would* be logged | grep of `packages/session`, `packages/core` [inferred] |
| OTel telemetry | Uploads session-log prefixes after explicit feedback (`FEEDBACK_ONLY` by default). `DSH_TELEMETRY_MODE=DISABLED` builds no transport | `packages/bundle/base/cordis.patch.yml:205-225`; `session-telemetry-otel/README.md:14,36-37` [verified] |
| `session-log-deepseek` | Sends log suffixes to the official DeepSeek API only, so it doesn't apply to our pi-ai routes. Set `enabled: false` anyway | `session-log-deepseek/README.md:12,30` [verified]; scope for pi-ai routes [inferred] |
| `--dump-config`, settings UI | `!!js` shown verbatim; `role('secret')` fields redacted | `app-boot/README.md:73`; `docs/subsystems/settings.md:79` [verified] |

**Can the model read a key?** Not through dsh's normal paths: the key isn't in the prompt, the log or the errors [inferred from the rows above]. It can read one through a tool. A file tool can read any `.env` or `.credentials.yaml`. Bash can `cat` those files, or ask the Keychain through `/usr/bin/security`, which a same-user process can call. A key also reaches a tool if an MCP row forwards it. The hardened profile's job is to close these paths.

**Process env visibility.** A quick harmless test (`FOO=… sleep`, then `ps eww`) showed no env on this Mac. But it ran inside Claude Code's own sandbox, so whether same-user processes can read dsh's env is **[unverified]**.

---

## 3. macOS-native options, and how each plugs into dsh

dsh only needs the key **in its launch environment** (headless) or in `.credentials.yaml` (web/SDK). So every option comes down to "who puts the value into dsh's env at exec time".

| Option | How it works | How it plugs into dsh | Fit |
|---|---|---|---|
| **Keychain via `security`** | `security add-generic-password -a "$USER" -s dsh-demo.OPENROUTER_API_KEY -w` with `-w` last, so it prompts and the key stays out of shell history. Read it back with `find-generic-password -s … -w`, which prints only the password. "By default, the application which creates an item is trusted to access its data without warning". `-T ""` removes that default, so each read prompts (`man security`, add/find-generic-password) [verified] | A launcher script exports the values only into the `exec dsh …` process [inferred] | **Best for one Mac.** Built in, no plaintext on disk. Caveat: an item made by the CLI is readable without a prompt by `/usr/bin/security` for any same-user process [inferred from the man page], so bash in the harness must stay off. Use `-T ""` if you want a prompt on every launch |
| **1Password `op run`** | `op run --env-file=dsh.op.env -- dsh …`. The file holds `op://vault/item/field` references, which aren't secrets. Secrets exist only for the life of the subprocess. Values printed to stdout/stderr show as `<concealed by 1Password>` unless `--no-masking` is set. 1Password advises a service account scoped to the vaults a session needs ([docs](https://www.1password.dev/cli/reference/commands/run/)) [verified] | Same: wraps the `dsh` exec. The reference file can be committed [inferred] | Equal choice if you already pay for 1Password. Output masking is a nice extra for logs |
| **direnv** | Runs an authorised `.envrc` (`direnv allow`) in a subshell on `cd` and exports the diff into **your interactive shell**. `dotenv` loads a `.env`. `source_env` files "are not checked by the security framework" ([direnv.net](https://direnv.net/), [stdlib](https://direnv.net/man/direnv-stdlib.1.html)) [verified] | dsh inherits the vars from the shell [inferred] | **Not recommended.** Every command started in that directory gets the keys, including other agents such as Claude Code |
| **dotenv (`.env`)** | dsh's own `<cwd>/.env` and `$DSH_HOME/.env` layers (section 1) [verified] | Native | **Not for keys.** Plaintext, readable by file tools, and copied into `process.env`. `$DSH_HOME/.env` is shared by every profile |
| **Web Models page / `.credentials.yaml`** | Plaintext YAML at `0600`, ranked first (section 1) [verified] | Native in web/SDK/ACP; ignored by headless | Avoid. It outranks the launch env, so a forgotten stored key silently wins over the launcher's key (`packages/credentials/credentials/README.md`, "What can go wrong") [verified] |
| **Own `credentials-keychain` plugin** | Implement `CredentialProvider.resolve()` by running `security find-generic-password -w` [inferred] | Replaces `credentials-local` in the composition | Later, maybe. Nice for learning Cordis seams, but headless doesn't mount `credentials` at all, so v1 doesn't need it |

---

## 4. Constraints from ADR 0003 and ADR 0004

- **Keys must not reach the model.** The model only sees prompts and tool results [inferred], so the risk is a tool that reads a key. ADR 0003 already turns off bash and PTC. Its **read allowlist must also deny** `$DSH_HOME/**` (`.env`, `.credentials.yaml`, sessions), any `.env*` outside the canary file, and `~/Library/Keychains/**` [inferred].
- **Keys must not reach the sandbox.** Keep every key name matching `/KEY|PASSWORD|SECRET|TOKEN/i` (all ours do: `*_API_KEY`), so the subprocess scrub drops them [verified]. Never forward a key through an MCP row's `env:` or `headers:` [inferred].
- **Keys must not reach a red-team run.** The red-team profile has no remote routes (ADR 0005). Three more steps keep keys out of the process entirely [inferred]:
  - Give it **its own `DSH_HOME`** (e.g. `~/.dsh-redteam`), so it shares no home patch, `.env` or sessions with the job profile.
  - Launch it with **no provider keys in its env**: `env -u OPENROUTER_API_KEY -u OPENAI_API_KEY -u TAVILY_API_KEY`, or better, never export them in your shell at all.
  - Set only the Ollama dummy key (`research/redteam-setup.md`).
- **Fail closed.** `MISSING_CREDENTIAL` already fails the call [verified]. Our Decisions and Tavily plugins should throw on a missing key, and ADR 0003 then treats that as a hit or denial [inferred]. They should read with `launchEnvironmentOf(ctx).getFrom(ref, ['process'])`, so a `.env` in some directory can never supply them (`packages/util/launch-environment/README.md`, "Resolving a value") [verified API; usage inferred].
- **The canary.** ADR 0003 plants the canary in the workspace `.env`. In headless runs the workspace *is* the cwd (`packages/bundle/headless/README.md:74`), so dsh loads that file as a credential layer and copies it into `process.env` [verified]. Give the canary a name **no route uses** (e.g. `CANARY_SERVICE_TOKEN`). If it were called `OPENROUTER_API_KEY` and the real key were missing, dsh would send the canary to OpenRouter as the bearer token [inferred].
- **ADR 0004 (masked findings).** This research doesn't change it. Scan targets must be passed as a tool argument, **not used as the cwd**. Otherwise the scanned repo's own `.env`, possibly holding real secrets, gets copied into dsh's `process.env` [inferred].
- **Telemetry off.** `DSH_TELEMETRY_MODE=DISABLED` must be **exported** by the launcher, because `.env` can't set `DSH_*` [verified]. Also add a profile patch with `session-log-deepseek: enabled: false` [inferred].

---

## 5. Recommendation: where each key and setting lives

### Keys

| Key | Lives in | Read by | Cap |
|---|---|---|---|
| `OPENROUTER_API_KEY` | Keychain item `dsh-demo.OPENROUTER_API_KEY` | `llm-pi-ai` route `openrouter` with `apiKeyEnv: OPENROUTER_API_KEY`, from the launch env | OpenRouter key limit $30, `monthly` reset (ADR 0006) |
| `OPENAI_API_KEY` (Decisions) | Keychain item `dsh-demo.OPENAI_API_KEY`; a key from a dedicated OpenAI project | Our Decisions plugin, `getFrom('OPENAI_API_KEY', ['process'])` | Project spend limit $5 with "Enforce a hard limit" |
| `TAVILY_API_KEY` | Keychain item `dsh-demo.TAVILY_API_KEY`; a Development key | Our Tavily plugin, `getFrom(..., ['process'])` | Per-key monthly limit, e.g. 1,000 credits |
| `DAYTONA_API_KEY` | Not in v1 (`research/sandbox.md`: start local). If added later, same pattern | — | Trial credit |
| Ollama dummy (`OLLAMA_DUMMY_KEY=ollama`) | Red-team launcher only (not a secret) | `llm-pi-ai` route `ollama-local` | — |
| Canary | Generated per run, written to the workspace `.env` under a non-route name | The defence plugins | — |

Never in a `.env`, never in `$DSH_HOME/.credentials.yaml`, never in `~/.zshrc`, never in a committed file.

### Settings

| Setting | Lives in | Why |
|---|---|---|
| Plugin selection and routes (`llm-pi-ai` providers, `agent-default-model`, defences, disabled rows) | Our **bundle** `dsh.bundle.patch` files in this repo, one per profile | Reviewed in PRs; same on every run |
| Machine-only tweaks | `$DSH_HOME/profiles/<name>/cordis.patch.yml` | Per profile |
| `$DSH_HOME/cordis.patch.yml` | **`[]` (empty list)** | It outranks every profile and would leak across them. An empty or comment-only file fails boot, so use `[]` (`app-boot/README.md:61`) |
| `DSH_HOME`, `DSH_TELEMETRY_MODE=DISABLED`, `DSH_PERMISSION_MODE` | Exported by the launcher | Bootstrap-only; refused from `.env` |
| `$DSH_HOME/.env` | Absent | Shared fallback for every profile |
| `.env.example` in this repo | Rewrite it to list Keychain service names, not `KEY=` lines | So nobody creates a plaintext `.env` by habit |

### Launcher shape (plan, not run)

```sh
#!/bin/sh
# bin/dsh-job: job profile. Keys come from the login Keychain, only for this process.
set -eu
k() { security find-generic-password -a "$USER" -s "dsh-demo.$1" -w; }
cd "${DSH_JOB_WORKSPACE:?set a dedicated job workspace, never the scanned repo}"
exec env \
  DSH_HOME="$HOME/.dsh" DSH_TELEMETRY_MODE=DISABLED \
  OPENROUTER_API_KEY="$(k OPENROUTER_API_KEY)" \
  OPENAI_API_KEY="$(k OPENAI_API_KEY)" \
  TAVILY_API_KEY="$(k TAVILY_API_KEY)" \
  dsh --profile job "$@"
```

```sh
#!/bin/sh
# bin/dsh-redteam: no provider keys at all; separate home.
set -eu
cd "${DSH_REDTEAM_WORKSPACE:?}"
exec env -u OPENROUTER_API_KEY -u OPENAI_API_KEY -u TAVILY_API_KEY -u DAYTONA_API_KEY \
  DSH_HOME="$HOME/.dsh-redteam" DSH_TELEMETRY_MODE=DISABLED OLLAMA_DUMMY_KEY=ollama \
  dsh --profile redteam "$@"
```

With 1Password, the job launcher becomes `exec op run --env-file=dsh.op.env -- env DSH_HOME=… dsh --profile job "$@"` [inferred].

**[Unverified] before relying on this:**

- That `dsh --profile job --dump-config` shows no key values.
- That a headless turn with `OPENROUTER_API_KEY` unset fails with `MISSING_CREDENTIAL`.
- That `env` inside a bash tool call (in a scratch profile with bash on) shows no `*_API_KEY`.
- Whether Keychain shows a prompt on first `security` read from a new terminal app.

---

## 6. Per-key spending limits

| Provider | Mechanism | When exceeded | Source |
|---|---|---|---|
| **OpenRouter** | Per-key `limit` (credits), plus `limit_reset` for daily, weekly or monthly reset at UTC midnight. Set via the dashboard or the Management API (`POST /api/v1/keys`, `PATCH /api/v1/keys/{hash}`). `GET /api/v1/key` returns `limit_remaining`, `usage_daily`, `usage_weekly`, `usage_monthly` and `effective_budget` | 402 with `limit_source: openrouter_key_limit`. The budget section of the same page lists 403 for the same source, so check actual responses | [limits](https://openrouter.ai/docs/api_reference/limits.md), [management keys](https://openrouter.ai/docs/guides/overview/auth/management-api-keys.md) [verified; the exact `limit_reset` strings are not fully listed] |
| **OpenAI** | Project settings → Limits → monthly spend limit, plus **"Enforce a hard limit"**. Without that toggle it is only an alert. It applies to traffic billed to the project | 429 `project_spend_limit_exceeded`. "Enforcement is not instantaneous", so spend can slightly overshoot. Resets monthly | [spend limits](https://developers.openai.com/api/docs/guides/spend-limits.md) [verified] |
| **Tavily** | Free plan: "1,000 free API Credits every month", no card. Each new key gets a type (Development, 100 RPM; Production, 1,000 RPM) and a **monthly limit** | Plan limit gives HTTP 432; pay-as-you-go limit gives 433 (help centre). Leave pay-as-you-go off | [credits](https://docs.tavily.com/documentation/api-credits) [verified]; [create key](https://help.tavily.com/articles/9170796666-how-can-i-create-an-api-key) [verified, article "updated 1 year ago"]; 432/433 codes [unverified, from search summary of help.tavily.com] |
| **Daytona** | Not needed in v1 | — | `research/sandbox.md` |

dsh's own token meter uses an out-of-date price table (`research/openrouter-models.md`), so these provider-side caps are the real hard stop.

---

## Corrections to earlier notes

- `research/openrouter-models.md` gives the credential precedence correctly (file > env > cwd `.env` > home `.env`), but it doesn't say that **headless disables the store**. For our job runs, only the env and `.env` layers apply.
- `.env.example` on `main` invites a plaintext `.env` with real keys. If dsh is launched from the repo root, that file is a credential layer. Replace it as described in section 5.

## Sources

- dsh `dsh-v0.2.1-rc.2`:
  - `apps/cli/src/bin.ts`, `apps/cli/reference/README.md`
  - `packages/boot/app-boot/{README.md,src/index.ts}`, `packages/util/launch-environment/README.md`, `packages/util/home-paths/src/index.ts`
  - `packages/credentials/{credentials,credentials-local}/{README.md,src/index.ts}`
  - `packages/bundle/base/cordis.patch.yml`, `packages/bundle/headless/{cordis.patch.yml,README.md}`
  - `packages/llm/llm-pi-ai/src/{index,auth,config}.ts`, `packages/llm/llm/src/index.ts`
  - `packages/subprocess/subprocess/{README.md,src/index.ts}`, `packages/subprocess/subprocess-local/src/spawn.ts`
  - `packages/mcp/mcp-client/{README.md,src/transport.ts}`, `packages/ptc-runtime/ptc-runtime-node/src/index.ts`
  - `packages/sandbox/sandbox-local/src/profiles.ts`, `packages/fs/fs-sandbox/README.md`
  - `packages/session/{session-log-deepseek,session-telemetry-otel}/README.md`
  - `packages/web/{web/README.md,web-search-exa/src/index.ts}`, `docs/subsystems/settings.md`
- pi-ai 1.1.0: `dist/env-api-keys.js`, `dist/utils/provider-env.js`, `dist/auth/helpers.js`, `dist/providers/openrouter.js`
- macOS `security(1)` man page (macOS 27.0.1)
- 1Password: <https://www.1password.dev/cli/reference/commands/run/>
- direnv: <https://direnv.net/>, <https://direnv.net/man/direnv-stdlib.1.html>
- OpenRouter: <https://openrouter.ai/docs/api_reference/limits.md>, <https://openrouter.ai/docs/guides/overview/auth/management-api-keys.md>
- OpenAI: <https://developers.openai.com/api/docs/guides/spend-limits.md>
- Tavily: <https://docs.tavily.com/documentation/api-credits>, <https://help.tavily.com/articles/9170796666-how-can-i-create-an-api-key>, <https://docs.tavily.com/documentation/rate-limits>
