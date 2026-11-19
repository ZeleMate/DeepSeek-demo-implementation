# Security policy

This is a personal, defensive-security project with one maintainer. It hardens an agent harness built on DeepSeek Harness (dsh) and measures it by attack success rate (ADR 0002).

## Supported versions

Only the latest commit on `development` and `main` is supported. There are no releases.

## Reporting a vulnerability

Report privately through GitHub's private vulnerability reporting: the **Report a vulnerability** button on this repo's [Security tab](https://github.com/ZeleMate/DeepSeek-demo-implementation/security/advisories/new). Never open a public issue, PR or discussion for a vulnerability.

This covers three kinds of bug:

- **A bug in this repo.** That includes our plugins, bundles, launchers, check scripts and CI workflows.
- **An upstream bug found here.** That is a bug in dsh, its bundled code or a pinned third-party MCP server that our red-team work turned up. ADR 0015 says what counts. Report it to us privately too, and we pass it on through the upstream project's own private channel.
- **A model-driven bypass of our harness.** Prompt injection, tool misuse or an unsafe action that gets past our defences, even when the root cause is model behaviour.

Please include what you did, what happened and the commit you tested. We aim to answer within 7 days. This is a hobby project, so there is no bounty.

## How we handle it

We follow [ADR 0015](docs/adr/0015-upstream-bugs-are-disclosed-privately.md).

- Reproductions stay out of git, in the gitignored `eval/embargoed/`, until the embargo ends.
- PR text, commit messages and scores say nothing about an unfixed bug.
- A PR that touches an embargoed bug is opened with the `embargo` label, so the Claude reviews skip it: their comments and CI annotations are public.
- The embargo ends when the fix ships or 90 days after the first report, whichever comes first.
- After it ends we publish a write-up, never a working exploit.

## Out of scope

- DVMCP and our test MCP server. They are vulnerable on purpose.
- A jailbroken local victim model. Defending against that is the project's job, not a bug.
- Attacking anything other than your own copy. Red-team runs target only our own harness, `127.0.0.1` labs and local victim models (ADR 0002).

## State of the harness

The defences in ADR 0003 and ADR 0013 are not built yet; the build order is in ADR 0012. Until they are, both profiles run with a read-only sandbox and no shell, PTC, async, web or instruction-loading tools, and the job profile has no file tools either. Don't point the job profile at material you wouldn't send to OpenRouter.

## Protections on this repo

- Changes land only through PRs that pass the required `ci-ok` check, and [CODEOWNERS](.github/CODEOWNERS) names the owner for every file. With one maintainer, no second person reviews them (ADR 0016).
- gitleaks runs on every commit and on the full history in CI, and GitHub secret scanning with push protection is on. Keys live in the macOS Keychain, never in files (ADR 0007).
- The Claude reviews in CI run only on PRs from branches of this repo, never forks or Dependabot. They never read issue or comment text from anyone but the owner, members and collaborators, and no CI job can push to the repo (ADR 0014).
- Workflow runs from outside contributors wait for approval. Actions must come from an allowlist and be pinned to a full commit SHA.
- Code scanning is CodeQL default setup, for JavaScript/TypeScript, Python and Actions. Dependabot alerts and security updates are on.
