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
