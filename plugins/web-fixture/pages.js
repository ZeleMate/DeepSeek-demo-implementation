// The fixture pages and the fetch provider that serves them (#47, ADR 0008). No network I/O:
// every page is read from disk once, when the plugin loads, so web_fetch answers the same way in
// every red-team attempt (ADR 0011).
import { readdirSync, readFileSync } from 'node:fs'
import { extname, join, relative, sep } from 'node:path'
import { fileURLToPath } from 'node:url'

/** The id the red-team bundle pins as the web service's fetchProvider. */
export const FIXTURE_FETCH_PROVIDER_ID = 'fixture'

const KINDS = { '.html': 'html', '.htm': 'html', '.md': 'text', '.txt': 'text' }

// Fixture hosts must be names that can never be a real third-party site (RFC 2606, RFC 6761),
// so a page can't point the victim at a real target (ADR 0002). Loopback addresses are refused
// too: the victim must not learn to fetch local services such as Ollama's API.
const RESERVED_DOMAINS = ['example.com', 'example.net', 'example.org']
const RESERVED_TLDS = ['test', 'example', 'invalid']

/** @param {string} host */
function isReservedHost(host) {
  if (RESERVED_DOMAINS.some(domain => host === domain || host.endsWith(`.${domain}`))) return true
  const labels = host.split('.')
  return labels.length > 1 && RESERVED_TLDS.includes(labels.at(-1) ?? '')
}

/**
 * Reads every page under root. Each top-level directory is a host and the files under it are
 * its paths, so root/docs.example.com/guide/install.html is https://docs.example.com/guide/install.html.
 * Throws on anything it can't serve as is, so a bad fixture stops the run instead of skewing a score.
 * @param {string | URL} root
 * @returns {Map<string, { kind: 'html' | 'text', content: string }>} pages keyed by canonical URL
 */
export function loadPages(root) {
  const dir = root instanceof URL ? fileURLToPath(root) : root
  /** @type {Map<string, { kind: 'html' | 'text', content: string }>} */
  const pages = new Map()
  for (const entry of readdirSync(dir, { recursive: true, withFileTypes: true })) {
    const file = join(entry.parentPath, entry.name)
    // OS litter such as macOS's .DS_Store would otherwise stop the plugin loading.
    if (relative(dir, file).split(sep).some(part => part.startsWith('.'))) continue
    if (entry.isSymbolicLink()) throw new Error(`web-fixture: ${file} is a symlink; fixture pages must be plain files`)
    if (!entry.isFile()) continue
    const [host, ...path] = relative(dir, file).split(sep)
    if (host === undefined || path.length === 0) {
      throw new Error(`web-fixture: ${file} must sit in a host directory`)
    }
    // A port or a trailing dot would load a page no request can reach.
    if (host.includes(':') || host.endsWith('.')) {
      throw new Error(`web-fixture: ${host} must be a plain host name, with no port or trailing dot`)
    }
    if (!isReservedHost(host.toLowerCase())) {
      throw new Error(`web-fixture: ${host} is not a reserved host (use example.com/.net/.org or a .test, .example or .invalid name)`)
    }
    const kind = KINDS[/** @type {keyof typeof KINDS} */ (extname(file).toLowerCase())]
    if (kind === undefined) throw new Error(`web-fixture: unsupported fixture file type: ${file}`)
    pages.set(new URL(`https://${host}/${path.join('/')}`).href, { kind, content: readFileSync(file, 'utf8') })
  }
  return pages
}

/**
 * The canonical page URL for a requested one: http and https are the same page, the query and
 * fragment are ignored, and a path ending in / means its index.html. Undefined for anything that
 * can't name a fixture page.
 * @param {string} input
 */
function canonical(input) {
  let url
  try { url = new URL(input) } catch { return undefined }
  if ((url.protocol !== 'https:' && url.protocol !== 'http:') || url.port !== '' || url.username !== '' || url.password !== '') {
    return undefined
  }
  const path = url.pathname.endsWith('/') ? `${url.pathname}index.html` : url.pathname
  return `https://${url.hostname}${path}`
}

/**
 * A dsh fetch provider over the loaded pages. A fixture page answers 200. Every other URL,
 * including loopback, metadata and unparseable ones, answers a 404 result, never a network call.
 * @param {Map<string, { kind: 'html' | 'text', content: string }>} pages
 */
export function createFixtureFetchProvider(pages) {
  return {
    id: FIXTURE_FETCH_PROVIDER_ID,
    title: 'Red-team fixtures',
    description: { en: 'Serves only the red-team fixture pages, from disk. Every other URL answers 404, with no network access.' },
    available: () => true,
    /** @param {{ url: string }} request */
    async fetch(request) {
      const url = canonical(request.url)
      const page = url === undefined ? undefined : pages.get(url)
      if (url === undefined || page === undefined) {
        return { url: request.url, statusCode: 404, body: { kind: 'text', content: 'Not Found' }, truncated: false }
      }
      return { url, statusCode: 200, body: { kind: page.kind, content: page.content }, truncated: false }
    },
  }
}
