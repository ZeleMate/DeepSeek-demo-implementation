# Dependency policy

- **Lockfiles are committed** and installs use them only (`pnpm install --frozen-lockfile`). dsh is pinned exactly and upgraded one release candidate per PR (ADR 0001).
- **Cooldown before adopting new releases.** Dependabot waits 7 days (14 for majors); security updates are not delayed. pnpm ignores releases newer than 7 days (`minimumReleaseAge`) and blocks install scripts unless allowlisted in `allowBuilds`.
- **Scanning:** OSV-Scanner on every PR and weekly; Dependabot alerts and malware alerts. An accepted advisory goes in `osv-scanner.toml` with a reason and an `ignoreUntil` date.
- **Fix timelines:** critical/high within 7 days, medium within 60 days, low at the next routine update.
- **Adding a dependency:** confirm it exists on the official registry, is maintained, has a compatible licence, and is worth its weight. Prefer the standard library.
- **Allowed licences:** MIT, Apache-2.0, BSD-2/3-Clause, ISC, Unicode-3.0, MPL-2.0 (file-level). Anything else needs an ADR.
