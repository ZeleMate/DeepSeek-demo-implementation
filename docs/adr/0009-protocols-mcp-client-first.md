# The harness is an MCP client first; it exposes no protocol of its own in v1

| Protocol | Role in v1 | How |
|---|---|---|
| **MCP** | Client only, and the **first** protocol we build for | dsh's `mcp-client`, for the servers under test and any tool servers. The pinning guard (ADR 0003) and half the attack set depend on it. |
| **Plugins** | Our extension unit | Cordis plugins in our bundles (ADR 0001). |
| **Skills** | Each security job's procedure | One `SKILL.md` per job in our bundle, next to the job's dedicated tools, loaded by dsh's `skill-filesystem`. |
| **AGENTS.md** | Instructions for our own workspace only | dsh's `agent-instructions`. The scanned repo is never the workspace (ADR 0007), so a scanned repo's AGENTS.md is never loaded as instructions; it is untrusted data like any other file. |
| **ACP** | Used as shipped | dsh's `acp-app` bundle, if you want to drive dsh from Zed or JetBrains. We build nothing for it. |
| **A2A** | None in v1 | dsh has no A2A support. Wrapping a job as an A2A agent comes later ([#44](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/44)). |

## Why

Every protocol we serve is a new inbound surface the hardened harness would have to defend and score. v1 has no second agent to talk to, so an A2A or MCP server would exist only to tick a box. The AGENTS.md rule closes a ready-made injection channel: a malicious repo could otherwise give the agent instructions just by containing that file.

## Consequences

- Exposing the secrets filter as an MCP server comes later, with its own threat model and attack cases ([#43](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/43)).
- An attack case plants instructions in a fixture repo's AGENTS.md, to check that the rule holds (ADR 0011).

Decided in [Which protocols does the harness speak, and in what role?](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/12). Research: research/protocols.md.
