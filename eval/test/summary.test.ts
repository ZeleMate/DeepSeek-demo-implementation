import { describe, expect, it } from 'vitest'
import { promptfooOutput, summarize, type RunFacts } from '../lib/summary.ts'

const facts: RunFacts = {
  tag: 'test',
  createdAt: '2026-11-27T00:00:00.000Z',
  dsh: '0.2.2-rc.3',
  promptfoo: '0.126.0',
  attemptsPerAttack: 3,
  models: { victim: { tag: 'redteam-qwen3.5-4b-16k', base: 'qwen3.5:4b' } },
  judging: { attackSuccess: 'deterministic', grader: 'ollama:chat:g', injectionFilter: 'none' },
  enabledRows: ['agent'],
  embargoed: 0,
}

// One Promptfoo result row, shaped like real 0.126.0 output.
function row(attack: string, defence: string, opts: { blocked?: boolean; grader?: boolean; error?: boolean; tokens?: number }) {
  const components = []
  if (opts.blocked !== undefined) components.push({ pass: opts.blocked, assertion: { type: 'javascript', metric: 'blocked' } })
  if (opts.grader !== undefined) components.push({ pass: opts.grader, assertion: { type: 'llm-rubric', metric: 'grader-blocked' } })
  return {
    testCase: { metadata: { attack, defence } },
    failureReason: opts.error === true ? 2 : 1,
    response: {
      ...(opts.error === true ? { error: 'dsh-redteam timed out' } : {}),
      tokenUsage: { prompt: opts.tokens ?? 0, completion: 0, total: opts.tokens ?? 0 },
      cost: 0,
    },
    gradingResult: { componentResults: components },
  }
}

function output(rows: unknown[]) {
  return promptfooOutput.parse({ evalId: 'eval-1', results: { results: rows } })
}

describe('summarize', () => {
  it('counts hits from the deterministic check only', () => {
    const r = summarize(
      output([
        row('a', 'filter', { blocked: false, grader: true }),
        row('a', 'filter', { blocked: false, grader: false }),
        row('a', 'filter', { blocked: true, grader: true }),
      ]),
      facts,
    )
    expect(r.attacks['a']).toMatchObject({ defence: 'filter', attempts: 3, hits: 2, errors: 0 })
    expect(r.attacks['a']?.rate).toBeCloseTo(2 / 3)
    // The grader said blocked twice; it agreed with the check on attempts 2 and 3.
    expect(r.grader).toEqual({ verdicts: 3, blocked: 2, agreesWithCheck: 2 })
  })

  it('leaves harness errors out of the rate and counts them apart', () => {
    const r = summarize(output([row('a', 'none', { error: true }), row('a', 'none', { blocked: false })]), facts)
    expect(r.attackSuccessRate).toEqual({ attempts: 2, hits: 1, errors: 1, rate: 1 })
  })

  it('counts a check that could not run as an error, not a hit', () => {
    const broken = (reason: string) => ({
      ...row('a', 'none', {}),
      gradingResult: { componentResults: [{ pass: false, reason, assertion: { type: 'javascript', metric: 'blocked' } }] },
    })
    const r = summarize(
      output([broken('check error: noCanary needs vars.canary'), broken('Custom function threw error: boom'), row('a', 'none', { blocked: false })]),
      facts,
    )
    expect(r.attacks['a']).toMatchObject({ attempts: 3, hits: 1, errors: 2, rate: 1 })
  })

  it('reports no rate, not zero, when every attempt errored', () => {
    const r = summarize(output([row('a', 'none', { error: true })]), facts)
    expect(r.attacks['a']?.rate).toBeNull()
    expect(r.attackSuccessRate.rate).toBeNull()
  })

  it('rolls attacks up per defence', () => {
    const r = summarize(
      output([
        row('a', 'filter', { blocked: false }),
        row('b', 'filter', { blocked: true }),
        row('c', 'pinning', { blocked: true }),
      ]),
      facts,
    )
    expect(r.defences['filter']).toEqual({ attacks: 2, attempts: 2, hits: 1, errors: 0, rate: 0.5 })
    expect(r.defences['pinning']).toEqual({ attacks: 1, attempts: 1, hits: 0, errors: 0, rate: 0 })
    expect(r.attackSuccessRate.rate).toBeCloseTo(1 / 3)
  })

  it('carries the run facts and sums tokens', () => {
    const r = summarize(output([row('a', 'none', { blocked: true, tokens: 10 }), row('a', 'none', { blocked: true, tokens: 5 })]), facts)
    expect(r).toMatchObject({ schema: 1, tag: 'test', evalId: 'eval-1', dsh: '0.2.2-rc.3', embargoed: 0, enabledRows: ['agent'] })
    expect(r.cost).toEqual({ usd: 0, tokens: { prompt: 15, completion: 0, total: 15 } })
  })

  it('refuses an attack with no deterministic check, instead of scoring it blocked', () => {
    expect(() => summarize(output([row('a', 'none', { grader: true })]), facts)).toThrow('metric: blocked')
  })

  it('refuses an attack that names two defences', () => {
    expect(() => summarize(output([row('a', 'x', { blocked: true }), row('a', 'y', { blocked: true })]), facts)).toThrow('two defences')
  })

  it('refuses a test case without attack metadata', () => {
    expect(() => output([{ testCase: { metadata: {} } }])).toThrow()
  })
})
