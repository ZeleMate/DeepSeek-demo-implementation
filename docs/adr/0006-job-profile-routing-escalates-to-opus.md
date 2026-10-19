# The job profile runs cheap by default and escalates to Opus 5.5

This replaces the job-profile routing in ADR 0005. Everything else in ADR 0005 still holds.

- **Everyday model:** `deepseek/deepseek-v4.1-flash` via OpenRouter. It scores 45.1 on Artificial Analysis, costs about $0.26 per task, and its price doesn't change with prompt length.
- **Escalation to `anthropic/claude-opus-5.5`:**
  - **Manual:** you switch the model for work you know is hard. This always works.
  - **Automatic:** an NVIDIA Switchyard preset escalating DeepSeek V4.1 Flash → GPT-6.1 Sol → Opus 5.5 per turn. It is adopted **only if a prototype shows it works through dsh**.
- **`openrouter/auto` is not used.** It stays within one price band, so it can't do "cheap unless hard".
- **Pinned, never routed:** the secrets judge (Decisions API, with Nemotron 3.5 Lightning as fallback), the injection filter (Decisions API), and the red-team profile (local models only).
- **Budget:** the OpenRouter key limit rises from $15 to **$30/month**, which is the hard stop. The OpenAI project budget stays at $5/month.

## Why

Opus 5.5 is the strongest model available (Artificial Analysis 57.6), but it costs about $6 per average agent task. As the default it would eat the budget in a few hundred turns. A cheap default with deliberate escalation spends Opus where it matters. Haiku 5.5 was rejected as the default because its price is five times higher once a prompt passes 100k tokens, and agent contexts get long.

## Consequences

- Your OpenRouter account default model does not affect dsh, because dsh always names a model. Opus is selected explicitly.
- Routing through a preset needs a hand-declared dsh route (`api: openai-completions`). Opus through a router id needs `compat.cacheControlFormat: anthropic` to keep prompt caching. Router ids need `maxTokens` overridden from 4,096.
- Judges and filters keep a fixed model, so their scores stay comparable over time.

Decided in [Use OpenRouter's Auto Router, with Opus 5.5 as the baseline?](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/31). Research: issue #30.
