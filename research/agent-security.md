# Agent security as the subject: can the harness attack and defend agents?

Research for issue #20. Sources were checked on **2026-10-18**. dsh facts come from the source tree at tag `dsh-v0.2.1-rc.2` (commit `687f282`), the version ADR 0001 pins. Anything I could not confirm from a primary source is marked **(unverified)**.

## Answer

**Yes. Agent security is a good subject for this harness, and dsh fits it unusually well.** The reason is that dsh already exposes the exact seams a defender needs: every tool call passes through `tools/pre-execute` → monotonic guards → `tools/execute` → `tools/post-execute` → `tools/result`. Model input passes through `agent/pre-step`, and every model call passes through `llm/stream`. The same harness can also act as an attacker, because an attacker is just an agent with tools that talk to a target.

- **Taxonomies to use:** OWASP Top 10 for LLM Apps (2025, plus a 2026 edition published August 2026), OWASP Top 10 for Agentic Applications (ASI01–ASI10, December 2025), OWASP MCP Top 10 (beta), and MITRE ATLAS (v2026.09, with many agent-specific techniques). Promptfoo maps its plugins to all of them.
- **Promptfoo is the right eval tool, with one catch.** Its agent and MCP plugins (`mcp`, `indirect-prompt-injection`, `hijacking`, `bola`, `bfla`, `ssrf`, `data-exfil`, `agentic:memory-poisoning`) and its default strategies (`jailbreak:meta`, `jailbreak:composite`) are **remote-only**: they call Promptfoo's hosted API and are subject to a free-tier probe limit. A fully local run with cheap OpenRouter models gives you fewer plugins and weaker attacks.
- **Open tools:** garak (model-level scanner), PyRIT (attack orchestration, moved to `microsoft/PyRIT`), Snyk Agent Scan (formerly Invariant `mcp-scan`; sends tool descriptions to Snyk's API), Cisco MCP Scanner (YARA rules plus an LLM, can run offline), AgentDojo (benchmark), LlamaFirewall/Prompt Guard 2 (defence). All are Python. Only Promptfoo is TypeScript.
- **dsh as a hardened target:** use sandbox mode `read-only` or `workspace-write`, approval policy `ask`, plus four of our own plugins: an MCP tool-pinning guard, an input/tool-result injection scanner on `tools/post-execute`, an egress/exfiltration policy on `tools/pre-execute`, and an audit observer on `tools/result`. dsh's sandbox governs **file effects only**, not network, so egress is the gap we would fill ourselves.
- **dsh as a red-team agent:** an attacker agent whose tools are "send a message to the target agent" (via `dsh headless --json`, ACP or HTTP) and "probe an MCP server". The important trap is that dsh's `mcp-client` puts a server's tool descriptions and instructions straight into the attacker's own prompt. So the attacker must **not** mount untrusted MCP servers natively. It needs its own probe tool that returns tool metadata as quoted data.

Recommended first project: **idea 1 (harden dsh against tool poisoning and indirect injection, measured with Promptfoo)**. It teaches the pipeline, gives a measurable before/after, and stays well under $5 a month.

## Threat taxonomy

### OWASP Top 10 for LLM Applications

The 2025 list is still what `genai.owasp.org/llm-top-10/` shows ([OWASP](https://genai.owasp.org/llm-top-10/)):

| ID | 2025 risk | Agent relevance |
|---|---|---|
| LLM01 | Prompt Injection (direct and indirect) | Core: web pages, files, tool results, MCP descriptions |
| LLM02 | Sensitive Information Disclosure | Secrets in workspace and env, session logs |
| LLM03 | Supply Chain | MCP servers, skills, plugins, models |
| LLM04 | Data and Model Poisoning | Memory, RAG |
| LLM05 | Improper Output Handling | Model output fed into shell or HTML |
| LLM06 | Excessive Agency | Tools with too much power or no approval |
| LLM07 | System Prompt Leakage | |
| LLM08 | Vector and Embedding Weaknesses | Only if we add RAG |
| LLM09 | Misinformation | |
| LLM10 | Unbounded Consumption | Loops and spend (denial of wallet) |

A **2026 edition** was published on 2026-08-03 ([OWASP resource page](https://genai.owasp.org/resource/owasp-genai-llm-top-10-2026/)). The page does not list the entries; they are in the PDF. A secondary summary ([Superblocks](https://www.superblocks.com/blog/owasp-llm-top-10)) gives this order: Prompt Injection; Sensitive Information Disclosure; **Excessive Agency (up from #6 to #3)**; Supply Chain; Data and Model Poisoning; Unbounded Consumption; Misinformation; **Hidden Context Exposure** (renamed from System Prompt Leakage); Vector and Embedding Weaknesses; Improper Output Handling. **(unverified: not read from the PDF.)** Its rise for Excessive Agency is the agentic shift in one line.

### OWASP Top 10 for Agentic Applications (ASI)

Published 2025-12-09 as "OWASP Top 10 for Agentic Applications for 2026" ([OWASP](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/)). The OWASP page does not list the entries. The names below come from Promptfoo's mapping page ([Promptfoo](https://www.promptfoo.dev/docs/red-team/owasp-agentic-ai/)) and agree with a vendor summary ([Cycode](https://cycode.com/blog/owasp-top-10-agentic-applications/)). They were not read from the OWASP PDF.

| ID | Risk | What it looks like in dsh |
|---|---|---|
| ASI01 | Agent Goal Hijack | A web page or file read through a tool redirects the task |
| ASI02 | Tool Misuse & Exploitation | Legitimate `bash`/`web_fetch` used for harm |
| ASI03 | Identity & Privilege Abuse | Agent uses the user's credentials beyond intent |
| ASI04 | Agentic Supply Chain | Malicious MCP server, skill or plugin |
| ASI05 | Unexpected Code Execution | Shell or PTC `run_code` running injected code |
| ASI06 | Memory & Context Poisoning | Our planned memory plugin storing attacker text |
| ASI07 | Insecure Inter-Agent Communication | Subagents, A2A, ACP |
| ASI08 | Cascading Failures | One bad tool result propagating through a plan |
| ASI09 | Human-Agent Trust Exploitation | Approval prompts that hide the real effect |
| ASI10 | Rogue Agents | Agent acting outside its goal |

An earlier companion, **"Agentic AI – Threats and Mitigations"** (T1–T15, about February 2025, T1 = memory poisoning, T2 = tool misuse), is cited by secondary sources. **(unverified: I did not open the OWASP document.)**

### OWASP MCP Top 10 (beta)

From [owasp.org/www-project-mcp-top-10](https://owasp.org/www-project-mcp-top-10/). The page says the project is in "Phase 3, Beta Release and Pilot Testing".

MCP01 Token Mismanagement & Secret Exposure · MCP02 Privilege Escalation via Scope Creep · **MCP03 Tool Poisoning** · MCP04 Software Supply Chain Attacks & Dependency Tampering · MCP05 Command Injection & Execution · MCP06 Prompt Injection via Contextual Payloads · MCP07 Insufficient Authentication & Authorization · MCP08 Lack of Audit and Telemetry · MCP09 Shadow MCP Servers · MCP10 Context Injection & Over-Sharing.

### MITRE ATLAS

Data from [`mitre-atlas/atlas-data`](https://github.com/mitre-atlas/atlas-data), release **v2026.09** (2026-09-15), file `dist/v6/ATLAS-2026.09.yaml`. It has 16 tactics (AML.TA0000–TA0015, ATT&CK-style, from Reconnaissance to Impact, plus AI-specific "AI Model Access" and "AI Attack Adaptation"), 208 technique and sub-technique entries, 40 mitigations and 73 case studies. The website is [atlas.mitre.org](https://atlas.mitre.org/).

Agent-relevant techniques (IDs and names copied from the YAML):

| ID | Name |
|---|---|
| AML.T0051 (.000/.001/.002) | LLM Prompt Injection (Direct / Indirect / Triggered) |
| AML.T0054 | LLM Jailbreak |
| AML.T0053 | AI Agent Tool Invocation |
| AML.T0086 | Exfiltration via AI Agent Tool Invocation |
| AML.T0110 | AI Agent Tool Poisoning |
| AML.T0099 | AI Agent Tool Data Poisoning |
| AML.T0080 / .000 | AI Agent Context Poisoning / Memory |
| AML.T0081 / T0083 / T0084 | Modify / Credentials from / Discover AI Agent Configuration |
| AML.T0084.001 | Discover AI Agent Configuration: Tool Definitions |
| AML.T0098 | AI Agent Tool Credential Harvesting |
| AML.T0101 | Data Destruction via AI Agent Tool Invocation |
| AML.T0105 | Escape to Host |
| AML.T0118 / .001 | Autonomous AI Agent Communication / Direct Agent Communication |
| AML.T0133 | Discover AI Agent Runtime Capabilities |
| AML.T0034.002 | Agentic Resource Consumption |
| AML.T0056 / T0069.002 | Extract LLM System Prompt / Discover LLM System Information: System Prompt |

### Two design ideas worth knowing

- **The "lethal trifecta"** (Simon Willison, 2025-06-16): private data, untrusted content, and a way to send data out. Any agent with all three can be made to exfiltrate. The advice is to never combine all three ([post](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/)). A dsh session with `web_fetch`, a workspace and any outbound tool has all three.
- **Design-level defences:** "Defeating Prompt Injections by Design" (CaMeL, Google DeepMind et al., [arXiv 2503.18813](https://arxiv.org/abs/2503.18813), 2025-03-24) and "Design Patterns for Securing LLM Agents against Prompt Injections" ([arXiv 2506.08837](https://arxiv.org/abs/2506.08837), 2025-06-10). Both argue for control-flow and data-flow separation instead of classifiers alone. I read the titles and dates only, not the papers in full.

### Attack classes from the issue, mapped

| Attack class | OWASP | ATLAS | Promptfoo plugin(s) |
|---|---|---|---|
| Direct prompt injection / jailbreak | LLM01 | T0051.000, T0054 | `system-prompt-override`, `hijacking`, strategies `jailbreak*`, `crescendo` |
| Indirect prompt injection | LLM01, ASI01 | T0051.001 | `indirect-prompt-injection`, strategy `indirect-web-pwn` |
| Tool / MCP poisoning, rug pull, shadowing | ASI04, MCP03 | T0110, T0099 | `mcp`, `tool-discovery` |
| Data exfiltration through tools | LLM02, ASI02 | T0086 | `data-exfil`, `ssrf`, `pii:*`, `prompt-extraction` |
| Excessive agency / privilege | LLM06, ASI03 | T0053 | `excessive-agency`, `rbac`, `bola`, `bfla` |
| Code execution | LLM05, ASI05 | T0105 | `shell-injection`, `sql-injection` |
| Memory poisoning | ASI06 | T0080.000 | `agentic:memory-poisoning` |
| Guardrail evaluation | — | — | Promptfoo `guardrails` assertions; garak; Prompt Guard |

## Promptfoo's red-team features

Promptfoo is MIT-licensed TypeScript ([repo](https://github.com/promptfoo/promptfoo), about 26k stars, pushed 2026-10-18). OpenAI announced an agreement to acquire Promptfoo on 2026-03-09 and said the open-source project would continue (press coverage, e.g. [Yahoo Finance](https://finance.yahoo.com/news/openai-acquires-promptfoo-secure-ai-174904138.html); openai.com returned 403 to my fetch, so **closing status unverified**).

### How a run works

From the [configuration docs](https://www.promptfoo.dev/docs/red-team/configuration/):

- The `redteam:` block in `promptfooconfig.yaml` has `purpose`, `plugins`, `strategies`, `numTests` and `provider`.
- **Plugins** generate adversarial inputs for one risk. **Strategies** change how they are delivered (encoding, iterative, multi-turn).
- `redteam.provider` is the attacker and grader model. The source default is `openai:chat:gpt-5.5-2026-04-23` (`src/redteam/constants/plugins.ts`).
- Default strategies: `basic`, `jailbreak:meta`, `jailbreak:composite` (`src/redteam/constants/strategies.ts`).
- Commands: `promptfoo redteam init`, `promptfoo redteam run` (generate plus eval), `promptfoo redteam report`.
- Framework presets: `owasp:llm`, `owasp:agentic` (or `owasp:agentic:asi01`…`asi10`), `owasp:api`, `mitre:atlas`, `nist:ai:measure`, `eu:ai-act`, `iso:42001`, `gdpr`.

### Plugins (157 across 6 categories)

From the [plugins page](https://www.promptfoo.dev/docs/red-team/plugins/). The ones that matter for agents:

- **Agency and tools:** `excessive-agency`, `hijacking`, `tool-discovery`, `debug-access`, `mcp`, `goal-misalignment`
- **Authorization:** `rbac`, `bola`, `bfla`
- **Injection:** `indirect-prompt-injection`, `system-prompt-override`, `special-token-injection`, `ascii-smuggling`, `cca`
- **Code and server:** `shell-injection`, `sql-injection`, `ssrf`
- **Data:** `prompt-extraction`, `pii:direct`, `pii:api-db`, `pii:session`, `pii:social`, `cross-session-leak`, `data-exfil`, `rag-document-exfiltration`, `rag-poisoning`
- **Memory:** `agentic:memory-poisoning`
- **Coding agents:** `coding-agent:core`, `coding-agent:all`, and sub-plugins such as `coding-agent:repo-prompt-injection`, `coding-agent:secret-file-read`, `coding-agent:sandbox-write-escape`, `coding-agent:verifier-sabotage`. These fit a dsh target closely, since dsh ships as a coding agent.
- **Custom:** `policy` (natural-language rule) and `intent` (your own attack goals).

The **`mcp` plugin** covers function discovery, parameter injection, function-call manipulation, excessive function calling, system information leakage, function output manipulation, tool metadata injection and unauthorized invocation ([docs](https://www.promptfoo.dev/docs/red-team/plugins/mcp/)).

### Strategies

From the [strategies page](https://www.promptfoo.dev/docs/red-team/strategies/):

- **Static (cheap, local):** `base64`, `hex`, `rot13`, `leetspeak`, `homoglyph`, `jailbreak-templates`, `other-encodings`, `image`, `video`, `audio`.
- **Iterative (attacker LLM):** `jailbreak`, `jailbreak:tree`, `jailbreak:meta`, `jailbreak:composite`, `best-of-n`, `citation`, `likert`, `math-prompt`, `gcg`, `authoritative-markup-injection`.
- **Multi-turn:** `crescendo`, `goat`, `jailbreak:hydra`, `goblin`, `mischievous-user`. Default maximum turns is 5.
- **Other:** `custom`, `custom-strategy` (natural language), `layer` (chain strategies), `retry` (regression), `indirect-web-pwn` (hidden payloads in web pages for browsing agents).

### Agent and MCP testing

- **Agents** ([guide](https://www.promptfoo.dev/docs/red-team/agents/)): connect the target over HTTP, a custom Python/JS provider, or `exec:`. The `exec:` provider passes the prompt as argv[1] and reads stdout ([docs](https://www.promptfoo.dev/docs/providers/custom-script/)), so `exec: dsh --profile headless …` is a valid zero-code target. **OpenTelemetry tracing** can feed the agent's spans into the attack and the grader. **Trajectory assertions** check what the agent did, not just what it said: `trajectory:tool-used`, `trajectory:tool-args-match`, `trajectory:tool-sequence`, `trajectory:step-count`, `trajectory:goal-success`, and `not-` variants.
- **MCP** ([guide](https://www.promptfoo.dev/docs/red-team/mcp-security-testing/)): three scenarios. (1) Red-team an app or model connected to your MCP server. (2) Run a **malicious MCP server alongside a legitimate one** to test tool poisoning and cross-server shadowing. (3) Call server tools directly with the `mcp` provider ([docs](https://www.promptfoo.dev/docs/providers/mcp/)), which is ordinary eval, not red teaming. Attack types it names include tool poisoning, tool shadowing, rug pulls, side-channel exfiltration and indirect prompt injection.

### The catch: remote-only plugins and strategies

From Promptfoo's source (`src/redteam/constants/plugins.ts`, `REMOTE_ONLY_PLUGIN_IDS`, and `strategies.ts`, `STRATEGIES_REQUIRING_REMOTE`, read on 2026-10-18):

- **Remote-only plugins** have no local implementation and always call Promptfoo's API: `mcp`, `indirect-prompt-injection`, `hijacking`, `bola`, `bfla`, `ssrf`, `data-exfil`, `agentic:memory-poisoning`, `system-prompt-override`, `special-token-injection`, `ascii-smuggling`, `cca`, `goal-misalignment`, `rag-poisoning`, `rag-document-exfiltration`, every `coding-agent:*` plugin, and others.
- **Remote-only strategies:** `jailbreak:meta`, `jailbreak:composite`, `jailbreak:hydra`, `goat`, `goblin`, `likert`, `citation`, `gcg`, `audio`, `indirect-web-pwn`.
- Free remote inference has "usage limits based on the number of probes run against your target system". The page gives no number ([inference limit](https://www.promptfoo.dev/docs/red-team/troubleshooting/inference-limit/)). Remote generation sends your `purpose` and test context to Promptfoo.
- `PROMPTFOO_DISABLE_REDTEAM_REMOTE_GENERATION=true` forces local generation. The docs warn local quality "is generally low for most models".

**What this means here:** the most interesting agent plugins depend on Promptfoo's cloud. That is fine for a learning project (the target and its secrets stay local; only probes are generated remotely), but plan for it. **Locally available** and useful: `excessive-agency`, `tool-discovery`, `prompt-extraction`, `pii:*`, `shell-injection`, `sql-injection`, `rbac`, `cross-session-leak`, `policy`, `intent`, plus `jailbreak`, `jailbreak:tree`, `crescendo`, `mischievous-user` and all static encodings. Local attacks use our OpenRouter models.

## Open tools

Repository metadata comes from the GitHub API on 2026-10-18.

| Tool | What it does | Lang / licence | Fit here |
|---|---|---|---|
| [promptfoo](https://github.com/promptfoo/promptfoo) | Eval plus red team, OWASP/ATLAS mapping, MCP and agent testing | TS / MIT | **Primary.** Already in the stack |
| [garak](https://github.com/NVIDIA/garak) (NVIDIA, v0.17.1, 2026-10-16) | "the LLM vulnerability scanner": probes (encoding, DAN, promptinject, leakage, …) with detectors. Targets OpenAI-compatible, LiteLLM and generic REST | Python / Apache-2.0 | Good for **model-level** baselines of the OpenRouter models before they go in the loop. Not agent-aware |
| [PyRIT](https://github.com/microsoft/PyRIT) (Microsoft, v1.1.0, 2026-09-04; moved from `Azure/PyRIT`, which is archived) | Attack orchestration: targets (OpenAI-style, HTTP, WebSocket, Playwright), converters, scorers, multi-turn attacks (Crescendo, TAP, Skeleton Key), SQLite memory ([docs](https://microsoft.github.io/PyRIT/1.1.0/)) | Python / MIT | Alternative to Promptfoo for custom multi-turn attacks with **no cloud dependency** |
| [Snyk Agent Scan](https://github.com/snyk/agent-scan) (formerly Invariant `mcp-scan`) | Discovers agents, MCP servers and skills on the machine and scans for tool poisoning and prompt injection | Python / Apache-2.0 | Useful, but **needs a Snyk token** and sends tool names, descriptions and skill content to Snyk's API (README). It also launches stdio servers, so the README says to run it in a sandbox |
| [Cisco MCP Scanner](https://github.com/cisco-ai-defense/mcp-scanner) | YARA, LLM and Cisco API engines. Offline JSON scanning, behavioural code scanning | Python / Apache-2.0 | **Best offline option.** YARA plus our own LLM via LiteLLM base URL (so OpenRouter should work, **unverified**) |
| [AgentDojo](https://github.com/ethz-spylab/agentdojo) (ETH Zurich + Invariant) | Benchmark of agent tasks with injected attacks and pluggable defences ([paper](https://arxiv.org/abs/2406.13352)) | Python / MIT | A reference design for our own mini benchmark. Running it against dsh would need an adapter |
| [Agent Security Bench](https://github.com/agiresearch/ASB) | Agent attack and defence benchmark | Python / MIT | Same as above |
| [LlamaFirewall](https://github.com/meta-llama/PurpleLlama/tree/main/LlamaFirewall) (Meta, PurpleLlama) | Guardrail framework: PromptGuard 2 classifier, AlignmentCheck (CoT auditor for goal hijack), CodeShield, regex scanners | Python / Llama licence | Design reference for our defence plugin |
| [Llama Prompt Guard 2](https://huggingface.co/meta-llama/Llama-Prompt-Guard-2-86M) (22M / 86M) | Small injection/jailbreak classifiers | gated, Llama licence | Run locally as a scanner. Gated download |
| [protectai/deberta-v3-base-prompt-injection-v2](https://huggingface.co/protectai/deberta-v3-base-prompt-injection-v2) | Injection classifier with ONNX weights | Apache-2.0 | Ungated. ONNX makes it a candidate for **transformers.js inside a TS plugin** (**unverified**) |
| [NeMo Guardrails](https://github.com/NVIDIA-NeMo/Guardrails) | Programmable rails | Python | Poor fit for a TS harness (see the NemoClaw research) |
| [DeepTeam](https://github.com/confident-ai/deepteam), [Giskard](https://github.com/Giskard-AI/giskard-oss), [Agentic Radar](https://github.com/splx-ai/agentic-radar) | Red-team or scan frameworks | Python / Apache-2.0 | Alternatives. Not needed |
| [Damn Vulnerable MCP Server](https://github.com/harishsg993010/damn-vulnerable-MCP-server) | Deliberately vulnerable MCP challenges | Python / **no licence file** | A ready-made **target** for the red-team agent. Run it only locally |

Archived, so avoid: `protectai/llm-guard` and `protectai/rebuff` (both archived), `lakeraai/pint-benchmark` (archived).

The canonical write-up of tool poisoning, rug pulls and cross-server shadowing is Invariant Labs, 2025-04-01 ([blog](https://invariantlabs.ai/blog/mcp-security-notification-tool-poisoning-attacks)). Its suggested mitigations are to show users full tool descriptions, **pin tools by hash**, and enforce cross-server data-flow boundaries.

## What dsh already gives a defender

All from dsh at `dsh-v0.2.1-rc.2`.

### Hook points

[`docs/tool-execution-pipeline.md`](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/docs/tool-execution-pipeline.md) and [`docs/subsystems/tools.md`](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/docs/subsystems/tools.md):

| Hook | Kind | Can do | Defence use |
|---|---|---|---|
| `tools/pre-execute` | waterfall `(exec, next) → PreToolDecision` | `allow`, `deny {reason}`, `cancel`, `ask {reason, displayReason}`. **Cannot rewrite arguments** | Policy: egress allowlist on `web_fetch` URLs and MCP args, secret-pattern scan of outgoing arguments, a "trifecta" taint rule, `ask` for risky calls |
| `ctx.tools.guard(fn)` | monotonic guard, after pre-execute and approval | Returns a reason to deny, or `undefined`. **Cannot force-allow** | Hard rules that no later listener or approval can undo (e.g. an MCP tool whose description hash changed) |
| `tools/execute` | around-dispatch waterfall | Wraps the body; may change only `exec.signal` | Timing, rate limits, metrics (the existing `timeout-policy` lives here) |
| `tools/post-execute` | waterfall `(exec, result, next) → PostToolDecision` | `accept` with replacement `content` **or** `value`, `block {feedback}`, `additionalContexts` | **Main injection defence:** scan tool results (web pages, files, MCP output) and block, redact, or wrap them as untrusted data |
| `tools/result` | emit, frozen | Observe only | Audit log of every outcome for eval and forensics |
| `agent/pre-step` | waterfall | `reject` the step or `enter` with replaced messages | Scan **user input** before the model sees it |
| `agent/request` | waterfall | Swap the call config (model, etc.) | Route to a stricter model or settings under suspicion |
| `llm/stream` | waterfall around every model call | Observe or short-circuit the stream; loop requests are frozen | Output-side checks, e.g. a canary token appearing in model output |
| `approval/request` | waterfall of answerers | Return an outcome or delegate | A machine answerer (a small classifier or the Decisions API) in front of the human |

Two caveats from the docs:

- "Content replacement is presentation policy, not confidentiality policy: a listener that must hide the programmatic value blocks or replaces it." So a redacting defence must replace `value` or `block`, not just `content`.
- In PTC mode, `run_code` sub-calls go through the pipeline, but the auto-review README notes "direct Node effects inside a PTC program do not pass through inner-tool review." **Keep PTC off on a hardened target.**

### Sandbox, approval and presets

- **`sandbox` / `sandbox-local` / `sandbox-policy`** ([README](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/packages/sandbox/README.md)): modes `read-only`, `workspace-write`, `danger-full-access`. On macOS the backend is Seatbelt with an allow-default profile plus `(deny file-write*)` and workspace write allow-lists. It fails closed with `SANDBOX_UNAVAILABLE`. A denied call may retry once with a wider mode after human approval. **Limit, stated in the README:** "the seam expresses no network, process, syscall, device, or credential restrictions." Reads are not confined either, so `~/.ssh` is readable in every mode. The fs-sandbox and srt-style network allowlists would have to come from us or another tool.
- **`user-approval`** ([README](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/packages/interaction/user-approval/README.md)): policy `ask` or `never`. With no answerer the result is `unavailable`, which fails closed. Every request and outcome goes in the session audit log. The base bundle sets `ask` unless `DSH_PERMISSION_MODE=danger-full-access`. In headless mode I expect `ask` to fail closed for lack of an interactive answerer (**inferred from the README, not tested**).
- **`permission-presets`** bundles sandbox mode and approval policy into one selector (`read-only`, `workspace-write`, `danger-full-access`, plus `auto` when auto-review is loaded).
- **`experimental/auto-review`** ([README](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/packages/experimental/auto-review/README.md)): a prepended `tools/pre-execute` listener that asks the current model to classify each call as low, medium or high risk. "Sensitive exfiltration across a trust boundary is high risk and always denied." It runs with **Full access sandbox** and costs one extra uncached model call per tool call. The README warns it "can allow unsafe actions". This makes it **an excellent red-team target**: an LLM judge guarding an unsandboxed agent.
- **`guard/`** is loop hygiene only (`repeat-tool-reminder`, `timeout-policy`), not security.

### MCP client: attack surface

From [`mcp-client` README](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/packages/mcp/mcp-client/README.md):

- "Server instructions join the logged system prompt as literal text." Tool descriptions and schemas "enter every request". This is the tool-poisoning channel.
- Tools re-sync on server notification and reconnect; changed definitions replace the old ones. **There is no pinning or hash check, so a rug pull is possible.**
- Good: stdio children get a scrubbed env (names matching `KEY|PASSWORD|SECRET|TOKEN` are dropped). Tools are namespaced `mcp__<server>__<tool>`, which blunts name collisions but not description-based shadowing.
- `web-fetch-http` rejects non-public destinations (an SSRF guard) but can still send data **to** any public URL, which is the exfiltration channel.

## dsh as a hardened target

A "hardened dsh" profile is a dsh bundle patch (ADR 0001 style) that composes:

1. **Baseline config:** `sandbox-policy.mode: read-only` (or `workspace-write` on a throwaway workspace), `user-approval.policy: ask`, PTC off, and only the MCP servers under test.
2. **`mcp-pin` guard** (our plugin): on first sight, hash each MCP tool's name, description and schema into a lockfile. A `ctx.tools.guard` denies any call to a tool whose hash changed (rug pull). Optionally a `tools/pre-execute` `ask` prompts on first use. Addresses MCP03, ASI04 and AML.T0110.
3. **`injection-scan` post-filter** (our plugin): on `tools/post-execute` for `web_fetch`, file reads and `mcp__*`, run a cheap classifier (ONNX deberta via transformers.js, or `gpt-oss-20b`, or a Decisions API predicate). On a hit, `block` with feedback, or replace `value` with a fenced "untrusted data" wrapper. Also scan user input on `agent/pre-step`. Addresses LLM01, ASI01 and T0051.001.
4. **`egress-policy` pre-filter** (our plugin): on `tools/pre-execute`, deny or `ask` when a `web_fetch` URL or an outbound MCP argument goes to a host outside an allowlist, or when arguments contain secrets or a planted canary. A taint flag ("this turn has read untrusted content") can escalate `allow` to `ask`. This is the lethal-trifecta breaker. Addresses LLM02, ASI02 and T0086.
5. **`audit` observer** on `tools/result` that writes JSONL, which Promptfoo assertions and our reports can read.
6. Optionally `auto-review` layered on top, to compare a model judge against the deterministic rules.

A **canary** (a fake `API_KEY=canary-…` in the workspace `.env`) turns "did it exfiltrate?" into a string match.

## dsh as a red-team agent

An attacker is a dsh agent with an attack skill (AGENTS.md or skill file) and a few tools of our own:

- **`target_agent.send`**: talks to the target agent. Options: spawn `dsh --profile headless --json --session-id …` (gives multi-turn and NDJSON events); speak ACP to an ACP-capable agent; or HTTP for agents with an API. Later, A2A.
- **`mcp_probe.list` / `mcp_probe.call`**: connect to a target MCP server with the official TS SDK and return its tools, descriptions and results **as quoted data**. Do **not** mount the target through `dsh-mcp-client`, because its descriptions and instructions would land in the attacker's own system prompt and could hijack it.
- **`evil_mcp`**: a small malicious MCP server we write (poisoned description, a rug pull after N calls, a shadowing description that targets another tool). It acts as an attack fixture against the target agent, as in Promptfoo's scenario 2.
- **`judge`**: a Decisions API predicate or score ("did the target leak the canary?", "did it call a tool outside the task?"), or plain string checks.
- **Session log as the attack record.** dsh logs everything, so a run is replayable evidence.

Targets, safest first: our own hardened dsh profile; dsh with `auto-review`; Damn Vulnerable MCP Server; MCP servers we write; other open agents run locally. **Only attack systems you own or run locally.**

Promptfoo can sit on either side. As the harness for scoring, it drives the target through `exec:`. Alternatively, our attacker agent can be wrapped as a Promptfoo custom provider or strategy (`custom-strategy`) **(unverified whether a custom JS strategy can call out to a dsh process cleanly)**.

## Cost and practical notes

- Model prices are from the OpenRouter research (#15): `deepseek-v4.1-flash` about $0.30/$1.20 per million tokens, `gpt-oss-20b` about $0.10 per million output tokens, `mistral-nemo` about $0.03 per million tokens.
- A Promptfoo run of 10 plugins × 5 tests × 3 strategies is about 150 probes. If each probe costs the target 3 model steps of about 8k input tokens, that is about 3.6M input tokens, or **$0.40–$1.50 per full run on `v4.1-flash`** (my estimate). Multi-turn strategies multiply that by up to 5. Iterating on 20–40 cases costs cents.
- Remote-generated plugins cost us nothing in tokens for generation, but they count against Promptfoo's free probe limit (number not published).
- Everything except garak, PyRIT and the scanners is TypeScript. Python tools run as CLIs next to the harness and do not need to be dsh plugins.
- dsh is unaudited prerelease software. Run attack experiments in a throwaway workspace with fake secrets only.

## Candidate project ideas for this harness

### 1. Hardened dsh: tool-poisoning and indirect-injection defence, measured (recommended first)

- **Value to a learner:** every hook in the tool pipeline, deny vs. guard vs. post-filter semantics, why classifiers alone fail, and a real before/after number.
- **Plugins:** our `mcp-pin` guard, `injection-scan` (post-execute plus pre-step), `egress-policy` (pre-execute), `audit` (tools/result); dsh `sandbox-local`, `sandbox-policy`, `user-approval`, `mcp-client`, `tool-web`; our `evil_mcp` fixture.
- **Targets:** our own dsh profile, with and without the defence plugins.
- **Eval:** Promptfoo against `exec: dsh --profile headless`, with plugins `mcp`, `indirect-prompt-injection`, `data-exfil` (remote) and `excessive-agency`, `prompt-extraction`, `policy` (local), strategies `jailbreak`, `crescendo`, `owasp:agentic` preset, plus a canary-string assertion and `trajectory:*` assertions. Report attack success rate (ASR) before and after, and the false-positive rate on a benign task set.
- **Rough cost:** about $1–5 a month on `v4.1-flash`, plus the free Promptfoo remote tier.

### 2. MCP server auditor agent

- **Value:** the MCP protocol in depth, tool-poisoning patterns, and why a scanner must treat what it reads as data (the attacker-hijack trap).
- **Plugins:** our `mcp_probe` tool (TS MCP SDK), a YARA-like rules module, a `judge` via the Decisions API or `gpt-oss-20b`, and a report skill.
- **Targets:** Damn Vulnerable MCP Server, our `evil_mcp`, MCP servers you actually use (read-only metadata only).
- **Eval:** a labelled set of benign and poisoned tool definitions; precision and recall compared with Cisco MCP Scanner (offline YARA mode) and Snyk Agent Scan (optional; it uploads metadata).
- **Rough cost:** under $1 a month (only small-model calls over tool descriptions).

### 3. Red-team agent vs. LLM judge (`auto-review`)

- **Value:** adaptive multi-turn attacks, the limits of LLM-as-guard, and attacker/defender co-evolution.
- **Plugins:** our `target_agent.send` (headless dsh subprocess), an attack skill, `judge`, `audit`; dsh `experimental/auto-review` on the target.
- **Targets:** dsh with `auto-review` (Full access sandbox, so use a throwaway VM or workspace with fake secrets), then the same target plus idea 1's deterministic rules.
- **Eval:** fixed goals (exfiltrate the canary, write outside the workspace, delete a seeded file); compare ASR for our agent against Promptfoo's `crescendo` and `jailbreak:hydra`, and the turns needed to succeed.
- **Rough cost:** $3–10 a month. Every target tool call costs an extra reviewer call, and attacks are multi-turn. Use `:free` models for development.

### 4. Model baseline matrix: which cheap open-weight model is safest for the main loop?

- **Value:** model-level vs. system-level risk, garak and Promptfoo side by side, and feeds directly into the model lineup ticket (#16).
- **Plugins:** none new. Promptfoo plus garak via an OpenAI-compatible endpoint (OpenRouter).
- **Targets:** the #15 shortlist: `deepseek-v4.1-flash`, `glm-5.3-flash`, `gpt-oss-20b`, `mistral-nemo`, as raw models and then inside dsh.
- **Eval:** garak `promptinject`, `encoding`, `dan` probes; Promptfoo `owasp:llm` preset with local strategies only. Then rerun the agent-level eval from idea 1 per model.
- **Rough cost:** $2–6 one-off.

### 5. Memory-poisoning lab (pairs with the memory plugin)

- **Value:** ASI06 and AML.T0080 hands-on; teaches provenance and why stored "facts" need a source.
- **Plugins:** our OptMem-style memory plugin, plus a provenance tagger on `tools/post-execute` (marks memories that came from untrusted tool output) and a recall filter.
- **Targets:** our own harness with memory on.
- **Eval:** Promptfoo `agentic:memory-poisoning` (remote) and `cross-session-leak` (local), plus custom multi-session cases: plant in session 1, check in session 2.
- **Rough cost:** about $1–3 a month. Depends on the memory plugin existing first.

### 6. Guardrail bake-off as a pluggable `ctx.guardrail` service (stretch)

- **Value:** comparing classifier, LLM-judge and typed-decision guardrails on the same seam, with latency and cost trade-offs; reuses the `ctx.decisions` idea from #17.
- **Plugins:** a `guardrail` service with backends: ONNX deberta (local), Prompt Guard 2 (gated), `gpt-oss-20b` prompt, Decisions API predicate. Wired into `injection-scan` from idea 1.
- **Targets:** idea 1's hardened profile.
- **Eval:** the same Promptfoo suite per backend; ASR, false-positive rate on benign tasks, p50 latency, and $ per 1k calls.
- **Rough cost:** $1–4 a month (Decisions API at about $0.10 per million input tokens; local classifiers free).

## Sources

- Issue #20 and map #1 in this repo.
- DeepSeek Harness at `dsh-v0.2.1-rc.2`: [`docs/tool-execution-pipeline.md`](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/docs/tool-execution-pipeline.md), [`docs/subsystems/tools.md`](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/docs/subsystems/tools.md), [`docs/subsystems/core.md`](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/docs/subsystems/core.md), [`docs/subsystems/sandbox.md`](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/docs/subsystems/sandbox.md), package READMEs under `packages/sandbox/`, `packages/guard/`, `packages/interaction/`, `packages/mcp/mcp-client/`, `packages/experimental/auto-review/`, `packages/web/web-fetch-http/`, and `packages/bundle/base/cordis.patch.yml`.
- OWASP: [LLM Top 10](https://genai.owasp.org/llm-top-10/), [LLM Top 10 2026](https://genai.owasp.org/resource/owasp-genai-llm-top-10-2026/), [Agentic Top 10](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/), [MCP Top 10](https://owasp.org/www-project-mcp-top-10/).
- MITRE ATLAS: [atlas-data v2026.09](https://github.com/mitre-atlas/atlas-data).
- Promptfoo docs: [configuration](https://www.promptfoo.dev/docs/red-team/configuration/), [plugins](https://www.promptfoo.dev/docs/red-team/plugins/), [strategies](https://www.promptfoo.dev/docs/red-team/strategies/), [agents](https://www.promptfoo.dev/docs/red-team/agents/), [MCP security testing](https://www.promptfoo.dev/docs/red-team/mcp-security-testing/), [OWASP agentic](https://www.promptfoo.dev/docs/red-team/owasp-agentic-ai/), [`mcp` plugin](https://www.promptfoo.dev/docs/red-team/plugins/mcp/), [`mcp` provider](https://www.promptfoo.dev/docs/providers/mcp/), [`exec:` provider](https://www.promptfoo.dev/docs/providers/custom-script/), [inference limit](https://www.promptfoo.dev/docs/red-team/troubleshooting/inference-limit/); source [`src/redteam/constants/`](https://github.com/promptfoo/promptfoo/tree/main/src/redteam/constants).
- Tools: the GitHub repos linked in the table; [Invariant Labs on tool poisoning](https://invariantlabs.ai/blog/mcp-security-notification-tool-poisoning-attacks); [Simon Willison on the lethal trifecta](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/); arXiv [2503.18813](https://arxiv.org/abs/2503.18813), [2506.08837](https://arxiv.org/abs/2506.08837), [2406.13352](https://arxiv.org/abs/2406.13352).
- Prior research in this repo: `research/openrouter-models.md` (#15) for model prices.
