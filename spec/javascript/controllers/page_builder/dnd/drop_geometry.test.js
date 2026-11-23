import { describe, it, expect } from "vitest"
import { pickRegion, resolveSlot } from "controllers/page_builder/dnd/drop_geometry"

// Pure geometry helpers — no DOM. We feed hand-built region/snapshot objects
// (the same shape DropResolver.buildSnapshot produces) so this is exact,
// deterministic logic testing, not fake-layout guessing.

const cell = (index, left, right, top = 0, bottom = 10, id = `c${index}`) =>
  ({ index, left, right, top, bottom, id })
const row = (top, bottom, cells) => ({ top, bottom, cells })

describe("pickRegion", () => {
  const nested = (rect, mayNest, key) => ({ rect, mayNest, region: { containerKey: key, rows: [] } })

  it("falls back to topLevel when no nested container contains the pointer", () => {
    const snapshot = {
      topLevel: { containerKey: "page", rows: [] },
      nested: [nested({ left: 0, right: 10, top: 0, bottom: 10 }, true, "group:g")],
    }
    expect(pickRegion(snapshot, { x: 100, y: 100 })).toBe(snapshot.topLevel)
  })

  it("selects a nested region whose rect contains the pointer", () => {
    const entry = nested({ left: 0, right: 50, top: 0, bottom: 50 }, true, "group:g")
    const snapshot = { topLevel: { containerKey: "page", rows: [] }, nested: [entry] }
    expect(pickRegion(snapshot, { x: 25, y: 25 })).toBe(entry.region)
  })

  it("ignores containers with mayNest=false", () => {
    const entry = nested({ left: 0, right: 50, top: 0, bottom: 50 }, false, "group:g")
    const snapshot = { topLevel: { containerKey: "page", rows: [] }, nested: [entry] }
    expect(pickRegion(snapshot, { x: 25, y: 25 })).toBe(snapshot.topLevel)
  })

  it("innermost/last matching container wins (loop keeps the last match)", () => {
    const outer = nested({ left: 0, right: 100, top: 0, bottom: 100 }, true, "outer")
    const inner = nested({ left: 10, right: 40, top: 10, bottom: 40 }, true, "inner")
    const snapshot = { topLevel: { containerKey: "page", rows: [] }, nested: [outer, inner] }
    expect(pickRegion(snapshot, { x: 20, y: 20 })).toBe(inner.region)
  })

  it("honours inclusive edges of the rect", () => {
    const entry = nested({ left: 0, right: 50, top: 0, bottom: 50 }, true, "g")
    const snapshot = { topLevel: { containerKey: "page", rows: [] }, nested: [entry] }
    expect(pickRegion(snapshot, { x: 0, y: 0 })).toBe(entry.region)
    expect(pickRegion(snapshot, { x: 50, y: 50 })).toBe(entry.region)
  })
})

describe("resolveSlot", () => {
  it("returns index 0 / horizontal for an empty region", () => {
    const region = { containerKey: "page", rows: [] }
    expect(resolveSlot(region, { x: 5, y: 5 })).toEqual({
      containerKey: "page", index: 0, orientation: "horizontal", rect: null,
    })
  })

  it("above the first row → prepend before it", () => {
    const region = { containerKey: "page", rows: [row(100, 120, [cell(0, 0, 50, 100, 120)])] }
    const slot = resolveSlot(region, { x: 25, y: 10 })
    expect(slot.orientation).toBe("horizontal")
    expect(slot.index).toBe(0)
    expect(slot.rect.top).toBe(100) // before → row.top
  })

  it("below the last row → append after it", () => {
    const region = { containerKey: "page", rows: [row(0, 20, [cell(0, 0, 50)])] }
    const slot = resolveSlot(region, { x: 25, y: 999 })
    expect(slot.orientation).toBe("horizontal")
    expect(slot.index).toBe(1) // after last cell → index + 1
    expect(slot.rect.top).toBe(20) // after → row.bottom
  })

  it("single-cell row: upper half inserts before, lower half after", () => {
    const region = { containerKey: "page", rows: [row(0, 20, [cell(3, 0, 50, 0, 20)])] }
    expect(resolveSlot(region, { x: 25, y: 4 }).index).toBe(3)  // before cell
    expect(resolveSlot(region, { x: 25, y: 16 }).index).toBe(4) // after cell (index+1)
  })

  it("multi-cell row: leading 60% of a cell inserts before it (vertical)", () => {
    const cells = [cell(0, 0, 100, 0, 20, "a"), cell(1, 100, 200, 0, 20, "b")]
    const region = { containerKey: "page", rows: [row(0, 20, cells)] }
    // x=10 is within first cell's leading 60% (< 0 + 100*0.6 = 60)
    const slot = resolveSlot(region, { x: 10, y: 10 })
    expect(slot.orientation).toBe("vertical")
    expect(slot.index).toBe(0)
    expect(slot.rect.left).toBe(0)
  })

  it("multi-cell row: trailing 40% of the last cell inserts after it", () => {
    const cells = [cell(0, 0, 100, 0, 20, "a"), cell(1, 100, 200, 0, 20, "b")]
    const region = { containerKey: "page", rows: [row(0, 20, cells)] }
    // x=190 is in trailing 40% of last cell (> 100 + 100*0.6 = 160)
    const slot = resolveSlot(region, { x: 190, y: 10 })
    expect(slot.orientation).toBe("vertical")
    expect(slot.index).toBe(2) // lastCell.index + 1
    expect(slot.rect.left).toBe(200) // lastCell.right
  })

  it("snaps to the nearest row across a between-rows gap", () => {
    const r1 = row(0, 20, [cell(0, 0, 50, 0, 20)])
    const r2 = row(60, 80, [cell(1, 0, 50, 60, 80)])
    const region = { containerKey: "page", rows: [r1, r2] }
    // y=25 is just below r1 (dist 5) vs above r2 (dist 35) → resolves in r1
    expect(resolveSlot(region, { x: 25, y: 25 }).rect.top).toBe(20)
    // y=55 is closer to r2 (dist 5) than r1 (dist 35) → resolves in r2
    expect(resolveSlot(region, { x: 25, y: 55 }).rect.top).toBe(60)
  })

  it("treats a missing `rows` property as empty (the `|| []` fallback)", () => {
    // `rows: []` is already truthy, so only an absent/undefined `rows` exercises
    // the `region.rows || []` fallback branch.
    const region = { containerKey: "page" }
    expect(resolveSlot(region, { x: 5, y: 5 })).toEqual({
      containerKey: "page", index: 0, orientation: "horizontal", rect: null,
    })
  })

  it("horizontalSlot defaults left/right/index to 0 when the edge row has no cells", () => {
    // A row with an empty cells array (e.g. an emptied section) still needs a
    // prepend/append slot — horizontalSlot's `cells.length ? … : 0` fallbacks.
    const emptyRow = row(100, 120, [])
    const region = { containerKey: "page", rows: [emptyRow] }

    const before = resolveSlot(region, { x: 25, y: 10 }) // above the row → "before"
    expect(before).toEqual({
      containerKey: "page", index: 0, orientation: "horizontal",
      rect: { left: 0, top: 100, width: 0, height: 2 },
    })

    const after = resolveSlot(region, { x: 25, y: 999 }) // below the row → "after"
    expect(after).toEqual({
      containerKey: "page", index: 0, orientation: "horizontal",
      rect: { left: 0, top: 120, width: 0, height: 2 },
    })
  })
})
