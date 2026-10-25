# OpenAI Decisions API: which jobs fit, and how do we call it from dsh?

Research for issue #17 (map: #1, blocks #16). Sources checked **2026-10-18**. Earlier context: [Jev/Laya findings](https://github.com/ZeleMate/DeepSeek-demo-implementation/blob/research/jev-laya/research/jev-laya.md) (issue #5).

Items marked **(unverified)** were not confirmed against a primary source, or I could not test them without spending money on an API key.

## TL;DR

- **It needs a direct OpenAI key.** OpenRouter lists `openai/gpt-6-luna` only as a chat/Responses model. OpenRouter's own `POST /api/alpha/decisions` is a different, **Jev-shaped** protocol, and its docs only show TypeSafe Jev models behind it. Plan for a separate OpenAI project key and a small separate budget.
- **The TypeScript SDK has a typed `client.decisions.create()`.** It is in `openai` **7.30.0 and later** and is absent from 7.28.0. 7.29.0 was never published. The current release is 7.38.0.
- **It is not cheaper per call than a tiny open-weight model** for short inputs. Both cost about $0.00004–0.0003 per call. What you gain is **calibrated probabilities with no output parsing**, up to 200 questions on one shared input, and speed (OpenAI says "about 10x faster than the Responses API"). Jev through OpenRouter costs less than half of Luna's input price.
- **Good fits** are intent routing, tool choice, source relevance, escalation gating and memory-write gating. **Eval judging** works for rubric scores, but it gives no written rationale.
- **dsh shape:** a Cordis `Service` (e.g. `ctx.decisions`) with a neutral `decide()` interface and pluggable backends (OpenAI Luna, OpenRouter Jev, local Laya). It is not an `llm` adapter.

## What it is (primary: OpenAI guide)

Source: [guides/decisions](https://developers.openai.com/api/docs/guides/decisions) ([.md](https://developers.openai.com/api/docs/guides/decisions.md)).

- Endpoint: `POST /v1/decisions`. The model is `gpt-6-luna`, the only one supported.
- The request has three parts:
  - `model`
  - `input`: a string, or user messages with `input_text` / `input_image` parts
  - `questions`: each has a unique `name`, a `type` and `instructions`
- Question types:
  - `predicate` returns `probability` (0–1).
  - `choice` takes `choices: [{value, description}]` and returns `choice`, a `probabilities` array and `confidence`.
  - `score` takes ordered `levels: [{label, description}]` and returns `score`: the probability-weighted mean of the 0-based level indices. It also returns `probabilities` and `confidence`.
- Any answer can be `type: "refusal"` instead. Other questions in the same request still get answers.
- The response has an `answers` array in question order, plus `model` and `usage` (from the SDK types).
- Independent questions can share a request. Dependent decisions need separate requests.
- The guide tells you to set thresholds from your own labelled examples, based on what false positives and false negatives cost you.
- Pricing: **$0.10 per 1M input tokens**, with "no cache-read, cache-write, or output-token charges". Regional processing premiums and long-context multipliers apply. The model page says prompts over 272K input tokens cost 2x input, and regional processing adds +10% ([models/gpt-6-luna](https://developers.openai.com/api/docs/models/gpt-6-luna.md)).
- Data controls: it is not used for training, and abuse monitoring retains data for 30 days. It is ZDR- and HIPAA-eligible for eligible customers, and Private Retention is "Pending confirmation". Regional processing covers the US and EU ([data controls](https://developers.openai.com/api/docs/guides/your-data)).

### Minimal TypeScript example (verbatim from the guide's "Select from fixed options")

```ts
import OpenAI from "openai";

const client = new OpenAI();
const decision = await client.decisions.create({
  model: "gpt-6-luna",
  input: "I was charged twice for my order.",
  questions: [
    {
      type: "choice",
      name: "department",
      instructions: "Which department should handle this complaint?",
      choices: [
        { value: "billing", description: "Payments, invoices, and refunds." },
        { value: "technical", description: "Problems using the product." },
        { value: "shipping", description: "Delivery and tracking." },
        { value: "other", description: "Requests outside these categories." },
      ],
    },
  ],
});

const answer = decision.answers[0];
if (answer.type === "refusal") {
  console.log(`Refused: ${answer.name}`);
} else if (answer.type === "choice") {
  console.log(
    `Department: ${answer.choice} (confidence: ${answer.confidence})`
  );
}
```

The guide shows this example response: `{"type":"choice","name":"department","choice":"billing","probabilities":[{"value":"billing","probability":0.95},…],"confidence":0.93}`.

## 1. OpenRouter vs a direct OpenAI key

- **Direct OpenAI key: required for Luna Decisions.**
- OpenRouter's models API (`/api/v1/models`, fetched 2026-10-18) lists `openai/gpt-6-luna` at $0.10/M input and $0.50/M output. Its `supported_parameters` are chat parameters (`tools`, `response_format`, `reasoning`, …). Nothing there shows the `/v1/decisions` endpoint.
- OpenRouter does have **`POST /api/alpha/decisions`** ("Alpha feature endpoints for Decisions requests", [API ref](https://openrouter.ai/docs/api/api-reference/alphadecisions/submit-a-decisions-request.md), [TS SDK `openRouter.alpha.decisions.create`](https://openrouter.ai/docs/client-sdks/typescript/sdks/decisions/README.md)). It uses **Jev's wire shape**, not OpenAI's:
  - `state` instead of `input`
  - `questions` as a map keyed by name
  - question types `noul` / `choice` / `score` / `box`, described with `criteria`
  - its only example model is `typesafe/jev-1.13`
- OpenRouter also proxies Jev's `/v1/systemone` for the TypeSafe SDK ([guide](https://openrouter.ai/docs/guides/community/typesafe-sdk.md)).
- **(unverified)** Whether OpenRouter's alpha decisions router accepts `openai/gpt-6-luna`. No doc says so, and I did not call it (that needs a key and spends credit). To check: `curl -X POST https://openrouter.ai/api/alpha/decisions -H "Authorization: Bearer $OPENROUTER_API_KEY" -H 'Content-Type: application/json' -d '{"model":"openai/gpt-6-luna","state":"hi","questions":{"q":{"type":"noul","instructions":"Is this a greeting?"}}}'`.
- **Budget:** keep a separate OpenAI project with a low monthly limit. At the per-call costs below, a few thousand calls a month comes to cents.
- The voice guide mentions an `api.decisions.write` permission ([decisions-voice](https://developers.openai.com/api/docs/guides/decisions-voice.md)). If you use a restricted key, it presumably needs that scope **(unverified for plain REST)**.

## 2. TypeScript SDK support

- **Yes, it is typed.** The guide says the examples need `openai` JS **7.30.0 or later**.
- I checked the npm tarballs:
  - `resources/decisions.*` exists in 7.30.0 and 7.38.0 (latest, published 2026-10-17).
  - It is absent in 7.28.0. The registry has no 7.29.0.
  - 7.30.0 was published 2026-10-06.
- 7.38.0 `resources/decisions.d.ts`:
  - `client.decisions.create(body: DecisionCreateParams, options?) → APIPromise<Decision>`
  - Answers are a discriminated union on `type`: `predicate | choice | score | refusal`. Narrowing with `answer.type === "choice"` therefore works.
  - Choice values are `string | boolean`.
  - `usage` has `input_tokens`, `input_tokens_details.{cached_tokens, cache_write_tokens}`, `output_tokens` and `output_tokens_details.reasoning_tokens`.
- Limits from the SDK doc comments (not stated in the guide):
  - 1–200 questions per request
  - 2–255 unique choices per `choice` question
  - at most 128 images per request
  - `prompt_cache_key`, `prompt_cache_options` (`mode: implicit|explicit`, `ttl: "30m"`), per-part `prompt_cache_breakpoint`, `safety_identifier`
- The CHANGELOG shows steady churn, including "add standalone Decisions support", "add Decisions prompt caching options" and "support Decisions in Live sessions". Pin the version.
- dsh has no OpenAI package. I grepped the deepseek-harness tree for `openai|decision|jev` and found nothing, so the plugin brings the `openai` dependency itself.

## 3. Rate limits and beta caveats

- **Rate limits (partly unverified).**
  - The guide names no Decisions-specific limits.
  - The `gpt-6-luna` model page lists default tiers: Build 5,000 RPM / 2M TPM, Launch 10,000 RPM / 10M TPM, Grow 30,000 RPM / 180M TPM.
  - That page's endpoint table does **not** list `/v1/decisions`. **(unverified)** Whether Decisions shares these limits; check the response's `x-ratelimit-*` headers on the first call.
  - Either way, these limits are far above what a personal CLI needs.
- **Beta caveats:**
  - It is "in public beta, and we expect to GA in the coming weeks". There is one model, and request and answer fields are still being "clarified" in SDK releases.
  - **Refusals happen per question.** Every consumer needs a refusal branch.
  - **No stand-alone reference page found.** The API reference index (`/api/reference/llms.txt`) has no Decisions entry (as of 2026-10-18), so the guide and SDK types are the spec.
  - **The docs disagree on images.** The guide says images must be inline base64, and that hosted HTTP(S) URLs and `file_id` are not supported. The 7.38.0 SDK types say "base64 data URLs or publicly accessible HTTP(S) URLs". Trust the guide until tested. This hardly matters for a text-only research assistant.
  - **Billing of output and reasoning tokens.** `usage` reports `output_tokens` and `reasoning_tokens`, but the guide says output tokens are not charged. **(unverified)** Whether question text counts as input tokens. It probably does, since everything you send is input. Read `usage.input_tokens` on real calls.
  - **No rationale.** You get numbers only. When a human needs a "why", use a generating model.

## 4. Comparison with Jev and Laya

| | OpenAI Decisions (Luna) | Jev (TypeSafe) | Laya |
|---|---|---|---|
| Endpoint | `POST api.openai.com/v1/decisions` | `POST api.typesafe.ai/v1/systemone`; also via OpenRouter (`/api/v1/systemone`, `/api/alpha/decisions`) | self-hosted `laya-serve` (Jev wire protocol) |
| Input field | `input` (string or user messages, text and images) | `state` (string, JSON object or array) | Jev-compatible |
| Questions | **array** with `name` | **map** keyed by name | Jev-compatible |
| Types | `predicate` / `choice` / `score` | `noul` / `choice` / `score` / `box` | `choice` / `score` / `noul` |
| Options | `choices[{value,description}]`, `levels[{label,description}]` | `criteria` map (choice, noul) or array (score) | Jev-compatible |
| Answers | array in order; `refusal` type | map keyed by name; score answers carry a `legend` | Jev-compatible |
| Price | $0.10/M input, no output charge | $0.042/M input (TypeSafe's "$42 per Btok"; OpenRouter's example: 476 tokens = $0.000019992) | free apart from your own compute |
| Key | OpenAI | TypeSafe, or **your existing OpenRouter key** | none |

- **Protocol: not wire-compatible.** OpenAI's shape differs from Jev's in every field name and in array vs map, so a Jev client or Laya server cannot point at OpenAI.
- The **concepts map one to one**:
  - `predicate` ↔ `noul`
  - `choices` ↔ `criteria` map
  - `levels` ↔ `criteria` array
- One adapter can therefore put a neutral interface in front of all three. Jev's `box` has no OpenAI equivalent.
- **Quality: (unverified).** I found no head-to-head benchmark of Luna Decisions against Jev or Laya. Laya's own numbers only cover Jev (see the [jev-laya notes](https://github.com/ZeleMate/DeepSeek-demo-implementation/blob/research/jev-laya/research/jev-laya.md)). Confidence is defined differently across all three, so thresholds do not carry over. Calibrate each one on your own labelled set.
- **Cost:** Jev through OpenRouter costs about 0.42x Luna per input token and uses the budget you already have. Luna's pull is learning OpenAI's API, image input, and maybe quality.

## 5. Which harness jobs fit, with rough cost per call

Assumptions:

- Prices from OpenRouter `/api/v1/models` and the OpenAI docs, 2026-10-18.
- Input tokens are the job's own evidence plus question text.
- For the open-weight LLM doing the same job, I add **+200 input tokens** (system prompt and output-format instructions) and **30 output tokens** (a short JSON verdict with reasoning off). Reasoning models such as `gpt-oss-20b` would emit many more output tokens. Thinking output would erase their price advantage.
- The comparison models (USD per 1M tokens, input/output) are `mistralai/mistral-nemo` $0.029/$0.030, `meta-llama/llama-3.1-8b-instruct` $0.05/$0.08 and `qwen/qwen3.5-9b` $0.10/$0.15.

| Job | Type | Input tok | Luna Decisions | Jev via OR | Mistral Nemo | Llama 3.1 8B | Qwen3.5 9B |
|---|---|---:|---:|---:|---:|---:|---:|
| Intent routing (~6 intents) | choice | 400 | $0.000040 | $0.000017 | $0.000018 | $0.000032 | $0.000064 |
| Tool choice (~10 tools) | choice | 900 | $0.000090 | $0.000038 | $0.000033 | $0.000057 | $0.000115 |
| Source relevance (per source) | predicate | 1,500 | $0.000150 | $0.000063 | $0.000050 | $0.000087 | $0.000175 |
| Escalate to the large model? | predicate / score | 2,000 | $0.000200 | $0.000084 | $0.000065 | $0.000112 | $0.000225 |
| Memory-write gating | predicate | 500 | $0.000050 | $0.000021 | $0.000021 | $0.000037 | $0.000074 |
| Eval judging (rubric) | score | 3,000 | $0.000300 | $0.000126 | $0.000094 | $0.000162 | $0.000324 |

How to read this:

- **Every option costs fractions of a cent per call.** 1,000 Luna source-relevance calls cost about $0.15. On a $10–20 budget, what moves the bill is the large model, not these gates.
- Luna is **not the cheapest**. For short inputs it sits between Llama 3.1 8B and Qwen3.5 9B.
- **Where Luna saves money:**
  1. Many questions on one input. Up to 200 questions share the input tokens, for example relevance, recency, primary-source and contradiction on the same source.
  2. Avoided retries from malformed JSON.
  3. Calibrated thresholds, which mean fewer needless escalations to the expensive model.
- I have not measured any of these savings.
- **Fit by job:**
  - **Intent routing / tool choice:** strong fit for `choice`. Include an `"other"` fallback, as the guide advises. The 255-choice cap is ample.
  - **Source relevance:** strong fit for `predicate`. Batch several criteria per source.
  - **Escalation gate:** good fit. Use `predicate` probability or `score` confidence against a threshold tuned on a labelled set.
  - **Memory-write gating:** good fit for `predicate` ("Is this a durable user preference or fact worth storing?").
  - **Eval judging:** partial fit. A `score` rubric is cheap and fast for regression evals, but there is no rationale. Keep an LLM judge for qualitative review.
  - **Not a fit:** extracting fields, writing answers, choosing tool *arguments*, and anything that needs explanation. Use the main LLM, Structured Outputs or function calling, as the guide itself says.

## 6. Shape of a dsh plugin (a service, not an LLM adapter)

The Cordis pattern comes from dsh's [services tutorial](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/cordis-tutorial/03-services.md). A `Service` subclass registers under a name with `super(ctx, name)`, and `declare module '@deepseek-ai/cordis'` adds it to `Context` for typing. Consumers either list it in `inject` or probe with `ctx.get(name)` when it is optional. The tutorial advises prefixing your own service names, since the harness claims plain names like `llm` and `tools`. Config uses `@deepseek-ai/schemastery`, as `dsh-time-context` does.

Sketch (my design, not from dsh docs):

```ts
import { Service, type Context } from '@deepseek-ai/cordis'
import z from '@deepseek-ai/schemastery'
import OpenAI from 'openai' // >= 7.30.0, pin it

// Neutral types, so Jev/Laya backends can sit behind the same interface.
export type Question =
  | { type: 'predicate'; name: string; instructions: string }
  | { type: 'choice'; name: string; instructions: string; choices: { value: string; description?: string }[] }
  | { type: 'score'; name: string; instructions: string; levels: { label: string; description?: string }[] }
export type Answer =
  | { type: 'predicate'; name: string; probability: number }
  | { type: 'choice'; name: string; choice: string; confidence: number; probabilities: Record<string, number> }
  | { type: 'score'; name: string; score: number; confidence: number }
  | { type: 'refusal'; name: string }
export interface DecideResult { answers: Record<string, Answer>; inputTokens: number; costUsd: number }

declare module '@deepseek-ai/cordis' {
  interface Context { decisions: DecisionsService }
}

export interface Config { backend: 'openai' | 'openrouter-jev'; model: string; apiKeyEnv: string; timeoutMs: number; monthlyBudgetUsd: number }
export const Config: z<Config> = z.object({ /* backend, model ('gpt-6-luna'), apiKeyEnv ('OPENAI_API_KEY'), timeoutMs, monthlyBudgetUsd */ })

export class DecisionsService extends Service {
  constructor(ctx: Context, private config: Config) { super(ctx, 'decisions') }
  async decide(input: string, questions: Question[]): Promise<DecideResult> {
    // openai backend: client.decisions.create({ model, input, questions }) and map answers[] to a map by name
    // openrouter-jev backend: POST /api/alpha/decisions with state + questions map (predicate -> noul, ...)
    // record usage.input_tokens * price, enforce the budget, throw a typed error on timeout so callers fall back
  }
}

export const name = 'research-decisions'
export function apply(ctx: Context, config: Config) { ctx.plugin(DecisionsService, config) }
```

Design notes:

- **Consumers own thresholds and fallbacks.** Examples: the router plugin, the source-ranker tool, the memory plugin and the eval runner.
  - Use `ctx.get('decisions')` when the gate is optional, and fall back to a small OpenRouter LLM or "always escalate" when it is missing.
  - Use `inject: ['decisions']` only where the plugin cannot work without it.
- **Log every decision** (question, probabilities, chosen action) so you can build the labelled set for calibrating thresholds. The guide recommends exactly this.
- dsh-agent exports a `PreStepDecision` type that `dsh-time-context` imports. That is a possible hook for an escalation gate before each step **(unverified: I did not read its semantics)**.
- Keep it out of `ctx.llm`. Its input and output have nothing in common with chat messages, and making it an adapter would leak decision semantics into the model layer.

## Sources

- OpenAI Decisions guide: <https://developers.openai.com/api/docs/guides/decisions> (.md variant read in full)
- OpenAI GPT-6 Luna model page (pricing, rate limits): <https://developers.openai.com/api/docs/models/gpt-6-luna.md>
- OpenAI data controls (from `/api/llms-full.txt`, sections on `/v1/decisions`): <https://developers.openai.com/api/docs/guides/your-data>
- OpenAI reference index (no Decisions entry found): <https://developers.openai.com/api/reference/llms.txt>
- `openai` npm package, tarballs 7.28.0 / 7.30.0 / 7.38.0, `resources/decisions.d.ts` and `CHANGELOG.md`: <https://registry.npmjs.org/openai>
- OpenRouter models API: <https://openrouter.ai/api/v1/models>
- OpenRouter alpha Decisions API reference: <https://openrouter.ai/docs/api/api-reference/alphadecisions/submit-a-decisions-request.md>
- OpenRouter TypeSafe SDK guide: <https://openrouter.ai/docs/guides/community/typesafe-sdk.md>
- dsh Cordis services tutorial: <https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/cordis-tutorial/03-services.md>
- dsh `packages/context/time-context/src/index.ts` (config pattern)
- Jev/Laya notes: `research/jev-laya.md` on branch `research/jev-laya`
