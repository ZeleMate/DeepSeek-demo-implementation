---
status: accepted
---

# Upstream bugs are disclosed privately and kept out of git until fixed

Red-team runs attack our own harness, and the harness is dsh plus its bundled code (including our patched pi-ai) and the pinned third-party MCP servers under test. So an attack attempt can succeed because of a real bug in someone else's code, not a gap in our defences. We call that an **upstream bug**.

**What counts.** An attack attempt is an upstream bug only if it reproduces without the model (a scripted tool call or plugin, no model choice involved) and breaks behaviour dsh documents: the read-only sandbox allows a write, `ctx.tools.guard` is bypassed, a hook is skipped, a disabled tool runs. These never count: a gap in our defences, model behaviour such as a jailbroken victim model, the baseline hits of the red-team baseline milestone (M2, ADR 0012), and anything in DVMCP or our test MCP server, which are vulnerable on purpose.

**Where we report.** For a bug in a pinned third-party MCP server, we follow the same steps with that project's own security policy or issue tracker. dsh has no `SECURITY.md` and GitHub private vulnerability reporting is off. We open a public dsh issue with no details that asks for a private channel or for private reporting to be turned on. With no answer in 14 days, we email the maintainers directly. Details go only through the private channel.

**What stays out of git.**

- The reproduction lives in `eval/embargoed/`, which is gitignored and refused by `scripts/checks/forbidden-paths.sh`.
- `eval/results/<version>.json` carries one top-level `"embargoed": <attack count>` field: no attack names, no defence, no rate. Embargoed attempts are left out of every attack success rate.
- PR text and commit messages say nothing about the bug.
- A cheap workaround in our own defences may ship before the fix, with a generic commit message; its test stays in `eval/embargoed/`.

**Timeline.** The embargo ends when the fix ships or 90 days after the first report, whichever comes first, and earlier if a public fix or commit already reveals the bug. After it ends we publish a write-up, never a working exploit (ADR 0002).

**Moving the pin.** The PR that moves dsh to the fixed release promotes the embargoed attack into the attack set and commits its results (ADR 0011). That PR may skip release candidates (ADR 0001).

**Our own repo.** It is private and has one user, so it has no `SECURITY.md` yet. Making it public requires adding `SECURITY.md` and turning on private vulnerability reporting first.

## Why

- Git history is permanent. A committed score, attack or PR description could describe an unfixed bypass long after the repo goes public.
- Requiring a model-free reproduction separates a real dsh bug from the model doing what models do, which is our job to defend against.
- A 90-day default keeps "until a fix ships" from meaning forever, which follows the coordinated disclosure in OpenAI's [Patch the Planet write-up](https://openai.com/index/coordinated-disclosure-of-critical-vulnerabilities/).
- A single count tells the reader a score has a hole without saying where.

## Consequences

- A results file with `embargoed` above 0 is not comparable on that attack until the promotion PR lands.
- Walking one rc at a time while a fixed rc exists would keep the bug open for nothing, so ADR 0001 gets a security exception.

Decided in [What do we do when a red-team hit is a real bug in dsh or a pinned MCP server?](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/115).
