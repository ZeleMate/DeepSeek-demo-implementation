# Small local models and red-team-friendly APIs

Research for [#28](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/28) (blocks #14, #16). Builds on `research/redteam-setup.md` (#25). Checked **2026-10-19**.

Markers: **[verified]** = read in a primary source (vendor model card, Ollama library page, official terms or docs, BFCL leaderboard data) on the check date. **[vendor]** = a number the model's own publisher reports, not independently reproduced. **[inferred]** = follows from verified facts. **[unverified]** = not confirmed; check before relying on it.

This is model and policy research only. It contains no attack content. Nothing was installed or run. I'm not a lawyer: the "reading" column in section 2 is a plain-language interpretation, not legal advice.

---

## TL;DR

1. **Victim (≤4B, tool calling):** start with **`qwen3.5:4b`** (Apache-2.0, 256K ctx, q4_K_M 3.3 GB; vendor BFCL-V4 50.3, TAU2 79.9). The second family is **`granite4.1:3b`** (Apache-2.0, 128K, 2.1 GB; vendor BFCL v3 60.80). Use **`qwen3:4b-instruct`** (2507, 2.5 GB) as the independently benchmarked baseline (BFCL V4 leaderboard **35.68%**). The best ≤4B on the independent leaderboard is **Nanbeige4-3B-Thinking** (**51.40%**, Apache-2.0), but it has no official Ollama tag [unverified].
2. **~8B comparison:** `qwen3:8b` (5.2 GB, leaderboard **42.57%**), `qwen3.5:9b` (q4_K_M 6.6 GB, vendor BFCL-V4 66.1), `granite4.1:8b` (5.3 GB, vendor BFCL v3 68.27).
3. **Judge (narrow classification):** for *our* questions ("did the agent follow the injected instruction?", "is this secret a false positive?"), use a **small general instruct model with a constrained JSON output** (`qwen3.5:2b`/`:4b`, `granite4.1:3b`). Of the off-the-shelf guards, only **`granite3-guardian:2b`** (Apache-2.0, has a `jailbreak` category and answers `Yes`/`No`) is aimed at jailbreak detection. Ollama's new **decision models** (`tev1:0.8b`/`:4b`, `/v1/systemone`) fit narrow classification but are labelled experimental.
4. **Providers:** **no provider grants a blanket right to jailbreak its model.** But **OpenAI, Anthropic and Google all tell developers to red-team their own app against prompt injection** in their docs. Their terms forbid circumventing *their* safeguards (jailbreaks aiming at harmful output). Groq has an **exception request** route. Mistral's commercial terms ban "vulnerability, penetration, or similar testing" outright. Together and DeepInfra ban probing or testing the service without authorisation or consent. DeepSeek bans testing vulnerabilities "without permission".
5. **OpenRouter:** email **<safety@openrouter.ai>** with the use case, models and providers, techniques and timeline. Review "generally takes 5 business days", is discretionary, and the answer comes in writing. Classifiers still run with ZDR.
6. **Implication for #14:** keep harmful-content jailbreak suites **local only**. API runs (if ever) should be **indirect-injection tests scored by canary and egress**, which matches what the vendors' own docs recommend. Even then, ask first where the terms say to (Groq, OpenRouter, DeepInfra, Mistral).

---

## 1. Small open-weight models

### 1a. How to read the benchmark numbers

- **Independent:** the [BFCL V4 leaderboard](https://gorilla.cs.berkeley.edu/leaderboard.html), "Last Updated: 2026-04-12", 109 rows ([`data_overall.csv`](https://gorilla.cs.berkeley.edu/data_overall.csv)) [verified]. V4 "Overall" mixes non-live AST, live, multi-turn, web search, memory and relevance. It has **no Qwen3.5, Granite 4.1, Gemma 4 or Ministral 3 rows**, because all of these are newer than or absent from the April update.
- **Vendor-reported:** model cards quote BFCL **v2, v3 or v4** with their own harness and mode (thinking or not). **Don't compare across versions or against leaderboard numbers.** A vendor BFCL-V4 of 50 isn't the same thing as a leaderboard 50%.
- The Ollama `tools` tag only means the chat template supports tools. **Reliability on our dsh harness is [unverified] for every model below.** The smoke test from `redteam-setup.md` §1 (10 tasks, keep ≥ 8/10) still applies.
- **Sizes** are Ollama download sizes. Ollama shows ranges when a tag has several builds (GGUF vs MLX). RAM at run time = weights + KV cache (grows with `OLLAMA_CONTEXT_LENGTH`) + runtime [inferred]. Check with `ollama ps`.

### 1b. Victim candidates, ≤4B (tool calling)

| Ollama tag | Params | Size (default / q4_K_M) | Ctx | Licence | Tool-calling evidence | Notes |
|---|---|---|---|---|---|---|
| **`qwen3.5:4b`** | 4B | 3.3–4.0 GB / `4b-q4_K_M` 3.3 GB | 256K | Apache-2.0 ([HF](https://huggingface.co/Qwen/Qwen3.5-4B)) | **BFCL-V4 50.3, TAU2 79.9** [vendor] | Vision + thinking. Model card cites Feb 2026. **Top pick.** |
| `qwen3.5:2b` | 2B | 2.7–3.1 GB / `2b-q4_K_M` 1.9 GB | 256K | Apache-2.0 ([HF](https://huggingface.co/Qwen/Qwen3.5-2B)) | BFCL-V4 43.6, TAU2 48.8 (thinking) [vendor] | Weaker, cheaper victim |
| `qwen3.5:0.8b` | 0.8B | 1.2–1.3 GB | 256K | Apache-2.0 | BFCL-V4 25.3, TAU2 11.6 [vendor] | Too weak to be a realistic agent [inferred] |
| **`granite4.1:3b`** | 3B | 2.1 GB | 128K | Apache-2.0 ([HF](https://huggingface.co/ibm-granite/granite-4.1-3b)) | **BFCL v3 60.80** [vendor] | Released 2026-04-29. Text only. **Second family.** |
| `qwen3:4b-instruct` (2507) | 4B | 2.5 GB | 256K | Apache-2.0 ([HF](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507)) | **BFCL V4 leaderboard 35.68%** (FC, rank 54); vendor BFCL-v3 61.9 | The only ≤4B candidate here with an independent score |
| `qwen3:4b` | 4B | 2.5 GB | 256K (tag) / 40K (`4b-q4_K_M`) | Apache-2.0 | (see 2507 row) | The two tags differ in context, so pin the tag |
| `ministral-3:3b` | 3B | 3.0 GB | 256K | Apache-2.0 ([HF](https://huggingface.co/mistralai/Ministral-3-3B-Instruct-2512)) | None published (card only says "native function calling") | Needs Ollama ≥ 0.13.1. Vision. |
| `llama3.2:3b` | 3B | 2.0 GB | 128K | Llama 3.2 Community Licence (custom, not OSI) ([HF](https://huggingface.co/meta-llama/Llama-3.2-3B-Instruct)) | Leaderboard **21.95%** (rank 98); vendor BFCL V2 67.0 | Old (2024) baseline |
| `phi4-mini` (3.8b) | 3.8B | 2.5 GB | 128K | Not stated on the Ollama page (MIT upstream [unverified]) | None found | — |
| `gemma4:e2b` / `:e4b` | 2.3B / 4.5B effective (5.1B / 8B with embeddings) | 4.6–7.5 GB / 6.6–9.5 GB (`e4b-it-q4_K_M` 6.6 GB) | 128K | Apache-2.0 ([HF](https://huggingface.co/google/gemma-4-E4B-it)) | Tau2 24.5% / 42.2% [vendor]; no BFCL | **The download is as heavy as an 8B model**, so it isn't a true ≤4B in RAM [inferred] |
| `bonsai-2:2b` / `:4b` (Prism ML) | 2B / 4B, ternary weights | 0.9 / 1.6 GB | 256K | Apache-2.0 (Ollama page) | **None** | Very small. Untested tool calling. [unverified] |
| `functiongemma:270m` | 270M | 301 MB | 32K | Not stated on the Ollama page | BFCL simple 61.6, live simple 36.2, irrelevance 73.7 [vendor] | "Not intended for use as a direct dialogue model". **Not a victim.** |
| Nanbeige4-3B-Thinking-2511 | 3B | — | — | Apache-2.0 ([HF](https://huggingface.co/Nanbeige/Nanbeige4-3B-Thinking-2511)) | **Leaderboard 51.40%** (rank 25, the best ≤4B) | **No official Ollama tag found** [unverified]; would need a GGUF import |
| xLAM-2-3b-fc-r (Salesforce) | 3B | — | — | **CC-BY-NC-4.0** ([HF](https://huggingface.co/Salesforce/xLAM-2-3b-fc-r)) | Leaderboard 41.22%, multi-turn 58.38% | Non-commercial licence; no official Ollama tag [unverified] |

Other ≤4B leaderboard rows for reference [verified, BFCL CSV]: Arch-Agent-3B 35.36% (katanemo-research licence), Hammer2.1-3b 29.71% (qwen-research licence), xLAM-2-1b 30.44%, Qwen3-1.7B 28.41%, MiniCPM3-4B 25.55%, Qwen3-0.6B 23.93%, Gemma-3-4b-it 19.62%, Granite-4.0-350m 18.98%, Llama-3.2-1B 10.82%.

### 1c. ~8B quantised, for comparison

| Ollama tag | Size | Ctx | Licence | Tool-calling evidence |
|---|---|---|---|---|
| `qwen3:8b` | 5.2 GB (q4_K_M) | 40K | Apache-2.0 | **Leaderboard 42.57%** (FC, rank 39) |
| `qwen3.5:9b` | 6.6 GB (`9b-q4_K_M`) | 256K | Apache-2.0 | BFCL-V4 66.1, TAU2 79.1 [vendor] |
| `granite4.1:8b` | 5.3 GB | 128K | Apache-2.0 | BFCL v3 68.27 [vendor] |
| `ministral-3:8b` | 6.0 GB | 256K | Apache-2.0 | None published |
| xLAM-2-8b-fc-r / ToolACE-2-8B / BitAgent-Bounty-8B | — | — | CC-BY-NC-4.0 / Apache-2.0 / Apache-2.0 | Leaderboard 46.68% / 42.44% / 46.23%; no official Ollama tags [unverified] |

### 1d. Judge candidates (narrow classification)

What the judge has to do here: label an agent transcript ("did it follow the injected instruction?", "did the canary leave?") or a secrets-scanner hit ("real secret or false positive?"). **Most of this is narrow, schema-shaped classification, not harm moderation.**

| Option | Tag(s) and size | Ctx | Licence | Output | Fit |
|---|---|---|---|---|---|
| **General instruct + JSON schema** | `qwen3.5:2b-q4_K_M` 1.9 GB, `qwen3.5:4b-q4_K_M` 3.3 GB, `granite4.1:3b` 2.1 GB | 256K / 128K | Apache-2.0 | Whatever schema we give (Ollama `format` with a JSON schema [unverified on this check]) | **Best fit** for our custom labels. Use a different family from the victim (`redteam-setup.md` §1). |
| **Decision models** (Ollama, blog 2026-09-29) | `tev1:0.8b` 0.8–1.5 GB, `tev1:4b` 4.4–4.6 GB (Together AI, fine-tuned from Qwen3.5) | Listing says 256K; notes say "about 2,000 tokens" (conflict) | **Not stated** for the weights (scripts MIT) [unverified] | `/v1/systemone`: `choice`, `noul` (yes/no) and `score`, with probabilities | Built for exactly this (triage, routing, moderation). Ollama eval: 4B 73.3%, 0.8B 63.5% mean accuracy over 13 datasets. Labelled **experimental**. Needs Ollama ≥ 0.35. |
| **`granite3-guardian:2b`** | 2.7 GB (`:8b` 5.8 GB) | **8K** | Apache-2.0 | One token, `Yes`/`No`; risk chosen via the system prompt | Has a **`jailbreak`** category plus RAG `groundedness` and `relevance`. Good as an input-side injection flag. No numbers on the page. |
| `llama-guard3:1b` | 1.6 GB (`:8b` 4.9 GB) | 128K | Not stated on the page (Llama community licence upstream [unverified]) | Safe/unsafe + S1–S13 | Harm taxonomy (MLCommons). **No injection or jailbreak category**, so it's a poor fit. |
| `shieldgemma:2b` | 1.7 GB | 8K | Not stated on the page | `Yes`/`No` | Only four harm categories, so it's a poor fit |
| Qwen3Guard-Gen 0.6B / 4B / 8B | HF only; **no official Ollama tag** | 32K in deployment examples | Apache-2.0 ([HF](https://huggingface.co/Qwen/Qwen3Guard-Gen-4B)) | Safe / Controversial / Unsafe | Jailbreak is detected on **input only** |
| ~8B comparison | `granite4.1-guardian:8b`, `nimble:9b` (decision model; 91 ms per decision on an M5 Max per Ollama), `llama-guard3:8b` | — | — | — | Only if the measurement ticket shows RAM headroom |

---

## 2. API providers: is red-teaming your own app allowed?

**Pattern across providers:** the terms ban *circumventing the provider's safeguards* (jailbreaks for harmful output) and *testing the provider's service* for vulnerabilities. The developer docs of OpenAI, Anthropic and Google **explicitly recommend** red-teaming your application against prompt injection. **None publishes a self-serve "red-team approval" form**, except OpenRouter (email) and Groq ("contact Groq").

| Provider | Terms checked (date shown on the page) | Key clause (verbatim) | Approval route | Reading |
|---|---|---|---|---|
| **OpenAI** | [Usage policies](https://openai.com/policies/usage-policies/) (effective 2025-10-29); [Services Agreement](https://openai.com/policies/services-agreement/) (updated 2025-12-01); [Safety best practices](https://developers.openai.com/api/docs/guides/safety-best-practices) | Usage: "you cannot use our services for: … **unsolicited safety testing** … **circumventing our safeguards**". SA §3.3(h): no "bypass any protective measures or safety mitigations for the Services". Docs: "**We recommend 'red-teaming' your application** to ensure it's robust to adversarial input … Can someone easily redirect the feature via prompt injections". | None public for general customers. "Unsolicited" implies a solicited route exists [inferred]; none found [unverified]. | Injection-robustness tests of your own app: **recommended**. Jailbreaking for harmful output, or safety-testing OpenAI's model: **not without OpenAI's invitation**. |
| **Anthropic** | [Usage Policy](https://www.anthropic.com/legal/aup), current version [effective 2025-09-15](https://www.anthropic.com/legal/archive/22742366-2ef0-4c7a-a833-6523f10d3944); the live page already shows a version **effective 2026-11-12**; [Commercial Terms](https://www.anthropic.com/legal/commercial-terms) (2025-06-17); [Mitigate jailbreaks](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/mitigate-jailbreaks) | Current AUP: no "Intentionally bypass capabilities, restrictions, or guardrails … for the purposes of instructing the model to produce harmful outputs (e.g., jailbreaking or prompt injection) **without prior authorization from Anthropic**". From 2026-11-12 the clause is broader: "Intentionally bypass or interfere with … guardrails … including by … instructing the model to produce harmful outputs (e.g., jailbreaking or prompt injection), without prior authorization from Anthropic". Docs: "**Red-team your own agent.** Before deploying, test your workflow with documents, emails, and tool outputs that deliberately contain injection attempts". | "Prior authorization from Anthropic". No public form found [unverified]. A Cyber Verification Program exists for cyber safeguards (2026-11-12 AUP). | Indirect-injection tests of your own agent: **recommended by the docs**. Jailbreak or injection aimed at **harmful outputs**: **needs prior authorisation**. |
| **Google (Gemini API)** | [Gemini API Additional Terms](https://ai.google.dev/gemini-api/terms) (last updated 2026-04-28); [Prohibited Use Policy](https://policies.google.com/terms/generative-ai/use-policy) (2024-12-17); [Safety guidance](https://ai.google.dev/gemini-api/docs/safety-guidance) | Terms: "The Services include safety features to block harmful content … **You may not attempt to bypass these protective measures**". PUP: no content that facilitates "**Circumvention of abuse protections or safety filters** -- for example, manipulating the model to contravene our policies", **but** "We may make exceptions … based on educational, documentary, **scientific** … considerations". Docs: "**Adversarial testing** involves proactively trying to break your application." | Exceptions are at Google's discretion. No application process published [unverified]. | Adversarial testing of your app: **recommended**. Bypassing safety filters: **prohibited** unless Google grants an exception. |
| **Mistral** (La Plateforme API) | [Usage Policy](https://legal.mistral.ai/terms/usage-policy) (effective 2026-06-11); [Commercial ToS](https://legal.mistral.ai/terms/commercial-terms-of-service) (effective 2026-09-25) | Usage: "**You shall not try to circumvent security protections and AI safety filters.**" ToS §2.2(f): no "circumventing, or bypassing security or moderation mechanisms … or **performing any vulnerability, penetration, or similar testing** of the Mistral AI Products". | None published. | **The most restrictive of the hosted APIs.** Note that Mistral's **open weights** (`ministral-3`, Apache-2.0) run locally under the licence, not these API terms [inferred]. |
| **Groq** | [Acceptable Use & Responsible AI Policy](https://console.groq.com/docs/legal/ai-policy) (effective 2025-10-15) | No use "to intentionally circumvent … abuse protections or safety mechanisms … or **to prompt models to act in a manner that violates our policies**". "Customers who have implemented adequate safeguards and require additional flexibility for lawful business or **research purposes, may contact Groq to request an exception**." | **Exception request: contact Groq**, case by case. | Jailbreak-style tests need an exception. Hosted open models may also carry their own licence AUPs (e.g. Llama) [unverified]. |
| **Together AI** | [Terms of Service](https://www.together.ai/terms-of-service) §4 (updated 2026-05-19) | "You will not … (b) attempt to **probe, scan, or test the vulnerability of the Services** … without proper authorization … (c) … engage in **competitive analysis or benchmarking**". | None published. No jailbreak-specific clause found. | Prompt-injection tests of your own app aren't named. "Test the vulnerability of the Services" and the **benchmarking** ban make ASR measurement on Together legally murky [inferred]. Ask first. |
| **DeepInfra** | [Terms of Service](https://deepinfra.com/terms) §11(a) (last modified 2026-10-15) | "(iv) breach, disable, **circumvent** … any security or authentication measures … (v) **probe, scan, or test the vulnerability of the Services** or any connected network **without Provider's prior written consent**". | **Prior written consent** (no form named). | No jailbreak clause, but vulnerability testing needs written consent. Model licences of hosted models are not checked [unverified]. |
| **DeepSeek** (dsh's default `deepseek-official`) | [Open Platform ToS](https://cdn.deepseek.com/policies/en-US/deepseek-open-platform-terms-of-service.html) (effective 2026-04-29), §3.1 incorporates the [Terms of Use](https://cdn.deepseek.com/policies/en-US/deepseek-terms-of-use.html) (2026-03-27) | ToU §3.5: no attempts to "interfere with, damage, or attack the Services, systems, networks, **models**" and no "attempting to probe, scan, or test vulnerabilities in the software system or network **without permission**". | "Permission". No route published. | No explicit jailbreak clause. "Attack … models" is broad enough to cover jailbreaks [inferred]. Relevant because dsh defaults to this API: **red-team profiles must not route to `deepseek-official`.** |
| **OpenRouter** | [Terms](https://openrouter.ai/terms) §7 and §8 (last updated 2026-08-31) | See section 3. | Written approval | — |

Not checked: Ollama Cloud (`*-cloud` tags; already disabled with `OLLAMA_NO_CLOUD=1`), Fireworks, Cerebras, AWS Bedrock, Azure, and the Meta Llama AUP (the page redirected to `dev.meta.ai` and didn't render) [unverified].

---

## 3. OpenRouter's written-approval process

Sources: [Terms](https://openrouter.ai/terms) (last updated 2026-08-31) and [Red Teaming policy doc](https://openrouter.ai/docs/cookbook/evaluate-and-optimize/red-teaming) [verified].

- **§7 Prohibited Conduct:** you may not "conduct, or work with any third parties to conduct, without OpenRouter's prior written approval, any Red Teaming of Models. 'Red Teaming' means prompt injection, jailbreaking, or taking any other adversarial action designed to compromise any Models and/or violate any Model Terms".
- **§8 Red Teaming:** "OpenRouter allows Red Teaming **only for legitimate research purposes** and requires users interested in Red Teaming to first submit a written request." Unauthorised red teaming "will be flagged by OpenRouter's and Model providers' monitoring systems and are likely to result in account and access termination by Model providers". OpenRouter will "approve or deny in writing, often within five (5) business days … not guaranteed".
- **How to apply:** email **<safety@openrouter.ai>** with:
  1. a description of your research or use case;
  2. the models and providers you intend to test;
  3. the types of adversarial techniques you plan to use;
  4. your expected timeline.
- **Why approval exists:** "Getting approval allows us to coordinate with providers and prevent your account from being flagged". The doc says "most model and provider terms of service do not support red-teaming".
- **Consequences without approval:** provider bans, model access restrictions, platform-wide account bans.
- **ZDR doesn't help:** "Prompts may therefore be flagged by classifiers even with full ZDR configured."
- **Unknowns [unverified]:** whether approval is scoped per model or provider, how long it lasts, whether personal or learning projects qualify as "legitimate research", and whether approval also binds the downstream providers (the doc implies OpenRouter coordinates with them).

---

## 4. What this means for the map

- **#14 / #16 default stays fully local.** ≤4B models cover a victim (`qwen3.5:4b`, `granite4.1:3b`) and a judge (`qwen3.5:2b` with a JSON schema, or `granite3-guardian:2b` for an input-side jailbreak flag). Together they fit in 16 GB if run one at a time [inferred, measure with `ollama ps`].
- **If a hosted model is ever needed as a stronger victim,** limit it to **indirect-injection fixtures scored by canary and egress**, with no harmful-content goal. That is the use OpenAI, Anthropic and Google document. Ask before running it on Groq, DeepInfra, Together, Mistral or OpenRouter.
- **Guard the profile:** the red-team profile should refuse any `llm-pi-ai` route other than `ollama-local` (fail closed, in the spirit of ADR 0003) so a run can't fall back to `deepseek-official` [recommendation].
- **Measurement ticket:** for each candidate, record the tool smoke-test score (≥ 8/10), RAM at `OLLAMA_CONTEXT_LENGTH=32768`, and tokens per second. Re-rank the tables above with our own numbers, because the vendor BFCL figures aren't comparable to each other.

## Open questions

- The real RAM use of `qwen3.5:4b` vs `gemma4:e4b` at a 32K context on the M5 with 16 GB.
- Whether Ollama's `/v1/systemone` is reachable from Promptfoo or dsh without custom code, and the `tev1` weight licence.
- Whether Nanbeige4-3B or xLAM-2-3b GGUF imports keep their tool-call templates in Ollama.
- OpenAI's and Anthropic's authorisation routes for jailbreak research: no public form was found.

## Sources

- **BFCL:** [leaderboard](https://gorilla.cs.berkeley.edu/leaderboard.html), [`data_overall.csv`](https://gorilla.cs.berkeley.edu/data_overall.csv) (updated 2026-04-12, V4, `bfcl-eval==2025.12.17`)
- **Ollama library:** [qwen3.5](https://ollama.com/library/qwen3.5/tags), [qwen3](https://ollama.com/library/qwen3/tags), [granite4.1](https://ollama.com/library/granite4.1), [granite4](https://ollama.com/library/granite4), [ministral-3](https://ollama.com/library/ministral-3), [llama3.2](https://ollama.com/library/llama3.2), [phi4-mini](https://ollama.com/library/phi4-mini), [gemma4](https://ollama.com/library/gemma4/tags), [bonsai-2](https://ollama.com/library/bonsai-2), [functiongemma](https://ollama.com/library/functiongemma), [tev1](https://ollama.com/library/tev1), [granite3-guardian](https://ollama.com/library/granite3-guardian), [llama-guard3](https://ollama.com/library/llama-guard3), [shieldgemma](https://ollama.com/library/shieldgemma), [decision models blog](https://ollama.com/blog/ollama-now-supports-decision-models)
- **Hugging Face model cards:** [Qwen3.5-4B](https://huggingface.co/Qwen/Qwen3.5-4B), [Qwen3.5-2B](https://huggingface.co/Qwen/Qwen3.5-2B), [Qwen3-4B-Instruct-2507](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507), [granite-4.1-3b](https://huggingface.co/ibm-granite/granite-4.1-3b), [gemma-4-E4B-it](https://huggingface.co/google/gemma-4-E4B-it), [Ministral-3-3B-Instruct-2512](https://huggingface.co/mistralai/Ministral-3-3B-Instruct-2512), [Llama-3.2-3B-Instruct](https://huggingface.co/meta-llama/Llama-3.2-3B-Instruct), [Qwen3Guard-Gen-4B](https://huggingface.co/Qwen/Qwen3Guard-Gen-4B)
- **Provider terms and docs:** linked in the section 2 table and section 3
