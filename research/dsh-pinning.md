# Pinning and upgrading dsh: how we follow its prereleases

Research for [#36](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/36). Builds on `research/deepseek-harness.md` (#2), `research/redteam-setup.md` (#25) and [ADR 0001](../docs/adr/0001-build-on-deepseek-harness.md). Checked **2026-10-19**.

Markers: **[verified]** = read in a primary source (source code, release notes, registry, official docs) on the check date. **[inferred]** = follows from verified facts but not run. **[unverified]** = not confirmed; test before relying on it.

Versions read:

| Thing | Version / commit | How |
|---|---|---|
| dsh | tag `dsh-v0.2.1-rc.2`, commit `687f282`; `master` is at the same commit | blobless git clone with all 32 tags |
| dsh releases | all 31 GitHub releases, `dsh-v0.1.0-rc.7` … `dsh-v0.2.1-rc.2` | `gh api repos/deepseek-ai/deepseek-harness/releases` |
| `@deepseek-ai/dsh` on npm | 36 versions, dist-tags `latest` = `next` = `0.2.1-rc.2`, `alpha` = `0.2.1-alpha.5` | `npm view` |
| `@deepseek-ai/dsh-llm-pi-ai` | `0.2.1-rc.2` | `npm pack` (read, not run) |
| pi-ai (`@earendil-works/pi-ai`) | 1.1.0 in dsh's lockfile; 1.3.0 is npm `latest` (2026-10-15) | dsh `pnpm-lock.yaml`; `npm view`; `npm pack` of 1.3.0 |
| Cordis (`@deepseek-ai/cordis`) | 4.0.5 (vendored in dsh) | `vendor/cordis/package.json`; `npm view` |
| pnpm docs | pnpm 11 docs on 2026-10-19 (dsh itself pins `pnpm@11.28.5`) | pnpm.io |

**There is no dsh release newer than `dsh-v0.2.1-rc.2`.** The newest tag, the newest GitHub release, the npm `latest` tag and `master` all point at rc.2 (2026-10-17) [verified]. Nothing was installed or run. The only command with a network side effect was `npm install --package-lock-only --ignore-scripts` in an empty scratch folder, which resolves versions without downloading or running package code.

---

## TL;DR

1. **dsh ships as about 86 npm packages under `@deepseek-ai/`, released in lockstep.** The CLI `@deepseek-ai/dsh` pins every `@deepseek-ai/dsh-*` package to the exact same version. Its third-party dependencies, and Cordis and Schemastery, use `^` or `~` ranges. Every release so far is a prerelease, and npm's **`latest` tag points at a prerelease**, so `npx @deepseek-ai/dsh` floats to whatever was published last.
2. **The cadence is fast.** There were 31 GitHub releases in 61 days (2026-08-17 to 2026-10-17), roughly one every two days. The 0.2.1 line alone had 7 releases in 14 days. An `rc` is close to the `alpha` before it (alpha.5 to rc.1 was 4 commits, rc.1 to rc.2 was 9 commits).
3. **The installed dsh does not match dsh's own tested build.** dsh's repo patches pi-ai 1.1.0 with pnpm `patchedDependencies` (an O(n²) streaming fix). The published `dsh-llm-pi-ai` asks for `pi-ai ^1.1.0`. A fresh npm resolution of `@deepseek-ai/dsh@0.2.1-rc.2` today picks **pi-ai 1.3.0, unpatched**. pnpm applies patches only from the top-level project, so **our repo must carry that patch itself** if we want it.
4. **dsh's stability promises are narrow but real.** There are none for the plugin API or config schema: the README says "THERE WILL BE COMPATIBILITY-BREAKING CHANGES". But (a) released session-log formats, prereleases included, are migration obligations, and the format has stayed at V4 since 0.1.7-alpha.1; (b) every breaking change since 0.2.0-rc.2 gets a written **upgrade guide** under `docs/upgrade-guide/<from-version>/`; (c) a bundle's **`engines.dsh` range is enforced** at install and at profile startup.
5. **Each release breaks something, mostly outside our surface.** From 0.2.0-rc.2 to 0.2.1-rc.2 there were 32 upgrade guides. About 9 of them touch a bundle like ours: tool presentation mode, `agent-instructions`, pi-ai route model discovery, credential precedence in headless, `engines.dsh`, profile reset. Cordis itself barely moved: one changed line in `vendor/cordis` across that range.
6. **Recommendation:** pin dsh as an exact devDependency in our pnpm workspace and run it with `pnpm exec dsh`. Commit the lockfile. Re-apply dsh's pi-ai patch through our own `overrides` + `patchedDependencies`. Declare an exact `engines.dsh` in every bundle so a version mismatch fails closed. Follow **rc releases only**, one PR per rc. Run a $0 upgrade check: frozen install, typecheck and tests, a config-dump diff, and a headless smoke turn against local Ollama.

---

## 1. How dsh is distributed

### npm packages and tags

- **Package and scope.** The CLI is `@deepseek-ai/dsh`, with bin `dsh` → `lib/bin.js`. Its repository field points at `apps/cli` in the monorepo (`npm view @deepseek-ai/dsh@0.2.1-rc.2`) [verified].
- **Lockstep versions.** It has 86 dependencies. 78 are `@deepseek-ai/dsh-*` packages pinned to exactly `0.2.1-rc.2`. The other eight use ranges: `@deepseek-ai/cordis ~4.0.5`, `@deepseek-ai/schemastery ~3.18.5`, three `cordis-plugin-*` packages with `~`, plus `js-yaml ^4.3.2`, `commander ^15.0.0` and `node-addon-require-builtin ^0.1.9` (same source) [verified].
- **Third-party ranges float.** `@deepseek-ai/dsh-llm-pi-ai@0.2.1-rc.2` depends on `@earendil-works/pi-ai ^1.1.0`, and declares Cordis and other dsh packages as peers (`npm view … dependencies peerDependencies`) [verified].
- **Dist-tags.** `latest: 0.2.1-rc.2`, `next: 0.2.1-rc.2`, `alpha: 0.2.1-alpha.5` [verified]. The publish script uses npm's `latest` default unless a release passes an explicit tag, and it refuses to move an existing tag (`scripts/release/publish.ts`, `publishTarball`, `verifyDistTag`) [verified]. So **`latest` is simply the newest publish, prerelease or not** [inferred].
- **Publishing.** Releases go out by a manual `workflow_dispatch` from a `dsh-v*` tag, with `pnpm install --frozen-lockfile` and a "verify packed install" step, behind a protected `npm-publish` environment (`.github/workflows/release-publish.yml`) [verified]. The publish step uses an `NPM_TOKEN`. The npm metadata has registry signatures but **no provenance attestation** (`dist.attestations` is empty) [verified]. No version is marked deprecated [verified].
- **GitHub releases have no assets.** All 31 have empty `assets` and are marked `immutable: true` (releases API) [verified]. The desktop app ships through a separate workflow (`desktop-publish.yml`) [verified that the file exists; not read].

### Tags vs npm vs releases

| Source | Count | Notes |
|---|---|---|
| git tags | 32 | includes `dsh-v0.1.5-rc.3`, which has no GitHub release [verified] |
| GitHub releases | 31 | all prerelease, all immutable [verified] |
| npm versions of `@deepseek-ai/dsh` | 36 | adds `0.0.1-rc.*` and `0.1.0-rc.2/3/6`, which predate the tags; `0.1.2-alpha.1` and `0.1.3-alpha.1` are tagged but not on npm [verified] |

### Release cadence

| Line | Releases (GitHub) | Span | Commits, first→last tag |
|---|---|---|---|
| 0.1.0–0.1.2 | 10 | 2026-08-17 → 09-03 | — |
| 0.1.3–0.1.7 | 11 | 2026-09-04 → 09-24 | — |
| 0.2.0 | 2 (rc.1, rc.2) | 2026-09-28 → 09-29 | 187 |
| 0.2.1 | 7 (alpha.1–5, rc.1–2) | 2026-10-03 → 10-17 | 266 + 669 + 852 + 89 + 36 + 4 + 9 |

Sources: `gh release list`; `git rev-list --count <a>..<b>` between consecutive tags [verified]. The pattern is a burst of alphas, then one or two rcs a few hours apart. **rc.1 → rc.2 took under three hours** (05:22 → 08:16 UTC on 2026-10-17) [verified]. The rc.1 release notes are cumulative from `dsh-v0.2.0-rc.2` (they link that compare range) [verified], so an rc's notes describe the whole line.

### What the options mean for a bundle repo like ours

| Option | What it gives | Problems | Verdict |
|---|---|---|---|
| **Exact npm version as a devDependency, run via `pnpm exec dsh`** | One lockfile pins dsh and every transitive version. Upgrades are one-line diffs plus a lockfile diff. | Third-party ranges resolve differently from dsh's own lockfile (pi-ai 1.3.0 vs 1.1.0, see §4). dsh's own pnpm patches are not applied. | **Use this**, with our own overrides and patch [inferred] |
| `npx @deepseek-ai/dsh` or a global install | Simplest; what the README shows (`README.md`, "Run from npm") [verified] | `npx` without a version follows `latest`, a prerelease; a global install is not recorded in the repo | Avoid [inferred] |
| Git submodule of the dsh repo at the tag, run from source | Exactly dsh's lockfile and patches (`pnpm install`, `pnpm run build`, `pnpm dsh`; `README.md`, "Run from source") [verified] | A full monorepo build on every upgrade; mixes dsh's workspace with ours | Fallback for debugging dsh itself [inferred] |
| pnpm git dependency (`github:deepseek-ai/deepseek-harness#dsh-v0.2.1-rc.2&path:/apps/cli`) | pnpm supports tag selectors and `path:` subdirectories (pnpm [package sources](https://pnpm.io/package-sources)) [verified] | `apps/cli/package.json` has 130 `workspace:` dependencies, which cannot resolve outside the monorepo [verified count]; git installs ship sources and need a build (`docs/user/develop/basic/publish.md`) [verified] | Don't [inferred] |
| pnpm workspace link to a local dsh checkout | Fast iteration on dsh internals | Same costs as the submodule; nothing is pinned unless the checkout is | Only while debugging dsh [inferred] |

How our bundle meets the runtime: a profile under `$DSH_HOME/profiles/<name>` installs our package with `dsh plugin --profile <name> add <path>`, which writes a `link:` dependency. In-box bundles such as `@deepseek-ai/dsh-base` "always resolve from the dsh installation itself". A linked plugin should declare the dsh packages it shares with the host as **both** `peerDependencies` and `devDependencies`. Peers resolve to the running installation's copy, and the devDependency copy serves the type checker and tests (`docs/user/develop/basic/publish.md`, "Install into a profile" and "The loading order") [verified]. So **the dsh version that matters at runtime is the `dsh` binary we launch**, and the devDependency versions must match it [inferred].

---

## 2. What dsh promises about stability

| Surface | Promise | Source |
|---|---|---|
| Overall | "developer preview … **THERE WILL BE COMPATIBILITY-BREAKING CHANGES.**" | `README.md` [verified] |
| Plugin API (Cordis core) | No written promise. In practice Cordis is very stable: 4.0.1 → 4.0.5 over all releases; `vendor/cordis/src` changed 9+/6− lines from 0.1.5-rc.2 to 0.1.7-rc.2, and one line from 0.1.7-rc.2 to 0.2.1-rc.2 | `vendor/cordis/package.json` at tags; `git diff --shortstat` [verified] |
| dsh service APIs (`ctx.tools`, `ctx.llm`, sessions, …) | No promise. They do break: `ctx.agent` removed (0.1.5), `SessionHandle` ownership (0.1.3-alpha.1), `./invariant` exports removed (0.2.1-alpha.1), synchronous session history APIs deprecated (0.1.6/0.1.7) | release notes [verified] |
| Config schema | No promise, but it is generated and checkable: `docs/config-catalog.md` changes in nearly every release (e.g. +305/−145 lines in 0.2.1-alpha.2), and `dsh --dump-config-schema` prints the JSON Schema of profile entries | `git diff --shortstat` per tag; `docs/cli-help.md` [verified] |
| Session log format | **Strong.** "An alpha, beta, or release-candidate product publication establishes released Session-format obligations. GitHub's prerelease flag does not make persisted user data disposable." Formats migrate forward through immutable adjacent steps; **downgrade reads are not supported** (V3 notes) | `docs/session-format-status.md`; 0.1.5 release notes [verified] |
| Session format history | `SESSION_FORMAT_VERSION`: 0 until 0.1.2-rc.1, 2 from 0.1.3-alpha.1, 3 from 0.1.5-alpha.1, **4 from 0.1.7-alpha.1 (2026-09-22) through rc.2** | `packages/core/session/src/types.ts` at every tag [verified] |
| Changelogs | Bilingual release notes per tag, with a "Chores"/"Other Changes" section where breaking items usually sit, sometimes labelled "Breaking change" | releases API [verified] |
| Upgrade guides | One `guide.md` per breaking change at `docs/upgrade-guide/<from-version>/<slug>/guide.md`, with "Change" and "Migration" steps. **The folder names the release you upgrade *from*.** For example, `v0.2.1-alpha.3/plugin-engines-dsh` describes a change that shipped in alpha.4 ("In v0.2.1-alpha.3 … In the next release …"). 42 guides exist at rc.2; the first ones were added in 0.2.0-rc.2 | `docs/upgrade-guide/` tree; guide text; per-tag `git diff --diff-filter=A` [verified] |
| Plugin compatibility | `engines.dsh` (a semver range) decides alone if present; otherwise the `@deepseek-ai/dsh*` peer ranges decide. Prereleases take part in ranges (`includePrerelease: true`). Install and profile startup **refuse** a mismatch unless an exact `name@version` × runtime exemption is granted with `dsh plugin allow-version` | `packages/boot/app-boot/src/plugin-compatibility.ts`; `docs/user/develop/basic/publish.md` [verified] |
| Community tooling | The 0.1.2-rc.1 notes point plugin authors to a community skill for upgrading plugin code across dsh versions (`oh-my-dsh/dsh-plugin-upgrade-skill`) | release notes [verified that it is linked; repo not read] |

So ADR 0001's "following dsh's upgrade guide" is concrete: read every `docs/upgrade-guide/<v>/` folder for each version from our current pin up to, but not including, the target [inferred from the folder convention].

---

## 3. What changed between releases (a sample of how much breaks)

Diff counts between consecutive tags. "src pkgs" counts packages with changes under `src/`; nearly every package's `package.json` changes on each release because of the lockstep version bump. "Seam files" counts non-test, non-doc files changed under `packages/core`, `packages/llm/llm`, `packages/llm/llm-pi-ai`, `packages/boot` and `vendor/cordis`. "Guides" counts new upgrade guides.

| From → to | Commits | Files | src pkgs | Seam files | config-catalog diff | Guides | pnpm patches changed |
|---|---|---|---|---|---|---|---|
| 0.1.5-rc.2 → 0.1.6-alpha.1 | 800 | 3942 | 169 | 52 | +326/−169 | 0 | osx-sign, pkg |
| 0.1.6-alpha.1 → alpha.2 | 887 | 2622 | 90 | 40 | +199/−15 | 0 | — |
| 0.1.6-alpha.2 → 0.1.7-alpha.1 | 1299 | 4754 | 195 | 77 | +490/−171 | 0 | **pi-ai 0.85.1**, fortune-sheet, pkg |
| 0.1.7-alpha.1 → alpha.2 | 162 | 869 | 36 | 8 | +31/−16 | 0 | exceljs |
| 0.1.7-alpha.2 → rc.1 | 156 | 933 | 38 | 16 | +19/−7 | 0 | fortune-sheet |
| 0.1.7-rc.1 → rc.2 | 346 | 3429 | 109 | 35 | +878/−702 | 0 | fortune-sheet |
| 0.1.7-rc.2 → 0.2.0-rc.1 | 261 | 1109 | 52 | 9 | +49/−15 | 0 | — |
| 0.2.0-rc.1 → rc.2 | 187 | 1022 | 38 | 4 | +23/−3 | 2 | **pi-ai 0.87.1** |
| 0.2.0-rc.2 → 0.2.1-alpha.1 | 266 | 4190 | 86 | 55 | +47/−28 | 4 | — |
| 0.2.1-alpha.1 → alpha.2 | 669 | 3226 | 139 | 44 | +305/−145 | 20 | **pi-ai 1.0.2**, node-pty |
| 0.2.1-alpha.2 → alpha.3 | 852 | 3311 | 107 | 63 | +87/−47 | 14 | **pi-ai 1.1.0**, app-builder-lib |
| 0.2.1-alpha.3 → alpha.4 | 89 | 831 | 27 | 21 | +32/−1 | 1 | — |
| 0.2.1-alpha.4 → alpha.5 | 36 | 586 | 13 | 5 | 0 | 1 | — |
| 0.2.1-alpha.5 → rc.1 | 4 | 355 | 0 | 0 | 0 | 0 | — |
| 0.2.1-rc.1 → rc.2 | 9 | 456 | 6 | 0 | +35/−5 | 0 | — |

Source: `git diff --name-only/--shortstat` and `git rev-list --count` between tags in the clone [verified]. The pi-ai patch was re-cut on every pi-ai bump: 0.82.1 (0.1.0-rc.7) → 0.84.2 → 0.85.1 → 0.87.1 → 1.0.2 → 1.1.0 (`pnpm-workspace.yaml` at tags) [verified].

### Breaking items from 0.2.0-rc.2 to 0.2.1-rc.2 that touch a bundle like ours

These come from the upgrade guides and the rc.1 notes [verified]. Which ones touch us is my reading of our ADRs [inferred].

| Change | Guide | Why it matters to us |
|---|---|---|
| Tool presentation accepts only `native` or `ptc`; `both` is rejected | `v0.2.1-alpha.1/tool-presentation-mode` | ADR 0003 turns PTC off; our profile config names this mode |
| `agent-instructions` no longer accepts `dshHome` | `v0.2.1-alpha.1/instruction-home-override` | AGENTS.md loading config |
| Python PTC requires sandbox services; file ops follow the file policy | `v0.2.1-alpha.1/python-ptc-sandbox` | Sandbox and policy composition (ADR 0003) |
| Session working directories replace built-in cwd config | `v0.2.1-alpha.1/working-directory` | Read-path policy |
| `dsh plugin` reads `--profile` only before the pnpm args | `v0.2.1-alpha.1/plugin-option-placement` | Our setup scripts |
| pi-ai routes that name a credential hide their models until it is set | `v0.2.1-alpha.2/pi-ai-model-discovery` | The OpenRouter route |
| Stored credentials beat env vars; **the headless profile ignores the credential store** | `v0.2.1-alpha.2/stored-credentials-precedence` | Job runs use headless and env keys |
| `--from-default-profile` now **deletes and replaces** an existing profile, including its `cordis.patch.yml` | `v0.2.1-alpha.2/from-default-profile-replaces-target` | Can wipe the user-owned profile patch |
| `engines.dsh` decides alone when present | `v0.2.1-alpha.3/plugin-engines-dsh` | Our pinning mechanism (§5) |

Other changes to watch for in our base-row overrides: between 0.1.7-rc.2 and 0.2.1-rc.2 the base bundle **moved the telemetry exporter URL** (`harness-telemetry.deepseeksvc.com` → `dsh-otel-collector.deepseeksvc.com`), added `maxRequestBytes`, and added new rows (`remote-access`, `working-directory`, `otel`) (`packages/bundle/base/cordis.patch.yml` diff) [verified]. Telemetry is switched off by the `DSH_TELEMETRY_DISABLED` environment variable ("any value"), not by row config (same file, comment above `session-telemetry-otel`) [verified]. Keep using the env var, so a moved endpoint does not matter [inferred].

**How much breaks:** each alpha has carried 1–20 guides; the two rcs carried none of their own. For a bundle that uses only seams (tools, hooks, `llm-pi-ai` config, MCP, sandbox policy), expect a handful of config edits per minor line, rarely code [inferred from the table]. The session format has not moved for 13 releases [verified].

---

## 4. Keeping the patches alive across upgrades

There are three different "patches". Keep them apart.

### 4a. dsh's pi-ai pnpm patch (a supply-chain patch, not ours)

- **What it is.** `patches/@earendil-works__pi-ai@1.1.0.patch` deletes the per-delta `parseStreamingJson(...)` re-parse in six pi-ai stream adapters, including `openai-completions.js`, which our OpenRouter and Ollama routes use. Unpatched, "a multi-megabyte argument stream costs O(n²) CPU on the event loop and stalls every session in the process". dsh says: "Re-apply or retire the patch on every pi-ai upgrade" (`packages/llm/llm-pi-ai/README.md`, Known Limitations; the patch file) [verified].
- **Upstream is not fixed.** [earendil-works/pi#9265](https://github.com/earendil-works/pi/issues/9265) is open (reopened) [verified]. pi-ai 1.3.0 still has `block.arguments = parseStreamingJson(block.partialArgs)` at `dist/api/openai-completions.js:456` [verified].
- **npm users do not get it.** dsh registers the patch in its own root `pnpm-workspace.yaml` (`patchedDependencies`) [verified]. pnpm reads `patchedDependencies` from the "top-level manifest" (pnpm [patch docs](https://pnpm.io/cli/patch)) [verified]. The published `dsh-llm-pi-ai` imports pi-ai straight from `node_modules` (`lib/index.js` lines 9–13) and has no copy of the fix [verified]. A lockfile-only resolution of `@deepseek-ai/dsh@0.2.1-rc.2` in an empty folder resolved **`@earendil-works/pi-ai` 1.3.0** [verified]. dsh tested 1.1.0 [verified]. **Correction:** `research/redteam-setup.md` lists "pi-ai 1.1.0 (dsh lockfile, patched)". That is true only for a source checkout, not for an npm install.
- **How we keep it.** In our root `pnpm-workspace.yaml`:

  ```yaml
  overrides:
    '@earendil-works/pi-ai': 1.1.0        # = dsh's lockfile at the pinned tag
  patchedDependencies:
    '@earendil-works/pi-ai@1.1.0': patches/@earendil-works__pi-ai@1.1.0.patch   # copied verbatim from the dsh tag
  ```

  `overrides` "can only be set at the root of the project" and accept `name@range` and `parent>child` selectors (pnpm [dependency resolution](https://pnpm.io/settings/dependency-resolution)) [verified]. In pnpm 11, "patch application failures always throw an error", and an unused patch fails install unless `allowUnusedPatches` is set (pnpm patch docs) [verified]. So a forgotten re-cut breaks the install loudly instead of silently [inferred]. Whether pnpm applies a root override and patch to a package reached only through a dependency chain is not stated on those pages **[unverified]**. Check with `pnpm why @earendil-works/pi-ai` and a grep of the installed file.
- **On each upgrade:** read dsh's `pnpm-workspace.yaml` at the new tag. If the pi-ai key changed, copy the new patch file and update both lines. If dsh dropped the patch, drop ours [inferred].

### 4b. Our bundle patch (`dsh.bundle.patch`, in the repo)

- A later layer "replaces a row's entire `config` value rather than deep-merging keys". A bundle that overrides a base row "must restate every key the row needs" (`docs/user/develop/basic/publish.md`, "The loading order") [verified]. So **every base row we override is a copy that drifts** when dsh changes that row. Example: the base `session-telemetry-otel` row gained `maxRequestBytes` and changed its URL between 0.1.7-rc.2 and 0.2.1-rc.2 [verified].
- Keep it alive by (1) **inserting our own rows** and avoiding overrides of base rows where we can; (2) keeping a short list of base row ids we override; (3) on upgrade, running `git diff <old-tag> <new-tag> -- packages/bundle/base/cordis.patch.yml packages/bundle/headless/cordis.patch.yml` and checking each listed id; (4) diffing `dsh --profile <ours> --dump-config` before and after (§6) [inferred].

### 4c. The user-owned profile patch (`$DSH_HOME/profiles/<name>/cordis.patch.yml`, out of the repo)

- It is applied after every bundle layer, before the home patch and `--patch` overlays (`publish.md`, "The loading order") [verified]. It has the same whole-row replacement rule, so a per-machine override of a row our bundle sets must restate that row too [inferred].
- **The real risk is deletion, not drift.** Since 0.2.1-alpha.3, `--from-default-profile` deletes the profile directory, "including its `package.json` dependencies, installed `node_modules`, and `cordis.patch.yml`" (`docs/upgrade-guide/v0.2.1-alpha.2/from-default-profile-replaces-target/guide.md`) [verified]. Never use that flag on our profiles. Before an upgrade, copy the patch aside, as the guide itself advises [verified].
- Keep it small: only machine-specific values, such as paths, the local Ollama URL and env-var names. Then a schema change touches few lines [inferred]. A committed `*.example.yml` beside the bundle would show its expected shape without breaking ADR 0001's "stays out of the repo" rule [inferred].

---

## 5. A cheap upgrade check ($0, no remote models)

Run these in the upgrade PR, in order. Each step is cheap, and each catches a different class of break [inferred]:

1. **Install gate.** `pnpm install --frozen-lockfile` after bumping the versions. It fails if the pi-ai patch no longer applies (pnpm 11) [verified behaviour]. Then grep the installed `openai-completions.js` to confirm the patched line is gone [inferred].
2. **Compatibility gate.** Every bundle declares `"engines": { "dsh": "<exact pinned version>" }`. dsh "refuse[s] a bundle whose range the running DSH does not satisfy" at install and at startup (`publish.md`; `plugin-compatibility.ts`) [verified]. A half-done upgrade, such as a new dsh binary with an old bundle, then fails closed before any agent runs [inferred]. Don't grant `dsh plugin allow-version` exemptions; bump the range in the same PR.
3. **Types and unit tests.** `tsc -b` and `vitest` against the new dsh devDependencies. This catches removed exports and changed service types, like the `./invariant` removal or `ctx.agent` [inferred].
4. **Config snapshot diff.** Commit the output of `dsh --profile job --dump-config` and `dsh --profile redteam --dump-config`, plus `dsh --profile job --dump-config-schema` filtered to the rows we configure. Diff after the bump. New, removed or changed rows show up before anything runs (`docs/cli-help.md` lists both flags) [verified flags; snapshot idea inferred]. The dump also shows whether a profile patch still lands where intended.
5. **Headless smoke turn, local model.** `dsh --profile redteam headless --json` (through the wrapper from #25) against Ollama `qwen3.5:4b`, with three fixed tasks: read a file, call a tool on our test MCP server, and attempt a write outside the allowed paths, which the defences must deny. Assert on the NDJSON events, not on model wording [inferred]. Run with `DSH_TELEMETRY_DISABLED=1` [verified variable].
   - A fully scripted alternative is dsh's `@deepseek-ai/dsh-llm-mock-server`. It is a "Scriptable Messages-compatible fault server … without a provider key" that can script tool calls (`packages/test-support/llm-mock-server/README.md`) [verified]. But npm has only an old `0.0.1-rc.1` of it [verified], so it would have to come from a dsh source checkout. Ollama is simpler for us [inferred].
6. **Session continuity.** Keep one committed session written by the old version, from a scratch `DSH_HOME`, and resume it with `--session-id` on the new version. Upgraded logs cannot be read by an older dsh, so **back up `$DSH_HOME` before upgrading** your real machine (`docs/session-format-status.md`; V3 notes) [verified rule; test inferred].
7. **Attack set, small slice.** Re-run a fixed subset of the Promptfoo attack set and compare the attack success rate with the pinned version. A defence that silently stopped firing, for example because a hook was renamed, shows up here and nowhere else [inferred].

Steps 1–4 run in seconds to minutes with no model. Steps 5–7 use only the local Ollama model. None costs money [inferred].

---

## 6. Recommended pinning and upgrade policy

### Pinning

1. Root `package.json` lists `"@deepseek-ai/dsh": "0.2.1-rc.2"` (exact, no `^`) as a devDependency. Always launch it with `pnpm exec dsh` or a package script, **never bare `npx @deepseek-ai/dsh`**. Also pin `packageManager` (pnpm 11) and `engines.node` (`^22.19.0 || >=24.0.0`, same as dsh's root `package.json`) [verified versions; policy inferred].
2. Commit `pnpm-lock.yaml` and install with `--frozen-lockfile`. The lockfile freezes the `~`/`^` ranges (Cordis, Schemastery, pi-ai, MCP SDK) that the exact dsh version leaves open [inferred].
3. Root `pnpm-workspace.yaml` carries `overrides` and `patchedDependencies` for pi-ai, matching dsh's lockfile and patch at the pinned tag (§4a). Also consider dsh's own supply-chain setting `minimumReleaseAge` (default 1440 minutes in pnpm 11) [verified default].
4. Every plugin package lists the `@deepseek-ai/dsh-*` packages it imports as `peerDependencies` **and** `devDependencies`, both at the exact pinned version (`publish.md`) [verified guidance]. Every bundle package declares `"engines": { "dsh": "0.2.1-rc.2" }` [verified mechanism].
5. Write the pinned version in **one place a script can read**, for example `dsh-version.txt`, and have a test assert that all of the above agree [inferred].

### Upgrading

<!-- markdownlint-disable MD029 -- numbering continues from Pinning (1–5), and §6.6–6.11 are cited -->
6. **Follow rc releases, skip alphas.** An rc is the settled end of a line. The two rcs carried no new upgrade guides, and the rc notes are cumulative [verified]. Skipping alphas skips the 1–20 guides per alpha arriving one by one; we read them in one batch instead [inferred]. This amends ADR 0001's "one release at a time" to **"one rc at a time"**.
7. **Wait about three days after an rc before upgrading.** rc.2 followed rc.1 within three hours [verified], so a fresh rc may be superseded quickly [inferred].
8. **One PR per upgrade.** It bumps every pin in §6.1–5 together, re-cuts the pi-ai patch if dsh did, records the reading of every `docs/upgrade-guide/<v>/` folder from the old pin up to the new one, updates the config snapshots, and must pass the upgrade check in §5.
9. **Read the release notes' Chores section and the guides first.** Do this before bumping, and list which guides touch us in the PR description. The table in §3 is the template [inferred].
10. **No forks, no exemptions.** If an upgrade needs a dsh code change, stay on the old pin and raise it in dsh Discussions (issues are off: `has_issues: false`) [verified]. ADR 0001 already limits forking to "a bundle can't do something".
11. **Rollback means reverting the PR and restoring the `$DSH_HOME` backup.** Upgraded session logs can't be read by the old version [verified].
<!-- markdownlint-enable MD029 -->

**Watching for releases** (cheap, no service needed): `gh release list -R deepseek-ai/deepseek-harness -L 3` and `npm view @deepseek-ai/dsh dist-tags` [verified commands]. A scheduled reminder is optional.

---

## Open questions and unverified points

- Whether root `overrides` + `patchedDependencies` reach pi-ai when it comes in only through `@deepseek-ai/dsh → dsh-llm-pi-ai`, and whether `pnpm exec dsh` then loads the patched copy **[unverified]**. Check after the first install.
- Whether pi-ai 1.3.0 (what npm resolves today) works with dsh 0.2.1-rc.2 **[unverified]**. The override to 1.1.0 avoids the question.
- Whether `--dump-config` output is stable enough to snapshot (ordering, absolute paths) **[unverified]**. It may need a small normalising filter.
- The desktop app's distribution and the community upgrade skill were not read.

## Sources

- dsh `dsh-v0.2.1-rc.2`: [`README.md`](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/README.md), [`package.json`](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/package.json), [`pnpm-workspace.yaml`](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/pnpm-workspace.yaml), [`patches/@earendil-works__pi-ai@1.1.0.patch`](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/patches/@earendil-works__pi-ai@1.1.0.patch), [`packages/llm/llm-pi-ai/README.md`](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/packages/llm/llm-pi-ai/README.md), [`packages/boot/app-boot/src/plugin-compatibility.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/packages/boot/app-boot/src/plugin-compatibility.ts), [`docs/user/develop/basic/publish.md`](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/docs/user/develop/basic/publish.md), [`docs/session-format-status.md`](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/docs/session-format-status.md), [`docs/cli-help.md`](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/docs/cli-help.md), [`docs/upgrade-guide/`](https://github.com/deepseek-ai/deepseek-harness/tree/dsh-v0.2.1-rc.2/docs/upgrade-guide) (all 42 guides' front matter; full text of `plugin-engines-dsh`, `stored-credentials-precedence`, `from-default-profile-replaces-target`, `mock-messages-events`), [`packages/bundle/base/cordis.patch.yml`](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/packages/bundle/base/cordis.patch.yml), [`packages/test-support/llm-mock-server/README.md`](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/packages/test-support/llm-mock-server/README.md), [`apps/cli/package.json`](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/apps/cli/package.json), [`.github/workflows/release-publish.yml`](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/.github/workflows/release-publish.yml), [`scripts/release/publish.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/scripts/release/publish.ts)
- dsh history: `packages/core/session/src/types.ts`, `vendor/cordis/package.json` and `pnpm-workspace.yaml` at every tag; `git diff` and `git rev-list` between consecutive tags `dsh-v0.1.5-rc.2` … `dsh-v0.2.1-rc.2`
- GitHub API: `repos/deepseek-ai/deepseek-harness` (`has_issues`, `pushed_at`), `/releases` (all 31 bodies), `/tags`
- npm registry: `@deepseek-ai/dsh` (versions, time, dist-tags, `0.2.1-rc.2` manifest), `@deepseek-ai/dsh-llm-pi-ai@0.2.1-rc.2` (manifest and tarball `lib/index.js`), `@deepseek-ai/cordis`, `@deepseek-ai/dsh-llm-mock-server`, `@earendil-works/pi-ai` (versions; 1.3.0 tarball `dist/api/openai-completions.js`); lockfile-only resolution of `@deepseek-ai/dsh@0.2.1-rc.2`
- Upstream issue [earendil-works/pi#9265](https://github.com/earendil-works/pi/issues/9265)
- pnpm docs: [settings](https://pnpm.io/settings), [dependency resolution](https://pnpm.io/settings/dependency-resolution) (`overrides`, `minimumReleaseAge`), [patch](https://pnpm.io/cli/patch) (`patchedDependencies`, `allowUnusedPatches`), [package sources](https://pnpm.io/package-sources) (git selectors, `path:`)
