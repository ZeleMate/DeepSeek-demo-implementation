// Reads dsh's warning about bundle rows that did not activate from an attempt's stderr.
// At the pinned dsh (0.2.2-rc.3), dsh-app-boot's startup audit stops only for its own required
// rows. Any other row that fails to import, throws or waits on a missing service gets a warning,
// `dsh: warning: N entries did not activate`, then one `id (package): why` line per row, and the
// session runs anyway. Every defence is a bundle row, so such a run is undefended (ADR 0003).
// bin/lib/launcher.sh matches the same text before it starts dsh, and the upgrade check confirms
// that dsh still prints it.

// Fails closed: any line saying a row did not activate counts, so a reworded header still voids.
const MARKER = /did not activate/
const ROW = /^([A-Za-z0-9@._/-]+) \([^()\s]+\): /

export interface InactiveRows {
  // The line that matched, for the error message.
  header: string
  // dsh's count from the header, or undefined when the header was reworded.
  count?: number
  // The row ids dsh listed under the header; stack frames and other lines are skipped.
  rows: string[]
}

export function inactiveRows(stderr: string): InactiveRows | undefined {
  const lines = stderr.split('\n')
  const at = lines.findIndex((line) => MARKER.test(line))
  if (at === -1) return undefined
  const header = lines[at] ?? ''
  const count = /^dsh: warning: (\d+) (?:entry|entries) did not activate$/.exec(header)?.[1]
  const want = count === undefined ? Infinity : Number(count)
  const rows: string[] = []
  for (const line of lines.slice(at + 1)) {
    if (rows.length >= want) break
    const id = ROW.exec(line)?.[1]
    if (id !== undefined) rows.push(id)
  }
  return count === undefined ? { header, rows } : { header, count: Number(count), rows }
}
