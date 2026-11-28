// PROTOTYPE (#104). validateCandidate(base, edits): the pure check the loop driver runs after an
// improver session, never inside it. Rules from #103. It collects every problem as fix-it prose
// and rejects the whole proposal on any of them. `base` and the result are `path -> text` maps.

const PROBE_TOOLS = ['read', 'glob', 'grep', 'skill', 'submit_answer']
const CAPS = { instructions: 4000, toolDescription: 600, skillDescription: 300, alwaysOn: 6000, skillBytes: 4000, skills: 5 }
const FRONTMATTER_KEYS = ['name', 'description', 'whenToUse']
const SKILL_PATH = /^skills\/([a-z0-9][a-z0-9-]{0,62})\/SKILL\.md$/
const ALLOWED_FORMS = 'instructions.md, tools.json, skills/<name>/SKILL.md'
// Answer-key and checker-output markers (#102). A hit is a leak: fall back at once, no retry.
export const MARKERS = ['ANSWER-KEY-MARKER-7f3a', 'CHECKER-OUTPUT-MARKER-c91e']

/** @returns {{ ok: true, harness: Record<string,string> } | { ok: false, tripwire: boolean, problems: string[] }} */
export function validateCandidate(base, edits) {
  const problems = []
  if (!Array.isArray(edits)) return { ok: false, tripwire: false, problems: ['edits must be an array'] }
  if (edits.length > 7) problems.push(`at most 7 edits, got ${edits.length}`)

  const offSurface = []
  const seen = new Set()
  const harness = { ...base }
  for (const edit of edits) {
    const path = edit?.path
    if (typeof path !== 'string' || !onSurface(path)) {
      offSurface.push(JSON.stringify(path))
      continue
    }
    if (seen.has(path)) {
      problems.push(`${path} is edited twice; give each path once`)
      continue
    }
    seen.add(path)
    const keys = Object.keys(edit).sort().join(',')
    if (keys === 'delete,path' && edit.delete === true) {
      if (!(path in harness)) problems.push(`${path} does not exist in the base harness, so it can't be deleted`)
      delete harness[path]
    } else if (keys === 'content,path' && typeof edit.content === 'string') {
      harness[path] = edit.content
    } else {
      problems.push(`${path}: an edit is {path, content} or {path, delete: true}, nothing else`)
    }
  }
  if (offSurface.length) {
    problems.push(`off-surface paths: ${offSurface.slice(0, 6).join(', ')}. Allowed forms: ${ALLOWED_FORMS}`)
  }

  const tripwire = Object.values(harness).some(text => MARKERS.some(m => text.includes(m)))
  if (tripwire) return { ok: false, tripwire: true, problems: ['answer-key or checker marker in the candidate'] }

  for (const [path, text] of Object.entries(harness)) {
    if (text.charCodeAt(0) === 0xfeff) problems.push(`${path} starts with a BOM`)
    if (text.includes('�')) problems.push(`${path} is not valid UTF-8`)
    // eslint-disable-next-line no-control-regex
    if (/[\u0000-\u0008\u000B-\u001F\u007F]/.test(text)) problems.push(`${path} contains control characters`)
    if (text.includes('{{')) problems.push(`${path} contains {{, which dsh would treat as a template`)
  }

  const instructions = harness['instructions.md'] ?? ''
  if (instructions.length > CAPS.instructions) problems.push(`instructions.md is over ${CAPS.instructions} chars`)
  let alwaysOn = instructions.length

  if ('tools.json' in harness) {
    let tools
    try {
      tools = JSON.parse(harness['tools.json'])
    } catch {
      tools = undefined
    }
    if (!tools || typeof tools !== 'object' || Array.isArray(tools)) {
      problems.push('tools.json must be a flat JSON object of tool name to description')
    } else {
      for (const [tool, description] of Object.entries(tools)) {
        if (!PROBE_TOOLS.includes(tool)) problems.push(`tools.json names ${JSON.stringify(tool)}; known tools are ${PROBE_TOOLS.join(', ')}`)
        else if (typeof description !== 'string' || description.trim() === '') problems.push(`tools.json: ${tool} needs a non-empty string`)
        else if (description.length > CAPS.toolDescription) problems.push(`tools.json: ${tool} is over ${CAPS.toolDescription} chars`)
        else alwaysOn += description.length
      }
    }
  }

  const skills = Object.keys(harness).filter(p => SKILL_PATH.test(p))
  if (skills.length > CAPS.skills) problems.push(`at most ${CAPS.skills} skills, got ${skills.length}`)
  for (const path of skills) {
    const folder = SKILL_PATH.exec(path)[1]
    const text = harness[path]
    if (Buffer.byteLength(text) > CAPS.skillBytes) problems.push(`${path} is over ${CAPS.skillBytes} bytes`)
    const fm = parseFrontmatter(text)
    if (typeof fm === 'string') {
      problems.push(`${path}: ${fm}`)
      continue
    }
    if (fm.name !== folder) problems.push(`${path}: name must be ${folder}`)
    if (!fm.description) problems.push(`${path}: description is required`)
    else if (fm.description.length > CAPS.skillDescription) problems.push(`${path}: description is over ${CAPS.skillDescription} chars`)
    alwaysOn += folder.length + (fm.description?.length ?? 0)
    if (!instructions.includes(folder)) problems.push(`${path}: name the skill ${folder} in instructions.md, or it never triggers`)
  }
  if (alwaysOn > CAPS.alwaysOn) problems.push(`always-on text is ${alwaysOn} chars, over ${CAPS.alwaysOn}`)

  return problems.length ? { ok: false, tripwire: false, problems } : { ok: true, harness }
}

function onSurface(path) {
  if (path === 'instructions.md' || path === 'tools.json') return true
  return SKILL_PATH.test(path)
}

/** Strict frontmatter: single-line keys from a fixed list, no YAML syntax at all. */
function parseFrontmatter(text) {
  const match = /^---\n([\s\S]*?)\n---\n/.exec(text)
  if (!match) return 'needs frontmatter between --- lines'
  const out = {}
  for (const line of match[1].split('\n')) {
    const kv = /^([A-Za-z]+): (.*)$/.exec(line)
    if (!kv) return `frontmatter line ${JSON.stringify(line)} is not "key: value"`
    const [, key, value] = kv
    if (!FRONTMATTER_KEYS.includes(key)) return `frontmatter key ${key} is not one of ${FRONTMATTER_KEYS.join(', ')}`
    if (key in out) return `frontmatter key ${key} appears twice`
    if (/^[!&*|>[{'"]/.test(value)) return `frontmatter ${key} starts with YAML syntax`
    out[key] = value
  }
  return out
}
