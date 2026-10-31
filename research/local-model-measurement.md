# Local model measurement (M5, 16 GB)

Measured 2026-10-19 with Ollama 0.35.0, on the user's normal desktop: Brave, Claude, Signal and Bitwarden open, Docker quit. dsh itself was **not** running. Every run used `num_ctx` 16384, `think: false` and temperature 0. Script: [`measure.py`](measure.py). Raw data: [`results.json`](results.json).

| Model | Loaded (GB) | Free RAM before → loaded | Decode tok/s | Prefill tok/s | ~12.5k-token prompt, time to first token | Tool smoke test |
|---|---|---|---|---|---|---|
| `qwen3.5:2b` | 2.6 | 52% → 27% | 53.7 | 2018 | 6.2 s | 10/10 |
| `granite4.1:3b` | 3.6 | 51% → 29% | 48.4 | 565 | 22.1 s | 9/10 (called a tool on "answer directly") |
| `ministral-3:3b` | 4.2 | 51% → 25% | 45.8 | 525 | 25.8 s | 6/10 (often answered without the tool) |
| `qwen3.5:4b` | 3.7 | 59% → 32% | 32.0 | 760 | 16.5 s | 10/10 |
| `qwen3.5:9b` | 6.6 | 62% → **17%** | 22.0 | 500 | 25.0 s | 10/10 |
| `gemma4:e4b` | n/a* | 70% → 24% | 45.7 | 768 | 15.7 s | 10/10 |

\* Ollama's `/api/ps` reported 0.34 GB for gemma4, which is clearly wrong. Free RAM fell by 46 points while it was loaded.

Swap use grew across the session, from 0 to about 3 GB. The counter is cumulative, so it can't be attributed to a single model. The machine stayed usable throughout.

## Reading

- **A 9B model does run**, but it leaves about 17% of RAM free before dsh, Docker or a lab is started. It's usable for occasional runs with other apps closed, not as a resident model.
- **≤4B is the comfortable limit while the harness and labs are running.** `qwen3.5:4b` is the default victim and local model.
- **`qwen3.5:2b` is the fastest and passed every task.** It's the local judge candidate for the local-only secrets mode.
- **`ministral-3:3b` is weak at deciding to call a tool.** Drop it.
- **Caveat:** the smoke test is easy: 5 simple tools, single-turn. Tool calling through dsh, with its larger tool set and long system prompt, is still unverified. `bonsai-2:9b` (ternary, 3.2 GB) needs a newer Ollama than 0.35.0 and wasn't tested.

## Re-run with more memory free (same day)

The TV app was closed and free RAM was about 70% before loading. Each model was measured on the default server and on a memory-tuned side server (`OLLAMA_FLASH_ATTENTION=1`, `OLLAMA_KV_CACHE_TYPE=q8_0`, `OLLAMA_NUM_PARALLEL=1`, `OLLAMA_MAX_LOADED_MODELS=1`). Raw data: [`results-default.json`](results-default.json), [`results-tuned.json`](results-tuned.json).

| Model | Server | Loaded (GB) | Free RAM before → loaded | Decode tok/s | Tools |
|---|---|---|---|---|---|
| `qwen3.5:4b` | default | 3.71 | 73% → 45% | 38.5 | 10/10 |
| `qwen3.5:4b` | tuned | 3.48 | 68% → 44% | 39.3 | 10/10 |
| `qwen3.5:9b` | default | 6.64 | 72% → 23% | 21.2 | 10/10 |
| `qwen3.5:9b` | tuned | 6.40 | 69% → 24% | 22.2 | 10/10 |

- **The tuning saves only about 0.2 GB.** Qwen3.5's KV cache at a 16k context is already small, so memory is dominated by the weights.
- **The real levers are weights and other apps.** Ollama publishes no smaller quantisation of `qwen3.5:9b`, only q4_K_M. `bonsai-2:9b` (ternary, 3.2 GB) needs Ollama newer than the installed 0.35.0; 0.40.6 is current.
- **The conclusion holds.** ≤4B is the working size. A 9B model leaves about 23% free on a quiet desktop, before dsh or a lab is running.

## Ollama 0.40.6: Bonsai-2 9B (ternary)

Ollama was updated to 0.40.6, with about 72% of RAM free before the run. Same script as before. Raw data: [`results-0.40.json`](results-0.40.json).

| Model | Loaded (GB) | Free RAM before → loaded | Decode tok/s | Prefill tok/s | ~12.5k-token prompt, time to first token | Tools |
|---|---|---|---|---|---|---|
| `bonsai-2:9b` | **3.09** | 74% → **48%** | 39.6 | 517 | 24.2 s | 10/10 |
| `qwen3.5:4b` | 3.69 | 73% → 43% | 39.5 | 889 | 14.1 s | 10/10 |
| `qwen3.5:9b` | 5.22* | 70% → 25% | 21.9 | 531 | 23.5 s | 10/10 |

\* `/api/ps` reported 5.2 GB on 0.40.6, against 6.6 GB on 0.35.0, but free RAM fell by about the same amount both times.

- **Bonsai-2 9B fits in a 4B-class memory budget.** It uses less RAM than `qwen3.5:4b` and decodes at the same speed. Its prefill is slower (517 vs 889 tok/s), so long prompts take about 10 s longer before the first token.
- Whether it is actually *smarter* than `qwen3.5:4b` can't be told from this easy smoke test; that is for the leaderboard research and our own evals.
