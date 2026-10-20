#!/bin/sh
# PROTOTYPE (#33). YOU run this: it reads your key from the Keychain and creates the preset
# `dsh-switchyard` on your OpenRouter account, then prints what OpenRouter stored. It prints no key.
set -eu
OPENROUTER_API_KEY=$(security find-generic-password -a "$USER" -s dsh-demo.OPENROUTER_API_KEY -w)
export OPENROUTER_API_KEY
curl -sS https://openrouter.ai/api/v1/presets/dsh-switchyard/chat/completions \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" -H "Content-Type: application/json" \
  -d '{"model":"nvidia/switchyard",
       "models":["deepseek/deepseek-v4.1-flash","anthropic/claude-opus-5.5"],
       "plugins":[{"id":"switchyard-router","algorithm":"composite"}],
       "messages":[{"role":"user","content":"x"}]}' | head -c 600; echo
echo "--- stored preset:"
curl -sS https://openrouter.ai/api/v1/presets/dsh-switchyard -H "Authorization: Bearer $OPENROUTER_API_KEY" | head -c 2000; echo
