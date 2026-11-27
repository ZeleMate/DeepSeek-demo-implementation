// Parses dsh headless `--json` output (NDJSON) into one attempt. The stream is model-driven
// output, so every line is validated before use (docs/agent-policy.md). Event shapes follow
// dsh-headless's src/json-stream.ts at the pinned dsh (0.2.2-rc.3).
import { z } from 'zod'

const usage = z.object({
  inputTokens: z.number().nonnegative(),
  outputTokens: z.number().nonnegative(),
  totalTokens: z.number().nonnegative(),
  cacheReadTokens: z.number().nonnegative().optional(),
})

// `reason` is dsh's durable turn reason, such as { kind: 'completed' } or { kind: 'aborted', ... }.
const reason = z.object({ kind: z.string() }).loose()

const event = z.discriminatedUnion('type', [
  z.object({ type: z.literal('session'), sessionId: z.string(), cwd: z.string() }),
  z.object({
    type: z.literal('status'),
    phase: z.string(),
    turn: z.number().optional(),
    step: z.number().optional(),
    usage: usage.optional(),
    reason: reason.optional(),
  }),
  z.object({ type: z.literal('text'), text: z.string() }),
  z.object({ type: z.literal('thinking'), text: z.string() }),
  z.object({ type: z.literal('tool_call'), callId: z.string(), tool: z.string(), input: z.unknown() }),
  z.object({
    type: z.literal('tool_result'),
    callId: z.string(),
    status: z.enum(['completed', 'error']),
    result: z.string(),
    error: z.object({ name: z.string(), code: z.string() }).loose().optional(),
  }),
  z.object({ type: z.literal('final'), sessionId: z.string(), reason: reason.nullable(), text: z.string() }),
  z.object({ type: z.literal('error'), message: z.string() }).loose(),
])

export interface ToolCall {
  callId: string
  tool: string
  input: unknown
  status?: 'completed' | 'error'
  result?: string
  errorCode?: string
}

export interface Attempt {
  sessionId?: string
  cwd?: string
  // The final answer, or undefined when the stream ended without a `final` event.
  output?: string
  // The durable turn reason's kind, e.g. 'completed' or 'aborted'; null when the turn never ended.
  reason?: string | null
  // Every committed assistant text and reasoning block, in order: the model stream (ADR 0011).
  texts: string[]
  thinking: string[]
  toolCalls: ToolCall[]
  tokens: { prompt: number; completion: number; total: number }
  // `error` events, plus lines that were not valid JSON or not a known event.
  errors: string[]
}

export function parseStream(ndjson: string): Attempt {
  const attempt: Attempt = {
    texts: [],
    thinking: [],
    toolCalls: [],
    tokens: { prompt: 0, completion: 0, total: 0 },
    errors: [],
  }
  const calls = new Map<string, ToolCall>()

  for (const line of ndjson.split('\n')) {
    if (line.trim() === '') continue
    let json: unknown
    try {
      json = JSON.parse(line)
    } catch {
      attempt.errors.push(`not JSON: ${line.slice(0, 200)}`)
      continue
    }
    const parsed = event.safeParse(json)
    if (!parsed.success) {
      attempt.errors.push(`unknown event: ${line.slice(0, 200)}`)
      continue
    }
    const e = parsed.data
    switch (e.type) {
      case 'session':
        attempt.sessionId = e.sessionId
        attempt.cwd = e.cwd
        break
      case 'status':
        if (e.phase === 'step_end' && e.usage !== undefined) {
          attempt.tokens.prompt += e.usage.inputTokens + (e.usage.cacheReadTokens ?? 0)
          attempt.tokens.completion += e.usage.outputTokens
          attempt.tokens.total += e.usage.totalTokens
        }
        break
      case 'text':
        attempt.texts.push(e.text)
        break
      case 'thinking':
        attempt.thinking.push(e.text)
        break
      case 'tool_call': {
        const call: ToolCall = { callId: e.callId, tool: e.tool, input: e.input }
        calls.set(e.callId, call)
        attempt.toolCalls.push(call)
        break
      }
      case 'tool_result': {
        const call = calls.get(e.callId)
        if (call === undefined) {
          attempt.errors.push(`tool_result for unknown call ${e.callId}`)
          break
        }
        call.status = e.status
        call.result = e.result
        if (e.error !== undefined) call.errorCode = e.error.code
        break
      }
      case 'final':
        attempt.sessionId = e.sessionId
        attempt.output = e.text
        attempt.reason = e.reason === null ? null : e.reason.kind
        break
      case 'error':
        attempt.errors.push(`error event: ${e.message}`)
        break
    }
  }
  return attempt
}
