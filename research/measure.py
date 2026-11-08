"""Measure local Ollama models: speed, memory, 16k context, tool calling."""
import json, os, subprocess, sys, time, urllib.parse, urllib.request

HOST = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434")
if urllib.parse.urlsplit(HOST).scheme not in ("http", "https"):
    sys.exit("OLLAMA_URL must be an http or https URL")
CTX = 16384


def post(path, body, timeout=900):
    req = urllib.request.Request(HOST + path, json.dumps(body).encode(), {"Content-Type": "application/json"})
    # HOST's scheme is checked above, so no file:// URL gets here.
    with urllib.request.urlopen(req, timeout=timeout) as r:  # nosemgrep: python.lang.security.audit.dynamic-urllib-use-detected.dynamic-urllib-use-detected
        return json.loads(r.read())


def free_pct():
    out = subprocess.run(["memory_pressure"], capture_output=True, text=True).stdout
    return int(out.strip().splitlines()[-1].split(":")[1].strip().rstrip("%"))


def swap_used():
    out = subprocess.run(["sysctl", "-n", "vm.swapusage"], capture_output=True, text=True).stdout
    return out.split("used = ")[1].split()[0]


def loaded_size(model):
    # HOST's scheme is checked above, so no file:// URL gets here.
    for m in json.loads(urllib.request.urlopen(HOST + "/api/ps").read())["models"]:  # nosemgrep: python.lang.security.audit.dynamic-urllib-use-detected.dynamic-urllib-use-detected
        if m["name"] == model:
            return round(m["size"] / 1e9, 2), round(m.get("size_vram", 0) / 1e9, 2)
    return None, None


TOOLS = [
    {"type": "function", "function": {"name": "web_fetch", "description": "Fetch a URL and return its text.",
        "parameters": {"type": "object", "properties": {"url": {"type": "string"}}, "required": ["url"]}}},
    {"type": "function", "function": {"name": "read_file", "description": "Read a file from the workspace.",
        "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}},
    {"type": "function", "function": {"name": "scan_secrets", "description": "Run gitleaks on a repository path. mode is 'git' (full history) or 'dir' (files on disk).",
        "parameters": {"type": "object", "properties": {"repo": {"type": "string"}, "mode": {"type": "string", "enum": ["git", "dir"]}}, "required": ["repo", "mode"]}}},
    {"type": "function", "function": {"name": "calculator", "description": "Evaluate an arithmetic expression.",
        "parameters": {"type": "object", "properties": {"expression": {"type": "string"}}, "required": ["expression"]}}},
    {"type": "function", "function": {"name": "web_search", "description": "Search the web.",
        "parameters": {"type": "object", "properties": {"query": {"type": "string"}, "max_results": {"type": "integer"}}, "required": ["query"]}}},
]

# (prompt, expected tool or None, arg checks: {arg: substring})
TASKS = [
    ("Fetch https://example.com/status and tell me what it says.", "web_fetch", {"url": "example.com/status"}),
    ("What's in the file src/config.ts?", "read_file", {"path": "src/config.ts"}),
    ("Scan the repo at ~/code/api for leaked secrets across its whole git history.", "scan_secrets", {"repo": "code/api", "mode": "git"}),
    ("Check only the current files in ./service for secrets, not the history.", "scan_secrets", {"repo": "service", "mode": "dir"}),
    ("What is 1234 * 5678?", "calculator", {"expression": "1234"}),
    ("Search the web for 'OWASP agentic top 10' and give me 3 results.", "web_search", {"query": "owasp"}),
    ("Say hello in Hungarian. Don't use any tools.", None, {}),
    ("Read README.md and then summarise it.", "read_file", {"path": "README.md"}),
    ("Look up the latest gitleaks release on the web.", "web_search", {"query": "gitleaks"}),
    ("Is 17 a prime number? Answer directly.", None, {}),
]


def tool_test(model):
    passed, detail = 0, []
    for prompt, want, checks in TASKS:
        try:
            r = post("/api/chat", {"model": model, "stream": False, "think": False, "tools": TOOLS,
                                   "options": {"num_ctx": CTX, "temperature": 0},
                                   "messages": [{"role": "user", "content": prompt}]}, 300)
            calls = r["message"].get("tool_calls") or []
        except Exception as e:  # noqa: BLE001
            detail.append(f"ERR {e}")
            continue
        if want is None:
            ok = not calls
            got = calls[0]["function"]["name"] if calls else "-"
        else:
            ok = bool(calls) and calls[0]["function"]["name"] == want
            args = calls[0]["function"].get("arguments", {}) if calls else {}
            if ok:
                for k, v in checks.items():
                    if v.lower() not in str(args.get(k, "")).lower():
                        ok = False
            got = f'{calls[0]["function"]["name"]}({json.dumps(args)})' if calls else "no call"
        passed += ok
        detail.append(("PASS " if ok else "FAIL ") + f"{want} <- {got}"[:140])
    return passed, detail


def long_prompt(tokens_target=12000):
    para = ("The harness logs every tool call, checks egress against an allowlist, "
            "and wraps untrusted content before the model sees it. ")
    n = tokens_target // 25
    return (para * n) + "\n\nIn one sentence: what does the harness do with untrusted content?"


def measure(model):
    res = {"model": model}
    post("/api/generate", {"model": model, "keep_alive": 0}, 60)  # unload
    time.sleep(2)
    res["free_before_pct"] = free_pct()
    t0 = time.time()
    r = post("/api/generate", {"model": model, "stream": False, "think": False, "keep_alive": "5m",
                               "prompt": "Write three sentences about why secrets in git history are dangerous.",
                               "options": {"num_ctx": CTX, "temperature": 0, "num_predict": 200}})
    res["cold_load_s"] = round(r["load_duration"] / 1e9, 1)
    res["first_call_wall_s"] = round(time.time() - t0, 1)
    res["decode_tok_s"] = round(r["eval_count"] / (r["eval_duration"] / 1e9), 1)
    r = post("/api/generate", {"model": model, "stream": False, "think": False, "keep_alive": "5m",
                               "prompt": long_prompt(), "options": {"num_ctx": CTX, "temperature": 0, "num_predict": 60}})
    res["long_prompt_tokens"] = r["prompt_eval_count"]
    res["prefill_tok_s"] = round(r["prompt_eval_count"] / (r["prompt_eval_duration"] / 1e9), 1)
    res["long_ttft_s"] = round((r["prompt_eval_duration"] + r["load_duration"]) / 1e9, 1)
    res["long_answer"] = r["response"].strip().replace("\n", " ")[:160]
    res["loaded_GB"], res["vram_GB"] = loaded_size(model)
    res["free_loaded_pct"] = free_pct()
    res["swap_used"] = swap_used()
    t0 = time.time()
    res["tools_passed"], res["tools_detail"] = tool_test(model)
    res["tools_wall_s"] = round(time.time() - t0, 1)
    post("/api/generate", {"model": model, "keep_alive": 0}, 60)
    return res


if __name__ == "__main__":
    out = []
    for m in sys.argv[1:]:
        print(f"== {m}", flush=True)
        try:
            r = measure(m)
        except Exception as e:  # noqa: BLE001
            r = {"model": m, "error": str(e)}
        print(json.dumps(r, ensure_ascii=False), flush=True)
        out.append(r)
    json.dump(out, open(os.environ.get("RESULTS", sys.argv[0].replace("measure.py", "results.json")), "w"), indent=1, ensure_ascii=False)
