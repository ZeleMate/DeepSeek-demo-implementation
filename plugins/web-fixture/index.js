// Fixture fetch provider for the red-team profile (#47, ADR 0008). Registers the `fixture` fetch
// provider with dsh's web service, so web_fetch serves only the pages under ./pages and never
// touches the network. Logs to stderr so a headless `--json` run keeps stdout machine-readable.
import { createFixtureFetchProvider, loadPages } from './pages.js'

export const name = 'zelemate-web-fixture'
export const inject = ['web']

/** @param {{ web: { registerFetchProvider(provider: unknown): () => void } }} ctx */
export function apply(ctx) {
  const pages = loadPages(new URL('./pages/', import.meta.url))
  ctx.web.registerFetchProvider(createFixtureFetchProvider(pages))
  console.error(`[zelemate-web-fixture] serving ${pages.size} fixture pages`)
}
