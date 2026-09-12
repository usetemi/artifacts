import test from "node:test"
import assert from "node:assert/strict"
import {readFileSync} from "node:fs"
import {fileURLToPath} from "node:url"
import {dirname, join} from "node:path"
import {applyOps, expand, get, ancestors} from "../js/state.js"

const here = dirname(fileURLToPath(import.meta.url))
const fixture = JSON.parse(readFileSync(join(here, "../../test/fixtures/state_cases.json"), "utf8"))

for (const c of fixture.cases) {
  test(c.name, () => {
    const result = applyOps(c.leaves, c.ops)
    assert.deepEqual(result, c.expected)
    assert.deepEqual(expand(result), c.expanded)
  })
}

test("get reads a subtree of an expanded object", () => {
  const state = expand({"a.b": 1, "a.c": 2})
  assert.deepEqual(get(state, "a"), {b: 1, c: 2})
  assert.equal(get(state, "a.b"), 1)
  assert.equal(get(state, "a.b.c"), undefined)
  assert.equal(get(state, "missing"), undefined)
})

test("ancestors lists every proper prefix", () => {
  assert.deepEqual(ancestors("a"), [])
  assert.deepEqual(ancestors("a.b.c"), ["a", "a.b"])
})
