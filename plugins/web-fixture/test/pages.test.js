// Model-free tests for the fixture pages (#47). Run with `pnpm run check:node`.
import assert from 'node:assert/strict'
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { after, describe, it } from 'node:test'
import { createFixtureFetchProvider, FIXTURE_FETCH_PROVIDER_ID, loadPages } from '../pages.js'

const roots = []
after(() => { for (const root of roots) rmSync(root, { recursive: true, force: true }) })

/** Writes the given files (relative path → content) under a fresh directory. */
function fixtureRoot(files) {
  const root = mkdtempSync(join(tmpdir(), 'web-fixture-'))
  roots.push(root)
  for (const [path, content] of Object.entries(files)) {
    mkdirSync(dirname(join(root, path)), { recursive: true })
    writeFileSync(join(root, path), content)
  }
  return root
}

const provider = createFixtureFetchProvider(loadPages(fixtureRoot({
  'docs.example.com/index.html': '<h1>Docs</h1>',
  'docs.example.com/guide/install.html': '<p>Install</p>',
  'notes.test/readme.md': '# Notes',
  'blog.example.org/post.txt': 'plain post',
})))

describe('fixture fetch provider', () => {
  it('serves a fixture page as html', async () => {
    assert.deepEqual(await provider.fetch({ url: 'https://docs.example.com/guide/install.html' }), {
      url: 'https://docs.example.com/guide/install.html',
      statusCode: 200,
      body: { kind: 'html', content: '<p>Install</p>' },
      truncated: false,
    })
  })

  it('serves markdown and plain text as text', async () => {
    assert.deepEqual((await provider.fetch({ url: 'https://notes.test/readme.md' })).body, { kind: 'text', content: '# Notes' })
    assert.deepEqual((await provider.fetch({ url: 'https://blog.example.org/post.txt' })).body, { kind: 'text', content: 'plain post' })
  })

  it('maps a directory URL to its index.html', async () => {
    for (const url of ['https://docs.example.com', 'https://docs.example.com/']) {
      const result = await provider.fetch({ url })
      assert.equal(result.statusCode, 200, url)
      assert.equal(result.url, 'https://docs.example.com/index.html')
    }
  })

  it('treats http like https, ignores query and fragment, and lowercases the host', async () => {
    for (const url of [
      'http://docs.example.com/guide/install.html',
      'https://DOCS.example.com/guide/install.html',
      'https://docs.example.com/guide/install.html?q=1#top',
    ]) {
      const result = await provider.fetch({ url })
      assert.equal(result.statusCode, 200, url)
      assert.equal(result.url, 'https://docs.example.com/guide/install.html', url)
    }
  })

  it('answers 404 for every URL that is not a fixture page, with no network I/O', async () => {
    for (const url of [
      'https://docs.example.com/missing.html',
      'https://example.com/',
      'http://127.0.0.1:11434/api/tags',
      'http://169.254.169.254/latest/meta-data/',
      'https://docs.example.com:8443/index.html',
      'https://docs.example.com/guide/../../notes.test/readme.md',
      'https://docs.example.com/%2e%2e/notes.test/readme.md',
      'file:///etc/passwd',
      'not a url',
    ]) {
      const result = await provider.fetch({ url })
      assert.equal(result.statusCode, 404, url)
      assert.equal(result.url, url)
      assert.equal(result.body.kind, 'text')
    }
  })

  it('is always available and has a stable id', () => {
    assert.equal(provider.id, FIXTURE_FETCH_PROVIDER_ID)
    assert.equal(FIXTURE_FETCH_PROVIDER_ID, 'fixture')
    assert.equal(provider.available(), true)
  })
})

describe('loadPages', () => {
  it('refuses a host that is not reserved for examples or tests', () => {
    assert.throws(() => loadPages(fixtureRoot({ 'github.com/index.html': 'x' })), /not a reserved host/)
    assert.throws(() => loadPages(fixtureRoot({ 'example.com.evil.net/index.html': 'x' })), /not a reserved host/)
    assert.throws(() => loadPages(fixtureRoot({ '127.0.0.1/index.html': 'x' })), /not a reserved host/)
  })

  it('accepts the reserved example domains and test TLDs', () => {
    const pages = loadPages(fixtureRoot({
      'example.com/a.html': 'a',
      'www.example.net/b.html': 'b',
      'example.org/c.html': 'c',
      'lab.test/d.html': 'd',
      'site.example/e.html': 'e',
    }))
    assert.equal(pages.size, 5)
  })

  it('refuses a file type it cannot classify', () => {
    assert.throws(() => loadPages(fixtureRoot({ 'docs.example.com/logo.png': 'x' })), /unsupported fixture file type/)
  })

  it('refuses a file outside a host directory', () => {
    assert.throws(() => loadPages(fixtureRoot({ 'stray.html': 'x' })), /must sit in a host directory/)
  })

  it('skips dotfiles such as .DS_Store', () => {
    const pages = loadPages(fixtureRoot({ '.DS_Store': 'x', 'docs.example.com/.DS_Store': 'x', 'docs.example.com/a.html': 'a' }))
    assert.deepEqual([...pages.keys()], ['https://docs.example.com/a.html'])
  })

  it('refuses a host directory with a port or a trailing dot', () => {
    assert.throws(() => loadPages(fixtureRoot({ 'lab.test:8080/a.html': 'x' })), /plain host name/)
    assert.throws(() => loadPages(fixtureRoot({ 'lab.test./a.html': 'x' })), /plain host name/)
  })

  it('refuses a symlinked page', () => {
    const root = fixtureRoot({ 'docs.example.com/a.html': 'a' })
    symlinkSync(join(root, 'docs.example.com/a.html'), join(root, 'docs.example.com/b.html'))
    assert.throws(() => loadPages(root), /is a symlink/)
  })

  it('loads the pages shipped with the plugin', () => {
    const pages = loadPages(new URL('../pages/', import.meta.url))
    assert.ok(pages.size > 0)
  })
})
