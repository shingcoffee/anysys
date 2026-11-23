import { describe, it, expect } from "vitest"
import versionDiff, { versionDiff as namedVersionDiff } from "versions/version_diff"

// Uses the REAL vendored jsdiff (pure). No mocking needed.

const types = (rows) => rows.map((r) => r.type)

describe("versionDiff", () => {
  it("exports the same function as default and named", () => {
    expect(namedVersionDiff).toBe(versionDiff)
  })

  it("produces all-context rows for identical configs", () => {
    const cfg = { a: 1, b: [1, 2] }
    const rows = versionDiff(cfg, cfg)
    expect(new Set(types(rows))).toEqual(new Set(["context"]))
    // Every context row mirrors left === right
    for (const r of rows) expect(r.left).toBe(r.right)
  })

  it("treats key-order differences as equal (stable pretty-print)", () => {
    const left = { a: 1, b: 2 }
    const right = { b: 2, a: 1 }
    expect(types(versionDiff(left, right)).every((t) => t === "context")).toBe(true)
  })

  it("accepts JSON strings and parses them", () => {
    const rows = versionDiff('{"a":1}', '{"a":1}')
    expect(types(rows).every((t) => t === "context")).toBe(true)
  })

  it("emits add rows (left null) for a new key, including the new line", () => {
    const rows = versionDiff({ a: 1 }, { a: 1, b: 2 })
    const adds = rows.filter((r) => r.type === "add")
    expect(adds.length).toBeGreaterThan(0)
    // every add row is right-only
    for (const r of adds) expect(r.left).toBeNull()
    // the new key surfaces on some add row
    expect(adds.some((r) => r.right.includes("b"))).toBe(true)
  })

  it("emits del rows (right null) for a removed key, including the dropped line", () => {
    const rows = versionDiff({ a: 1, b: 2 }, { a: 1 })
    const dels = rows.filter((r) => r.type === "del")
    expect(dels.length).toBeGreaterThan(0)
    for (const r of dels) expect(r.right).toBeNull()
    expect(dels.some((r) => r.left.includes("b"))).toBe(true)
  })

  it("row shape is always {type,left,right}", () => {
    const rows = versionDiff({ a: 1 }, { a: 2 })
    for (const r of rows) {
      expect(Object.keys(r).sort()).toEqual(["left", "right", "type"])
    }
  })

  it("recursively sorts nested object keys", () => {
    const left = { outer: { z: 1, a: 2 } }
    const right = { outer: { a: 2, z: 1 } }
    expect(types(versionDiff(left, right)).every((t) => t === "context")).toBe(true)
  })
})
