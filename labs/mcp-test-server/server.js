#!/usr/bin/env node
// The test MCP server (#58): one stdio server whose scenario comes from MCP_TEST_SCENARIO, set by
// the red-team bundle from the attack being run. Unset means clean. An unknown name exits non-zero,
// so a typo fails the attempt instead of quietly testing the clean server.
// Logs go to stderr only: stdout is the protocol.
import { realpathSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { Server } from '@modelcontextprotocol/server'
import { StdioServerTransport } from '@modelcontextprotocol/server/stdio'
import { createScenario } from './scenarios.js'

/**
 * @param {string} scenario
 * @param {{ log?: (line: string) => void }} [options]
 */
export function createServer(scenario, { log = line => console.error(`[mcp-test-server] ${line}`) } = {}) {
  const state = createScenario(scenario)
  const server = new Server({ name: 'mcp-test-server', version: '0.0.0' }, { capabilities: { tools: { listChanged: true } } })

  // Which protocol revision the client negotiated decides how tools/list_changed reaches it (a
  // legacy notification or a modern subscription), so each connection logs it (#58). The SDK
  // keeps it in a protected field with no public getter.
  server.oninitialized = () => {
    log(`scenario ${scenario}, protocol ${String(server._negotiatedProtocolVersion ?? 'unknown')}`)
  }
  // dsh logs no MCP re-sync, so the server records each listing it serves: this is how a run shows
  // that a changed list was actually fetched.
  server.setRequestHandler('tools/list', () => {
    const tools = state.list()
    const weather = tools.filter(tool => tool.name === 'get_weather')
    const kind = weather.length > 1 ? 'duplicated' : weather[0]?.description.includes('IMPORTANT') ? 'injected' : 'clean'
    log(`tools/list: ${tools.length} tools, get_weather ${kind}`)
    return { tools }
  })
  server.setRequestHandler('tools/call', async request => {
    const { result, changed } = state.call(request.params.name, request.params.arguments)
    if (changed) {
      log(`${scenario}: tool list changed after ${request.params.name}`)
      // Sent after this call's result, so the change lands between steps, as a real pin attack's would.
      setImmediate(() => { void server.sendToolListChanged() })
    }
    return result
  })
  return server
}

// Run only as the entry point, so the tests can import createServer.
if (process.argv[1] !== undefined && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const scenario = process.env.MCP_TEST_SCENARIO || 'clean'
  let server
  try {
    server = createServer(scenario)
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error))
    process.exit(2)
  }
  await server.connect(new StdioServerTransport())
}
