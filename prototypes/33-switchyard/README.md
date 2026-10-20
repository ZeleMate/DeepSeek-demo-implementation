# PROTOTYPE, throwaway: does a Switchyard preset escalate correctly through dsh? (#33)

**Verdict: yes.** Run on 2026-10-20 against the published dsh `0.2.1-rc.2`, OpenRouter preset `@preset/dsh-switchyard` (`nvidia/switchyard` with `deepseek/deepseek-v4.1-flash` and `anthropic/claude-opus-5.5`), through a local proxy that logs each response's model, routing decision and cost (`evidence-calls.jsonl`, no headers logged) and stops at $2. **Total spend: $0.13.**

| Check (from #33) | Result |
|---|---|
| Tool calls and streaming | Work. Parallel tool calls (2 per step) and streamed answers through a hand-declared `openai-completions` route |
| Easy turns stay cheap | "17 + 25" → DeepSeek V4.1 Flash, $0.0002 per run (2/2) |
| Hard turns escalate | Bug-hunt with file reads → Opus 5.5, $0.01–0.05 per run (2/2); a file-not-found loop stayed on Opus (2/2) |
| Reasoning replay survives model switches | One session, easy turn then hard turn: DeepSeek → Opus → DeepSeek → DeepSeek, all 200, correct answer (`resume-switch.sh`) |
| Which model answered, and the cost | The session log records `model=@preset/dsh-switchyard` plus `responseModel` (the real model) and `responseId` per step. Cost comes back in `usage.cost` |
| Anthropic prompt caching behind the preset id | Works with `compat.cacheControlFormat: anthropic`: 7.5k–8.5k cached prompt tokens on later steps |

## Surprises

- **A preset takes at most 3 models, counting `nvidia/switchyard` itself**, so it holds only two candidates. The three-model plan (with GPT-6.1 Sol in the middle) is rejected with 400. The middle candidate would never be chosen first anyway; it was only a fallback.
- **The preset dropped `plugins`**, so the `composite` algorithm can't be set. The router runs its default, `stage`, which scores tool results (errors push to Opus, successful steps back to DeepSeek) and asks a judge otherwise. `stage` worked well here. dsh can't send per-request `plugins`.
- **The judge (`google/gemini-3.5-flash-lite`) receives a truncated projection of the prompt.** Judge calls are billed as ordinary generations. Job-profile prompts only ever carry masked findings (ADR 0004), so nothing secret reaches it.
- Without a `session_id` (dsh can't send one), OpenRouter identifies the conversation by a hash of the first system and user messages. That was enough here.
- dsh's title LLM call was disabled (`session-title-llm`), so it didn't add an extra paid call per run.

## Run it

Needs the key in the Keychain as `dsh-demo.OPENROUTER_API_KEY` (ADR 0007) and the preset (`create-preset.sh`, run once).

```sh
npm install
./run.sh easy 2 && ./run.sh hard 2 && ./resume-switch.sh
```
