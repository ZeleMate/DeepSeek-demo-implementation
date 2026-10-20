#!/bin/sh
# PROTOTYPE, throwaway (#33). Usage: ./run.sh easy|hard [n]
# Reads the key from the Keychain into this process only (ADR 0007). Spend is capped by proxy.mjs (CAP_USD, default 2).
set -eu
cd "$(dirname "$0")"
kind=$1; n=${2:-1}
mkdir -p out
OPENROUTER_API_KEY=$(security find-generic-password -a "$USER" -s dsh-demo.OPENROUTER_API_KEY -w)
export OPENROUTER_API_KEY DSH_HOME="$PWD/out/dsh-home" DSH_TELEMETRY_DISABLED=1
node proxy.mjs & proxy=$!
trap 'kill $proxy' EXIT
sleep 0.5
case $kind in
  easy) task="What is 17 + 25? Reply with only the number." ;;
  hard) task="The file fixture/range.js has a bug described in fixture/range.test.md. Read both files, explain the root cause in one sentence, and show the corrected function. Do not edit any file." ;;
esac
i=1
while [ $i -le $n ]; do
  before=$(wc -l < out/calls.jsonl 2>/dev/null || echo 0)
  npx dsh headless --patch ./patch.yml "$task" > "out/$kind-$i.stdout" 2> "out/$kind-$i.stderr" || echo "dsh exited $?"
  echo "=== $kind #$i: steps (model that answered, tool calls, cost)"
  tail -n +"$((before + 1))" out/calls.jsonl | node -e 'let s=0;for(const l of require("fs").readFileSync(0,"utf8").trim().split("\n").filter(Boolean)){const r=JSON.parse(l);s+=r.cost;console.log(" ",r.status,r.model,"strategy="+(r.strategy??"-"),"finish="+r.finish,"tools="+r.toolCalls,"cached="+(r.cachedTokens??0),"$"+(r.cost??0).toFixed(5),r.error??"")}console.log("  run cost $"+s.toFixed(4))'
  echo "  answer: $(tail -c 300 "out/$kind-$i.stdout" | tr '\n' ' ')"
  i=$((i + 1))
done
node -e 'const f=require("fs");const s=f.existsSync("out/calls.jsonl")?f.readFileSync("out/calls.jsonl","utf8").trim().split("\n").filter(Boolean).reduce((a,l)=>a+(JSON.parse(l).cost??0),0):0;console.log("TOTAL spent so far $"+s.toFixed(4))'
