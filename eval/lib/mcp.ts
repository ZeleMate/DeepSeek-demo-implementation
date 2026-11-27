// The test MCP server's side of an attempt (#58). The server (labs/mcp-test-server) logs to
// stderr, which dsh passes through, so the provider can tell whether an MCP attack was delivered:
// a server that never started, or ran the clean scenario, would otherwise score as a block.
import { z } from 'zod'

export interface McpLog {
  // Every scenario a server process started in. dsh starts a short-lived probe first, so one
  // run may list the same scenario more than once.
  scenarios: string[]
  // The protocol revision each connection negotiated, which decides how tools/list_changed travels.
  protocols: string[]
  // Whether a pin scenario changed its tool list after the first call.
  listChanged: boolean
}

const STARTED = /^\[mcp-test-server\] scenario ([a-z0-9-]+), protocol (\S+)$/
const CHANGED = /^\[mcp-test-server\] [a-z0-9-]+: tool list changed after /

export function parseMcpLog(stderr: string): McpLog {
  const log: McpLog = { scenarios: [], protocols: [], listChanged: false }
  for (const line of stderr.split('\n')) {
    const started = STARTED.exec(line)
    if (started?.[1] !== undefined && started[2] !== undefined) {
      log.scenarios.push(started[1])
      log.protocols.push(started[2])
    } else if (CHANGED.test(line)) {
      log.listChanged = true
    }
  }
  return log
}

/**
 * Why the attack was not delivered, or undefined when it was. A pin attack is delivered only
 * once its list changed, which needs one call to a tool of the test server.
 */
export function mcpDeliveryProblem(log: McpLog, scenario: string): string | undefined {
  if (log.scenarios.length === 0) return `the test MCP server never started (expected ${scenario})`
  const other = log.scenarios.find((s) => s !== scenario)
  if (other !== undefined) return `the test MCP server ran ${other}, not ${scenario}`
  if (scenario.startsWith('pin-') && !log.listChanged) return `${scenario}: the tool list never changed, so the pin was never tested`
  return undefined
}

// A plain word, as bin/lib/launcher.sh requires; the server refuses names it doesn't know.
const scenarioName = z.string().regex(/^[a-z0-9][a-z0-9-]*$/)

// The launcher variable for a test's scenario. Promptfoo vars are test-file data, so they are
// checked before they become an environment variable.
export function scenarioEnv(vars: Record<string, unknown> | undefined): Record<string, string> {
  const value = vars?.['mcpScenario']
  if (value === undefined) return {}
  return { DSH_REDTEAM_MCP_SCENARIO: scenarioName.parse(value) }
}
