# Does dsh connect to OpenRouter, and which open-source models fit?

Research for issue #15 (map: #1). Checked on **2026-10-18**.

Sources pinned:

- **dsh**: `deepseek-ai/deepseek-harness` at commit `687f282` (2026-10-17).
- **pi-ai**: `@earendil-works/pi-ai@1.1.0`, the version dsh's lockfile pins. Its `dist/providers/openrouter.js`, `dist/providers/data/openrouter.json`, `dist/api/openai-completions.js`, `dist/types.d.ts` and `README.md` were read from the npm tarball.
- **OpenRouter**: the public `GET https://openrouter.ai/api/v1/models` and `GET /api/v1/models/{id}/endpoints` responses, plus the docs pages linked inline below.

## TL;DR

- **Yes, dsh connects to OpenRouter.** You don't need a custom gateway. `openrouter` is a **built-in pi-ai catalog provider**, and dsh's `llm-pi-ai` adapter exposes it as a route. The route defaults to the `https://openrouter.ai/api/v1` base URL and the `OPENROUTER_API_KEY` environment variable. It uses the `openai-completions` protocol, which supports streaming (SSE) and tool calling.
- **Gap 1: provider routing.** The OpenRouter `provider` routing object is **not configurable from dsh**. pi-ai supports it as `compat.openRouterRouting`, but dsh deliberately withholds that key and rejects it if you write it.
- **Gap 2: fallbacks.** OpenRouter's `models` fallback array is never sent, because pi-ai has no code path for it.
- **Workarounds** for both gaps: set routing account-wide in OpenRouter, use an `@preset/...` model id, or use a slug variant such as `:exacto`. All three are untested with dsh.
- **Recommended small models:** `openai/gpt-oss-20b`, `nvidia/nemotron-3.5-lightning` (it has a `:free` variant) and `mistralai/mistral-nemo`.
- **Recommended large models:** `deepseek/deepseek-v4.1-flash`, with `z-ai/glm-5.3-flash` as the alternative and fallback. All of these support tools, have 131k to 1M context, and cost well under $1.50 per million output tokens on mainstream providers.

---

## 1. dsh ↔ OpenRouter

### How it is wired

| Fact | Evidence |
|---|---|
| pi-ai ships an `openrouter` provider with id `openrouter` and base URL `https://openrouter.ai/api/v1`. Auth is an API key from `OPENROUTER_API_KEY`, or OpenRouter OAuth. Its protocols are `openai-completions` and `anthropic-messages`. | pi-ai `dist/providers/openrouter.js` |
| pi-ai's installed catalog has 385 OpenRouter chat models on `openai-completions` and 16 on `anthropic-messages` (Claude models). | pi-ai `dist/providers/data/openrouter.json` |
| dsh lists `openrouter` as a configurable built-in provider, with `defaultBaseURL: 'https://openrouter.ai/api/v1'` and `nativeAuth: { env: ['OPENROUTER_API_KEY'], oauth: true }`. | dsh `packages/llm/llm-pi-ai/src/provider-data.generated.ts:37`; `tests/dynamic-config.spec.ts:94-98` |
| The route is a normal `llm-pi-ai` provider profile under `providers.<route>`. dsh tests exercise `provider: 'openrouter'` end to end against a mock server. | `tests/dynamic-config.spec.ts:80-120` |
| dsh treats OpenRouter as a supported target: one gateway can serve many model ids, and ids like `openai/gpt-*` are first-class. | `.agents/notes/implemented/architecture/2026-07-14-provider-routed-llm-adapters.md` |
| There is a recorded OpenRouter `/models` reply in the test fixtures, which the discovery parser replays. | `packages/llm/llm-pi-ai/tests/fixtures/model-listings/openrouter-2026-09-02.json` |

### Config

The config goes in a profile patch: `$DSH_HOME/profiles/<profile>/cordis.patch.yml`, where `<profile>` is `web` for `dsh web` (from `docs/user/guide/providers.md`). You can also add the provider in the Web UI under **Settings → Models → Add model provider → Third-party → `openrouter`**.

The patch below is put together from the README, the config catalog and the tests. It has **not been run end-to-end**.

```yaml
# $DSH_HOME/profiles/<profile>/cordis.patch.yml
- id: llm-pi-ai
  config:
    providers:
      openrouter:                       # catalog route: no api/baseURL needed
        apiKeyEnv: OPENROUTER_API_KEY   # credential reference, not the secret
        models:                         # optional: narrows the catalog to these
          - id: deepseek/deepseek-v4.1-flash
          - id: z-ai/glm-5.3-flash
          - id: openai/gpt-oss-20b
          - id: nvidia/nemotron-3.5-lightning
          - id: mistralai/mistral-nemo
```

- **Plugin key.** The user guide spells the entry `- id: llm-pi-ai`. The package README spells it `- name: '@deepseek-ai/dsh-llm-pi-ai'`. Both appear in the dsh docs.
- **`models` list.** It **replaces** the route's catalog rather than adding to it. Each entry inherits its context window, max tokens, reasoning levels and `compat` from the installed catalog entry with the same id (llm-pi-ai README, "Resolve the model catalog"). Leave `models` out to get all ~400 catalog models in the picker. Use `modelOverrides` to tweak only a few.
- **Models outside the catalog** (newer models, `:exacto` slugs, `@preset/...`) **need `api: openai-completions` on the route**. The OpenRouter catalog mixes two protocols, so dsh can't infer one. dsh refuses such a model with "needs an api; the installed catalog does not describe it" (`tests/dynamic-config.spec.ts:90`). A route-level `api` overrides every model on the route. There is no per-model `api` field (`PiAiModelProfile` in `docs/config-catalog.md`). That is harmless here, because every model recommended below is `openai-completions`.

### Credentials

- `apiKeyEnv` is resolved for each request through dsh's credential seam. The precedence is `$DSH_HOME/.credentials.yaml`, then the process environment, then `<cwd>/.env`, then `$DSH_HOME/.env` (`packages/credentials/credentials-local/src/index.ts:1-10`).
- If the reference resolves to nothing, the request fails with `MISSING_CREDENTIAL`.
- If you omit `apiKeyEnv`, pi-ai's ambient discovery falls back to `OPENROUTER_API_KEY` (llm-pi-ai README, "Configure provider routes").
- You can also store the key through the Models page, or sign in with OpenRouter OAuth. The stored record lives at `llm-pi-ai/openrouter`.

### Streaming and tool calling

- **Streaming.** pi-ai's `openai-completions` always sends `stream: true` and `stream_options: {include_usage: true}` (`dist/api/openai-completions.js` ~L575-583). dsh converts pi-ai events into its own `StreamChunk`s for reasoning, text, tool calls, usage and finish (llm-pi-ai README, "Provider response").
- **Tool calling.** pi-ai sends `tools` and `tool_choice` (~L600-614). Every catalog entry checked has `supportsStrictMode: true` and `thinkingFormat: "openrouter"`, which sends `reasoning: {effort}`. dsh parses the tool-call arguments and re-serialises them as raw JSON. dsh also carries a pi-ai patch that avoids O(n²) re-parsing of streamed tool arguments (README, "Known Limitations").
- **Routing to tool-capable providers.** OpenRouter "makes a best effort to route to providers known to support tool use" whenever `tools` is present ([provider-selection](https://openrouter.ai/docs/guides/routing/provider-selection.md), Price-Based Load Balancing tip).

### Known gaps and gotchas

1. **Provider routing can't be set from dsh.** pi-ai sends `params.provider = model.compat.openRouterRouting` (`openai-completions.js` L732-733). The `OpenRouterRouting` type covers `order`, `only`, `ignore`, `sort`, `max_price`, `quantizations`, `require_parameters`, `allow_fallbacks`, `data_collection` and `zdr` (`dist/types.d.ts:809`). dsh's compat gate marks `openRouterRouting: 'withhold'` (`packages/llm/llm-pi-ai/src/catalog.ts:268`), so writing it is **refused**, not ignored (`.agents/notes/archived/feature/2026-08-18-pi-ai-wire-compat-surface.md`). No catalog entry sets it either. The result is OpenRouter's default routing: price-weighted load balancing across providers.
   - *Workarounds (none tested with dsh):*
     - Set OpenRouter account defaults under Settings → Preferences. The API exposes `default_provider_sort` with the values price, throughput, latency or exacto.
     - Create an OpenRouter **preset** and use `@preset/<slug>` as the model id. Presets "encapsulate model selection, provider routing, system prompts, and generation parameters" (llms-full.txt, Presets).
     - Use a slug variant such as `<model>:exacto`. The last two need `api: openai-completions` on the route, as explained above.
2. **No `models` fallback array.** pi-ai's request builder never sets `models`. dsh's `llm-retry` retries the same route, and this research did not find a cross-model fallback in dsh. A preset is the likely way to get OpenRouter-side fallbacks (unverified).
3. **App-attribution headers are deliberately not sent.** These are `HTTP-Referer` and `X-OpenRouter-Title`; dsh sends only `User-Agent` (`.agents/notes/archived/architecture/2026-06-21-mandatory-app-attribution-headers.md`). This is harmless. The profile's `headers` field can add them if wanted.
4. **Catalog prices are a snapshot.** The `cost` in pi-ai 1.1.0's catalog can differ from live prices. For example, `deepseek/deepseek-v4.1-flash` is $0.30/$1.20 in the catalog but listed at $0.065/$0.144 live. Trust OpenRouter's billing, or `GET /api/v1/key`, over dsh's token meter for spend.
5. **Other limits.** `GenerateOptions.stop` is unsupported (`UNSUPPORTED_OPTION`). pi-ai doesn't expose the provider's HTTP status. Model discovery for a catalog route answers from the catalog, not from the live OpenRouter list; to see live models you'd need a custom route (`docs/user/guide/providers.md`, "Discover models").

---

## 2. Open-weight models on OpenRouter

### Method

- **Open-weight test:** the model has a non-empty `hugging_face_id` in `/api/v1/models`. This is a proxy; check licences before relying on it.
- **Tools:** `tools` appears in `supported_parameters`.
- **`:free`:** an `<id>:free` entry exists in `/models`.
- **Prices** are USD per million tokens, input/output.
- **"Listed"** is the model-level `pricing` from `/models`. It is often the cheapest endpoint, sometimes quantised (fp4/int4) and served by a small provider. Because routing is price-weighted, real cost floats across the **endpoint range** taken from `/models/{id}/endpoints`. The range below covers live endpoints and ignores outliers with inverted pricing.

### Small and cheap (classification, memory compression, summarising)

| Model id | Listed in / out | Endpoint range (out) | Context | Tools | `:free` | In pi-ai catalog |
|---|---|---|---|---|---|---|
| **`openai/gpt-oss-20b`** | 0.018 / 0.09 | 0.09-0.30 (11 endpoints; 2 without tools) | 131,072 | yes | no | yes (reasoning) |
| **`nvidia/nemotron-3.5-lightning`** | 0.07 / 0.20 | 0.12-0.20 (4 endpoints, all with tools) | 262,144 (`:free` 1,000,000) | yes | **yes** | yes (reasoning) |
| **`mistralai/mistral-nemo`** | 0.029 / 0.03 | 0.022-0.15 (5 endpoints; 2 without tools) | 131,072 | yes | no | yes (non-reasoning) |
| `qwen/qwen3.5-9b` | 0.10 / 0.15 | 0.13-0.25 (6) | 262,144 | yes | no | yes |
| `meta-llama/llama-3.1-8b-instruct` | 0.05 / 0.08 | 0.04-0.29 (5; tools only on Groq and CoreWeave) | 131,072 | partial | no | yes |
| `mistralai/ministral-8b-2512` | 0.15 / 0.15 | 0.15-0.165 (Mistral only) | 262,144 | yes | no | yes |
| `google/gemma-4-26b-a4b-it` | 0.068 / 0.225 | 0.18-0.60 (13; 3 without tools) | 262,144 | yes | **yes** | yes |
| `inclusionai/ling-3.0-flash` | 0.021 / 0.063 | 0.063-0.18 (2) | 262,144 | yes | no | yes |

**Pick 2-3:**

1. **`openai/gpt-oss-20b`** for classification and routing decisions. It is a reasoning model with many providers and tools, and costs about $0.10 per million output tokens.
2. **`nvidia/nemotron-3.5-lightning`** for memory compression of long context. It has 262k context (1M on `:free`) and tools on every endpoint, and its `:free` variant is useful for development.
3. **`mistralai/mistral-nemo`** for bulk summarising, where you don't want reasoning tokens. It is the cheapest option at about $0.03 per million output tokens. Pin it to a tool-capable host if it ever needs tools.

### Large but cheap (main research loop with tool calls)

| Model id | Listed in / out | Mainstream providers (in / out) | Context | Tools | `:free` | In pi-ai catalog |
|---|---|---|---|---|---|---|
| **`deepseek/deepseek-v4.1-flash`** | 0.065 / 0.144 | 0.30 / 1.20 (Together, Fireworks, Nebius, SiliconFlow and others; 34 endpoints, all with tools) | 1,048,576 | yes | no | yes (reasoning) |
| **`z-ai/glm-5.3-flash`** | 0.048 / 0.20 | 0.15 / 0.50 (Z.AI first-party, Fireworks, Together and others; 35 endpoints, all with tools) | 1,048,576 | yes | no | yes (reasoning) |
| `openai/gpt-oss-120b` | 0.15 / 0.60 | 0.03-0.15 / 0.15-0.95 (24 endpoints; 5 without tools) | 131,072 | yes | no | yes |
| `nvidia/nemotron-3-super-120b-a12b` | 0.08 / 0.45 | 0.085 / 0.40 (DeepInfra; 3 endpoints) | 262,144 | yes | **yes** | yes |
| `deepseek/deepseek-v4-pro` | 0.209 / 0.418 | 1.0-1.9 / 2.1-3.8 (16 endpoints) | 1,048,576 | yes | no | yes |
| `qwen/qwen3-235b-a22b-2507` | 0.09 / 0.55 | 0.09-0.25 / 0.35-1.00 (7) | 262,144 | yes | no | yes (non-reasoning) |
| `nvidia/nemotron-3-ultra-550b-a55b` | 0.60 / 2.40 | - | 262,144 | yes | **yes** | yes |

**Pick 1-2:**

1. **`deepseek/deepseek-v4.1-flash`** for the main loop. It has 1M context, every one of its 34 endpoints supports tools, and it matches dsh's DeepSeek-first design. Budget about $0.30/$1.20 per million tokens if you don't pin a provider.
2. **`z-ai/glm-5.3-flash`** as the alternative and fallback. Its first-party price is about $0.15/$0.50, it also has 1M context, and every one of its 35 endpoints supports tools.

For a zero-cost development loop, use `nvidia/nemotron-3-super-120b-a12b:free`, within the free limits in section 3.

### Budget sanity check

This is illustrative arithmetic, not a measurement.

- **Main loop:** 20M input plus 2M output tokens a month on `deepseek-v4.1-flash` at mainstream prices is 20 × 0.30 + 2 × 1.20 = **$8.40**.
- **Small jobs:** 10M input plus 1M output on `gpt-oss-20b` costs **under $0.50**.

Both fit the $10-20 a month cap. Prompt caching and the cheaper providers can lower this further.

### What this research did not verify

- **Tool-call reliability** (how often each model calls tools correctly) was **not measured**. Only advertised support is listed. The issue asked for reliability, so treat it as open and measure it in a prototype.
- **Ways to bias routing toward reliable hosts:** OpenRouter's `:exacto` variant "prefers providers with stronger tool-calling quality signals" ([exacto](https://openrouter.ai/docs/guides/routing/model-variants/exacto.md)). The `require_parameters: true` routing option excludes providers that would ignore `tools`. From dsh, both have to go through the workarounds in Gap 1.
- **`:free` lifetime:** some `:free` variants expire. `/models` lists `expiration_date: 2026-10-31` for both `poolside/laguna-*:free` variants, so those are not recommended.

---

## 3. OpenRouter features for a budget harness

| Feature | What it does | Usable from dsh today? |
|---|---|---|
| **Per-key credit limit** | Set a credit cap on an API key, with an optional `daily`, `weekly` or `monthly` reset. Once spent, requests fail with 402 (`limit_source: openrouter_key_limit`), or 403 for a budget limit. OpenRouter recommends "setting a credit limit on every key". `GET /api/v1/key` returns `limit_remaining`, `usage_daily` and `usage_monthly`. Sources: [limits](https://openrouter.ai/docs/api_reference/limits.md); [management API keys](https://openrouter.ai/docs/guides/overview/auth/management-api-keys.md); llms-full.txt "credit limit". | **Yes.** It works on the key with no dsh change. Recommended: a $15 limit with a `monthly` reset. |
| **`:free` variants** | Append `:free` where an entry exists. The limits are **20 requests per minute**, and **50 requests per day** with less than 10 credits purchased ever, or **1,000 per day** with at least 10. A negative balance can return 402 even on free models. Source: [limits](https://openrouter.ai/docs/api_reference/limits.md), constants `FREE_MODEL_*`; [free variant](https://openrouter.ai/docs/guides/routing/model-variants/free.md). | **Yes.** 15 `:free` ids are in pi-ai's catalog, including `nemotron-3.5-lightning:free`, `nemotron-3-super-120b-a12b:free` and `gemma-4-26b-a4b-it:free`. |
| **Provider routing** (`provider` object) | `order`, `only`, `ignore`, `sort` (price, throughput or latency), `max_price` (a hard cap that refuses the request if exceeded), `quantizations`, `require_parameters`, `allow_fallbacks`, `data_collection` and `zdr`. Source: [provider-selection](https://openrouter.ai/docs/guides/routing/provider-selection.md). | **No, not per request** (dsh withholds `openRouterRouting`). Use account preferences or a preset instead. |
| **Model fallbacks** (`models` array) | Tries models in priority order on errors, rate limits, downtime or moderation, and bills for the model actually used. Source: [model-fallbacks](https://openrouter.ai/docs/guides/routing/model-fallbacks.md). | **No** (pi-ai doesn't send it). A preset may provide it (untested). |
| **Presets** (`@preset/slug`) | A named server-side configuration covering model, routing and parameters. You call it like a model id. Source: llms-full.txt "Presets". | Probably, as a model id on a route with `api: openai-completions` (untested). |
| **`:exacto` variant** | Sorts providers by tool-calling quality instead of price. Source: [exacto](https://openrouter.ai/docs/guides/routing/model-variants/exacto.md). | Probably, the same way as presets (untested). |
| **In-flight spending budget** | For low-balance prepaid accounts, holds the estimated cost of concurrent requests and returns 402 `openrouter_in_flight_budget` with a `Retry-After` header. Setting `max_tokens` keeps the estimate small. Source: [limits](https://openrouter.ai/docs/api_reference/limits.md). | Automatic. dsh's `llm-retry` should treat it as transient. |

## Follow-ups for the map

- **Prototype** the patch above with a real key and a tool-calling turn on `deepseek/deepseek-v4.1-flash`. Confirm streaming, tool calls and reasoning replay. Then measure tool-call success across the shortlisted models.
- **Decide** how to get routing and fallbacks: an OpenRouter preset, account defaults, or an upstream dsh change that offers `openRouterRouting` on the catalog route.
