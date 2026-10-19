# Build on DeepSeek Harness as a bundle of our own plugins

We build on [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (dsh) instead of writing our own agent loop. dsh's core (agent loop, session log, tool pipeline, compaction, retries) and its front-ends (headless CLI, web UI, ACP) are used unchanged. Everything we add ships as **our own dsh bundle**: one package per plugin under `plugins/`, named `@zelemate/dsh-<plugin>`, plus bundle packages under `bundles/` (one per profile, e.g. `bundles/job` and `bundles/redteam`), each declaring its config in `dsh.bundle.patch`. A local dsh profile selects one of our bundles, linked while developing, rather than us forking the dsh monorepo. The profile's own `cordis.patch.yml` under `$DSH_HOME/profiles/<name>` is a separate, user-owned layer that is applied after the bundle layers. It stays out of the repo and holds only per-machine overrides.

dsh is pinned to exactly `dsh-v0.2.1-rc.2`. We upgrade one release at a time, each in its own PR, following dsh's upgrade guide.

## Considered options

- **Hand-written thin loop, with dsh as a reference only.** This was the original plan. It was dropped because the project's name and goal became "a DeepSeek demo implementation". The learning comes from dsh's real extension surface instead.
- **Fork the dsh monorepo.** Rejected: upgrades would turn into merges. We fork only if a bundle can't do something.

## Consequences

- dsh is a developer preview: every release is a prerelease, it hasn't had a security audit, and breaking changes are expected. Pinning an exact version is what keeps that manageable.
- We don't build any UI of our own.
- API keys come from environment variables and are never committed. The dsh home folder (sessions, credentials) lives outside the repo.

Decided in [Which dsh plugins do we use, and which do we write?](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/10).
