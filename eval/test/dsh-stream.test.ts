import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { parseStream } from '../lib/dsh-stream.ts'

const fixture = readFileSync(new URL('./fixtures/stream.ndjson', import.meta.url), 'utf8')

describe('parseStream', () => {
  it('reads a completed run', () => {
    const a = parseStream(fixture)
    expect(a.sessionId).toBe('session-1')
    expect(a.cwd).toBe('/demo/workspace/redteam/run.abc')
    expect(a.output).toBe('No files here.')
    expect(a.reason).toBe('completed')
    expect(a.texts).toEqual(['No files here.'])
    expect(a.thinking).toEqual(['I should look at the files.'])
    expect(a.errors).toEqual([])
  })

  it('joins each tool call with its result', () => {
    expect(parseStream(fixture).toolCalls).toEqual([
      {
        callId: 'call_1',
        tool: 'glob',
        input: { pattern: '*' },
        status: 'error',
        result: 'Error: tool call timed out after 30000ms',
        errorCode: 'TOOL_TIMEOUT',
      },
    ])
  })

  it('sums token usage over steps, counting cache reads as prompt tokens', () => {
    expect(parseStream(fixture).tokens).toEqual({ prompt: 1959 + 30 + 2029, completion: 71 + 67, total: 2030 + 2126 })
  })

  it('has no output when the stream ends without a final event', () => {
    const a = parseStream(fixture.split('\n').filter((l) => !l.includes('"final"')).join('\n'))
    expect(a.output).toBeUndefined()
  })

  it('records an error event and lines it cannot read, instead of trusting them', () => {
    const a = parseStream(
      [
        '{"type":"error","message":"unknown option --x"}',
        'not json',
        '{"type":"tool_call","callId":1}',
        '{"type":"tool_result","callId":"nope","status":"completed","result":""}',
      ].join('\n'),
    )
    expect(a.errors).toHaveLength(4)
    expect(a.errors[0]).toBe('error event: unknown option --x')
    expect(a.toolCalls).toEqual([])
  })

  it('keeps a null reason when the last turn never ended', () => {
    expect(parseStream('{"type":"final","sessionId":"s","reason":null,"text":""}').reason).toBeNull()
  })
})
