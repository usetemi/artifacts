// The state-tree rules, mirrored from lib/artifacts/state.ex. Both sides
// apply the same op to the same leaves and must reach the same result;
// test/fixtures/state_cases.json is run against both.

export function expand(leaves) {
  const out = {}
  for (const path of Object.keys(leaves).sort()) {
    putAt(out, path.split("."), leaves[path])
  }
  return out
}

function putAt(obj, keys, value) {
  let node = obj
  for (let i = 0; i < keys.length - 1; i++) {
    const key = keys[i]
    if (!isObject(node[key])) node[key] = {}
    node = node[key]
  }
  node[keys[keys.length - 1]] = value
}

export function get(state, path) {
  let node = state
  for (const key of path.split(".")) {
    if (!isObject(node) || !(key in node)) return undefined
    node = node[key]
  }
  return node
}

export function flatten(path, value) {
  if (value === null || value === undefined) return {}
  if (isObject(value) && Object.keys(value).length > 0) {
    const out = {}
    for (const [key, nested] of Object.entries(value)) {
      Object.assign(out, flatten(`${path}.${key}`, nested))
    }
    return out
  }
  return {[path]: value}
}

export function applyOps(leaves, ops) {
  const next = {...leaves}
  for (const op of ops) {
    removeSubtree(next, op.path)
    if (op.op === "set") {
      for (const ancestor of ancestors(op.path)) delete next[ancestor]
      Object.assign(next, flatten(op.path, op.value))
    }
  }
  return next
}

function removeSubtree(leaves, path) {
  const prefix = `${path}.`
  for (const key of Object.keys(leaves)) {
    if (key === path || key.startsWith(prefix)) delete leaves[key]
  }
}

export function ancestors(path) {
  const segments = path.split(".")
  const out = []
  for (let i = 1; i < segments.length; i++) out.push(segments.slice(0, i).join("."))
  return out
}

function isObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}
