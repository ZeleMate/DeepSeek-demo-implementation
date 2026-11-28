// Promptfoo custom provider: one attempt is one bin/dsh-redteam launch (ADR 0011, #57).
// - The prompt goes on stdin, never as an argument: an attack prompt that starts with `--` could
//   otherwise be read as a dsh option, and Promptfoo's own `exec:` appends its options and
//   context JSON, which dsh would join into the task (research/redteam-setup.md, 3e).
// - The only arguments are `--json -`. Never `--session-id`: each attempt starts a fresh session
//   in a fresh run directory (#110), so attempts stay independent.
// - The launcher clears the environment itself; this passes it only what it needs to start.
import { spawn } from 'node:child_process'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { inactiveRows } from '../lib/activation.ts'
import { parseStream, type Attempt } from '../lib/dsh-stream.ts'
import { dvmcpEnv, parseDvmcpLog, type DvmcpLog } from '../lib/dvmcp.ts'
import { parseMcpLog, scenarioEnv, type McpLog } from '../lib/mcp.ts'

const repo = join(dirname(fileURLToPath(import.meta.url)), '..', '..')

export const LAUNCHER = join(repo, 'bin', 'dsh-redteam')
export const LAUNCHER_ARGS: readonly string[] = ['--json', '-']

// What reaches the launcher from Promptfoo's environment. DSH_DEMO_ROOT moves the whole root.
const PASSED_ENV = ['HOME', 'USER', 'PATH', 'LANG', 'TERM', 'TMPDIR', 'DSH_DEMO_ROOT'] as const

export function launcherEnv(env: NodeJS.ProcessEnv): Record<string, string> {
  const out: Record<string, string> = {}
  for (const name of PASSED_ENV) {
    const value = env[name]
    if (value !== undefined) out[name] = value
  }
  return out
}

export interface RunResult {
  exitCode: number | null
  signal: NodeJS.Signals | null
  stdout: string
  stderr: string
  timedOut: boolean
}

export interface RunOptions {
  timeoutMs: number
  // How long a timed-out attempt gets after SIGTERM before its whole process group is killed.
  graceMs?: number
  launcher?: string
  // Per-attack variables for the launcher, on top of launcherEnv: only DSH_REDTEAM_MCP_SCENARIO,
  // from scenarioEnv (#58), and DSH_REDTEAM_DVMCP_CHALLENGE, from dvmcpEnv (#59). The launcher
  // lets only its own pass_env names through.
  env?: Record<string, string>
}

// Each attempt runs in its own process group, so a timeout ends everything the attempt started,
// not just dsh. Otherwise a hung child could overlap the next attempt (maxConcurrency: 1).
export function runLauncher(prompt: string, options: RunOptions): Promise<RunResult> {
  const { timeoutMs, graceMs = 10_000, launcher = LAUNCHER, env = {} } = options
  return new Promise((resolve, reject) => {
    const child = spawn(launcher, LAUNCHER_ARGS, {
      cwd: repo,
      env: { ...launcherEnv(process.env), ...env },
      stdio: ['pipe', 'pipe', 'pipe'],
      detached: true,
    })
    const killGroup = (signal: NodeJS.Signals): void => {
      if (child.pid === undefined) return
      try {
        // A negative pid signals the whole group the attempt leads.
        process.kill(-child.pid, signal)
      } catch {
        // ESRCH: the group has already exited.
      }
    }
    let stdout = ''
    let stderr = ''
    let timedOut = false
    let killTimer: NodeJS.Timeout | undefined
    const timer = setTimeout(() => {
      timedOut = true
      killGroup('SIGTERM')
      killTimer = setTimeout(() => killGroup('SIGKILL'), graceMs)
    }, timeoutMs)
    const settle = (): void => {
      clearTimeout(timer)
      clearTimeout(killTimer)
      // Anything the attempt left running in its group ends with it.
      killGroup('SIGKILL')
    }
    child.stdout.setEncoding('utf8').on('data', (chunk: string) => (stdout += chunk))
    child.stderr.setEncoding('utf8').on('data', (chunk: string) => (stderr += chunk))
    child.on('error', (err) => {
      settle()
      reject(err)
    })
    child.on('close', (exitCode, signal) => {
      settle()
      resolve({ exitCode, signal, stdout, stderr, timedOut })
    })
    child.stdin.end(prompt)
  })
}

export interface AttemptMetadata {
  attempt: Attempt
  exitCode: number | null
  // dsh's own stderr diagnostics, cut to the end, for reading a failed attempt.
  stderrTail: string
  // What the test MCP server logged, read from the whole stderr (#58).
  mcp: McpLog
  // Which DVMCP challenges started, read from the whole stderr (#59).
  dvmcp: DvmcpLog
  // The bundle rows dsh said did not activate; any at all voids the attempt (ADR 0003).
  inactiveRows: string[]
}

// What Promptfoo gets back. A turn that ends, completed or aborted, is a result: a defence that
// stops the turn is an outcome to score. Only a harness failure is an error, and errors are
// counted apart from the attack success rate. A harness failure is a stream with no `final`
// event, or a bundle row that did not activate: dsh still runs the turn then, so its answer
// comes from a harness with a defence missing and must not be scored (ADR 0003).
export function toResponse(run: RunResult): {
  output?: string
  error?: string
  metadata: AttemptMetadata
  tokenUsage: { prompt: number; completion: number; total: number; numRequests: number }
  cost: number
} {
  const attempt = parseStream(run.stdout)
  const inactive = inactiveRows(run.stderr)
  const metadata: AttemptMetadata = {
    attempt,
    exitCode: run.exitCode,
    stderrTail: run.stderr.slice(-2000),
    mcp: parseMcpLog(run.stderr),
    dvmcp: parseDvmcpLog(run.stderr),
    inactiveRows: inactive?.rows ?? [],
  }
  // Local models only, so every attempt costs nothing (ADR 0005).
  const common = { metadata, tokenUsage: { ...attempt.tokens, numRequests: 1 }, cost: 0 }
  if (inactive !== undefined) {
    const count = inactive.count ?? inactive.rows.length
    const what = inactive.rows.length > 0
      ? `${String(count)} bundle ${count === 1 ? 'row' : 'rows'} did not activate (${inactive.rows.join(', ')})`
      : `a bundle row did not activate (${inactive.header.trim().slice(0, 200)})`
    return { ...common, error: `dsh-redteam: ${what}; the attempt ran undefended and is not scored` }
  }
  if (run.timedOut) return { ...common, error: 'dsh-redteam timed out' }
  if (attempt.output === undefined) {
    const why = attempt.errors.at(-1) ?? run.stderr.trim().split('\n').at(-1) ?? 'no output'
    return { ...common, error: `dsh-redteam exited ${String(run.exitCode)} without a final event: ${why}` }
  }
  return { ...common, output: attempt.output }
}

interface ProviderOptions {
  id?: string
  config?: { timeoutMs?: unknown }
}

export default class DshRedteamProvider {
  readonly #id: string
  readonly #timeoutMs: number

  constructor(options: ProviderOptions = {}) {
    this.#id = options.id ?? 'dsh-redteam'
    const timeout = options.config?.timeoutMs
    this.#timeoutMs = typeof timeout === 'number' && timeout > 0 ? timeout : 15 * 60 * 1000
  }

  id(): string {
    return this.#id
  }

  // A bad mcpScenario or dvmcpChallenge throws here, before dsh starts, and Promptfoo records it as an error.
  async callApi(prompt: string, context?: { vars?: Record<string, unknown> }): Promise<ReturnType<typeof toResponse>> {
    return toResponse(await runLauncher(prompt, { timeoutMs: this.#timeoutMs, env: { ...scenarioEnv(context?.vars), ...dvmcpEnv(context?.vars) } }))
  }
}
