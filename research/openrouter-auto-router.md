# OpenRouter Auto Router: how it works, and can dsh use it with an Opus-first, cost-aware pool?

Research for [#30](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/30) (map: #1). **All sources were checked on 2026-10-19.**
This file builds on `research/openrouter-models.md` (branch `research/openrouter-models`) and `research/model-leaderboards.md` (branch `research/model-leaderboards`).

> **Scope (issue body as corrected by the user, 2026-10-19).** Frontier models, American ones included, are welcome. The baseline main model is **Claude Opus 5.5**, which the user set as the OpenRouter account default. Cheaper alternatives should be used whenever they are good enough. The budget is an OpenRouter key limit of **$15 a month**.

Pinned sources:

- **dsh**: `deepseek-ai/deepseek-harness` tag `dsh-v0.2.1-rc.2`, which is commit `687f282` (2026-10-17).
- **pi-ai**: `@earendil-works/pi-ai@1.1.0`, the version in dsh's lockfile. It was read from the npm tarball.
- **OpenRouter**: the docs pages linked inline, the public `GET /api/v1/models` endpoint (469 models), and `GET /api/v1/models/{id}/endpoints`.
- **Artificial Analysis (AA)**: model pages `artificialanalysis.ai/models/<slug>`, Intelligence Index v4.3.2. All numbers come from the page data and are AA's own runs (independent).

Legend: ✅ verified in a primary source · ⚠️ inferred or partly documented · ❌ not verified (needs a live test with a key; no key was used for this research)

---

## TL;DR

1. **Opus 5.5 costs $4 per million input tokens and $20 per million output** on OpenRouter (cache read $0.20, 5-minute cache write $5). AA measures **$5.98 per average Intelligence-Index task** and **$13.11 per Terminal-Bench 4.0 task** at Max effort. **A $15 month cannot afford Opus as the always-on main loop.** Realistic agent use comes to roughly 100–400 Opus turns a month (section 5). Opus has to be the **escalation tier**, not the default.
2. **The account default model does not affect dsh.** OpenRouter uses it only "if the `model` parameter is omitted" ✅. pi-ai always sends `model` (`openai-completions.js:573`) ✅. To use Opus in dsh, select `anthropic/claude-opus-5.5` there; it is in pi-ai's catalog.
3. **`openrouter/auto` doesn't do "Opus when needed, cheap otherwise".**
   - It ranks models by **market spend share for the prompt's task type**, then keeps one **cost band** (`cost_tier`).
   - "A tier is a band, not a ceiling", so a band that admits Opus excludes the cheap models, and the default `low` band excludes Opus. ✅
   - What it does well: biasing toward cheap models. Use `cost_tier: low` (the default) plus an allow list of cheap strong models.
4. **`nvidia/switchyard` is the router that matches the goal.** You give it up to 3 models. The cheapest becomes the "efficient" tier and the priciest the "capable" tier. A judge, or tool-result signals (`stage`, the default), decides per turn whether the efficient model will do, and otherwise uses the capable one.
   - dsh can't send its `models` array, but a **preset can store "an array of models"** ✅ and the default algorithm needs no plugin.
   - So `@preset/<slug>` with `model: nvidia/switchyard` and `models: [cheap, anthropic/claude-opus-5.5]` should work from dsh (❌ untested).
5. **Restricting or biasing the Auto Router from dsh** works through **account defaults** on the workspace Routing page (allowed models, excluded models, cost preference, plus "prevent overrides") ✅, because dsh can't send `plugins`. Presets probably can carry the plugin too (⚠️).
6. **dsh traps** when using a router slug:
   - The catalog caps `openrouter/auto` at **4,096 output tokens**, so override `maxTokens`.
   - pi-ai adds Anthropic `cache_control` only when the model id starts with `anthropic/`. Through a router slug, **Opus turns would run uncached** unless you set `compat.cacheControlFormat: anthropic`. dsh offers that switch ✅.
   - The picked model is stored as `responseModel` in dsh's replay envelope ✅. Exact per-turn cost comes from `GET /api/v1/generation?id=…` ✅.
7. **Recommended setup:**
   - **(a)** Default dsh model **`anthropic/claude-haiku-5.5`** (AA 43.4 at $0.10/$0.50) or **`deepseek/deepseek-v4.1-flash-1017`** (AA 45.1 at $0.15/$0.60) for everyday turns.
   - **(b)** A **Switchyard preset** pairing that efficient model with Opus 5.5 for automatic escalation, with **GPT-6.1 Sol** (AA 51.8, $0.72 per AA task) as the middle fallback.
   - **(c)** Manual switch to Opus 5.5 for known-hard work.
   - **(d)** Keep `openrouter/auto` as an optional "cheap-band" router with an allow-listed pool.

---

## 1. How `openrouter/auto` works

Source: [Auto Router](https://openrouter.ai/docs/guides/routing/routers/auto-router.md), plus the `AutoRouterPlugin` schema in the [chat-completions/preset API reference](https://openrouter.ai/docs/api/api-reference/presets/create-a-preset-from-a-chat-completions-request-body.md).

| Step | What happens | ✅/⚠️ |
|---|---|---|
| 1. Classify | A lightweight classifier tags the prompt with one of about 30 task types, for example `code:debugging`, `agent:multi_step_planning` or `qa_knowledge`. Prompts are classified in flight without being retained. | ✅ |
| 2. Rank | Models are ranked by **share of spend** for that task type across the OpenRouter community over a trailing 7-day window ([task-spend rankings](https://openrouter.ai/rankings#task-spend)). The ranking reflects popularity, **not task difficulty**. | ✅ |
| 3. Cost band | `cost_tier` picks cost-percentile bands: `low` [0,20), `medium` [20,40), `high` [40,60), `xhigh` [60,80), `max` [80,100]. "A tier is a band, not a ceiling": models cheaper than the band are excluded too. With no setting, routing behaves like roughly `low`. The deprecated `cost_quality_tradeoff` (0-10) is still accepted. | ✅ |
| 4. Filter and route | The router applies account model and provider restrictions, guardrails, ZDR, `allowed_models`/`excluded_models` and modality needs. The top survivors, in spend order, become the primary pick plus fallbacks. If routing infrastructure fails, it uses a default model set. | ✅ |

### Plugin fields (`id: auto-router`)

- **`allowed_models`**: wildcard patterns, up to 1,024.
- **`excluded_models`**: the same syntax, applied **after** the allow list.
- **`cost_tier`**.
- **`pin_model`**: reuses the last assistant message's model.
- **`enabled`**.

If nothing survives the restrictions, the request fails with **404**. ✅

### Behaviour

- **No vendor named.** The current docs name no third-party router vendor. Only OpenRouter's classifier and market data are described. ✅
- **Tool calling and streaming.** "Streaming is supported"; "all standard OpenRouter features (tool calling, etc.) work with the selected model"; the router weighs tool support when ranking. ✅
- **Extra cost.** "You pay the standard rate for whichever model is selected. There is no additional fee." ✅
- **Session stickiness.** The router prefers the model a conversation already landed on while it stays a top candidate. It identifies the conversation from `session_id`, the `x-session-id` header, or a message fingerprint. ✅
- **Which model was picked.**
  - The response `model` field names the chosen model. ✅
  - `X-OpenRouter-Metadata: enabled` adds `openrouter_metadata` (`strategy: auto`, candidate endpoints, attempts, `pipeline[].data.task_type`) on the **final stream chunk** ([router metadata](https://openrouter.ai/docs/guides/features/router-metadata.md)). ✅
  - `GET /api/v1/generation?id=<gen-id>` returns `model`, `provider_name`, `router` and `total_cost` ([API reference](https://openrouter.ai/docs/api/api-reference/generations/get-request-&-usage-metadata-for-a-generation.md)). ✅
- **Related slugs:**
  - `openrouter/auto-beta` is the early-access track; account defaults apply to both.
  - `typesafe/jev-router`'s `allowed_models` is only a *preference with fallback*, not a hard list.

---

## 2. The account default model (Opus 5.5) vs requests that name a model, and dsh

| Question | Answer | Evidence |
|---|---|---|
| When does the default apply? | **Only when a request omits `model`.** "If the `model` parameter is omitted, the user or payer's default is used." | [API overview](https://openrouter.ai/docs/api_reference/overview) ✅ |
| Where is it stored? | It is a workspace setting, `default_text_model`, in the Workspaces API (alongside `default_provider_sort`). | Workspaces API docs ✅ |
| Does dsh ever omit `model`? | **No.** pi-ai's Chat Completions builder always sets `model: model.id` (`dist/api/openai-completions.js:573`), and dsh resolves a concrete model id per route before dispatch. **The account default never affects dsh traffic.** | pi-ai source ✅ |
| Does it influence `openrouter/auto`, presets or Switchyard? | Not documented. The Auto Router's own fallback is "a default model set", not the user's default model. Treat the default model as unrelated to routers. | ❌ |
| How to make Opus the dsh baseline anyway | Pick `anthropic/claude-opus-5.5` in dsh. It is in pi-ai's catalog on the **`anthropic-messages`** protocol (OpenRouter's Anthropic-compatible endpoint), with `maxTokens` 128,000 and catalog cost $4/$20/cache $0.20/$5. pi-ai's Anthropic path adds `cache_control` itself (`anthropic-messages.js:31, 859`). | pi-ai catalog and source ✅ |

The account default is useful for the OpenRouter chatroom and for clients that send no model. **For dsh it is a no-op.**

---

## 3. Restricting and biasing the pool when dsh can only set the model id

### What dsh can and can't send

- pi-ai never emits `plugins` or `models`, and dsh refuses `compat.openRouterRouting` (the per-request `provider` object): `catalog.ts`, `openRouterRouting: 'withhold'`. ✅
- dsh **can** set the model id, extra request `headers` and several `compat` switches, including `cacheControlFormat`, which is marked `'offer'` in `catalog.ts`. ✅

### Options

| Mechanism | What it can hold | Works with dsh? | Notes |
|---|---|---|---|
| **Account defaults**, workspace [Routing page](https://openrouter.ai/settings/routing), Auto Router section | Allowed models, excluded models and a cost preference. These apply to every Auto Router request unless the request sets the same field. **"Prevent overrides" makes them final.** They cover `auto` and `auto-beta`. | **Yes**, with no change: dsh sends no plugin. ✅ (docs) / ❌ (no live test) | The simplest way to restrict or bias `openrouter/auto`. |
| **Preset** (`@preset/<slug>`, or `<model>@preset/<slug>`) ([Presets](https://openrouter.ai/docs/guides/features/presets.md)) | Documented contents: **model selection, "specific model or array of models with fallbacks"**, provider routing (sort, only/ignore, quantisation, `max_price`), system prompt, generation parameters and tools. **Plugins**: the preset `config` is free-form, and the docs mention a `web` plugin arriving "from a preset", but `auto-router` inside a preset is undocumented. ⚠️ | **Yes, as a model id** on a route with `api: openai-completions` (the id is outside pi-ai's catalog). | The only way to get `provider.max_price`, `quantizations`, a `models` array (Switchyard) or `pin_model` from dsh. Request fields override preset fields, but dsh sends none of these. |
| **Guardrail** on the dsh key ([guardrails](https://openrouter.ai/docs/guides/features/guardrails.md)) | A hard model or provider allowlist plus a budget. | Yes (key-level) | ❌ It is not documented whether router slugs such as `openrouter/auto` or `nvidia/switchyard` must themselves be allow-listed. |
| **Account privacy settings** | Allowed or ignored providers, account-wide. | Yes | Use them to keep low-precision (fp4) hosts away from open-weight models. |

### Biasing `openrouter/auto` toward cheaper models

1. **Leave `cost_tier` at its default (≈ `low`) or set it to `low`.** Low favours "the cheapest capable models". ✅
2. **Allow-list cheap strong models only.** Within the band, the order is still spend share. ✅
3. **Cap price.** `provider.max_price` "still applies" to whichever model the router resolves ✅. It is per-request, so from dsh it needs a preset ⚠️.
4. **Don't put Opus in the Auto Router allow list and expect escalation.** Opus (about $4/$20) almost certainly falls in a top band (`xhigh`/`max`). ⚠️ The band edges are percentiles of the market's average cost per generation per task, and the exact placement wasn't observable. With `low`, Opus is never eligible. With `max`, the cheap models are excluded. ✅ (band semantics)

### Getting "cheap unless hard, then Opus": Switchyard

Source: [Switchyard Router](https://openrouter.ai/docs/guides/routing/routers/switchyard-router.md).

**How it picks:**

- `nvidia/switchyard` takes 1-3 concrete models in `models`. On every request it labels the **cheapest** candidate *efficient* and the **priciest** *capable*; a middle candidate is only a fallback. ✅
- **`stage`** (the default; no plugin needed) scores the tool results already in the conversation. Errors, repeated failures and long exploration point to capable; landed edits and passing tests point to efficient. When the signals aren't decisive, including the first turn, it asks a judge. ✅
- **`composite`** keeps the tier for a whole agent task unless tool results argue otherwise. **`capability`** asks the judge once per human turn. **`auto`** never calls the judge. ✅
- The judge is `google/gemini-3.5-flash-lite` by default. It is billed as separate small generations ("a fraction of a cent"), has a 2.5-second budget, and **fails open to the capable tier**. ✅

**Cost and visibility:**

- There is no routing fee; you pay the model that answered, plus judge calls. ✅
- Metadata shows `resolved_to`, `strategy` and `judge_ms`. ✅

**Using it from dsh:**

- Use a preset with `model: "nvidia/switchyard"` and `models: [efficient, …, "anthropic/claude-opus-5.5"]`. The `models` array in presets is documented; with the default `stage` algorithm, no plugin is required. ⚠️/❌ (untested end to end)
- The `nvidia/switchyard` row in `/api/v1/models` lists **no `supported_parameters`**. The docs say both candidates must support the features you use, such as tools. ❌ Tool calling through Switchyard was not verified live.

---

## 4. dsh-specific behaviour with router slugs

| Topic | Finding | Evidence |
|---|---|---|
| `openrouter/auto` accepted on the catalog route? | **Yes.** It is in pi-ai's catalog (`openai-completions`, `reasoning: true`, `contextWindow` 2M, `sendSessionAffinityHeaders: true`). No `api` override is needed. | `dist/providers/data/openrouter.json` ✅ |
| `@preset/…` or `nvidia/switchyard`? | Not in the catalog. They need a route with `api: openai-completions`. **Don't put that on the built-in `openrouter` route**: a route-level `api` overrides every model on the route and would push Claude off its catalog `anthropic-messages` protocol. Use a **second, hand-declared route** (for example `openrouter-routers`) with `api` and `baseURL: https://openrouter.ai/api/v1`. | llm-pi-ai README "Configure provider routes"; `config.ts` profile schema ✅ |
| **Output cap trap** | The catalog gives `openrouter/auto` **`maxTokens: 4096`**. `streamSimple` → `buildBaseOptions` sends `options.maxTokens ?? model.maxTokens` (`simple-options.js:23`), and dsh passes `maxTokens` only when configured (`adapter.ts:329-331, 419`). Unconfigured, every routed turn is capped at 4,096 output tokens, reasoning included. **Set `maxTokens`.** On a hand-declared route the fallback is `defaultMaxTokens` (32,768). | ✅ |
| **Prompt caching trap** | pi-ai's Chat Completions path adds Anthropic `cache_control` breakpoints only when `model.id` starts with `anthropic/` (`openai-completions.js:1261`). Through `openrouter/auto`, `@preset/…` or `nvidia/switchyard`, an Opus turn would carry **no cache breakpoints**, and OpenRouter says Anthropic "require[s] you to enable it". That means paying $4 per million on the whole context every turn. **Fix:** set `compat: { cacheControlFormat: anthropic }` on the router model entry; dsh marks it `'offer'`. OpenRouter maps Anthropic-style `cache_control` to `prompt_cache_breakpoint` for OpenAI models ([prompt caching](https://openrouter.ai/docs/guides/best-practices/prompt-caching.md)); other providers cache automatically. | pi-ai source ✅; dsh gate ✅; effect on non-Anthropic picks ⚠️ |
| Session stickiness | dsh stamps `GenerateOptions.sessionId` (`packages/llm/llm/src/types.ts:560-564`). pi-ai sends it as **`x-session-id`** to OpenRouter (`openai-completions.js:542-544`), which is the header both routers and provider-sticky caching use. On a hand-declared route, OpenRouter is detected from the base URL (`isOpenRouter`, `openai-completions.js:1230, 1297`). | ✅ code; ❌ wire |
| Streaming and tools | pi-ai always streams on Chat Completions and sends `tools`/`tool_choice`. The routers pass these through. | earlier research ✅; Auto Router docs ✅ |
| Which model answered | pi-ai records `responseModel` when the chunk's `model` differs from the requested id (`openai-completions.js:360-361`). dsh persists `responseModel` and `responseId` in its replay envelope (`llm-pi-ai/src/replay.ts:30-31, 84-85`). dsh's `TokenUsage` has no model field (`stream.ts:24-31`), and dsh never reads `openrouter_metadata`, because there is no `onProviderStreamEvent` hook. **For eval logs, join `responseId` with `GET /api/v1/generation`.** | ✅ |
| Cost meter | Router catalog cost is a sentinel (`-1000000`), but dsh maps token counts only, so nothing breaks. Use OpenRouter (`GET /api/v1/key`, the generation API) for dollars. | ✅ |
| Model switching mid-conversation | ⚠️ **Risk, untested.** dsh replay keys signatures on the *requested* id (the router slug), so reasoning blocks from model A may be replayed to model B. Switchyard's `composite`, and Auto Router's `pin_model` (preset-only), reduce switches. | `replay.ts:27-29` ✅; behaviour ❌ |

---

## 5. Opus 5.5 price and a realistic month against $15

### Price (`/api/v1/models/anthropic/claude-opus-5.5/endpoints`, 2026-10-19)

- **Base price on 5 providers** (Anthropic, Amazon Bedrock, Azure, Google, Claude Platform on AWS): **$4.00 input / $20.00 output per million tokens**, cache read $0.20, 5-minute cache write $5.00, 1-hour cache write $8.00. ✅
- **Other endpoints:** regional endpoints at $4.40/$22.00, and one Anthropic endpoint at **$8/$40**, probably a priority or fast tier (⚠️). OpenRouter's price-weighted balancing should prefer the $4 endpoints.
- **Batch variant:** `anthropic/claude-opus-5.5:batch` costs $2/$10 but is asynchronous, so it isn't usable for an interactive loop.

### What AA measured (Max effort, its own harness)

| | Opus 5.5 |
|---|---|
| AA Intelligence Index | **57.6**, the top model AA lists |
| Terminal-Bench 4.0 | 59.6% |
| AutomationBench | 69.5% |
| ITBench-SRE | 38.2% |
| Speed | 94.7 t/s |
| **Cost per average index task** | **$5.98** |
| **Cost per Terminal-Bench 4.0 task** | **$13.11** |

Source: [AA Opus 5.5](https://artificialanalysis.ai/models/claude-opus-5-5).

### Monthly arithmetic

This is illustrative arithmetic, not a measurement. It assumes one agent turn has 30k tokens of context and 1.5k output tokens, at $4/$20.

| Scenario | Per turn | Turns for $15 |
|---|---|---|
| Uncached (for example through a router slug without the `cacheControlFormat` fix) | 30k × $4/M + 1.5k × $20/M = **$0.15** | **≈ 100** |
| Cached, about 90% of the prefix read from cache plus 3k fresh written | 27k × $0.20/M + 3k × $5/M + 1.5k × $20/M = **$0.05** | **≈ 300** |
| AA's hard agentic task (Terminal-Bench) | $13.11 per task | **≈ 1** |

The earlier research's 20M-input + 2M-output month on Opus:

- uncached: 20 × 4 + 2 × 20 = **$120**
- fully cached prefix: about 2 × 4 + 18 × 0.2 + 2 × 20 ≈ **$52**

**Conclusion:** Opus-as-default overruns $15 in any real agent month. Keep it for escalation, and lower its reasoning effort; AA's figures are at Max.

---

## 6. Pool: Opus 5.5 on top, cheaper strong alternatives below

AA v4.3.2 figures are all measured, not estimated. "Cost/task" is AA's average cost per Intelligence-Index task at the listed effort. It captures token efficiency, which per-token prices hide. OpenRouter prices are first-party per million tokens. Hallucination rate (AA-Omniscience) is better when lower.

| Role | Model (OpenRouter id) | AA index | Terminal-Bench 4.0 | AutomationBench | Halluc. rate | $/M in/out (first-party) | AA cost/task | In pi-ai catalog |
|---|---|---|---|---|---|---|---|---|
| **Top / escalation** | `anthropic/claude-opus-5.5` | **57.6** | 59.6% | 69.5% | 58.6% | 4.00 / 20.00 | $5.98 | ✅ (anthropic-messages) |
| Near-Opus, same cost per task | `anthropic/claude-sonnet-5.5` | 56.0 | **63.6%** | 71.8% | 47.0% | 2.00 / 10.00 | $5.46 (uses 1.7× Opus's tokens) | ✅ |
| **Strong and token-efficient (mid)** | `openai/gpt-6.1-sol` | 51.8 | 56.1% | 64.9% | 54.3% | 2.00 / 10.00 | **$0.72** | ✅ (openai-completions) |
| Strong (not in pi-ai catalog; fine behind a router) | `google/gemini-4-argon` | 52.6 | 57.1% | **77.5%** | **15.1%** | 2.00 / 10.00 | $1.99 | ❌ |
| **Cheap frontier** | `anthropic/claude-haiku-5.5` | 43.4 | 32.8% | 35.4% | 40.4% | **0.10 / 0.50**; **0.50 / 2.50 above 100k prompt tokens** | $0.21 | ✅ |
| **Cheap open-weight** | `deepseek/deepseek-v4.1-flash-1017` | 45.1 | 33.8% | 66.6% | 66.8% | 0.15 / 0.60 (DeepSeek); fp8 from $0.078 / $0.235 | $0.26 | ❌ (released 10-17; needs `api`) |
| Cheap open-weight | `xiaomi/mimo-v2.6-pro` | 46.3 | 34.8% | 58.6% | 40.6% | 0.435 / 0.87 | $0.13 | ✅ |
| Cheap open-weight, low hallucination | `z-ai/glm-5.3-flash` | 41.8 | 32.8% | 60.4% | **27.6%** | 0.15 / 0.50 | $0.28 | ✅ |
| Cheapest usable | `openai/gpt-6-luna` | 38.1 | 12.6% | 53.2% | 76.7% | 0.10 / 0.50 | $0.07 | ✅ |
| Cheapest usable | `xiaomi/mimo-v2.6-flash` | 37.9 | 22.7% | 64.1% | 54.4% | 0.14 / 0.28 | $0.06 | ✅ |
| Fast mid | `google/gemini-3.8-flash` | 40.9 | 19.7% | 59.9% | 55.2% | 0.825 / 4.125 (OpenRouter listed) | $1.24 | ✅ |
| Open-weight premium | `z-ai/glm-5.3` | 44.8 | 41.9% | 62.2% | 29.6% | 1.40 / 4.40 | $2.01 | ✅ |
| Not recommended | `x-ai/grok-4.7` | 46.4 | 25.8% | 65.6% | 29.3% | 2.00 / 6.00 | $3.74 | ✅ |

Sources:

- AA pages: [Opus 5.5](https://artificialanalysis.ai/models/claude-opus-5-5), [Sonnet 5.5](https://artificialanalysis.ai/models/claude-sonnet-5-5), [GPT-6.1 Sol](https://artificialanalysis.ai/models/gpt-6-1-sol), [Gemini 4 Argon](https://artificialanalysis.ai/models/gemini-4-argon), [Haiku 5.5](https://artificialanalysis.ai/models/claude-haiku-5-5), [DeepSeek V4.1 Flash 1017](https://artificialanalysis.ai/models/deepseek-v4-1-flash-1017), [MiMo-V2.6-Pro](https://artificialanalysis.ai/models/mimo-v2-6-pro), [GLM-5.3-Flash](https://artificialanalysis.ai/models/glm-5-3-flash), [GPT-6 Luna](https://artificialanalysis.ai/models/gpt-6-luna), [MiMo-V2.6-Flash](https://artificialanalysis.ai/models/mimo-v2-6-flash), [Gemini 3.8 Flash](https://artificialanalysis.ai/models/gemini-3-8-flash), [GLM-5.3](https://artificialanalysis.ai/models/glm-5-3) and [Grok 4.7](https://artificialanalysis.ai/models/grok-4-7).
- Prices: OpenRouter `/models` and `/endpoints`.

### Reading the table

- **Best value under Opus is GPT-6.1 Sol.** It costs 8× less per AA task than Opus for about 90% of the index score and 94% of Opus's Terminal-Bench score, because it uses far fewer tokens: 38k vs 119k output per task.
- **Sonnet 5.5 is *not* cheaper than Opus per task**, despite half the token price, because it uses more tokens. It's an alternative to Opus, not a cost saver.
- **Haiku 5.5 and DeepSeek V4.1 Flash 1017** are the cheapest models in the low-40s on the index, at about $0.21–0.26 per task, roughly **25× cheaper than Opus**.
  - Haiku's price rises 5× above 100k prompt tokens, which agent loops reach.
  - DeepSeek has a high hallucination rate.
  - GLM-5.3-Flash is the most factually cautious cheap option.

### Open-weight provider precision

Covered in the earlier draft and unchanged:

- Prefer fp8/bf16 endpoints. The official checkpoints are FP8 or packed 8-bit, except Qwen3.8-Flash-Next, which is BF16.
- fp8 endpoints for `deepseek-v4.1-flash-1017`: DeepInfra, InferenceNet, Crusoe and AtlasCloud.
- fp8 endpoints for `glm-5.3-flash`: Z.AI, Near AI, AtlasCloud, BaseTen and SiliconFlow.
- `mimo-v2.6-pro` is fp8 everywhere, and GMICloud serves bf16.
- Hosts that served only fp4/mxfp4 for these models today: OpenInference, Wafer, Darkbloom and Decart. Add them to the account-wide ignored providers.
- Other open-weight options checked: Kimi K3 (43.6, $3/$15, too expensive), Step 5 Preview (43.7, $1/$2.70), Ling 3.1 Flash (41.1), Qwen3.8-Flash-Next (39.8), MiniMax-M3 (29.2) and Mistral (no strong open model; Mistral Large 4 Preview is closed). They add nothing over the table above for this budget.

**No independent tool-calling reliability data** (BFCL or Arena Agent) exists for most of these models. Arena returned 403 to automated fetches today; the last numbers are in `model-leaderboards.md`.

---

## 7. Recommended configuration

### Strategy

| Layer | Model | Used for |
|---|---|---|
| Default | `anthropic/claude-haiku-5.5` (or `deepseek/deepseek-v4.1-flash-1017`) | Everyday main-loop turns, chosen in dsh |
| Automatic escalation | `@preset/opus-escalate`: Switchyard, with Haiku as efficient, GPT-6.1 Sol as the middle fallback, and Opus 5.5 as capable | Runs where you want auto-escalation; ❌ test first |
| Manual | `anthropic/claude-opus-5.5` | Known-hard planning, reviews and incident analysis |
| Optional | `openrouter/auto` with account defaults (cheap allow list, `low`) | A market-driven cheap router for side jobs |

### OpenRouter settings

**1. Workspace Routing page → Auto Router** (only if you use `openrouter/auto`; field names are from the docs, UI labels weren't seen ❌):

- Allowed models: `anthropic/claude-haiku-5.5`, `deepseek/deepseek-v4.1-flash-1017`, `z-ai/glm-5.3-flash`, `xiaomi/mimo-v2.6-pro`, `openai/gpt-6-luna`
- Cost: default (≈ low)
- Prevent overrides: on

**2. Switchyard preset.** Create it once from a request body ([preset API](https://openrouter.ai/docs/api/api-reference/presets/create-a-preset-from-a-chat-completions-request-body.md)). This uses the key and is **for the user to run**:

```bash
curl https://openrouter.ai/api/v1/presets/opus-escalate/chat/completions \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" -H "Content-Type: application/json" \
  -d '{"model":"nvidia/switchyard",
       "models":["anthropic/claude-haiku-5.5","openai/gpt-6.1-sol","anthropic/claude-opus-5.5"],
       "plugins":[{"id":"switchyard-router","algorithm":"composite"}],
       "messages":[{"role":"user","content":"x"}]}'
```

Then confirm with `GET /api/v1/presets/opus-escalate` that `models` was stored, and whether `plugins` was (⚠️). If `plugins` was dropped, the default `stage` algorithm still applies.

How the tiers fall out by price:

- efficient: Haiku, about $0.60/M combined
- capable: Opus, $24/M
- GPT-6.1 Sol, the middle candidate: fallback only

**3. Key:** keep the $15 limit with a monthly reset.

### dsh profile patch

`$DSH_HOME/profiles/<profile>/cordis.patch.yml`. The field names are checked against `llm-pi-ai/src/config.ts` at the pinned tag. ❌ It has not been run end to end.

```yaml
- id: llm-pi-ai
  config:
    providers:
      openrouter:                          # built-in catalog route (keeps Claude on anthropic-messages + caching)
        apiKeyEnv: OPENROUTER_API_KEY
        models:                            # replaces the ~400-model catalog; entries inherit catalog fields
          - id: anthropic/claude-opus-5.5
          - id: anthropic/claude-haiku-5.5
          - id: openai/gpt-6.1-sol
          - id: z-ai/glm-5.3-flash
          - id: xiaomi/mimo-v2.6-pro
          - id: openrouter/auto            # in the catalog; fix its 4096 cap and caching
            maxTokens: 32768
            contextWindow: 1000000         # smallest window in the allowed pool (judgment)
            compat:
              cacheControlFormat: anthropic
      openrouter-routers:                  # hand-declared route for ids pi-ai's catalog lacks
        displayName: OpenRouter routers
        apiKeyEnv: OPENROUTER_API_KEY
        api: openai-completions
        baseURL: https://openrouter.ai/api/v1
        compat:
          cacheControlFormat: anthropic    # so Opus turns behind the router are cached
        models:
          - id: "@preset/opus-escalate"
            contextWindow: 1000000
            maxTokens: 32768
          - id: deepseek/deepseek-v4.1-flash-1017   # newer than pi-ai 1.1.0's catalog
            contextWindow: 1048576
            maxTokens: 32768
```

- Quote `@preset/…` in YAML, because `@` is a reserved indicator.
- ⚠️ The per-model `compat` field exists on `models` entries (`modelFields` in `config.ts`). On the catalog route, check that dsh accepts `cacheControlFormat` for `openrouter/auto`; the gate marks it `'offer'`.

### Smoke tests (the user runs them; they need the key)

1. **Opus direct:** send a dsh turn on `anthropic/claude-opus-5.5`. Check that the OpenRouter Activity page shows `cache_discount` > 0 on the second turn.
2. **Escalation:** use `@preset/opus-escalate` with `X-OpenRouter-Metadata: enabled` (curl, not dsh). An easy prompt should resolve to Haiku; a failing-test tool loop should resolve to Opus. Check `pipeline[name=switchyard-router].data.resolved_to`.
3. **Router restriction:** send `openrouter/auto` with `"plugins":[{"id":"auto-router","allowed_models":["anthropic/claude-fable-5.1"]}]`. With "prevent overrides" on, it must still land in the allowed pool.

---

## Open questions and unverified items

1. ❌ **Live behaviour of presets from dsh:** whether `models` and `plugins` are persisted, and whether tool calls and streaming work through `nvidia/switchyard`.
2. ⚠️ **Which `cost_tier` band each model falls in.** The band is computed per task type from market cost percentiles and isn't published per model.
3. ❌ **Account Routing defaults with "prevent overrides"** have not been observed restricting a plugin-less request.
4. ❌ **Reasoning replay across model switches in dsh** (section 4).
5. ❌ **Whether a guardrail model allowlist must list the router slugs.**
6. ❌ **Actual monthly spend.** Measure per-turn cost from `/api/v1/generation` joined with dsh `responseId`. The section 5 numbers are arithmetic.
7. ❌ **Independent tool-call reliability** for Haiku 5.5, GPT-6.1 Sol, MiMo and GLM-Flash. BFCL has no 2026 models and Arena was unreachable today.
8. **Historical note, ❌ not re-verified:** earlier Auto Router versions were reported to use a third-party router (Not Diamond). The current docs credit only OpenRouter's own classifier and market data.
