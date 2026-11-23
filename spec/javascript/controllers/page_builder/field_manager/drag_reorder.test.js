import { describe, it, expect, beforeEach } from "vitest"
import { FieldManager } from "controllers/page_builder/field_manager"
import { makeCtrl, field } from "../../../support/page_builder.js"

// DragReorderMixin is applied to FieldManager.prototype and leans on
// _isSectionField / _isAutoSectionDivider from the base class, so we test it
// through a real FieldManager instance.
const sec = (id) => field({ id, field_type: "section", property_type: "layout" })
const autoDiv = (id) => field({ id, field_type: "divider", property_type: "layout", auto_section_divider: true })
const ids = (list) => list.map((f) => f.id)

describe("DragReorderMixin._sectionIdForDrag", () => {
  let ctrl, fm
  beforeEach(() => {
    ctrl = makeCtrl({ currentPage: { id: "p1", fields: [sec("s1"), field({ id: "a" })] } })
    fm = new FieldManager(ctrl)
  })

  it("returns the dragged id when it is a section header", () => {
    expect(fm._sectionIdForDrag("s1")).toBe("s1")
  })

  it("returns null when a plain field is dragged with no section in the selection", () => {
    expect(fm._sectionIdForDrag("a")).toBeNull()
  })

  it("finds a section header inside the active multi-selection", () => {
    ctrl.reorderingFieldIds = ["a", "s1"]
    expect(fm._sectionIdForDrag("a")).toBe("s1")
  })
})

describe("DragReorderMixin._reorderSection", () => {
  // [S1, a, b, S2, c, d]
  const build = () => makeCtrl({
    currentPage: { id: "p1", fields: [sec("S1"), field({ id: "a" }), field({ id: "b" }), sec("S2"), field({ id: "c" }), field({ id: "d" })] },
  })

  it("moves a section block after the target section when dragging down", () => {
    const ctrl = build()
    const fm = new FieldManager(ctrl)
    const moved = fm._reorderSection("S1", "c")
    expect(moved).toEqual(["S1", "a", "b"])
    expect(ids(ctrl.currentPage.fields)).toEqual(["S2", "c", "d", "S1", "a", "b"])
  })

  it("moves a section block before the target section when dragging up", () => {
    const ctrl = build()
    const fm = new FieldManager(ctrl)
    const moved = fm._reorderSection("S2", "a")
    expect(moved).toEqual(["S2", "c", "d"])
    expect(ids(ctrl.currentPage.fields)).toEqual(["S2", "c", "d", "S1", "a", "b"])
  })

  it("strips auto dividers off the working list (re-added on next render)", () => {
    const ctrl = makeCtrl({
      currentPage: { id: "p1", fields: [sec("S1"), field({ id: "a" }), autoDiv("D"), sec("S2"), field({ id: "c" })] },
    })
    const fm = new FieldManager(ctrl)
    fm._reorderSection("S1", "c")
    expect(ids(ctrl.currentPage.fields)).not.toContain("D")
  })

  it("dropping onto the block's own field is a no-op", () => {
    const ctrl = build()
    const fm = new FieldManager(ctrl)
    const moved = fm._reorderSection("S1", "a")
    expect(moved).toEqual(["S1", "a", "b"])
    expect(ids(ctrl.currentPage.fields)).toEqual(["S1", "a", "b", "S2", "c", "d"])
  })

  it("returns null when the section id is not found", () => {
    const ctrl = build()
    const fm = new FieldManager(ctrl)
    expect(fm._reorderSection("ghost", "a")).toBeNull()
  })

  it("returns the moved ids unchanged when the target id is not found", () => {
    const ctrl = build()
    const fm = new FieldManager(ctrl)
    const moved = fm._reorderSection("S1", "ghost")
    expect(moved).toEqual(["S1", "a", "b"])
    expect(ids(ctrl.currentPage.fields)).toEqual(["S1", "a", "b", "S2", "c", "d"])
  })

  it("drops above the page when the target sits before any section header", () => {
    // [x, y, S1, a, S2, c] — "x" has no section header at or before it.
    const ctrl = makeCtrl({
      currentPage: {
        id: "p1",
        fields: [field({ id: "x" }), field({ id: "y" }), sec("S1"), field({ id: "a" }), sec("S2"), field({ id: "c" })],
      },
    })
    const fm = new FieldManager(ctrl)
    const moved = fm._reorderSection("S2", "x")
    expect(moved).toEqual(["S2", "c"])
    expect(ids(ctrl.currentPage.fields)).toEqual(["S2", "c", "x", "y", "S1", "a"])
  })

  it("resolves beforeId to null when the leading field carries no id (`?? null` branch)", () => {
    // First field is an id-less object (still an object, so the later
    // `f.order = i` write-back succeeds) sitting before any section header.
    const noId = { field_type: "text", property_type: "string", label: "x" }
    const ctrl = makeCtrl({
      currentPage: { id: "p1", fields: [noId, field({ id: "t" }), sec("S1"), field({ id: "a" })] },
    })
    const fm = new FieldManager(ctrl)
    const moved = fm._reorderSection("S1", "t")
    expect(moved).toEqual(["S1", "a"])
    // beforeId resolves to null → the block is appended to the end.
    expect(ids(ctrl.currentPage.fields.filter((f) => f.id))).toEqual(["t", "S1", "a"])
  })
})
