# Domain docs

How the engineering skills read this repo's domain documentation. The repo is single-context: one glossary and one ADR folder at the root.

## Before exploring, read these

- **[CONTEXT.md](../../CONTEXT.md)** at the repo root: the vocabulary. Each entry lists the words it replaces.
- **[docs/adr/](../adr/)**: read the ADRs that touch the area you're about to work in.

If a file is missing, proceed silently. Don't flag its absence and don't suggest creating it upfront. The `/domain-modeling` skill creates entries lazily when terms or decisions actually get resolved.

## File structure

```text
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-build-on-deepseek-harness.md
│   └── ...
├── plugins/
├── bundles/
└── labs/
```

The `plugins/`, `bundles/` and `labs/` workspace packages share the root glossary and ADRs. They have no `CONTEXT.md` of their own.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as `CONTEXT.md` defines it. Don't drift to synonyms the glossary lists as replaced.

If the concept you need isn't in the glossary yet, that's a signal. Either you're inventing language the project doesn't use (reconsider), or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, say so explicitly rather than silently overriding it:

> _Contradicts ADR 0003 (hardened profile fails closed), but worth reopening because…_

A change that alters a decision amends that ADR or adds the next numbered one in the same PR (see [AGENTS.md](../../AGENTS.md)).
