# Models are fixed per dsh profile; the red-team profile can't reach any remote model

Routing lives in **dsh profiles**, not in a router plugin. Each profile names its models in config.

| Profile | Main loop | Fallback | Decisions API | Local models |
|---|---|---|---|---|
| **Job profile** | `deepseek/deepseek-v4.1-flash` via OpenRouter (`glm-5.3-flash` if it fails) | `nvidia/nemotron-3.5-lightning` for masked secret judging | injection filter and secrets judge | `qwen3.5:2b` for the per-repo local-only secrets mode |
| **Red-team profile** | `qwen3.5:4b` as victim (`bonsai-2:9b` as a second victim) | none | none | `granite4.2:3b` as grader (a different family from the victim) |

## Why

- **Red-team profile:** OpenRouter, DeepSeek, OpenAI, Anthropic and most other providers forbid jailbreak or injection testing against their models without permission. So the red-team profile is wired to local Ollama only, with **no API fallback of any kind**, not even dsh's default DeepSeek API.
- **Main loop:** DeepSeek-V4.1-Flash was chosen over GLM-5.3-Flash for its higher LMArena agent ranking and fewer hallucinated tool calls at about the same cost per task, even though GLM leads Artificial Analysis's index.
- **Model sizes:** local models stay at the measured working size of this M5/16 GB Mac (about 4B; `bonsai-2:9b` fits because it is ternary).

## Consequences

- No dynamic small→large escalation in v1. That would need a router plugin and is left for later.
- OpenRouter provider quality is set at account level, avoiding fp4/int4 endpoints, with an OpenRouter preset as the fallback mechanism, because dsh blocks per-request provider routing.
- **Budgets:** an OpenRouter key credit limit of $15/month with a monthly reset, and an OpenAI project budget of $5/month. Spend is tracked on the providers' dashboards, because dsh's price table is out of date.

Decided in [Model lineup and routing policy](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/16).
