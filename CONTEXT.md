# DeepSeek demo implementation

A personal, learning-first agent harness built as our own plugins on top of DeepSeek Harness (dsh). This glossary uses dsh's vocabulary wherever dsh already names a concept.

## Language

### Composition

**Plugin**:
A Cordis unit that registers services, tools or event handlers on a context, all of which are undone when it unloads.
_Avoid_: extension, module, add-on

**Service**:
A named capability a plugin provides on the context (e.g. `ctx.tools`, `ctx.decisions`), which other plugins declare they need.
_Avoid_: provider, manager

**Seam**:
A service definition plus the plugin that provides it and the plugins that use it, where one provider can be swapped for another without touching the callers.
_Avoid_: interface, port

**Bundle**:
An installable package of plugins plus a profile patch; this repo is one bundle.
_Avoid_: distribution, plugin pack

**Profile**:
A named dsh composition: ordered bundles plus YAML patch layers that decide which plugins load with which config.
_Avoid_: preset, environment

### Running

**Turn**:
Everything the agent does in response to one user input; zero or more steps.
_Avoid_: run, exchange

**Step**:
One model request plus the tool calls it makes.
_Avoid_: iteration, round

**Session log**:
The append-only record of session events from which the model's history is rebuilt; the source of truth.
_Avoid_: transcript, history, conversation

**Decision**:
A typed answer (predicate, choice or score with calibrated probabilities) from a decisions model, as opposed to generated text.
_Avoid_: classification, judgement

### Security

**Hardened harness**:
Our dsh profile with the defence plugins enabled; the thing red-team runs attack and the thing security jobs run on.
_Avoid_: secure mode, safe harness

**Defence**:
A plugin that blocks or filters at a tool-pipeline hook (egress allowlist, injection filter, MCP pinning guard, canary check).
_Avoid_: guardrail, protection

**Attack set**:
The fixed collection of attacks (DVMCP challenges, our malicious MCP server, local Promptfoo red-team probes) that the hardened harness is scored against.
_Avoid_: test suite, red-team suite

**Attack success rate**:
The share of attacks in the attack set that achieve their goal; measured before and after each defence.
_Avoid_: ASR (in prose), pass rate

**Canary secret**:
A planted fake credential that must never appear in model output or outbound requests; its appearance is how a leak is detected.
_Avoid_: honeytoken, dummy key

**Victim model**:
The model under attack in red-team runs; always a local Ollama model, never one reached through OpenRouter.
_Avoid_: target model

**Security job**:
A defensive task the hardened harness performs on the user's own material, such as the secrets false-positive filter.
_Avoid_: workload, use case

**Finding**:
A candidate issue raised by a deterministic tool (e.g. a gitleaks hit) before any model judges it.
_Avoid_: alert, hit, result
