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
An installable package that declares a `dsh.bundle.patch` layer selecting and configuring plugins; this repo ships one bundle per profile.
_Avoid_: distribution, plugin pack

**Profile**:
A named dsh composition: ordered bundle layers, then the user-owned `cordis.patch.yml` in `$DSH_HOME`, deciding which plugins load with which config.
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

**Launcher**:
The committed per-profile script that reads API keys from the macOS Keychain, sets dsh's bootstrap variables and starts dsh; the only way keys reach a dsh process.
_Avoid_: wrapper, start script

**Job profile**:
The dsh profile that runs security jobs with remote models (OpenRouter, Decisions API).
_Avoid_: production profile, main profile

**Interactive profile**:
The dsh profile you use by hand, with the job profile's models and defences plus web search and fetch; the only profile that reaches the open web.
_Avoid_: dev profile, chat mode

**Red-team profile**:
The dsh profile used for attack runs; it reaches local models only and has no remote fallback.
_Avoid_: test profile, attack mode

### Security

**Hardened harness**:
Our dsh profile with the defence plugins enabled; the thing red-team runs attack and the thing security jobs run on.
_Avoid_: secure mode, safe harness

**Control plane**:
The part of the hardened harness that decides whether an action proposal may run, enforces that policy decision, and records it with its effect; the model takes no part in it.
_Avoid_: guardrails, governance layer

**Action proposal**:
A tool call from the model, treated as a request to act and never as permission to.
_Avoid_: intent

**Policy decision**:
The control plane's one allow, deny or ask answer for an action proposal, reached deterministically from the proposal, its context and the policy version. Always "policy decision", never plain "decision", which is a decisions model's answer.
_Avoid_: verdict, permission check

**Risk tier**:
The consequence class of an action proposal, from T0 (observe) through T1 (draft), T2 (reversible) and T3 (approve) to T4 (critical, denied); set by the bundle's policy, never by the tool or the model, and raised but never lowered by context such as taint.
_Avoid_: risk level, autonomy level

**Executor**:
What performs an allowed action, holding only the authority that action needs.
_Avoid_: broker, runner

**Effect**:
The change an executed action actually made, recorded as verified, failed or unknown; a dispatched action with no verified effect is never reported as done.
_Avoid_: result, outcome

**Ledger**:
The tamper-evident, hash-chained record of a run's action proposals, policy decisions and effects, kept apart from anything the model sees.
_Avoid_: audit log, audit trail, transcript

**Defence**:
A detector or rule whose result feeds a policy decision (egress allowlist, read allowlist, taint, injection filter, MCP pinning guard, canary check); each is scored by its effect on attack success rate.
_Avoid_: guardrail, protection

**Attack set**:
The fixed collection of attacks (DVMCP challenges, our malicious MCP server, local Promptfoo red-team probes) that the hardened harness is scored against.
_Avoid_: test suite, red-team suite

**Attack attempt**:
One run of one attack from the attack set; each attack is attempted several times because the victim model is nondeterministic.
_Avoid_: trial, sample

**Attack success rate**:
The share of attack attempts that achieve their goal, judged by deterministic checks only; measured before and after each defence.
_Avoid_: ASR (in prose), pass rate

**Upstream bug**:
A successful attack attempt that reproduces without the model and breaks behaviour dsh or its bundled code documents; reported privately, never counted as a gap in our defences.
_Avoid_: vulnerability, 0-day, CVE (before one is assigned)

**Canary secret**:
A planted fake credential that must never appear in model output or outbound requests; its appearance is how a leak is detected.
_Avoid_: honeytoken, dummy key

**Victim model**:
The model under attack in red-team runs: a local model, or one behind an API whose terms allow testing your own app; never one reached through OpenRouter without its approval.
_Avoid_: target model

**Taint**:
A per-session flag set once the agent has read untrusted content; while it is set, outbound calls need approval. No turn boundary clears it.
_Avoid_: contamination, dirty flag

**Pin**:
The recorded hash of an MCP tool's name, description, schema and server instructions, kept in a committed lockfile; a changed tool is refused until it is re-approved.
_Avoid_: lock, signature

**Untrusted data**:
Tool output that the injection filter has fenced off as data, never instructions, before the model sees it.
_Avoid_: quarantined content, sanitised output

**Security job**:
A defensive task the hardened harness performs on the user's own material, such as the secrets false-positive filter.
_Avoid_: workload, use case

**Masked finding**:
A finding with the secret value replaced by a shape token (length, charset, entropy, known vendor prefix), sent with its surrounding lines; the only form of a finding that may leave the machine.
_Avoid_: redacted secret, sanitised hit

**Finding**:
A candidate issue raised by a deterministic tool (e.g. a gitleaks hit) before any model judges it.
_Avoid_: alert, hit, result

### Harnessing

**Fixture task**:
A self-contained task (inputs, a task domain and an answer key) used only to probe harness candidates.
_Avoid_: benchmark, test case

**Task domain**:
A family of fixture tasks that share an answer shape and an experience library.
_Avoid_: category, suite

**Answer key**:
A fixture task's expected answer, read only by the checker and never shown to the agent or the improver.
_Avoid_: ground truth, gold, label

**Checker**:
Deterministic code that scores a submitted answer against its answer key. It scores an answer to a fixture task, not an attack attempt, so it is distinct from the deterministic checks that judge attack success (ADR 0011), and from a grader or judge, which is a model.
_Avoid_: grader, judge, scorer
