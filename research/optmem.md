# What is OptMem?

Research for issue #3. Checked 2026-10-18 against the repo itself (GitHub API, `main` at `1fb164c`). Every claim cites the file or API response it comes from.

## Answer

**Yes, it exists as linked, and it is agent memory.** [VictorTaelin/OptMem](https://github.com/VictorTaelin/OptMem) is described as "Permanent memory for AI agents. A 426-token prompt, a script, plug and play." (repo description, README). It is one dependency-free Python 3 CLI (`memo`) plus a block of instructions you paste into `AGENTS.md`/`CLAUDE.md`. The agent remembers by running shell commands: it appends one-line notes to an append-only log and writes its own summaries into a binary tree. The tool itself never calls a model. **There is no license** (GitHub reports `license: null`, and issue #8 "license?" is open with no answer), so legally we cannot copy its code. For own-harness, the best route is to **re-implement the idea** behind a TypeScript `Memory` interface. That is roughly a few hundred lines of file I/O, and it fits a learning-first harness well. Shelling out to the Python script is possible too.

## Facts

| | |
|---|---|
| Language | Python 3, one file `memo` (~31 KB, ~860 lines), no dependencies. GitHub language: Python. The `anim/` folder is a JS explainer animation only. [tree of `main`] |
| Created | 2026-07-25. Last push 2026-07-31. 40 commits, nearly all on 07-25 to 07-26. [commits API] |
| Popularity | ~2.2k stars, 138 forks, 16 open issues (2026-10-18). [repos API] |
| Releases/tags | None. You install it with `curl … install.sh \| sh`, which pulls `main` into `~/.optmem/memo`. [install.sh, README] |
| License | **None** (`license: null`). Issue #8 "license?" is still open. A commenter notes it "can[not] legally be used elsewhere without a license." [license API, issue #8] |
| Tests | `test.py` checks invariants over a synthetic 5,000-memory life, using a fake compressor. [test.py header] |
| Platforms | POSIX `fcntl` lock. Native Windows works through a `msvcrt` fallback (PR #2). [memo `locked()`, WINDOWS.md] |

**Maturity:** a young, single-author project with a burst of commits. It looks carefully engineered: crash repair of torn records, locking, and UTF-8 byte limits (memo source, commit messages). But it is unversioned, has been untouched upstream since July, and has open correctness issues (#10/#11 torn TREE records, #12/#13 line separators, #21 install race). Several community ports exist, including TS ones, e.g. `krzyzanowskim/pi-optmem` (`index.ts`, `memo.ts`, also no license) and `rarf/optmem-hermes-plugin` (search API).

## How it works

### Integration model

All of the integration is a prompt. `memo init` prints a `## Memory` block that tells the agent to (README "The prompt"; `TEMPLATE` in memo):

- run `memo wake` before any other tool call, every session, and do what it prints;
- run `memo note "<1 line, ≤280 bytes>"` whenever it learns something new, important, and lasting;
- if `note` asks for a compression, do it before the next action;
- use `memo recall <regex>` / `memo zoom <a-b>` to find old memories;
- never let subagents run `memo`.

"Nothing ever runs in the background" (README). **The model that is using the memory does the summarisation.** `note` and `wake` print a "Compress memories #lo-hi into one line…" prompt, and the agent replies with `memo nap lo-hi "<line>"` (`nap_prompt`, `cmd_note`, `cmd_nap`).

### Commands (README table, `main()` in memo)

`init`, `wake [part [T]]`, `note "..."`, `nap [lo-hi "..."]`, `recall <regex>`, `zoom <lo>-<hi>`, `forget <lo>-<hi>`, `config [NAME=N]`, `import <file>` (bulk bootstrap).

### Storage model (memo source, README "Files")

```text
~/.optmem/memory/   (or $MEMORY_DIR)
  LOG.txt   append-only, fixed 320-byte records: "#<id> <YYYY-MM-DD> <text>"
  TREE/<s>  one file per block size s=2,4,8…; fixed 288-byte records
  config    knobs: WAKE_LINES=96, ENTRY_CHARS=280, PART_CHARS=20000, PART_LINES=500
  .lock
```

- **Position is identity.** Memory *i* sits at byte `i*320` of LOG.txt. Block `[k*s,(k+1)*s)` sits at `k*288` of `TREE/s`. Every lookup is one seek, with no index. The README claims `wake` takes 0.03 s at a million memories (608 MB).
- **Binary merge tree.** A block is an aligned power-of-two range of memories, summarised into one line. Blocks of ≤16 memories are summarised from the raw log. Bigger blocks are summarised from their two child summaries (`RAW_MAX`, `nap_prompt`). Blocks are built strictly in order, smallest first (`pending`).
- **Decay-with-age wake.** `cover(T, WAKE_LINES)` tiles all memories with at most 96 blocks: recent ones verbatim, older ones collapsed into ever-larger summaries. A binary search over an "age vs. size" factor sets the boundary, and leftover budget goes to the present. Output is split into parts of ≤20 KB, because harnesses truncate long tool output (comment in memo: Claude Code cuts at 30k chars, pi at 50 KB, Codex at 10k tokens).
- **Recall** is a streamed, case-insensitive regex scan over the whole log, capped to the newest matches that fit 20 KB (`cmd_recall`). There are no embeddings and no vector store.
- **The tree is a cache.** `forget` truncates a node and everything built from it, and it is rebuilt from LOG.txt. The log is never edited.
- **One identity per machine.** Parallel sessions all write to the same store, and only `init` may create it (`store()` comment).

Known costs are raised in the issues. With a two-part wake, the session starts with extra inference rounds just to read memory (#6: one user moved `wake` into a Claude Code `SessionStart` hook instead). Byte limits hurt non-Latin scripts (#6, #7). The prompt encourages transient status notes (#14).

## Can it sit behind a memory interface in a TS harness?

| Route | Fit |
|---|---|
| **Native TS import** | No. It is a Python CLI, not a library, and has no JS package. |
| **Subprocess** (`child_process.execFile('python3', [memo, 'note', …])`) | Works. Expose the CLI as agent tools, or call `wake` in harness code and inject the output. Cost: a python3 runtime dependency, text-parsing of its outputs, no license for redistribution (installing it from upstream is fine for personal use), and an unmaintained upstream. |
| **Service** | Nothing to talk to. It has no server. We would have to wrap it ourselves. |
| **FFI** | Not applicable. |
| **Re-implement the idea** | **Recommended.** The algorithm is small and fully described above: fixed-width append-only log, power-of-two summary tree, age-decayed cover, regex recall, model-written summaries. A TS version behind our own `Memory` interface (`wake()`, `note()`, `pendingCompressions()`, `nap()`, `recall()`, `zoom()`) is a good learning exercise, needs no Python, and avoids the license problem, because ideas are not copyrighted and only the code is. Our harness owns the loop, so it can inject `wake` at session start (as #6 suggests) instead of spending tool-call rounds. It can also run the compressions through its own OpenRouter model call instead of trusting the agent to obey the prompt. |

What we would be choosing: OptMem is a **personal, single-user, chronological "life log" memory** with lossy summaries and exact regex recall. It has no semantic or vector search, no per-project scoping (#9 is open), and no multi-tenant design. That suits a personal research assistant. If the harness later needs semantic retrieval, add it beside OptMem, not inside it.

## Sources

- Repo metadata: `gh api repos/VictorTaelin/OptMem` (description, language, stars, `license: null`, dates)
- `README.md`, `install.sh`, `WINDOWS.md`, `memo`, `test.py` on `main` @ `1fb164c`
- Commit history: `gh api repos/VictorTaelin/OptMem/commits`
- Issues #6, #7, #8, #9, #10–#14, #21 on VictorTaelin/OptMem
- Map issue ZeleMate/own-harness#1 "Original brief": "Memory: OptMem"
