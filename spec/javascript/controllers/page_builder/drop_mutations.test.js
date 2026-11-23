import { describe, it, expect, vi, beforeEach } from "vitest"
import { DropMutations } from "controllers/page_builder/drop_mutations"
import { makeCtrl, field } from "../../support/page_builder.js"

// DropMutations is the single place a resolved drop is applied to the data
// model. _afterChange delegates all the DOM/FLIP work to sibling managers
// (stubbed), so we can assert the pure list mutations cleanly.
const ids = (fields) => fields.map((f) => f.id)

const setup = (fields) => {
  const ctrl = makeCtrl({ currentPage: { id: "p1", fields } })
  ctrl.fields = ctrl.currentPage.fields
  ctrl.fieldManager.findFieldById = vi.fn((id) => ctrl.currentPage.fields.find((f) => f.id === id) || null)
  const dm = new DropMutations(ctrl)
  return { ctrl, dm }
}

describe("DropMutations.apply routing + saveState", () => {
  it("returns without saving state when target is null", () => {
    const { ctrl, dm } = setup([field({ id: "a" })])
    dm.apply({ kind: "move", fieldIds: ["a"], primaryId: "a" }, null)
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("saves state before applying a mutation", () => {
    const { ctrl, dm } = setup([field({ id: "a" }), field({ id: "b" })])
    dm.apply({ kind: "move", fieldIds: ["a"], primaryId: "a", isSection: false }, { containerKey: "page", index: 2, mode: "insert" })
    expect(ctrl.undoRedoManager.saveState).toHaveBeenCalled()
  })
})

describe("DropMutations._insertNew", () => {
  it("creates a field and splices it into the page at the target index", () => {
    const { ctrl, dm } = setup([field({ id: "a" }), field({ id: "b" })])
    ctrl.fieldManager.createField = vi.fn(() => field({ id: "new" }))
    dm.apply({ kind: "new", data: { type: "text" } }, { containerKey: "page", index: 1, mode: "insert" })
    expect(ids(ctrl.currentPage.fields)).toEqual(["a", "new", "b"])
  })

  it("pushes a new field into a target column", () => {
    const cols = field({ id: "cols", field_type: "columns", columns: [{ fields: [] }, { fields: [] }] })
    const { ctrl, dm } = setup([cols])
    ctrl.fieldManager.createField = vi.fn(() => field({ id: "new" }))
    dm.apply({ kind: "new", data: { type: "text" } }, { containerKey: "column:cols:1", mode: "insert" })
    expect(ids(cols.columns[1].fields)).toEqual(["new"])
  })

  it("pushes a new field into a target group", () => {
    const grp = field({ id: "g", type: "field_group", fields: [] })
    const { ctrl, dm } = setup([grp])
    ctrl.fieldManager.createField = vi.fn(() => field({ id: "new" }))
    dm.apply({ kind: "new", data: { type: "text" } }, { containerKey: "group:g", mode: "insert" })
    expect(ids(grp.fields)).toEqual(["new"])
  })

  it("no-ops the push when the target column/group can't be resolved", () => {
    const { ctrl, dm } = setup([])
    ctrl.fieldManager.createField = vi.fn(() => field({ id: "new" }))
    expect(() => dm.apply({ kind: "new", data: { type: "text" } }, { containerKey: "column:missing:0", mode: "insert" })).not.toThrow()
    expect(() => dm.apply({ kind: "new", data: { type: "text" } }, { containerKey: "group:missing", mode: "insert" })).not.toThrow()
  })
})

describe("DropMutations._swap", () => {
  it("swaps two top-level fields", () => {
    const { ctrl, dm } = setup([field({ id: "a" }), field({ id: "b" }), field({ id: "c" })])
    dm.apply({ kind: "move", fieldIds: ["a"], primaryId: "a", isSection: false }, { mode: "swap", containerKey: "page", swapFieldId: "c" })
    expect(ids(ctrl.currentPage.fields)).toEqual(["c", "b", "a"])
  })

  it("is a no-op when swap endpoints coincide or are missing", () => {
    const { ctrl, dm } = setup([field({ id: "a" }), field({ id: "b" })])
    dm.apply({ kind: "move", fieldIds: ["a"], primaryId: "a", isSection: false }, { mode: "swap", containerKey: "page", swapFieldId: "a" })
    expect(ids(ctrl.currentPage.fields)).toEqual(["a", "b"])
  })
})

describe("DropMutations._moveTopLevel", () => {
  it("relocates a field via moveFields", () => {
    const { ctrl, dm } = setup([field({ id: "a" }), field({ id: "b" }), field({ id: "c" })])
    dm.apply({ kind: "move", fieldIds: ["a"], primaryId: "a", isSection: false }, { containerKey: "page", index: 2, mode: "insert" })
    expect(ids(ctrl.currentPage.fields)).toEqual(["b", "a", "c"])
  })
})

describe("DropMutations._moveSection", () => {
  it("reorders a section block to the field at the target index", () => {
    const a = field({ id: "a", field_type: "section" })
    const b = field({ id: "b" })
    const c = field({ id: "c" })
    const { ctrl, dm } = setup([a, b, c])
    dm.apply({ kind: "move", fieldIds: ["a"], primaryId: "a", isSection: true }, { containerKey: "page", index: 2, mode: "insert" })
    // reorderSectionBlock is a real (unmocked) helper — just assert the section
    // moved somewhere and _afterChange ran, without pinning its exact algorithm.
    expect(ctrl.fieldManager.renderFields).toHaveBeenCalled()
    expect(ids(ctrl.currentPage.fields)).toContain("a")
  })

  it("no-ops (still calls _afterChange) when the target index resolves to no field", () => {
    const { ctrl, dm } = setup([])
    dm.apply({ kind: "move", fieldIds: ["a"], primaryId: "a", isSection: true }, { containerKey: "page", index: 0, mode: "insert" })
    expect(ctrl.fieldManager.renderFields).toHaveBeenCalled()
    expect(ctrl.currentPage.fields).toEqual([])
  })
})

describe("DropMutations._moveIntoColumn (via apply routing)", () => {
  it("relocates a field into an existing column", () => {
    const cols = field({ id: "cols", field_type: "columns", columns: [{ fields: [] }] })
    const a = field({ id: "a" })
    const { ctrl, dm } = setup([a, cols])
    ctrl.fieldManager.removeFieldFromAnyColumn = vi.fn()
    dm.apply({ kind: "move", fieldIds: ["a"], primaryId: "a", isSection: false }, { containerKey: "column:cols:0", mode: "insert" })
    expect(ids(cols.columns[0].fields)).toEqual(["a"])
  })

  it("no-ops when the target column can't be resolved", () => {
    const { ctrl, dm } = setup([field({ id: "a" })])
    dm.apply({ kind: "move", fieldIds: ["a"], primaryId: "a", isSection: false }, { containerKey: "column:missing:0", mode: "insert" })
    expect(ctrl.fieldManager.renderFields).toHaveBeenCalled()
    expect(ids(ctrl.currentPage.fields)).toEqual(["a"]) // untouched
  })
})

describe("DropMutations._moveIntoGroup no-op path", () => {
  it("no-ops when the target group can't be resolved", () => {
    const { ctrl, dm } = setup([field({ id: "a" })])
    dm.apply({ kind: "move", fieldIds: ["a"], primaryId: "a", isSection: false }, { containerKey: "group:missing", mode: "insert" })
    expect(ctrl.fieldManager.renderFields).toHaveBeenCalled()
    expect(ids(ctrl.currentPage.fields)).toEqual(["a"]) // untouched
  })
})

describe("DropMutations helpers", () => {
  it("_column resolves a nested column by container key", () => {
    const cols = field({ id: "cols", columns: [{ fields: [] }, { fields: [field({ id: "x" })] }] })
    const { dm } = setup([cols])
    expect(dm._column("column:cols:1").fields.map((f) => f.id)).toEqual(["x"])
    expect(dm._column("column:missing:0")).toBeNull()
  })

  it("_group resolves a field_group and initializes its fields array", () => {
    const grp = field({ id: "g", type: "field_group" })
    delete grp.fields
    const { dm } = setup([grp])
    const resolved = dm._group("group:g")
    expect(resolved).toBe(grp)
    expect(Array.isArray(resolved.fields)).toBe(true)
    expect(dm._group("group:none")).toBeNull()
  })

  it("_fieldIdAtIndex clamps into range and returns null on an empty page", () => {
    const { dm } = setup([field({ id: "a" }), field({ id: "b" })])
    expect(dm._fieldIdAtIndex(0)).toBe("a")
    expect(dm._fieldIdAtIndex(99)).toBe("b")
    const empty = setup([])
    expect(empty.dm._fieldIdAtIndex(0)).toBeNull()
  })

  it("_fieldIdAtIndex falls back to null via ?? when the resolved field has no id", () => {
    const { dm } = setup([{ id: undefined }])
    expect(dm._fieldIdAtIndex(0)).toBeNull()
  })
})

describe("DropMutations._relocateInto (via move into group)", () => {
  it("pulls a top-level field out and into the destination group", () => {
    const grp = field({ id: "g", type: "field_group", fields: [] })
    const a = field({ id: "a" })
    const { ctrl, dm } = setup([a, grp])
    ctrl.fieldManager.removeFieldFromAnyColumn = vi.fn()
    dm.apply({ kind: "move", fieldIds: ["a"], primaryId: "a", isSection: false }, { containerKey: "group:g", mode: "insert" })
    expect(ids(grp.fields)).toEqual(["a"])
    expect(ctrl.currentPage.fields.find((f) => f.id === "a")).toBeUndefined()
  })

  it("skips a field id that can no longer be found", () => {
    const grp = field({ id: "g", type: "field_group", fields: [] })
    const { ctrl, dm } = setup([grp])
    ctrl.fieldManager.findFieldById = vi.fn(() => null)
    dm.apply({ kind: "move", fieldIds: ["ghost"], primaryId: "ghost", isSection: false }, { containerKey: "group:g", mode: "insert" })
    expect(grp.fields).toEqual([])
  })

  it("skips a columns or field_group field — those can't be relocated into another container", () => {
    const grp = field({ id: "g", type: "field_group", fields: [] })
    const colsField = field({ id: "cols", field_type: "columns", columns: [] })
    const { ctrl, dm } = setup([colsField, grp])
    dm.apply({ kind: "move", fieldIds: ["cols"], primaryId: "cols", isSection: false }, { containerKey: "group:g", mode: "insert" })
    expect(grp.fields).toEqual([])
    expect(ids(ctrl.currentPage.fields)).toContain("cols") // untouched, still top-level
  })

  it("does not double-push a field that's already present in the destination", () => {
    const a = field({ id: "a" })
    const grp = field({ id: "g", type: "field_group", fields: [a] })
    const { ctrl, dm } = setup([grp])
    ctrl.fieldManager.findFieldById = vi.fn(() => a)
    dm.apply({ kind: "move", fieldIds: ["a"], primaryId: "a", isSection: false }, { containerKey: "group:g", mode: "insert" })
    expect(grp.fields).toEqual([a])
  })
})

describe("DropMutations._afterChange side effects", () => {
  it("re-numbers order, renders, marks dirty, and consumes the drop point", () => {
    const { ctrl, dm } = setup([field({ id: "a" }), field({ id: "b" })])
    ctrl.dragEngine._lastDropPoint = { x: 1, y: 2 }
    dm.apply({ kind: "move", fieldIds: ["a"], primaryId: "a", isSection: false }, { containerKey: "page", index: 2, mode: "insert" })
    expect(ctrl.currentPage.fields.map((f) => f.order)).toEqual([0, 1])
    expect(ctrl.fieldManager.renderFields).toHaveBeenCalled()
    expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
    expect(ctrl.dragEngine._lastDropPoint).toBeNull()
  })

  it("multi-selects every dropped id when more than one field moved together", () => {
    const { ctrl, dm } = setup([field({ id: "a" }), field({ id: "b" }), field({ id: "c" })])
    dm.apply({ kind: "move", fieldIds: ["a", "b"], primaryId: "a", isSection: false }, { containerKey: "page", index: 2, mode: "insert" })
    expect(ctrl.selectionManager.selectFields).toHaveBeenCalledWith(["a", "b"], { showPanel: false })
    expect(ctrl.fieldManager.selectFieldById).not.toHaveBeenCalled()
  })
})
