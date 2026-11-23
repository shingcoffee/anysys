import { describe, it, expect } from "vitest"
import { isSection, moveFields, reorderSectionBlock } from "controllers/page_builder/dnd/field_mutations"

// Pure list math — no DOM. Functions return NEW arrays.
const f = (id, extra = {}) => ({ id, ...extra })
const section = (id) => f(id, { property_type: "layout", field_type: "section" })
const ids = (list) => list.map((x) => x.id)

describe("isSection", () => {
  it("is true only for layout section fields", () => {
    expect(isSection(section("s"))).toBe(true)
    expect(isSection(f("a"))).toBe(false)
    expect(isSection(f("b", { property_type: "layout", field_type: "divider" }))).toBe(false)
    expect(isSection(null)).toBe(false)
    expect(isSection(undefined)).toBe(false)
  })
})

describe("moveFields", () => {
  it("returns a new array (does not mutate input)", () => {
    const list = [f("a"), f("b"), f("c")]
    const out = moveFields(list, ["a"], 2)
    expect(out).not.toBe(list)
    expect(ids(list)).toEqual(["a", "b", "c"])
  })

  it("moves a single field forward, compensating for removed-before items", () => {
    const list = [f("a"), f("b"), f("c")]
    // Move "a" to targetIndex 2 (against original list). One moving item sits
    // before the target, so insertAt = 2 - 1 = 1 in the remaining [b, c].
    expect(ids(moveFields(list, ["a"], 2))).toEqual(["b", "a", "c"])
  })

  it("moves a field backward", () => {
    const list = [f("a"), f("b"), f("c")]
    expect(ids(moveFields(list, ["c"], 0))).toEqual(["c", "a", "b"])
  })

  it("keeps moving fields in their original relative order", () => {
    const list = [f("a"), f("b"), f("c"), f("d")]
    expect(ids(moveFields(list, ["a", "c"], 4))).toEqual(["b", "d", "a", "c"])
  })

  it("clamps target index into range", () => {
    const list = [f("a"), f("b")]
    expect(ids(moveFields(list, ["a"], 99))).toEqual(["b", "a"])
    expect(ids(moveFields(list, ["b"], -5))).toEqual(["b", "a"])
  })
})

describe("reorderSectionBlock", () => {
  // Layout: [S1, a, b, S2, c, d]  — two section blocks.
  const build = () => [section("S1"), f("a"), f("b"), section("S2"), f("c"), f("d")]

  it("moves a whole section block (header + members) after the target section when dragging down", () => {
    const { list, movedIds } = reorderSectionBlock(build(), "S1", "c")
    expect(movedIds).toEqual(["S1", "a", "b"])
    // S1 block relocates after S2's block.
    expect(ids(list)).toEqual(["S2", "c", "d", "S1", "a", "b"])
  })

  it("moves a section block before the target section when dragging up", () => {
    const { list, movedIds } = reorderSectionBlock(build(), "S2", "a")
    expect(movedIds).toEqual(["S2", "c", "d"])
    expect(ids(list)).toEqual(["S2", "c", "d", "S1", "a", "b"])
  })

  it("dropping onto the section's own block is a no-op (returns a copy)", () => {
    const input = build()
    const { list, movedIds } = reorderSectionBlock(input, "S1", "a")
    expect(list).not.toBe(input)
    expect(ids(list)).toEqual(["S1", "a", "b", "S2", "c", "d"])
    expect(movedIds).toEqual(["S1", "a", "b"])
  })

  it("returns an unchanged copy with empty movedIds when the section id is missing", () => {
    const input = build()
    const { list, movedIds } = reorderSectionBlock(input, "nope", "a")
    expect(ids(list)).toEqual(ids(input))
    expect(movedIds).toEqual([])
  })

  it("returns unchanged when the target id is missing", () => {
    const { list, movedIds } = reorderSectionBlock(build(), "S1", "ghost")
    expect(ids(list)).toEqual(["S1", "a", "b", "S2", "c", "d"])
    expect(movedIds).toEqual(["S1", "a", "b"])
  })

  it("inserts before the whole list when the target sits ahead of any section header", () => {
    // [x, y, S1, a] — "x" has no section header at or before it (tStart stays -1).
    const input = [f("x"), f("y"), section("S1"), f("a")]
    const { list, movedIds } = reorderSectionBlock(input, "S1", "x")
    expect(movedIds).toEqual(["S1", "a"])
    // beforeId resolves to list[0]'s id ("x"), so the block lands at the front.
    expect(ids(list)).toEqual(["S1", "a", "x", "y"])
  })

  it("falls back to appending when list[0] is a falsy leading entry", () => {
    // `0` is falsy but a safe stand-in (property access via `&&`/`? :` never
    // throws on it), so it exercises the `list[0] ? … : null` false branch
    // without needing `list` to actually be empty (which the earlier findIndex
    // guards already rule out).
    const input = [0, f("y"), section("S1"), f("a")]
    const { list, movedIds } = reorderSectionBlock(input, "S1", "y")
    expect(movedIds).toEqual(["S1", "a"])
    // beforeId stays null → no beforeId/afterId match → block appends at the end.
    expect(ids(list)).toEqual([undefined, "y", "S1", "a"])
  })
})
