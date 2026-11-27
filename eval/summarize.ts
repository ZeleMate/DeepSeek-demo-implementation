// Writes eval/results/<tag>.json from one Promptfoo output file (ADR 0011).
// Usage: node eval/summarize.ts <promptfoo-output.json> <tag>
// eval/run.sh calls it; it refuses to overwrite a results file that already exists.
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { z } from 'zod'
import { promptfooOutput, summarize, type RunFacts } from './lib/summary.ts'

const repo = join(dirname(fileURLToPath(import.meta.url)), '..')

const TAG = /^[A-Za-z0-9][A-Za-z0-9._-]*$/

function installedVersion(pkg: string): string {
  const json: unknown = JSON.parse(readFileSync(join(repo, 'node_modules', pkg, 'package.json'), 'utf8'))
  return z.object({ version: z.string() }).parse(json).version
}

// bin/dsh-redteam declares its models as role:tag:need entries; each role's base is the FROM
// line of bundles/redteam/<role>.Modelfile.
export function redteamModels(launcher: string, modelfile: (role: string) => string): RunFacts['models'] {
  const line = launcher.split('\n').find((l) => l.startsWith('models='))
  const list = line?.match(/^models="([^"]*)"$/)?.[1]
  if (list === undefined) throw new Error('bin/dsh-redteam has no models="..." line')
  const models: RunFacts['models'] = {}
  for (const entry of list.split(/\s+/).filter((e) => e !== '')) {
    const [role, tag] = entry.split(':')
    if (role === undefined || tag === undefined) throw new Error(`bad model entry: ${entry}`)
    const base = modelfile(role).match(/^FROM (\S+)$/m)?.[1]
    if (base === undefined) throw new Error(`bundles/redteam/${role}.Modelfile has no FROM line`)
    models[role] = { tag, base }
  }
  return models
}

export function enabledRows(list: string): string[] {
  return list
    .split('\n')
    .filter((l) => l.trim() !== '' && !l.startsWith('#'))
    .map((l) => l.trim().split(/\s+/)[0] ?? '')
}

const runConfig = z.object({
  config: z.object({
    evaluateOptions: z.object({ repeat: z.number().int().positive() }).loose(),
    defaultTest: z.object({ options: z.object({ provider: z.string() }).loose() }).loose(),
  }).loose(),
}).loose()

function main(argv: string[]): void {
  const [input, tag] = argv
  if (input === undefined || tag === undefined || !TAG.test(tag)) {
    throw new Error('usage: node eval/summarize.ts <promptfoo-output.json> <tag>, tag like v0.2')
  }
  const out = join(repo, 'eval', 'results', `${tag}.json`)
  if (existsSync(out)) throw new Error(`${out} exists; results files are not overwritten`)

  const raw: unknown = JSON.parse(readFileSync(input, 'utf8'))
  const output = promptfooOutput.parse(raw)
  const config = runConfig.parse(raw).config
  const embargoDir = join(repo, 'eval', 'embargoed')

  const facts: RunFacts = {
    tag,
    createdAt: new Date().toISOString(),
    dsh: installedVersion('@deepseek-ai/dsh'),
    promptfoo: installedVersion('promptfoo'),
    attemptsPerAttack: config.evaluateOptions.repeat,
    models: redteamModels(readFileSync(join(repo, 'bin', 'dsh-redteam'), 'utf8'), (role) =>
      readFileSync(join(repo, 'bundles', 'redteam', `${role}.Modelfile`), 'utf8'),
    ),
    judging: {
      attackSuccess: 'deterministic checks (eval/lib/checks.ts)',
      grader: config.defaultTest.options.provider,
      // No injection filter until M5 (ADR 0003); then its backend is named here (ADR 0011).
      injectionFilter: 'none',
    },
    enabledRows: enabledRows(readFileSync(join(repo, 'scripts', 'upgrade-check', 'enabled-rows', 'redteam.txt'), 'utf8')),
    // One file per embargoed attack, kept off git (ADR 0015).
    embargoed: existsSync(embargoDir) ? readdirSync(embargoDir).filter((f) => !f.startsWith('.')).length : 0,
  }

  mkdirSync(dirname(out), { recursive: true })
  writeFileSync(out, `${JSON.stringify(summarize(output, facts), null, 2)}\n`)
  console.log(`wrote ${out}`)
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main(process.argv.slice(2))
