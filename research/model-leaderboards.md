# What independent leaderboards say about our candidate models

Research for [#29](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/29), part of map #1.
**All sources were checked on 2026-10-19.** Leaderboards change often, so re-check any number before you rely on it.

## TL;DR: picks per role

| Role | Pick | Runner-up | Why (one line) |
|---|---|---|---|
| **Local victim** (tool calling, attacked) | `qwen3.5:4b` | `qwen3.5:9b` | 4B has the highest AA index of our local candidates (13, **estimated**) and fits in 16 GB with room for a judge; the 9B has a measured score (11) but uses tight memory. |
| **Local judge** (narrow yes/no) | `gemma4:e4b` | `granite4.2:3b` *(not on list)* | Gemma has a measured, non-estimated AA score (9) and comes from a different family than the victim, so the two models share fewer blind spots. Granite 4.2 3B replaces the deprecated 4.1 and scores 9 (measured). |
| **OpenRouter small fallback** (judges masked findings) | `nvidia/nemotron-3.5-lightning` | `openai/gpt-oss-20b` | Nemotron has the higher AA index (13 vs 9), is the fastest model AA measures (299 t/s), and costs about $0.07/$0.20. gpt-oss-20b is the cheapest and has measured IFBench and τ² scores. |
| **OpenRouter main loop** (tool-calling agent) | `deepseek/deepseek-v4.1-flash` | `z-ai/glm-5.3-flash` | DeepSeek ranks clearly higher than GLM on Arena's real-session **Agent** board (rank 19 vs 33, with non-overlapping rank spreads) at a similar cost per task, and it is 3x faster. GLM scores slightly higher on AA (42 vs 39) and costs about half per token. |

Caveats behind these picks:

- **No candidate has independent tool-calling data from BFCL.** The local picks rest on general-intelligence scores plus proxies from older model generations.
- The local picks need our own eval in the harness. Neither leaderboard measures prompt-injection susceptibility or classification accuracy on our task.

---

## Sources used, and what each one measures

| Source | What it measures | Independent? | Coverage of our candidates |
|---|---|---|---|
| [Artificial Analysis (AA)](https://artificialanalysis.ai) | Intelligence Index v4.3.2 (10 evals, incl. Terminal-Bench 4.0 and GDPval-AA), speed, price | Yes. AA runs the evals itself, but it marks some scores **"Estimate (independent evaluation forthcoming)"** | All except Mistral NeMo (its current page returns 404) and Bonsai-2 |
| [BFCL V4](https://gorilla.cs.berkeley.edu/leaderboard.html) | Function calling: AST, live, multi-turn, irrelevance detection | Yes (UC Berkeley) | **Only Mistral NeMo.** The page says "Last Updated: 2026-04-12", and its [data CSV](https://gorilla.cs.berkeley.edu/data_overall.csv) has 108 rows with no 2026-generation models |
| [Arena Text](https://arena.ai/leaderboard/text) (formerly LMArena) | Human-preference Elo, style-controlled | Yes (crowd votes) | gpt-oss-20b, Nemotron 3.5 Lightning, DeepSeek V4.1 Flash, GLM-5.3-Flash |
| [Arena Agent](https://arena.ai/leaderboard/agent) | Real agent sessions: success, steerability, tool hallucination, cost per task | Yes | DeepSeek V4.1 Flash, GLM-5.3-Flash |
| [OpenRouter rankings](https://openrouter.ai/rankings) and [models API](https://openrouter.ai/api/v1/models) | Usage (tokens), per-provider price, and whether a model supports `tools` | Usage only. OpenRouter itself says the rankings "do not rank models by accuracy" | All five OpenRouter candidates |
| OpenRouter model pages ("AutoExacto" benchmarks) | GPQA and TAU-Bench re-run per provider, tool-call error rate | Yes for the reruns. They also mirror AA and Vals AI scores | All five OpenRouter candidates; numbers for some |

---

## Local candidates

### Artificial Analysis

| Model | AA Intelligence Index (v4.3.2) | Estimated? | Params (per AA) | Notes |
|---|---|---|---|---|
| qwen3.5:2b (Reasoning) | **7** | ⚠️ estimated | 2.3B | No public API, so AA shows no speed ([AA](https://artificialanalysis.ai/models/qwen3-5-2b)) |
| qwen3.5:4b (Reasoning) | **13** | ⚠️ estimated | 4.7B | API median of 13.8 t/s (that is a provider number, not local speed) ([AA](https://artificialanalysis.ai/models/qwen3-5-4b)) |
| qwen3.5:9b (Reasoning) | **11** | measured | 9.7B | 68.0 t/s via API ([AA](https://artificialanalysis.ai/models/qwen3-5-9b)) |
| granite4.1:3b | **6** | ⚠️ estimated | 3B | **AA marks it deprecated** and points to Granite 4.2 3B ([AA](https://artificialanalysis.ai/models/granite-4-1-3b)) |
| gemma4:e4b (Reasoning) | **9** | measured | 8B total, 4.5B active per AA | Non-reasoning variant: 7 (estimated) ([AA](https://artificialanalysis.ai/models/gemma-4-e4b), [AA non-reasoning](https://artificialanalysis.ai/models/gemma-4-e4b-non-reasoning)) |
| bonsai-2:9b (ternary) | — | **no independent data** | 9B, about 2 GB (vendor figure) | See below |

Things to watch out for:

- **The 4B scores higher than the 9B (13 vs 11), but the 4B's 13 is an estimate and the 9B's 11 is measured.** Don't read this as "4B is smarter" until AA publishes a measured 4B score.
- Older search snippets and localised pages show different numbers: Qwen3.5 4B at 20 and 9B at 21 under index v4.1. **The index versions are not comparable**, so this file uses only the v4.3.2 English pages.
- AA publishes **no per-model tool-use or agentic sub-scores** for any local candidate. The pages list the agentic evals but leave the cells blank.

### Tool calling (BFCL): no direct data, only proxies from older generations

None of the local candidates is on BFCL V4 ([CSV](https://gorilla.cs.berkeley.edu/data_overall.csv)). The closest relatives come from the previous generation and serve only as **proxies**:

| BFCL V4 model (proxy) | Overall | Multi-turn | Irrelevance detection | Rank of 108 |
|---|---|---|---|---|
| Qwen3-8B (FC) | 42.57% | 41.75% | 79.07% | 39 |
| Qwen3-4B-Instruct-2507 (FC) | 35.68% | 22.12% | 84.93% | 54 |
| Qwen3-1.7B (FC) | 28.41% | 11.00% | 76.54% | 71 |
| Gemma-3-4b-it (Prompt) | 19.62% | 0.38% | — | 101 |
| Granite-4.0-350m (FC) | 18.98% | 2.50% | — | 103 |
| *xLAM-2-3b-fc-r (FC), a specialist* | 41.22% | 58.38% | 63.45% | 42 |

What the proxies suggest, unverified for the current generation: at ≤4B, Qwen's native FC path held up far better than Gemma's prompt-based calling, and multi-turn accuracy falls off steeply below 8B.

### bonsai-2:9b

- **No independent benchmark exists for the 9B.** No AA page or BFCL entry turned up, and it does not appear on Arena.
- Vendor claims, not verified: PrismML announced Bonsai 2 at 2B, 4B and 9B on 2026-10-15. The models are Qwen3.5-based, use ternary weights (about 1.58 bits per weight), and the 9B is about 2.0 GB ([PrismML](https://prismml.com/news/ternary-bonsai); coverage by [toolnavs](https://toolnavs.com/de/article/2625-ternary-bonsai-2-adds-three-small-models-the-9b-takes-just-2gb-and-runs-on-a-pho)).
- The only related third-party data covers the **27B** ternary build. In community tool-eval tests reported second-hand, it lost some tool-calling accuracy against full precision ([pasqualepillitteri.it](https://pasqualepillitteri.it/de/news/8240/bonsai-27b-iphone-3-9-gb-de)). This is **not verified** and does not apply directly to the 9B.
- If the 2 GB claim holds, a Qwen3.5-9B-class model fits easily in 16 GB, so the 9B is worth a local spot-check. Until then, it is not a pick.

### Arena Text (local-relevant)

None of our local candidates (Qwen3.5 2B/4B/9B, Granite 4.1 3B, Gemma 4 E4B) is on the [Arena text board](https://arena.ai/leaderboard/text) (updated Oct 15, 2026; 416 models). The nearest entries are Granite 4.2 3B at 1290 (rank 292) and Gemma 3n E4B IT at 1318 (rank 266).

---

## OpenRouter candidates

### Intelligence, speed and price (Artificial Analysis)

| Model | AA Intelligence Index | Speed (t/s, AA) | AA price in/out per 1M | Params |
|---|---|---|---|---|
| deepseek/deepseek-v4.1-flash (Max) | **39** (#10 of 121) | 231.2 | $0.30 / $1.20 | 552B total / 16B active |
| z-ai/glm-5.3-flash | **42** (#6 of 121) | 78.0 | $0.15 / $0.50 | 320B / 18B |
| nvidia/nemotron-3.5-lightning | **13** | 299.4 (#1 of 64) | $0.06 / $0.20 | 31.6B / 3.6B |
| openai/gpt-oss-20b | **9** | 253.3 | $0.058 / $0.215 | 21B / 3.6B (per OpenRouter) |
| mistralai/mistral-nemo | — (**no current AA page**; it returns 404) | — | — | 12B |

Sources: [AA DeepSeek V4.1 Flash](https://artificialanalysis.ai/models/deepseek-v4-1-flash), [AA GLM-5.3-Flash](https://artificialanalysis.ai/models/glm-5-3-flash), [AA Nemotron 3.5 Lightning](https://artificialanalysis.ai/models/nemotron-3-5-lightning), [AA gpt-oss-20b](https://artificialanalysis.ai/models/gpt-oss-20b).

- Nemotron 3.5 Lightning's AA [launch article](https://artificialanalysis.ai/articles/nemotron-3-5-lightning-launch) (2026-08-11) said **24**, but the current model page says **13**. The 13 is under the newer index version.
- The DeepSeek V4.1 Flash **non-reasoning** variant scores 24.7 (AA, mirrored on [OpenRouter](https://openrouter.ai/deepseek/deepseek-v4.1-flash)).

### Agentic and tool-use sub-scores (AA, mirrored on OpenRouter model pages)

| Model | AA Agentic Index | Terminal-Bench 4.0 | τ-Bench / τ²-Bench | IFBench | AA-Omniscience non-hallucination |
|---|---|---|---|---|---|
| GLM-5.3-Flash | **50.9** | 32.8% | τ-Bench Banking 47.2% | — | 72.4% |
| DeepSeek V4.1 Flash (Max) | not shown | 27% ([AA compare](https://artificialanalysis.ai/models/comparisons/deepseek-v4-1-flash-vs-glm-5-3-flash)) | not shown | — | — |
| DeepSeek V4.1 Flash (non-reasoning) | — | 5.6% | — | — | 46.0% |
| Nemotron 3.5 Lightning | 3.5 | 0.5% | τ-Bench Banking 8.9% | — | 62.4% |
| gpt-oss-20b (High) | 1.2 | — | τ²-Telecom 60.2% | 65.1% | — |
| gpt-oss-20b (Low) | — | Terminal-Bench Hard 4.5% | τ²-Telecom 50.3% | 57.8% | 13.3% |
| Mistral NeMo | — | — | — | — | — |

Sources: OpenRouter model pages for [GLM-5.3-Flash](https://openrouter.ai/z-ai/glm-5.3-flash), [DeepSeek V4.1 Flash](https://openrouter.ai/deepseek/deepseek-v4.1-flash), [Nemotron 3.5 Lightning](https://openrouter.ai/nvidia/nemotron-3.5-lightning) and [gpt-oss-20b](https://openrouter.ai/openai/gpt-oss-20b), which credit Artificial Analysis. The gpt-oss τ²/IFBench rows use AA's older eval suite, so **don't compare them directly** with the τ-Bench Banking rows.

OpenRouter's own **AutoExacto TAU-Bench** reruns per provider: DeepSeek V4.1 Flash scores 76.2–77.9% across its top 5 providers, and GLM-5.3-Flash scores 76.1–78.0%. The lowest tool-call error rates shown are about 0.00–0.05% for DeepSeek and 0.04–0.11% for GLM.

### Arena (human preference and real agent sessions)

| Model | Arena Text score (rank of 416) | Arena Agent rank of 52 (spread) | Agent: cost/task P50 | Agent: tool hallucination |
|---|---|---|---|---|
| DeepSeek V4.1 Flash (Max) | 1475 ±6 (#38) | **#19 (12–26)**, 241,716 sessions | $0.14 | 0.48% |
| GLM-5.3-Flash | 1474 ±5 (#41) | #33 (29–36), 87,298 sessions | $0.15 | 0.61% |
| gpt-oss-20b | 1317 ±6 (#267) | not listed | — | — |
| Nemotron 3.5 Lightning (NVFP4) | 1351 ±6 (#216) | not listed | — | — |
| Mistral NeMo | **not listed** | not listed | — | — |

Sources: [Arena Text](https://arena.ai/leaderboard/text) (dated Oct 15, 2026), [Arena Agent](https://arena.ai/leaderboard/agent).

### BFCL

Only **Mistral NeMo (2407)** is on BFCL. It scores 27.63% overall in FC mode (rank 79 of 108), with **7.75% multi-turn** and 61.77% irrelevance detection. In prompt mode it scores 19.31% ([CSV](https://gorilla.cs.berkeley.edu/data_overall.csv)). That is weak for an agent loop.

### OpenRouter price, tool support and usage

Prices come from the [OpenRouter models API](https://openrouter.ai/api/v1/models) and the `/endpoints` lists for each model. "From" is the cheapest provider, which often serves **fp4 quantisation**. "1st-party" is the vendor's own endpoint.

| Model | From (in/out per 1M) | 1st-party / typical | Context | `tools` supported | Usage (week to Oct 18) |
|---|---|---|---|---|---|
| deepseek/deepseek-v4.1-flash | $0.044 / $0.08 (OpenInference, fp4) | $0.30 / $1.20 | 1M | yes | **#1**, 32.8T tokens |
| z-ai/glm-5.3-flash | $0.048 / $0.20 (OpenInference, fp4) | Z.AI $0.15 / $0.50 | 1M | yes | **#2**, 12.2T tokens |
| nvidia/nemotron-3.5-lightning | $0.025 / $0.12 (Darkbloom, int4) | $0.07 / $0.20; there is also a `:free` variant | 262K | yes | not in top 10 |
| openai/gpt-oss-20b | $0.018 / $0.09 (Darkbloom, fp8) | $0.03–0.075 / $0.13–0.30 | 131K | yes (not via SiliconFlow or Google) | not in top 10 |
| mistralai/mistral-nemo | $0.017 / $0.022 (Io Net) | Mistral $0.15 / $0.15 | 128–131K | partly: DekaLLM and Parasail don't support it | not in top 10 |

Usage figures come from [OpenRouter rankings](https://openrouter.ai/rankings) and measure popularity, not quality. "DeepSeek Harness" ranks #6 among OpenRouter apps today, with 329B tokens.

> Pin providers. If the budget pushes you toward the cheapest fp4 or int4 endpoints, tool-calling quality may differ from the AA and Arena numbers above, which were measured on first-party or typical endpoints. That gap has not been verified for these models.

---

## Are there clearly better models outside our list?

| Slot | Contender | Evidence | Verdict |
|---|---|---|---|
| Local ≤4B | **K2 Horizon 3.7B** (MBZUAI IFM, Apache 2.0, 2026-09-03) | AA index **16**, measured (not estimated), versus our best ≤4B score of 13 (estimated). But it is very verbose (180M eval tokens), and AA has no tool-use data for it ([AA](https://artificialanalysis.ai/models/k2-horizon-3-7b)) | **Worth a spot-check.** Not clearly better for tool calling, and Ollama availability is unverified |
| Local ≤4B | **MiniCPM5-2B** (12), **G9v3-3B** (11) | [AA tiny-models list](https://artificialanalysis.ai/models/open-source/tiny) | Possible judge candidates. No tool data |
| Local judge | **Granite 4.2 3B** | AA index **9** (measured), 215.7 t/s, Apache 2.0, released 2026-08-25. AA calls Granite 4.1 3B deprecated ([AA](https://artificialanalysis.ai/models/granite-4-2-3b)) | **Clearly better than granite4.1:3b.** Use it in place of 4.1 if Ollama ships it (unverified) |
| OR small fallback | **Gemma 4 26B A4B** | AA index **17** at 72 t/s ([AA small list](https://artificialanalysis.ai/models/open-source/small)). OpenRouter price $0.09/$0.30 | Smarter than Nemotron (13) or gpt-oss-20b (9) at a similar price, but slower and with no tool data. A reasonable alternative, not clearly better |
| OR main loop | MiMo-V2.6-Flash, Qwen3.8-Flash | Heavily used on OpenRouter. Qwen3.8-Flash-Next is #36 on Arena Agent | **Not checked** on AA. Nothing found that clearly beats DeepSeek or GLM at this price |
| — | Mistral NeMo | Weakest candidate on every board where it appears | **Drop it** |

---

## Independent results vs vendor claims

- **Independent:** every AA, BFCL, Arena and OpenRouter number above, except where it is marked ⚠️ estimated.
- **Vendor claims, not verified:** Bonsai 2 size, tool calling and "retention" figures (PrismML). Nemotron 3.5 Lightning "performs like gpt-oss-120b" comes from AA's launch article and is now outdated by AA's own lower score. The OpenRouter model descriptions are written by vendors.
- **Unverified here:** which of these models Ollama ships, and under what tags (`granite4.2:3b`, K2 Horizon). Local tokens/s on an M5 with 16 GB. How quantisation affects tool calling.

## Open questions this file does not answer

1. Local tool-calling reliability of qwen3.5:4b vs gemma4:e4b in dsh. This needs our own eval.
2. Judge accuracy on our actual yes/no prompts.
3. Whether a monthly budget of $10–20 holds with DeepSeek V4.1 Flash on first-party pricing. Arena puts the median at $0.14 per task, which would be about 70–140 agent tasks a month. That is a rough estimate, not measured on our workload.
