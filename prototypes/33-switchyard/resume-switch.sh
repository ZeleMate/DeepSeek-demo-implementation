#!/bin/sh
# PROTOTYPE, throwaway (#33): one session, two human turns. Turn 1 is easy (expect DeepSeek),
# turn 2 is a debugging task (expect Opus), so Opus must replay DeepSeek's turn, reasoning included.
set -eu
cd "$(dirname "$0")"
mkdir -p out
OPENROUTER_API_KEY=$(security find-generic-password -a "$USER" -s dsh-demo.OPENROUTER_API_KEY -w)
export OPENROUTER_API_KEY DSH_HOME="$PWD/out/dsh-home" DSH_TELEMETRY_DISABLED=1
node proxy.mjs & proxy=$!
trap 'kill $proxy' EXIT
sleep 0.5
before=$(wc -l < out/calls.jsonl)
npx dsh headless --patch ./patch.yml --json "What is 17 + 25? Reply with only the number." > out/resume-1.jsonl 2> out/resume-1.stderr
sid=$(grep -o '"session[A-Za-z]*":"session-[^"]*"' out/resume-1.jsonl | head -1 | sed 's/.*:"//; s/"$//')
[ -n "$sid" ] || sid=$(grep -o 'session-[A-Za-z0-9_-]*' out/resume-1.jsonl | head -1)
echo "session: $sid"
npx dsh headless --patch ./patch.yml --session-id "$sid" "Now: the file fixture/range.js has a bug described in fixture/range.test.md. Read both, explain the root cause in one sentence, and show the fix. Do not edit files." > out/resume-2.stdout 2> out/resume-2.stderr || echo "turn 2: dsh exited $?"
tail -n +"$((before + 1))" out/calls.jsonl | node -e 'let s=0;for(const l of require("fs").readFileSync(0,"utf8").trim().split("\n").filter(Boolean)){const r=JSON.parse(l);s+=r.cost;console.log(" ",r.status,r.model,"strategy="+(r.strategy??"-"),"finish="+r.finish,"tools="+r.toolCalls,"$"+(r.cost??0).toFixed(5),r.error??"")}console.log("  cost $"+s.toFixed(4))'
echo "turn 2 answer: $(tail -c 250 out/resume-2.stdout | tr '\n' ' ')"
grep -i "error\|invalid\|signature" out/resume-2.stderr | head -5 || true
