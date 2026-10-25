# What are Jev and Laya?

Research for issue #5 (map: #1). Sources read 2026-10-18. Both links resolve and are on-topic.

## TL;DR

- **Neither is a TypeScript typing or validation library.** Both are **"System 1" decision models**: you send a piece of text (the *state*) plus typed questions (`choice`, `score`, `noul` = yes/no probability) and get back calibrated probabilities in one pass, with no generated text.
- **Jev** is TypeSafe's **hosted, closed model** behind `POST https://api.typesafe.ai/v1/systemone`, with Python and TypeScript SDKs. You pay per input token.
- **Laya** is an **open-source (Apache-2.0), self-hostable look-alike of Jev**. It is mainly Python/PyTorch, runs encoder checkpoints (ModernBERT / mmBERT) on Hugging Face, and its HTTP server speaks Jev's wire protocol. It benchmarks itself against Jev.
- **Relation:** Laya is a third-party open alternative to Jev that can replace it on the wire. They come from different authors: Convai Innovations / NandhaKishorM, and TypeSafe.
- **Harness role:** an optional **fast classifier tool or router** (for example: which tool or sub-agent to use, does this source answer the question, does this need a human or a stronger LLM). It is not core-loop infrastructure. For typing and validation of tool I/O you still need something like Zod or TypeBox.

## Jev (TypeSafe)

What it is

- Docs call Jev TypeSafe's "flagship model and the first System One model". It takes a state and returns typed answers with probabilities, not generated text. The name comes from Kahneman's System 1. Input is text only (strings, JSON, arrays of text). It does not write replies, write code or explain its reasoning. [docs.typesafe.ai/concepts/system-one](https://docs.typesafe.ai/concepts/system-one)
- Primitives are Choice, Score and Noul. Each returns probabilities. Choice and score also return `confidence`. Docs say the probabilities are trained for calibration, measured across groups of predictions, and that a single answer is not guaranteed correct. [quickstart](https://docs.typesafe.ai/introduction/quickstart), [system-one](https://docs.typesafe.ai/concepts/system-one)
- Intended agent use, per the docs: several narrow judgments on one input, combined with deterministic code checks, then a choice to act or to escalate to a human or a reasoning model based on confidence. [system-one](https://docs.typesafe.ai/concepts/system-one)

Language and runtime

- Hosted HTTP API only. Auth is `Authorization: Bearer <key>`, and requests carry `state`, `model` (e.g. `jev-latest`) and `questions`. [quickstart](https://docs.typesafe.ai/introduction/quickstart)
- The docs list no weights and no self-hosting option. They say "the same weights serve every account" and that Jev is not fine-tuned on customer data. [docs.typesafe.ai/models](https://docs.typesafe.ai/models)
- The architecture is not disclosed in the pages read.
- SDKs:
  - TypeScript: `@typesafe-ai/sdk`. Docs say "Answer types are inferred from your questions". Question helpers are `choice`, `score`, `noul` and `box`, and the call is `client.systemOne({ state, questions, model?, assets? })`. Ships ESM, CJS and type declarations, and reads its key from `TYPESAFE_API_KEY`. [sdk/javascript](https://docs.typesafe.ai/sdk/javascript)
  - Python: `typesafe-sdk`. [quickstart](https://docs.typesafe.ai/introduction/quickstart)
  - The Node version requirement differs between pages: the JS SDK page says Node 22+, the quickstart says Node 20+.

Maturity (as of 2026-10-18)

- Models: `jev-1.13.0` is `jev-latest` (stable). `jev-1.14.0` is `jev-preview`, available from 2026-10-14. [models](https://docs.typesafe.ai/models)
- Pricing as the models page states it: "$42 per Btok", paid on input tokens only. Context is 64k per request and 32k per question, or 262k behind a "Danger-Zone" header. [models](https://docs.typesafe.ai/models)
- npm `@typesafe-ai/sdk` was created 2026-09-12, latest 0.7.0, MIT. PyPI `typesafe-sdk` is at 0.7.5. Both are pre-1.0 and about a month old. (Source: npm registry and PyPI JSON APIs.)
- The pages read show no public paper and no open weights.

## Laya (NandhaKishorM/laya)

What it is

- The README calls it a "Multilingual, non-autoregressive System 1 decision engine". It answers typed decisions over 100+ languages in one forward pass (it claims 33 ms per question on a T4). Training is RL against proper scoring rules ("RLCD"), and a `Router` picks a checkpoint per request. [README](https://github.com/NandhaKishorM/laya)
- It uses the same question types as Jev: `choice`, `score`, `noul`. Its `decide()` turns a JSON Schema (enum, boolean, bounded int) into questions. [README](https://github.com/NandhaKishorM/laya), [laya-ts/README](https://github.com/NandhaKishorM/laya/tree/main/laya-ts)
- Checkpoints on Hugging Face:

  | Checkpoint | Encoder | Params | Context |
  |---|---|---|---|
  | `convaiinnovations/laya` | ModernBERT-large | 421M | 512 |
  | `laya-multilingual` | mmBERT-base | 322M | 1024, up to 8192 |
  | `laya-typed-decisions` | ModernBERT-large | 421M | 1024 |

  [README](https://github.com/NandhaKishorM/laya)

Relation to Jev (stated by Laya itself)

- `laya-serve` "exposes Laya over the TypeSafe Jev `/v1/systemone` wire protocol". A Jev client can point its base URL at it, and `LAYA_JEV_STRICT=1` returns the strict Jev response shape. [docs/http-api.md](https://github.com/NandhaKishorM/laya/blob/main/docs/http-api.md)
- The README benchmarks Laya against "Jev 1.13.0". Laya says its Jev figures are "third-party published, never measured here (no TypeSafe API access)".
  - Laya's claims: it leads on fine-tuned typed decisions (0.766 vs 0.727 argmax).
  - Laya's own "Where Jev leads" section admits it trails on many-option label sets (Banking77: 0.870 for Jev vs 0.425 for Laya) and on soft-distribution accuracy. The cause is a fixed per-question option token budget.
  - Confidence is defined differently from Jev's, so thresholds do not carry over. [README](https://github.com/NandhaKishorM/laya)

Language and runtime

- The core is **Python 3.10+, PyTorch, transformers**: `pip install laya`. Extras add an HTTP server, an MCP server, LangChain/LlamaIndex/CrewAI/Agno integrations, ONNX and pydantic. [README](https://github.com/NandhaKishorM/laya)
- **TypeScript:**
  - `laya-ts/` runs inference in Node (onnxruntime-node) or the browser (WebGPU, falling back to WASM) from split ONNX exports. It is ESM-only, and the exports are produced by a Python script.
  - `sdk/typescript` is an HTTP client for `laya-serve`.
  - `laya-ts`'s package.json is version 0.1.0. The README says it is published from `laya-ts-v*` tags, but the repo has no such release and npm returns "Not found" for both `laya-ts` and `laya-client`. Today the TS path means building from source. [laya-ts/package.json](https://github.com/NandhaKishorM/laya/blob/main/laya-ts/package.json)
- The repo also has Rust, Go, Java and .NET ports (`laya-rust`, `laya-go`, `laya-java`, `laya-dotnet`).

Maturity (as of 2026-10-18)

- The repo was created 2026-09-18, so it is about one month old.
  - About 2,390 commits.
  - Latest release v0.4.11 (2026-10-17). Several releases ship per day, and PyPI shows 49 versions.
  - About 33k stars and an active contributor base (top committer is the author with about 860 commits).
  - Apache-2.0. (Source: GitHub API, PyPI JSON.)
- The project documents its limits openly ("Honest limits", "Where Jev leads"). It is pre-1.0 and changing very fast, so expect API churn.

## What role could each play in own-harness?

- **Not typing or validation.** Neither replaces Zod, TypeBox or TS types for tool schemas. The "typed" in their names refers to the *answer shape* of a classification. Jev's TS SDK infers answer types, and Laya's `decide()` accepts JSON Schema, including from `z.toJSONSchema()`.
- **Not the core runtime.** They don't run loops, call tools or generate text.
- **Plausible use: a cheap, fast "System 1" tool or router next to the LLM.** In the research-assistant use case this could mean:
  - classifying the user's intent
  - choosing which tool to call (Laya has a `LayaToolSelector`)
  - judging whether a fetched source is relevant or answers the question
  - gating on confidence before escalating to the main LLM or asking the user
- **Practical trade-off:**
  - Jev is a hosted API with a polished TS SDK. It needs an API key and network access, and is closed.
  - Laya is local and free. It is heavy (300-400M param models, a Python/PyTorch stack or a self-built ONNX path for TS) and very young.
  - Because Laya speaks Jev's protocol, one HTTP adapter could target either.
- For a learning-first thin core, this is an **optional later plug-in**, not a dependency for the first milestones.

## Open questions / not verified

- Jev's architecture, any independent benchmarks, and TypeSafe's company background: none of these appear in the docs pages read.
- Laya's benchmark numbers come from Laya's own repo. Its Jev numbers come from third parties, not from runs Laya did itself.
- I did not run either system.
