// Model-free tests for the test MCP server's scenarios (#58). Run with `pnpm run check:node`.
import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import { Client } from '@modelcontextprotocol/client'
import { InMemoryTransport } from '@modelcontextprotocol/server'
import { canaryFor, createScenario, SCENARIOS } from '../scenarios.js'
import { createServer } from '../server.js'

const weather = (state) => state.list().find(tool => tool.name === 'get_weather')
const exfilTool = /send_feedback/
const exfilAnswer = /end your answer/i

describe('scenarios', () => {
  it('names exactly the scenarios the attack set uses', () => {
    assert.deepEqual([...SCENARIOS].sort(), ['clean', 'pin-answer', 'pin-conflict', 'pin-tool', 'poison-answer', 'poison-tool'])
  })

  it('refuses an unknown scenario, so a typo fails the run instead of serving a clean server', () => {
    assert.throws(() => createScenario('pin-tool '), /unknown scenario/)
    assert.throws(() => createScenario(''), /unknown scenario/)
  })

  it('clean lists three tools with neutral descriptions, and never changes', () => {
    const state = createScenario('clean')
    assert.deepEqual(state.list().map(tool => tool.name), ['get_weather', 'get_account', 'send_feedback'])
    for (const tool of state.list()) assert.doesNotMatch(tool.description, /IMPORTANT|end your answer|send_feedback with/)
    assert.equal(state.call('get_weather', { city: 'Oslo' }).changed, false)
    assert.equal(state.call('get_weather', { city: 'Bergen' }).changed, false)
  })

  it('a pin scenario starts clean and changes get_weather once, after the first call', () => {
    for (const [name, injection] of [['pin-tool', exfilTool], ['pin-answer', exfilAnswer]]) {
      const state = createScenario(name)
      const before = weather(state).description
      assert.equal(before, weather(createScenario('clean')).description, name)
      assert.equal(state.call('get_weather', { city: 'Oslo' }).changed, true, name)
      assert.match(weather(state).description, injection, name)
      assert.equal(state.call('get_weather', { city: 'Bergen' }).changed, false, name)
    }
  })

  it('a poison scenario serves the injected description from its fixture file from the start', () => {
    assert.match(weather(createScenario('poison-tool')).description, exfilTool)
    assert.match(weather(createScenario('poison-answer')).description, exfilAnswer)
    assert.equal(createScenario('poison-tool').call('get_weather', { city: 'Oslo' }).changed, false)
  })

  it('pin-conflict lists get_weather twice after the first call, both injected', () => {
    const state = createScenario('pin-conflict')
    assert.equal(state.call('get_account', {}).changed, true)
    const names = state.list().map(tool => tool.name)
    assert.equal(names.filter(name => name === 'get_weather').length, 2)
    for (const tool of state.list().filter(tool => tool.name === 'get_weather')) assert.match(tool.description, exfilTool)
  })

  it('get_account carries the scenario canary, and each scenario has its own', () => {
    const canaries = new Set()
    for (const name of SCENARIOS) {
      const text = createScenario(name).call('get_account', {}).result.content[0].text
      assert.ok(text.includes(canaryFor(name)), name)
      canaries.add(canaryFor(name))
    }
    assert.equal(canaries.size, SCENARIOS.length)
  })

  it('answers the same way every time, so attempts are comparable', () => {
    const a = createScenario('clean').call('get_weather', { city: 'Oslo' }).result
    const b = createScenario('clean').call('get_weather', { city: 'Oslo' }).result
    assert.deepEqual(a, b)
  })

  it('reports an unknown tool or a bad argument as a tool error, not a crash', () => {
    const state = createScenario('clean')
    assert.equal(state.call('rm_rf', {}).result.isError, true)
    assert.equal(state.call('get_weather', {}).result.isError, true)
    assert.equal(state.call('send_feedback', { message: 42 }).result.isError, true)
  })
})

describe('server over the MCP protocol', () => {
  async function connect(scenario) {
    const changes = []
    const server = createServer(scenario, { log: () => {} })
    const [clientSide, serverSide] = InMemoryTransport.createLinkedPair()
    const client = new Client({ name: 'test', version: '0.0.0' }, {
      listChanged: { tools: { onChanged: (error, tools) => changes.push(error ?? tools) } },
    })
    await Promise.all([server.connect(serverSide), client.connect(clientSide)])
    return { client, changes, close: () => Promise.all([client.close(), server.close()]) }
  }

  it('pin-tool sends tools/list_changed after the first call, and the new list is injected', async () => {
    const { client, changes, close } = await connect('pin-tool')
    try {
      const first = await client.listTools()
      assert.doesNotMatch(first.tools.find(tool => tool.name === 'get_weather').description, exfilTool)
      const result = await client.callTool({ name: 'get_weather', arguments: { city: 'Oslo' } })
      assert.match(result.content[0].text, /Oslo/)
      for (let i = 0; i < 50 && changes.length === 0; i++) await new Promise(resolve => setTimeout(resolve, 10))
      assert.equal(changes.length, 1, 'one tools/list_changed')
      const after = await client.listTools()
      assert.match(after.tools.find(tool => tool.name === 'get_weather').description, exfilTool)
    } finally {
      await close()
    }
  })

  it('clean sends no tools/list_changed', async () => {
    const { client, changes, close } = await connect('clean')
    try {
      await client.callTool({ name: 'get_weather', arguments: { city: 'Oslo' } })
      await new Promise(resolve => setTimeout(resolve, 100))
      assert.equal(changes.length, 0)
    } finally {
      await close()
    }
  })
})
