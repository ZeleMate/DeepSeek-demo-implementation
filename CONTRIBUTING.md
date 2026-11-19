# Contributing

This is a one-person project. Issues and bug reports are welcome. For larger changes, open an issue first so we can agree on the approach.

## Workflow

1. Branch from `development`. `main` only moves by merging `development`.
2. Make the change with tests. Install the hooks once with `lefthook install`, and run `lefthook run pre-commit --all-files` before pushing.
3. Open a PR into `development` with a Conventional Commits title (`feat: …`, `fix: …`). It is squash-merged.
4. CI must pass and review threads must be resolved. Read [AGENTS.md](AGENTS.md) and the ADRs in [docs/adr/](docs/adr/) first.

Security issues: see [SECURITY.md](SECURITY.md).
