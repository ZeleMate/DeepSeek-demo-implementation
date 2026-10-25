# Protocol landscape: A2A, ACP, MCP, Plugins, Skills, AGENTS.md

Research for issue #6, as of 2026-10-18. Sources are primary (spec sites, official repos, npm registry) unless marked otherwise.

## Answer in brief

- **MCP** (agent-to-tool) and **A2A** (agent-to-agent) are the two wire protocols that matter. Both are now hosted by the Linux Foundation's Agentic AI Foundation (AAIF), and both have mature, official TypeScript SDKs.
- **ACP** in the brief most likely means the **Agent Client Protocol** (client-to-agent: editor or UI to agent, from Zed and JetBrains). IBM's Agent Communication Protocol was archived and merged into A2A in Aug 2025.
- **Skills** (Agent Skills / `SKILL.md`) and **AGENTS.md** are file conventions, not protocols. They need no SDK; a harness only has to load Markdown.
- **"Plugin"** has no cross-vendor standard. The closest are the Claude Code and Codex plugin bundle formats (which package skills and MCP servers) and MCP Bundles (`.mcpb`).

## Summary table

| Name | Standardises | Layer | Maintainer | Status (Oct 2026) | TS SDK |
|---|---|---|---|---|---|
| MCP | How an agent host connects to tools, resources and prompts (JSON-RPC over stdio or Streamable HTTP) | agent-to-tool | MCP Steering Group; LF Projects series, founding AAIF project | Spec `2026-07-28` (stateless rewrite) | Official, first-class: `@modelcontextprotocol/server` and `/client` v2.3.1; legacy `@modelcontextprotocol/sdk` 1.32.1 |
| A2A | Agent discovery (Agent Card), tasks, messages and artifacts between opaque agents; JSON-RPC, gRPC and REST bindings | agent-to-agent | Linux Foundation TSC; AAIF hosted project since 2026-08-17 | Spec v1.0.0 (Mar 2026), v1.0.1 tag (May 2026) | Official: `@a2a-js/sdk` 1.3.0 (client and server, 3 transports) |
| ACP (Agent **Client** Protocol) | Editor/UI to coding-agent sessions (JSON-RPC over stdio; remote is still WIP); reuses MCP JSON types | client-to-agent | Zed + JetBrains joint governance; no foundation yet | Protocol version 1 stable; v2 schema in alpha | Official: `@agentclientprotocol/sdk` 1.9.0 (weekly releases) |
| ACP (Agent **Communication** Protocol, IBM/BeeAI) | REST-based agent-to-agent messaging | agent-to-agent | IBM / BeeAI, now folded into A2A | Archived Aug 2025 | `acp-sdk` exists but is dead; do not use |
| Agent Skills (`SKILL.md`) | A folder holding `SKILL.md` (YAML frontmatter: `name`, `description`) plus scripts and references, loaded by progressive disclosure | packaging / instruction convention | agentskills.io; created by Anthropic, open to contributions; not an AAIF project | Spec published; widely adopted | None official (reference validator `skills-ref` is Python, "demonstration only"); community npm packages exist |
| AGENTS.md | Free-form Markdown "README for agents" in a repo; the nearest file wins | instruction convention | AAIF (founding project, from OpenAI and others) | Stable; 60k+ repos | Not needed (plain Markdown) |
| Plugins | Vendor-specific bundles of skills, commands, agents, hooks and MCP servers | packaging | Per vendor (Anthropic, OpenAI) | Active, no cross-vendor spec | n/a (file formats) |

## MCP: Model Context Protocol

- **Standardises:** how a host (agent) discovers and calls tools, reads resources and fetches prompts from servers, plus OAuth-based authorisation for remote servers.
- **Maintainer:** "Model Context Protocol a Series of LF Projects, LLC". Lead maintainers are David Soria Parra and Den Delimarsky, with a Core Maintainer group and SEP process ([governance](https://modelcontextprotocol.io/community/governance)). It was a founding project of the AAIF, announced 2025-12-09 together with goose and AGENTS.md ([LF press release](https://www.linuxfoundation.org/press/linux-foundation-announces-the-formation-of-the-agentic-ai-foundation)).
- **Status:** the latest spec is `2026-07-28` (GitHub release 2026-07-28; the previous one was `2025-11-25`). It is a big change ([changelog](https://modelcontextprotocol.io/specification/2026-07-28/changelog)):
  - The `initialize` handshake and protocol sessions are removed (stateless); a new `server/discover` RPC replaces them.
  - Server-to-client requests are replaced by Multi Round-Trip Requests (`input_required` results).
  - Tasks moved to an official extension.
  - Roots, Sampling and Logging are deprecated.
- **TS SDK:** [modelcontextprotocol/typescript-sdk](https://github.com/modelcontextprotocol/typescript-sdk), the reference SDK.
  - v2 is split into `@modelcontextprotocol/server` and `@modelcontextprotocol/client` (2.3.1, 2026-10-05) and implements spec 2026-07-28.
  - Runs on Node, Bun and Deno. Schemas use Standard Schema (Zod v4, Valibot, ArkType). There are middleware packages for Express, Fastify, Hono and Node HTTP.
  - v1 (`@modelcontextprotocol/sdk` 1.32.1) gets fixes for at least 6 months after the v2 release (2026-07-27).
  - Related: MCP Apps UI extension SDK `@modelcontextprotocol/ext-apps` 2.0.3 (npm).
- **For own-harness:** the harness is an MCP *client/host*. Starting from v2 avoids a migration. Note that much older tutorial code is written against v1 and the stateful handshake.

## A2A: Agent2Agent Protocol

- **Standardises:** how independent, opaque agents find each other and delegate work ([spec](https://a2a-protocol.org/latest/specification/)).
  - Discovery: the Agent Card, a JSON metadata document covering identity, skills, endpoint and auth. Cards can be signed and are served from a well-known URI.
  - Work objects: Task (with states SUBMITTED, WORKING, INPUT_REQUIRED, AUTH_REQUIRED, COMPLETED, FAILED, CANCELED, REJECTED), Message, Part (text, file or data) and Artifact.
  - Delivery: streaming and webhook push notifications.
  - Bindings: JSON-RPC, gRPC and HTTP+JSON/REST, with equivalent behaviour required.
- **Maintainer:** created by Google (Apr 2025) and donated to the Linux Foundation (Jun 2025). It has a TSC with AWS, Cisco, Google, IBM Research, Microsoft, Salesforce, SAP and ServiceNow ([a2a-protocol.org](https://a2a-protocol.org/latest/)). It joined the AAIF as a hosted project on 2026-08-17 ([AAIF blog](https://aaif.io/blog/a2a-joins-aaif)).
- **Status:** v1.0.0 released 2026-03-12 and v1.0.1 tag on 2026-05-28 ([releases](https://github.com/a2aproject/A2A/releases)). Compatibility is keyed on Major.Minor.
- **TS SDK:** [`@a2a-js/sdk`](https://github.com/a2aproject/a2a-js) 1.3.0 (2026-09-29), described as the official TypeScript/JavaScript SDK.
  - Covers client and server, with JSON-RPC, REST and gRPC (gRPC is Node-only).
  - Has an opt-in v0.3 compatibility layer, plus task and push-config stores (Postgres, MySQL, SQLite, D1).
  - Express is a peer dependency for the server.
  - It is solid, but smaller than the MCP SDK (about 645 GitHub stars vs 13.6k). The Python SDK is the flagship.
- **For own-harness:** this is the natural wire for the later multi-agent "team". It is not needed for the single-agent research assistant.

## ACP: resolving the ambiguity

At least two protocols use the acronym "ACP":

1. **Agent Communication Protocol** (IBM Research / BeeAI): a REST-based agent-to-agent protocol. Its repo [i-am-bee/acp](https://github.com/i-am-bee/acp) is **archived** (last push 2025-08-25), and its README says it is "now part of A2A under the Linux Foundation". The AAIF blog likewise says it merged into A2A in August 2025.
2. **Agent Client Protocol** (Zed + JetBrains): an LSP-style protocol between a *client* (editor, IDE, TUI, desktop app) and a *coding agent* ([agentclientprotocol.com](https://agentclientprotocol.com/overview/introduction)).
   - Transport: local agents run as subprocesses and talk JSON-RPC over stdio; remote HTTP/WebSocket support is still in progress. It reuses MCP's JSON representations where possible and adds diffs and similar types.
   - Governance: joint between Zed and JetBrains, with lead maintainers Ben Brandt (Zed) and Sergey Ignatov (JetBrains). It is "working toward" an independent foundation ([governance](https://agentclientprotocol.com/community/governance)).
   - Status: protocol version `1` is stable, the v2 schema is in alpha, and the repo releases weekly (v1.12.0 on 2026-10-16).
   - Adoption: many clients, including Zed, JetBrains, VS Code extensions, Neovim, Emacs and Obsidian. Agents include Claude Code, Codex CLI, Gemini CLI, OpenCode and Cursor ([clients](https://agentclientprotocol.com/overview/clients)).
   - TS SDK: official [`@agentclientprotocol/sdk`](https://github.com/agentclientprotocol/typescript-sdk) 1.9.0 (2026-10-16). It replaces the older `@zed-industries/agent-client-protocol` (last 0.4.5, Oct 2025). Releases are frequent; the repo is small (about 263 stars) but tied to the official schema.

**Which one the brief means:** most likely the **Agent Client Protocol**, for three reasons.

- The brief's harness is *DeepSeek Harness*. The ACP clients page lists third-party clients that drive "DeepSeek Harness" as an ACP agent (for example Martty, Perch and Vibex). DeepSeek Harness is not in the official agents list, though, so this is community evidence, not first-party.
- IBM's protocol no longer exists separately. Listing it next to A2A would mean listing A2A twice.
- Agent Client Protocol fills a slot the other items leave empty (client-to-agent), which matters because the first interface is a CLI.

Caveat: if the brief was copied from a 2025 "MCP vs A2A vs ACP" comparison article, the author may have meant IBM's ACP. The practical conclusion is the same either way, because that work now lives in A2A.

## Agent Skills (`SKILL.md`)

- **Standardises:** a skill is a directory containing `SKILL.md` ([spec](https://agentskills.io/specification)).
  - Required YAML frontmatter: `name` (1-64 characters of lowercase letters, digits and hyphens; must match the directory name) and `description` (1-1024 characters, saying what the skill does and when to use it).
  - Optional fields: `license`, `compatibility`, `metadata`, and experimental `allowed-tools`.
  - The body is free Markdown. Optional folders: `scripts/`, `references/`, `assets/`.
  - Progressive disclosure has three steps:
    1. Load `name` and `description` at startup (about 100 tokens).
    2. Load the full body (recommended under 5k tokens) when the skill activates.
    3. Load bundled resources on demand.
- **Maintainer:** the agentskills.io project ([agentskills/agentskills](https://github.com/agentskills/agentskills)). It "was originally developed by Anthropic, released as an open standard", and outside contributions are accepted. I found no evidence it is an AAIF project.
- **Status:** the spec is published and adopted by many clients (agentskills.io/clients). Codex plugins and Claude Code plugins both use `SKILL.md`.
- **TS support:** there is no official TS SDK. The only reference tool, `skills-ref` (validator), is Python and labelled "demonstration purposes only". There are community npm packages (`@skill-tools/core`, `@tanstack/ai-skills`, `skills` from vercel-labs), but none is official. That is fine: the format is YAML frontmatter plus Markdown, and a loader is a few dozen lines. It is a good learning exercise for own-harness.

## AGENTS.md

- **Standardises:** almost nothing formally ([agents.md](https://agents.md/)). It is a predictable file name for agent-facing project instructions, written as plain Markdown with no required fields.
  - Precedence: the nearest AGENTS.md in the directory tree wins, and explicit user prompts override everything.
- **Maintainer:** developed collaboratively by OpenAI Codex, Amp, Google Jules, Cursor and Factory. It is now "stewarded by the Agentic AI Foundation under the Linux Foundation" as a founding AAIF project.
- **Status:** stable and widely supported, by Codex, Jules, Cursor, Gemini CLI, VS Code, Copilot coding agent, Zed, goose, Aider and others. The site says 60k+ open-source projects use it.
- **TS support:** n/a. Reading it is a file read plus a directory walk.

## "Plugin": what it could mean

There is no cross-vendor plugin standard. Plausible referents:

1. **Claude Code plugins.** Manifest at `.claude-plugin/plugin.json` (optional; only `name` is required), distributed through marketplaces (`marketplace.json`) ([reference](https://code.claude.com/docs/en/plugins-reference)).
   - Bundles skills (`SKILL.md`), commands, subagents, hooks, MCP servers (`.mcp.json` or `.mcpb` bundles), LSP servers and output styles.
   - Anthropic-specific, but it builds on open pieces (Agent Skills, MCP).
2. **Codex plugins (OpenAI).** Manifest at `.codex-plugin/plugin.json` (per OpenAI docs via search snippets; the current docs page did not show the path).
   - Bundles skills, MCP servers, hooks and browser extensions, shared through marketplaces ([docs](https://learn.chatgpt.com/docs/plugins.md)).
   - OpenAI's developer site has a guide to submitting a Claude Code plugin, which it converts to the Codex format. So the two formats are close but not identical.
3. **MCP Bundles (`.mcpb`, formerly `.dxt`).** A zip format for one-click installation of local MCP servers ([modelcontextprotocol/mcpb](https://github.com/modelcontextprotocol/mcpb)). Under the MCP org, so it is the most "standard" of the three, but it only packages MCP servers.
4. **Historic or other meanings:**
   - ChatGPT Plugins (2023), now superseded; OpenAI's Apps SDK builds on MCP.
   - The MCP Apps extension for interactive UI.
   - A framework's own plugin system (for example, a harness's internal extension API).

**Reading for own-harness:** "Plugin" most plausibly means *a bundle that packages skills, MCP servers and hooks behind one manifest*, in the style of Claude Code and Codex. Map issue "Packaging for plugins and skills" is the place to decide whether to mimic one of those layouts or define a minimal own manifest.

## Overlap map

```text
             ┌──────────── client-to-agent ────────────┐
  CLI / IDE ─┤ ACP (Agent Client Protocol)             ├─► Agent (own-harness)
             └─────────────────────────────────────────┘        │  ▲
                                                                │  │ instructions/packaging
   agent-to-agent: A2A  ◄───────────────────────────────────────┤  │  AGENTS.md (repo context)
   (IBM ACP merged here)                                        │  │  SKILL.md (on-demand know-how)
                                                                │  │  Plugins (bundle of skills + MCP + hooks)
   agent-to-tool:  MCP  ◄───────────────────────────────────────┘
```

- **Agent-to-tool:** MCP. ACP reuses MCP types and lets clients pass MCP server configs through to the agent.
- **Agent-to-agent:** A2A (IBM ACP is absorbed). A2A "skills" in the Agent Card are advertised capabilities, which is unrelated to `SKILL.md` despite the name.
- **Client-to-agent:** Agent Client Protocol.
- **Packaging and instruction conventions:**
  - AGENTS.md: always-on project context.
  - Agent Skills: lazily loaded procedures and scripts.
  - Plugins: distribution bundles that contain skills and MCP servers.
- **Real overlaps to watch:**
  - Skills vs MCP tools: both add capability. Skills are prompt plus scripts and cost almost nothing until activated; MCP tools are typed RPC.
  - MCP tasks extension vs A2A tasks: both model long-running work.
  - A2A vs ACP if ACP ever goes remote: both are "talk to an agent". ACP is session/UI-oriented; A2A is opaque peer delegation.

## Implications for own-harness (input for later tickets, not decisions)

- Highest value first: an MCP client (v2 TS SDK) and an Agent Skills loader (hand-written) give the research assistant tools and a skill wiki.
- AGENTS.md support is trivial and useful once the coding-agent direction starts.
- Agent Client Protocol (`@agentclientprotocol/sdk`) is an optional second front-end. Exposing the harness as an ACP agent would let it run in Zed, JetBrains or Neovim for free, and it fits the "interface we own" seam.
- A2A (`@a2a-js/sdk`) belongs to the later multi-agent phase.
- Plugins: decide in the packaging ticket. A minimal manifest compatible with the Claude Code/Codex shape (skills/ + .mcp.json) is the low-regret option.

## Sources

- MCP: <https://modelcontextprotocol.io/community/governance>, <https://modelcontextprotocol.io/specification/2026-07-28/changelog>, <https://github.com/modelcontextprotocol/typescript-sdk>, <https://github.com/modelcontextprotocol/modelcontextprotocol/releases>, npm registry (`@modelcontextprotocol/server`, `/client`, `/sdk`, `/ext-apps`)
- AAIF: <https://www.linuxfoundation.org/press/linux-foundation-announces-the-formation-of-the-agentic-ai-foundation>, <https://aaif.io/blog/a2a-joins-aaif>
- A2A: <https://a2a-protocol.org/latest/>, <https://a2a-protocol.org/latest/specification/>, <https://github.com/a2aproject/A2A/releases>, <https://github.com/a2aproject/a2a-js>
- Agent Client Protocol: <https://agentclientprotocol.com/overview/introduction>, <https://agentclientprotocol.com/community/governance>, <https://agentclientprotocol.com/overview/clients>, <https://github.com/agentclientprotocol/agent-client-protocol>, <https://github.com/agentclientprotocol/typescript-sdk>
- Agent Communication Protocol: <https://github.com/i-am-bee/acp> (archived)
- Agent Skills: <https://agentskills.io/specification>, <https://github.com/agentskills/agentskills>
- AGENTS.md: <https://agents.md/>, <https://github.com/agentsmd/agents.md>
- Plugins: <https://code.claude.com/docs/en/plugins-reference>, <https://learn.chatgpt.com/docs/plugins.md>, <https://github.com/modelcontextprotocol/mcpb>
