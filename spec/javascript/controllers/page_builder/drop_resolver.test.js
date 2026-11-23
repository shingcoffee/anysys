// NOTE: buildSnapshot / _topLevelRegion / _allNestedEntries / _buildEntry are
// exercised below by stubbing getBoundingClientRect on real DOM nodes (per
// AGENT_GUIDE). _containerRegion's `:scope > .field-card` query is a genuine
// happy-dom limitation — `:scope` with a leading combinator always returns 0
// matches there even though real browsers resolve it fine — so its forEach
// body (the only place per-card rects get read) is UNREACHABLE here; see the
// dedicated describe block below for what we CAN assert about it.
import { describe, it, expect, vi } from "vitest"
import { DropResolver } from "controllers/page_builder/drop_resolver"
import { makeCtrl, field } from "../../support/page_builder.js"
import * as dropGeometry from "controllers/page_builder/dnd/drop_geometry"

const cell = (id, index, left, right, top = 0, bottom = 20) => ({ id, index, left, right, top, bottom })

// Builds a field card element with a stubbed getBoundingClientRect (happy-dom
// always returns zeros for real layout).
const cardEl = (fieldId, rect = { left: 0, right: 100, top: 0, bottom: 20 }) => {
  const el = document.createElement("div")
  el.dataset.fieldId = fieldId
  el.className = "field-card"
  Object.defineProperty(el, "getBoundingClientRect", { value: () => rect })
  return el
}

describe("DropResolver.resolve (pure, off a cached snapshot)", () => {
  it("returns null without a snapshot", () => {
    const dr = new DropResolver(makeCtrl())
    expect(dr.resolve({ x: 0, y: 0 }, { kind: "new", data: {} }, null)).toBeNull()
  })

  it("resolves an insert slot and tags targetFieldId for the page container", () => {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "a" }), field({ id: "b" })] } })
    const dr = new DropResolver(ctrl)
    const snapshot = {
      topLevel: { containerKey: "page", rows: [{ top: 0, bottom: 20, cells: [cell("a", 0, 0, 100), cell("b", 1, 100, 200)] }] },
      nested: [],
    }
    // New-field drag (not a move) so no swap path; point in leading part of cell b.
    const slot = dr.resolve({ x: 110, y: 10 }, { kind: "new", data: { type: "text" } }, snapshot)
    expect(slot.mode).toBe("insert")
    expect(slot.containerKey).toBe("page")
    expect(slot.index).toBe(1)
    expect(slot.targetFieldId).toBe("b")
  })

  it("produces a swap target when a single field is dragged over another field's body", () => {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "a" }), field({ id: "b" })] } })
    const dr = new DropResolver(ctrl)
    const snapshot = {
      topLevel: { containerKey: "page", rows: [{ top: 0, bottom: 20, cells: [cell("a", 0, 0, 100), cell("b", 1, 100, 200)] }] },
      nested: [],
    }
    // Dragging "a", pointer over the central body of "b" (x=150 within 12% pads).
    const slot = dr.resolve({ x: 150, y: 10 }, { kind: "move", fieldIds: ["a"], primaryId: "a", isSection: false }, snapshot)
    expect(slot.mode).toBe("swap")
    expect(slot.swapFieldId).toBe("b")
  })
})

describe("DropResolver._swapTarget guards", () => {
  const region = { containerKey: "page", rows: [{ top: 0, bottom: 20, cells: [cell("b", 1, 100, 200)] }] }
  const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "a" }), field({ id: "b" })] } })
  const dr = new DropResolver(ctrl)

  it("returns null for non-page regions", () => {
    expect(dr._swapTarget({ containerKey: "group:x", rows: [] }, { x: 150, y: 10 }, { kind: "move", fieldIds: ["a"], primaryId: "a" })).toBeNull()
  })
  it("returns null for section drags and multi-field selections", () => {
    expect(dr._swapTarget(region, { x: 150, y: 10 }, { kind: "move", isSection: true, fieldIds: ["a"], primaryId: "a" })).toBeNull()
    expect(dr._swapTarget(region, { x: 150, y: 10 }, { kind: "move", fieldIds: ["a", "c"], primaryId: "a" })).toBeNull()
  })
  it("returns null over the outer 12% padding (that region is an insert, not a swap)", () => {
    expect(dr._swapTarget(region, { x: 105, y: 10 }, { kind: "move", fieldIds: ["a"], primaryId: "a" })).toBeNull()
  })
})

describe("DropResolver._mayNest / _typeOf", () => {
  it("is false for section drags and for columns/group payloads", () => {
    const ctrl = makeCtrl()
    ctrl.fieldManager.findFieldById = vi.fn(() => ({ type: "columns" }))
    const dr = new DropResolver(ctrl)
    expect(dr._mayNest({ isSection: true })).toBe(false)
    expect(dr._mayNest({ kind: "new", data: { type: "columns" } })).toBe(false)
    expect(dr._mayNest({ kind: "new", data: { type: "field_group" } })).toBe(false)
    expect(dr._mayNest({ kind: "move", primaryId: "x" })).toBe(false) // findFieldById → columns
  })

  it("is true for an ordinary new field", () => {
    const dr = new DropResolver(makeCtrl())
    expect(dr._mayNest({ kind: "new", data: { type: "text" } })).toBe(true)
  })
})

describe("DropResolver._newFieldAllowed", () => {
  it("rejects nullish data and entity fields without an html type", () => {
    const dr = new DropResolver(makeCtrl())
    expect(dr._newFieldAllowed(null)).toBe(false)
    expect(dr._newFieldAllowed({ type: "entity" })).toBe(false)
    expect(dr._newFieldAllowed({ type: "entity", htmlType: "text" })).toBe(true)
  })

  it("rejects a field whose property slug is already used", () => {
    const ctrl = makeCtrl()
    ctrl.fieldManager.getUsedPropertySlugs = vi.fn(() => new Set(["email"]))
    const dr = new DropResolver(ctrl)
    expect(dr._newFieldAllowed({ type: "text", propertySlug: "email" })).toBe(false)
    expect(dr._newFieldAllowed({ type: "text", propertySlug: "phone" })).toBe(true)
  })
})

describe("DropResolver.resolve — remaining branches", () => {
  it("returns null when resolveSlot finds no slot", () => {
    // resolveSlot (the pure geometry helper) always returns an object in
    // practice — this guard is defensive. Stub it to exercise the guard.
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "a" })] } })
    const dr = new DropResolver(ctrl)
    const spy = vi.spyOn(dropGeometry, "resolveSlot").mockReturnValue(null)
    const snapshot = { topLevel: { containerKey: "page", rows: [] }, nested: [] }
    expect(dr.resolve({ x: 0, y: 0 }, { kind: "new", data: { type: "text" } }, snapshot)).toBeNull()
    spy.mockRestore()
  })

  it("falls back to null targetFieldId when the resolved index is past the end of the field list", () => {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "a" })] } })
    const dr = new DropResolver(ctrl)
    const snapshot = {
      topLevel: { containerKey: "page", rows: [{ top: 0, bottom: 20, cells: [cell("a", 0, 0, 100)] }] },
      nested: [],
    }
    // Point well past the only cell -> insert-after-last, index beyond fields.length.
    const slot = dr.resolve({ x: 500, y: 10 }, { kind: "new", data: { type: "text" } }, snapshot)
    expect(slot.mode).toBe("insert")
    expect(slot.targetFieldId).toBeNull()
  })
})

describe("DropResolver._swapTarget — remaining guard", () => {
  it("returns null when the dragged field isn't itself a top-level field", () => {
    const region = { containerKey: "page", rows: [{ top: 0, bottom: 20, cells: [cell("b", 1, 100, 200)] }] }
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "b" })] } }) // "a" not top-level
    const dr = new DropResolver(ctrl)
    expect(dr._swapTarget(region, { x: 150, y: 10 }, { kind: "move", fieldIds: ["a"], primaryId: "a" })).toBeNull()
  })
})

describe("DropResolver._typeOf", () => {
  it("returns null when the field can't be found", () => {
    const ctrl = makeCtrl() // findFieldById default mock returns undefined
    const dr = new DropResolver(ctrl)
    expect(dr._typeOf("missing")).toBeNull()
  })

  it("falls back to field_type when type is absent", () => {
    const ctrl = makeCtrl()
    ctrl.fieldManager.findFieldById = vi.fn(() => ({ field_type: "text" }))
    const dr = new DropResolver(ctrl)
    expect(dr._typeOf("a")).toBe("text")
  })
})

describe("DropResolver geometry readers (real DOM, stubbed rects)", () => {
  const withContainer = (children) => {
    const ctrl = makeCtrl()
    const container = document.createElement("div")
    children.forEach((el) => container.appendChild(el))
    ctrl.hasFieldsContainerTarget = true
    ctrl.fieldsContainerTarget = container
    return ctrl
  }

  describe("_topLevelRegion", () => {
    it("builds cells for rendered cards, skipping moving fields and fields with no rendered card", () => {
      const fields = [field({ id: "a" }), field({ id: "b" }), field({ id: "c" })]
      // Only "a" and "b" have rendered cards; "c" is in the data but not the DOM.
      const ctrl = withContainer([cardEl("a", { left: 0, right: 100, top: 0, bottom: 20 }), cardEl("b", { left: 100, right: 200, top: 0, bottom: 20 })])
      ctrl.currentPage = { id: "p1", fields }
      const dr = new DropResolver(ctrl)
      const region = dr._topLevelRegion({ kind: "move", fieldIds: ["a"] })
      expect(region.containerKey).toBe("page")
      const ids = region.rows.flatMap((r) => r.cells.map((c) => c.id))
      expect(ids).toEqual(["b"]) // "a" skipped (moving), "c" skipped (no card)
    })

    it("does not skip anything for a non-move payload", () => {
      const fields = [field({ id: "a" })]
      const ctrl = withContainer([cardEl("a")])
      ctrl.currentPage = { id: "p1", fields }
      const dr = new DropResolver(ctrl)
      const region = dr._topLevelRegion({ kind: "new", data: {} })
      expect(region.rows.flatMap((r) => r.cells.map((c) => c.id))).toEqual(["a"])
    })
  })

  describe("_allNestedEntries / _buildEntry", () => {
    it("collects group and column containers as nested entries with their rect", () => {
      const groupEl = document.createElement("div")
      groupEl.dataset.groupFieldsContainer = "g1"
      Object.defineProperty(groupEl, "getBoundingClientRect", { value: () => ({ left: 5, right: 55, top: 5, bottom: 55 }) })

      const colEl = document.createElement("div")
      colEl.dataset.columnIndex = "0"
      colEl.dataset.parentFieldId = "cols1"
      Object.defineProperty(colEl, "getBoundingClientRect", { value: () => ({ left: 60, right: 110, top: 5, bottom: 55 }) })

      const ctrl = withContainer([groupEl, colEl])
      const dr = new DropResolver(ctrl)
      const entries = dr._allNestedEntries({ kind: "new", data: {} })
      expect(entries).toHaveLength(2)
      expect(entries[0]).toMatchObject({ mayNest: true, rect: { left: 5, right: 55, top: 5, bottom: 55 } })
      expect(entries[0].region.containerKey).toBe("group:g1")
      expect(entries[1].region.containerKey).toBe("column:cols1:0")
    })

    it("returns an empty list when there are no nestable containers", () => {
      const ctrl = withContainer([])
      const dr = new DropResolver(ctrl)
      expect(dr._allNestedEntries({ kind: "new", data: {} })).toEqual([])
    })
  })

  describe("_containerRegion", () => {
    it("builds a row from each direct-child field-card (rects stubbed)", () => {
      const containerEl = document.createElement("div")
      containerEl.appendChild(cardEl("x"))
      const ctrl = makeCtrl()
      const dr = new DropResolver(ctrl)
      const region = dr._containerRegion(containerEl, "group:g1", { kind: "new", data: {} })
      expect(region.containerKey).toBe("group:g1")
      expect(region.rows).toHaveLength(1)
      expect(region.rows[0].cells).toHaveLength(1)
      expect(region.rows[0].cells[0].id).toBe("x")
    })

    it("skips cards that are being moved (payload.fieldIds)", () => {
      const containerEl = document.createElement("div")
      containerEl.appendChild(cardEl("a"))
      const dr = new DropResolver(makeCtrl())
      const region = dr._containerRegion(containerEl, "group:g1", { kind: "move", fieldIds: ["a"] })
      expect(region).toEqual({ containerKey: "group:g1", rows: [] })
    })

    it("builds the moving-fields set from payload.fieldIds on a move payload", () => {
      const containerEl = document.createElement("div")
      const ctrl = makeCtrl()
      const dr = new DropResolver(ctrl)
      const region = dr._containerRegion(containerEl, "group:g1", { kind: "move", fieldIds: ["a"] })
      expect(region).toEqual({ containerKey: "group:g1", rows: [] })
    })
  })

  describe("buildSnapshot", () => {
    it("returns null without a fields container", () => {
      const ctrl = makeCtrl()
      ctrl.hasFieldsContainerTarget = false
      const dr = new DropResolver(ctrl)
      expect(dr.buildSnapshot({ kind: "new", data: { type: "text" } })).toBeNull()
    })

    it("returns null for a disallowed new field", () => {
      const ctrl = withContainer([])
      const dr = new DropResolver(ctrl)
      expect(dr.buildSnapshot({ kind: "new", data: null })).toBeNull()
    })

    it("builds a full snapshot with topLevel + nested entries when nesting is allowed", () => {
      const fields = [field({ id: "a" })]
      const groupEl = document.createElement("div")
      groupEl.dataset.groupFieldsContainer = "g1"
      Object.defineProperty(groupEl, "getBoundingClientRect", { value: () => ({ left: 0, right: 50, top: 0, bottom: 50 }) })
      const ctrl = withContainer([cardEl("a"), groupEl])
      ctrl.currentPage = { id: "p1", fields }
      const dr = new DropResolver(ctrl)
      const snapshot = dr.buildSnapshot({ kind: "new", data: { type: "text" } })
      expect(snapshot.topLevel.rows.flatMap((r) => r.cells.map((c) => c.id))).toEqual(["a"])
      expect(snapshot.nested).toHaveLength(1)
    })

    it("skips nested-entry collection when the dragged payload may not nest", () => {
      const ctrl = withContainer([cardEl("a")])
      ctrl.currentPage = { id: "p1", fields: [field({ id: "a" })] }
      const dr = new DropResolver(ctrl)
      const snapshot = dr.buildSnapshot({ kind: "new", data: { type: "columns" } })
      expect(snapshot.nested).toEqual([])
    })
  })
})

describe("DropResolver._cellsToRows", () => {
  it("groups overlapping cells into one row, sorted by left edge", () => {
    const ctrl = makeCtrl()
    const dr = new DropResolver(ctrl)
    const cells = [cell("b", 0, 100, 200, 0, 20), cell("a", 1, 0, 100, 2, 22)]
    const rows = dr._cellsToRows(cells)
    expect(rows).toHaveLength(1)
    expect(rows[0].cells.map((c) => c.id)).toEqual(["a", "b"]) // sorted by left
  })

  it("starts a new row when a cell's top is not within the overlap threshold", () => {
    const ctrl = makeCtrl()
    const dr = new DropResolver(ctrl)
    const cells = [cell("a", 0, 0, 100, 0, 20), cell("b", 1, 0, 100, 40, 60)]
    const rows = dr._cellsToRows(cells)
    expect(rows).toHaveLength(2)
  })

  it("returns no rows for an empty cell list", () => {
    const ctrl = makeCtrl()
    const dr = new DropResolver(ctrl)
    expect(dr._cellsToRows([])).toEqual([])
  })
})
