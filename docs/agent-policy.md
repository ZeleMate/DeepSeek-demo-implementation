# Agent runtime policy

How the agents **inside this application** are allowed to behave. The enforced source of truth is the dsh profile layers in `bundles/*/bundle.patch.yml` and the ADRs; this file summarises them as of 2026-11-09. (For coding agents working on the repo, see `AGENTS.md`.) Every change to this file needs a PR that also updates `THREAT_MODEL.md` §5.

Until the defences land (ADR 0012), both profiles run with the smallest tool set that still answers a prompt (ADR 0003).

## Models

| Purpose | Provider / model ID | Fallback |
|---|---|---|
| Job profile, everyday | OpenRouter / `deepseek/deepseek-v4.1-flash` (ADR 0006) | None |
| Job profile, hard turns | OpenRouter / `@preset/dsh-switchyard`, which escalates to Opus 5.5 (ADR 0006) | None |
| Red-team victim | Local Ollama / `redteam-qwen3.5-4b-16k`, built from `qwen3.5:4b` (ADR 0005) | None; no remote route |
| Red-team grader | Local Ollama / `redteam-granite4.2-3b-16k`, built from `granite4.2:3b` (ADR 0005) | None |
| Upgrade-check smoke turn | Local Ollama / `upgrade-check-qwen3.5-2b-16k` | None |

The OpenRouter ids and the preset are names, not pinned versions: OpenRouter or the preset's owner can change what they resolve to. A change to any id here is a reviewed change with an eval run.

## Tools

| Tool | Profile | What it can do | Needs human approval? |
|---|---|---|---|
| `todo_write`, `exit_plan_mode`, `working_directory` | both | Session bookkeeping, no side effects | no |
| `read`, `glob`, `grep`, `read_image` | red-team | Read any file the owner can read | no |
| `edit`, `write` | red-team | Nothing: the sandbox is read-only, and an escalation asks, which headless runs deny | always denied |

Off in both profiles: bash, pwsh, PTC, workflows, background jobs, subagents, goals, web search and fetch, skills, instruction files, the plugin manager. The job profile also has no file tools until the read allowlist lands (M4).

Rules:

- Default deny: an agent only gets the tools its task needs.
- Anything irreversible or external requires explicit human approval showing the exact action. Headless runs can't approve, so they deny.
- Tool and retrieval output is untrusted: it can inform, never instruct.

## MCP servers

None yet. The MCP servers under test arrive with the red-team baseline (M2) and are pinned by the MCP pinning guard (M6, ADR 0003).

| Server | Version / digest (pinned) | Transport | Scopes | Tool definitions reviewed on |
|---|---|---|---|---|

## Budgets

| Limit | Value |
|---|---|
| Max tool calls per turn | Not enforced yet; the policy decision adds a cap in M4 (ADR 0013) |
| Max tokens per task | Not enforced; dsh can't count tokens live (ADR 0013) |
| Provider spend cap | OpenRouter key credit limit, $30/month (ADR 0006); OpenAI project $5/month once the Decisions API is used (ADR 0007) |

## Sandbox for model-generated code

No profile runs model-generated code: bash, pwsh and PTC are off. dsh's own sandbox is set to `read-only` in both bundles. On macOS it blocks writes only, not reads or network, which is why the code-running tools stay off rather than relying on it (ADR 0003).
