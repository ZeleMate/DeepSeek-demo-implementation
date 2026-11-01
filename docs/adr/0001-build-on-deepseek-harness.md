---
status: accepted; pinning and upgrade policy amended 2026-10-19 (#36); overrides' home and security overrides added 2026-11-01 (#96)
---

# Build on DeepSeek Harness as a bundle of our own plugins

We build on [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (dsh) instead of writing our own agent loop. dsh's core (agent loop, session log, tool pipeline, compaction, retries) and its front-ends (headless CLI, web UI, ACP) are used unchanged. Everything we add ships as **our own dsh bundle**: one package per plugin under `plugins/`, named `@zelemate/dsh-<plugin>`, plus bundle packages under `bundles/` (one per profile, e.g. `bundles/job` and `bundles/redteam`), each declaring its config in `dsh.bundle.patch`. A local dsh profile selects one of our bundles, linked while developing, rather than us forking the dsh monorepo. The profile's own `cordis.patch.yml` under `$DSH_HOME/profiles/<name>` is a separate, user-owned layer that is applied after the bundle layers. It stays out of the repo and holds only per-machine overrides.

dsh is pinned to exactly `dsh-v0.2.1-rc.2`, as an exact npm devDependency with a committed lockfile (installs use `--frozen-lockfile`), and run with `pnpm exec dsh`. Every plugin pins its dsh peer and dev dependencies exactly, and every bundle declares an exact `engines.dsh`, which dsh enforces at install and profile start. We follow **release candidates only, one rc at a time**, each in its own PR, after reading every `docs/upgrade-guide/<from-version>/` folder in between.

**We carry dsh's pi-ai patch ourselves.** dsh patches an O(n²) streaming bug in pi-ai 1.1.0 inside its own repo, but the published `dsh-llm-pi-ai` asks for `pi-ai ^1.1.0`, so an npm install gets 1.3.0 unpatched. Our `pnpm-workspace.yaml` pins pi-ai 1.1.0 with pnpm `overrides` and re-applies the patch with `patchedDependencies`. The same `overrides` also lift dependencies that dsh pins exactly past a security alert. Each of those matches only the vulnerable range and is dropped on the dsh upgrade that ships the fix.

Each upgrade PR must pass a $0 check before it merges: frozen install (fails if the patch no longer applies), typecheck and tests, a diff of `--dump-config` and `--dump-config-schema` snapshots, one headless `--json` smoke turn on local Ollama, resuming a session from the previous version, and a small slice of the attack set. Back up `$DSH_HOME` first, because upgraded session logs can't be read by an older dsh.

## Considered options

- **Hand-written thin loop, with dsh as a reference only.** This was the original plan. It was dropped because the project's name and goal became "a DeepSeek demo implementation". The learning comes from dsh's real extension surface instead.
- **Fork the dsh monorepo.** Rejected: upgrades would turn into merges. We fork only if a bundle can't do something.

## Consequences

- dsh is a developer preview: every release is a prerelease, it hasn't had a security audit, and breaking changes are expected (31 releases in its first 61 days). dsh promises nothing about the plugin API or config schema; only session-log formats and `engines.dsh` are enforced. Pinning an exact version is what keeps that manageable.
- npm's `latest` tag points at a prerelease, so never run dsh through `npx @deepseek-ai/dsh`.
- Our bundle patches replace whole base rows, so each row we override can drift when dsh changes it. The upgrade check's config-dump diff is what catches that.
- Never run `--from-default-profile` on an existing profile: since 0.2.1-alpha.3 it deletes the profile, including its user-owned `cordis.patch.yml`.
- We don't build any UI of our own.
- API keys live in the macOS Keychain and reach dsh through a launcher (ADR 0007); they are never committed. The dsh home folder (sessions, credentials) lives outside the repo.

Decided in [Which dsh plugins do we use, and which do we write?](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/10). Pinning and upgrade policy amended after [Pinning and upgrading dsh: how do we follow its prereleases?](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/36) (research/dsh-pinning.md).
