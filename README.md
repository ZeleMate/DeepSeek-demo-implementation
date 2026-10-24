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

Run dsh only as `pnpm exec dsh`, never `npx @deepseek-ai/dsh`: npm's `latest` tag points at whatever prerelease came out last (ADR 0001).

API keys are Keychain items, never files; see [.env.example](.env.example) and ADR 0007. CI ([ci.yml](.github/workflows/ci.yml)) runs the same checks as the hooks.
