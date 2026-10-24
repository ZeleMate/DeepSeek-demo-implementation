# DeepSeek demo implementation

A personal, learning-first agent harness built as a bundle of our own plugins on [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness).

- Planning happens on the [wayfinder map](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/1).
- Glossary: [CONTEXT.md](CONTEXT.md)
- Decisions: [docs/adr/](docs/adr/)

## Setup

```bash
brew bundle                     # pnpm, lefthook, gitleaks, actionlint, zizmor, shellcheck, markdownlint-cli2
lefthook install                # pre-commit, commit-msg and pre-push hooks (lefthook.yml)
pnpm install --frozen-lockfile  # dsh pinned exactly, pi-ai patched (pnpm-workspace.yaml)
```

Run dsh only as `pnpm exec dsh`, never `npx @deepseek-ai/dsh`: npm's `latest` tag points at whatever prerelease came out last (ADR 0001). Every dsh upgrade PR must pass `pnpm check:upgrade`, which needs Ollama running with `qwen3.5:2b` and calls no remote model.

## Running the job profile

```bash
security add-generic-password -U -a "$USER" -s dsh-demo.OPENROUTER_API_KEY -w   # prompts for the key
bin/dsh-job "what is 17+25?"
```

[bin/dsh-job](bin/dsh-job) is the only way keys reach dsh. It reads them from the login Keychain, exports them only into the dsh process, and starts dsh in a dedicated workspace, never inside a repo. On first run it creates the `job` profile (dsh's headless template plus [bundles/job](bundles/job)). It keeps everything under `~/.dsh-demo` (set `DSH_DEMO_ROOT` to move it):

- `home/` is `DSH_HOME`: profiles and session logs. Its `cordis.patch.yml` must stay exactly `[]`, because that file outranks every profile; the launcher creates it and refuses to start if it changes.
- `workspace/job/` is where dsh runs.

API keys are Keychain items, never files; see [.env.example](.env.example) and ADR 0007. CI ([ci.yml](.github/workflows/ci.yml)) runs the same checks as the hooks.
