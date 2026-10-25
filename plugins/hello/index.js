// Proves that a profile running our bundle loads our code. Logs to stderr so a
// headless `--json` run keeps stdout machine-readable.
export const name = 'zelemate-hello'

export function apply() {
  console.error('[zelemate-hello] loaded')
}
