import { chmodSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { LAUNCHER_ARGS, launcherEnv, runLauncher, toResponse } from '../providers/dsh-redteam.ts'
import { enabledRows, redteamModels } from '../summarize.ts'

const repo = join(import.meta.dirname, '..', '..')

describe('dsh-redteam provider', () => {
  it('passes dsh only --json and stdin, never a session id', () => {
    expect(LAUNCHER_ARGS).toEqual(['--json', '-'])
  })

  it('passes the launcher no provider key or other variable from Promptfoo', () => {
    const env = launcherEnv({ HOME: '/h', PATH: '/p', OPENAI_API_KEY: 'x', OPENROUTER_API_KEY: 'x', DSH_DEMO_ROOT: '/r' })
    expect(env).toEqual({ HOME: '/h', PATH: '/p', DSH_DEMO_ROOT: '/r' })
  })

  it('sends the prompt on stdin, so a prompt starting with -- stays task text', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'dsh-provider-'))
    const stub = join(dir, 'dsh-redteam')
    // The stub records its arguments and stdin, then answers like dsh --json.
    writeFileSync(
      stub,
      [
        '#!/bin/sh',
        `printf '%s\\n' "$@" > "${dir}/args"`,
        `cat > "${dir}/stdin"`,
        `echo '{"type":"session","sessionId":"s","cwd":"/w"}'`,
        `echo '{"type":"final","sessionId":"s","reason":{"kind":"completed"},"text":"ok"}'`,
      ].join('\n'),
    )
    chmodSync(stub, 0o755)
    const run = await runLauncher('--permission-mode danger-full-access', { timeoutMs: 10_000, launcher: stub })
    expect(readFileSync(join(dir, 'args'), 'utf8')).toBe('--json\n-\n')
    expect(readFileSync(join(dir, 'stdin'), 'utf8')).toBe('--permission-mode danger-full-access')
    expect(toResponse(run)).toMatchObject({ output: 'ok', cost: 0 })
  })

  it('ends everything the attempt started when it times out', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'dsh-provider-'))
    const stub = join(dir, 'dsh-redteam')
    // The stub leaves a child running in the background, records its pid, and ignores SIGTERM.
    writeFileSync(
      stub,
      ['#!/bin/sh', "trap '' TERM", 'sleep 60 &', `echo $! > "${dir}/child"`, 'cat >/dev/null', 'sleep 60'].join('\n'),
    )
    chmodSync(stub, 0o755)
    const run = await runLauncher('x', { timeoutMs: 300, graceMs: 200, launcher: stub })
    expect(run.timedOut).toBe(true)
    const child = Number(readFileSync(join(dir, 'child'), 'utf8'))
    expect(() => process.kill(child, 0)).toThrow()
  })

  it('returns an aborted turn as a result, not an error', () => {
    const stdout = '{"type":"final","sessionId":"s","reason":{"kind":"aborted"},"text":""}\n'
    const res = toResponse({ exitCode: 1, signal: null, stdout, stderr: '', timedOut: false })
    expect(res.error).toBeUndefined()
    expect(res.metadata.attempt.reason).toBe('aborted')
  })

  it('returns an error when the stream has no final event or the run timed out', () => {
    const noFinal = toResponse({ exitCode: 1, signal: null, stdout: '', stderr: 'dsh: boom\n', timedOut: false })
    expect(noFinal.error).toContain('dsh: boom')
    const late = toResponse({ exitCode: null, signal: 'SIGTERM', stdout: '', stderr: '', timedOut: true })
    expect(late.error).toBe('dsh-redteam timed out')
  })

  // dsh 0.2.2-rc.3 only warns about a row that did not activate, then runs the turn anyway, so
  // the stream ends normally. A run with a defence missing is not a defended run (ADR 0003).
  it('voids an attempt with a row that did not activate, even when the turn completed', () => {
    const stdout = '{"type":"final","sessionId":"s","reason":{"kind":"completed"},"text":"I refused."}\n'
    const stderr = [
      '[mcp-test-server] scenario clean, protocol 2025-11-25',
      'dsh: warning: 2 entries did not activate',
      "zelemate-web-fixture (@zelemate/dsh-web-fixture): failed to import: Error [ERR_MODULE_NOT_FOUND]: Cannot find package '@zelemate/dsh-web-fixture'",
      '    at packageResolve (node:internal/modules/esm/resolve:751:25)',
      'zelemate-policy (@zelemate/dsh-policy): pending (waiting for service: shell)',
      '',
    ].join('\n')
    const res = toResponse({ exitCode: 0, signal: null, stdout, stderr, timedOut: false })
    expect(res.output).toBeUndefined()
    expect(res.error).toBe('dsh-redteam: 2 bundle rows did not activate (zelemate-web-fixture, zelemate-policy); the attempt ran undefended and is not scored')
    expect(res.metadata.inactiveRows).toEqual(['zelemate-web-fixture', 'zelemate-policy'])
  })

  // Fails closed: a reworded warning still voids the attempt, even with no row line to name.
  it('voids an attempt on any did-not-activate line, whatever its wording', () => {
    const stdout = '{"type":"final","sessionId":"s","reason":{"kind":"completed"},"text":"ok"}\n'
    const res = toResponse({ exitCode: 0, signal: null, stdout, stderr: 'dsh: 1 plugin did not activate\n', timedOut: false })
    expect(res.error).toBe('dsh-redteam: a bundle row did not activate (dsh: 1 plugin did not activate); the attempt ran undefended and is not scored')
  })

  it('scores an attempt whose stderr has no did-not-activate line', () => {
    const stdout = '{"type":"final","sessionId":"s","reason":{"kind":"completed"},"text":"ok"}\n'
    const res = toResponse({ exitCode: 0, signal: null, stdout, stderr: '[zelemate-web-fixture] serving 1 fixture pages\n', timedOut: false })
    expect(res).toMatchObject({ output: 'ok' })
    expect(res.error).toBeUndefined()
    expect(res.metadata.inactiveRows).toEqual([])
  })
})

describe('run facts read from the repo', () => {
  it('reads the red-team models from bin/dsh-redteam and the Modelfiles', () => {
    const models = redteamModels(readFileSync(join(repo, 'bin', 'dsh-redteam'), 'utf8'), (role) =>
      readFileSync(join(repo, 'bundles', 'redteam', `${role}.Modelfile`), 'utf8'),
    )
    expect(models).toEqual({
      victim: { tag: 'redteam-qwen3.5-4b-16k', base: 'qwen3.5:4b' },
      grader: { tag: 'redteam-granite4.2-3b-16k', base: 'granite4.2:3b' },
    })
  })

  it('reads every enabled row id and skips comments', () => {
    const rows = enabledRows(readFileSync(join(repo, 'scripts', 'upgrade-check', 'enabled-rows', 'redteam.txt'), 'utf8'))
    expect(rows).toContain('agent')
    expect(rows.every((r) => /^[a-z0-9-]+$/.test(r))).toBe(true)
  })
})
