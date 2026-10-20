// PROTOTYPE, throwaway (#33): forwards to OpenRouter and logs, per response, the generation id,
// the model that answered, usage and cost. Never logs headers (the API key travels in Authorization).
// Hard stop: once the cost in out/calls.jsonl reaches CAP_USD, further requests get HTTP 402 locally.
import http from 'node:http'
import https from 'node:https'
import { appendFileSync, existsSync, readFileSync } from 'node:fs'
const PORT = Number(process.env.PORT ?? 18080)
const CAP = Number(process.env.CAP_USD ?? 2)
const LOG = process.env.CALLS_LOG ?? 'out/calls.jsonl'
const spent = () => existsSync(LOG) ? readFileSync(LOG, 'utf8').trim().split('\n').filter(Boolean).reduce((s, l) => s + (JSON.parse(l).cost ?? 0), 0) : 0

http.createServer((req, res) => {
  const chunks = []
  req.on('data', c => chunks.push(c))
  req.on('end', () => {
    if (spent() >= CAP) { res.writeHead(402, { 'content-type': 'application/json' }); res.end(JSON.stringify({ error: { message: `prototype cap of $${CAP} reached` } })); return }
    let body = Buffer.concat(chunks)
    let requested
    try { const j = JSON.parse(body.toString()); requested = j.model; j.usage = { include: true }; body = Buffer.from(JSON.stringify(j)) } catch {}
    const headers = { ...req.headers, host: 'openrouter.ai', 'content-length': String(body.length), 'x-openrouter-metadata': 'enabled' }
    const up = https.request({ host: 'openrouter.ai', path: req.url, method: req.method, headers }, r => {
      res.writeHead(r.statusCode, r.headers)
      let text = ''
      r.on('data', c => { text += c; res.write(c) })
      r.on('end', () => {
        res.end()
        let id, model, usage, finish, toolCalls = 0, error, router
        const objs = text.includes('data:') ? text.split('\n').filter(l => l.startsWith('data:') && !l.includes('[DONE]')).map(l => { try { return JSON.parse(l.slice(5)) } catch { return null } }).filter(Boolean) : [(() => { try { return JSON.parse(text) } catch { return {} } })()]
        for (const o of objs) {
          id ??= o.id; model = o.model ?? model; usage = o.usage ?? usage; error ??= o.error?.message
          const step = o.openrouter_metadata?.pipeline?.find?.(p => p.name === 'switchyard-router'); if (step) router = step.data
          for (const ch of o.choices ?? []) { finish = ch.finish_reason ?? finish; toolCalls += (ch.delta?.tool_calls ?? ch.message?.tool_calls ?? []).filter(t => t.id).length }
        }
        appendFileSync(LOG, JSON.stringify({ t: new Date().toISOString(), status: r.statusCode, requested, id, model, finish, toolCalls, promptTokens: usage?.prompt_tokens, completionTokens: usage?.completion_tokens, cachedTokens: usage?.prompt_tokens_details?.cached_tokens, cost: usage?.cost ?? 0, error, strategy: router?.strategy, resolvedTo: router?.resolved_to, judgeMs: router?.judge_ms }) + '\n')
      })
    })
    up.on('error', e => { res.writeHead(502); res.end(String(e)) })
    up.end(body)
  })
}).listen(PORT, '127.0.0.1')
