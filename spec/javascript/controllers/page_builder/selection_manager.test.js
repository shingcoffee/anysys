import { describe, it, expect, beforeEach, vi, afterEach } from "vitest"
import { SelectionManager } from "controllers/page_builder/selection_manager"
import { makeCtrl, field } from "../../support/page_builder.js"

// NOTE: rubber-band selection (updateRubberBand / _highlightIntersecting /
// _selectIntersecting) resolves membership via getBoundingClientRect() card
// geometry, which happy-dom reports as zeroed rects — covered by Playwright
// (spec/e2e), not here. We test the pure selection algebra + the DOM-structural
// overlay lifecycle only, never fake-geometry hit results.

function selCtrl(fields = [], overrides = {}) {
  const ctrl = makeCtrl({ currentPage: { id: "p1", name: "Page 1", fields }, ...overrides })
  ctrl.propertyManager = {
    hideFloatingPanel: vi.fn(),
    showFloatingPanel: vi.fn(),
    showMultiSelectToolbar: vi.fn(),
    enableToolbarWidthForMulti: vi.fn(),
  }
  ctrl.pageManager = { moveFieldsToPage: vi.fn() }
  return ctrl
}

function newSM(fields = [], overrides = {}) {
  const ctrl = selCtrl(fields, overrides)
  const sm = new SelectionManager(ctrl)
  sm.initialize()
  return { sm, ctrl }
}

describe("SelectionManager — core selection algebra", () => {
  it("initialize() sets up empty state", () => {
    const { sm } = newSM()
    expect(sm.count).toBe(0)
    expect(sm.isEmpty).toBe(true)
    expect(sm.selectedFieldIds instanceof Set).toBe(true)
    expect(sm.lastSelectedFieldId).toBeNull()
  })

  it("single-select replaces the selection and sets the anchor", () => {
    const { sm } = newSM([field({ id: "a" }), field({ id: "b" })])
    sm.selectField("a")
    sm.selectField("b")
    expect(sm.getSelectedFieldIds()).toEqual(["b"])
    expect(sm.selectionAnchorId).toBe("b")
    expect(sm.lastSelectedFieldId).toBe("b")
    expect(sm.isSingleSelect).toBe(true)
  })

  it("meta-select toggles membership without clearing", () => {
    const { sm } = newSM([field({ id: "a" }), field({ id: "b" })])
    sm.selectField("a")
    sm.selectField("b", { meta: true })
    expect(sm.getSelectedFieldIds().sort()).toEqual(["a", "b"])
    expect(sm.isMultiSelect).toBe(true)
    sm.selectField("a", { meta: true }) // toggle off
    expect(sm.getSelectedFieldIds()).toEqual(["b"])
  })

  it("shift-select builds an inclusive range from the anchor", () => {
    const ids = ["a", "b", "c", "d"].map((id) => field({ id }))
    const { sm } = newSM(ids)
    sm.selectField("b") // anchor = b
    sm.selectField("d", { shift: true })
    expect(sm.getSelectedFieldIds()).toEqual(["b", "c", "d"])
  })

  it("shift-select works backwards (target before anchor)", () => {
    const ids = ["a", "b", "c", "d"].map((id) => field({ id }))
    const { sm } = newSM(ids)
    sm.selectField("c")
    sm.selectField("a", { shift: true })
    expect(sm.getSelectedFieldIds()).toEqual(["a", "b", "c"])
  })

  it("shift-select with an unknown anchor falls back to single-select", () => {
    const { sm } = newSM([field({ id: "a" }), field({ id: "b" })])
    sm.selectionAnchorId = "ghost"
    sm.selectField("b", { shift: true })
    expect(sm.getSelectedFieldIds()).toEqual(["b"])
  })

  it("selectAll selects every (flattened) field", () => {
    const { sm } = newSM([field({ id: "a" }), field({ id: "b" }), field({ id: "c" })])
    sm.selectAll()
    expect(sm.count).toBe(3)
    expect(sm.selectionAnchorId).toBe("a")
    expect(sm.lastSelectedFieldId).toBe("c")
  })

  it("selectFields takes an explicit id list and drops falsy entries", () => {
    const { sm } = newSM([field({ id: "a" }), field({ id: "b" })])
    sm.selectFields(["a", null, "b", undefined])
    expect(sm.getSelectedFieldIds()).toEqual(["a", "b"])
    expect(sm.selectionAnchorId).toBe("a")
    expect(sm.lastSelectedFieldId).toBe("b")
  })

  it("deselectAll clears everything and hides the panel", () => {
    const { sm, ctrl } = newSM([field({ id: "a" })])
    sm.selectField("a")
    sm.deselectAll()
    expect(sm.isEmpty).toBe(true)
    expect(sm.selectionAnchorId).toBeNull()
    expect(ctrl.propertyManager.hideFloatingPanel).toHaveBeenCalled()
  })

  it("addToSelection adds a single id without side effects", () => {
    const { sm } = newSM([field({ id: "a" })])
    sm.addToSelection("a")
    expect(sm.isSelected("a")).toBe(true)
  })

  it("selectFields defaults a missing id list to [] (`fieldIds || []`)", () => {
    const { sm } = newSM([field({ id: "a" })])
    sm.selectFields()
    expect(sm.getSelectedFieldIds()).toEqual([])
  })

  it("meta-select as the first action seeds the anchor (`!selectionAnchorId`)", () => {
    const { sm } = newSM([field({ id: "a" }), field({ id: "b" })])
    sm.selectField("a", { meta: true }) // no prior anchor
    expect(sm.selectionAnchorId).toBe("a")
    expect(sm.getSelectedFieldIds()).toEqual(["a"])
  })
})

describe("SelectionManager — flattening nested fields", () => {
  it("_currentPageAllFields expands columns and field_groups", () => {
    const fields = [
      field({ id: "top" }),
      {
        id: "cols", field_type: "columns",
        columns: [{ fields: [field({ id: "c1" })] }, { fields: [field({ id: "c2" })] }],
      },
      { id: "grp", type: "field_group", fields: [field({ id: "g1" })] },
    ]
    const { sm } = newSM(fields)
    const ids = sm._currentPageAllFields().map((f) => f.id)
    expect(ids).toEqual(["top", "cols", "c1", "c2", "grp", "g1"])
  })

  it("tolerates sparse containers and an undefined field list (defensive `|| []`)", () => {
    const fields = [
      { id: "cols_nocols", field_type: "columns" },                 // no columns array
      { id: "cols_nofields", field_type: "columns", columns: [{}] }, // column w/o fields
      { id: "grp_nofields", type: "field_group" },                  // group w/o fields
    ]
    const { sm, ctrl } = newSM(fields)
    expect(sm._currentPageAllFields().map((f) => f.id)).toEqual(["cols_nocols", "cols_nofields", "grp_nofields"])
    ctrl.currentPage.fields = undefined // currentPageFields getter → undefined → `|| []`
    expect(sm._currentPageAllFields()).toEqual([])
  })

  it("getSelectedFields resolves ids back to nested field objects", () => {
    const fields = [
      { id: "cols", field_type: "columns", columns: [{ fields: [field({ id: "c1", label: "Nested" })] }] },
    ]
    const { sm } = newSM(fields)
    sm.selectFields(["c1"])
    expect(sm.getSelectedFields().map((f) => f.label)).toEqual(["Nested"])
  })
})

describe("SelectionManager — syncScalarState", () => {
  it("mirrors the single selection onto controller scalars", () => {
    const { sm, ctrl } = newSM([field({ id: "a" })])
    sm.selectField("a")
    expect(ctrl.selectedFieldId).toBe("a")
    expect(ctrl.selectedFieldValue).toBe("a")
  })

  it("nulls the scalars when the selection is not exactly one", () => {
    const { sm, ctrl } = newSM([field({ id: "a" }), field({ id: "b" })])
    sm.selectFields(["a", "b"])
    expect(ctrl.selectedFieldId).toBeNull()
    expect(ctrl.selectedFieldValue).toBeNull()
  })
})

describe("SelectionManager — updateVisuals (DOM, no geometry)", () => {
  function withCards(ids) {
    const container = document.createElement("div")
    ids.forEach((id) => {
      const card = document.createElement("div")
      card.className = "field-card"
      card.dataset.fieldId = id
      container.appendChild(card)
    })
    return container
  }

  it("toggles single-select ring classes on the selected card", () => {
    const { sm, ctrl } = newSM([field({ id: "a" }), field({ id: "b" })])
    const container = withCards(["a", "b"])
    ctrl.hasFieldsContainerTarget = true
    ctrl.fieldsContainerTarget = container
    sm.selectField("a")
    const cardA = container.querySelector("[data-field-id='a']")
    expect(cardA.classList.contains("ring-indigo-500")).toBe(true)
    expect(cardA.classList.contains("selected")).toBe(true)
    const cardB = container.querySelector("[data-field-id='b']")
    expect(cardB.classList.contains("selected")).toBe(false)
  })

  it("adds a multi-select checkbox overlay to each selected card and removes it on deselect", () => {
    const { sm, ctrl } = newSM([field({ id: "a" }), field({ id: "b" })])
    const container = withCards(["a", "b"])
    ctrl.hasFieldsContainerTarget = true
    ctrl.fieldsContainerTarget = container
    sm.selectFields(["a", "b"])
    expect(container.querySelectorAll(".multi-select-check")).toHaveLength(2)
    const cardA = container.querySelector("[data-field-id='a']")
    expect(cardA.classList.contains("ring-blue-400")).toBe(true)

    sm.selectField("a") // collapse to single
    expect(container.querySelectorAll(".multi-select-check")).toHaveLength(0)
  })

  it("is a no-op without a fields container target", () => {
    const { sm } = newSM([field({ id: "a" })])
    expect(() => sm.updateVisuals()).not.toThrow()
  })
})

describe("SelectionManager — bulk operations", () => {
  afterEach(() => vi.restoreAllMocks())

  it("bulkSetWidth applies width + explicit flag to every selected field", () => {
    const fields = [field({ id: "a", width: "full" }), field({ id: "b", width: "full" })]
    const { sm, ctrl } = newSM(fields)
    sm.selectFields(["a", "b"])
    sm.bulkSetWidth({ currentTarget: { dataset: { width: "half" } } })
    expect(fields.every((f) => f.width === "half" && f.width_explicit === true)).toBe(true)
    expect(ctrl.undoRedoManager.saveState).toHaveBeenCalled()
    expect(ctrl.fieldManager.renderFields).toHaveBeenCalled()
    expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
  })

  it("bulkSetWidth is a no-op with no width or empty selection", () => {
    const { sm, ctrl } = newSM([field({ id: "a" })])
    sm.bulkSetWidth({ currentTarget: { dataset: {} } })
    sm.selectField("a")
    ctrl.undoRedoManager.saveState.mockClear()
    sm.selectedFieldIds.clear()
    sm.bulkSetWidth({ currentTarget: { dataset: { width: "half" } } })
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("bulkDelete removes selected fields (including nested) when confirmed", () => {
    vi.spyOn(window, "confirm").mockReturnValue(true)
    const fields = [
      field({ id: "a" }),
      { id: "cols", field_type: "columns", columns: [{ fields: [field({ id: "c1" })] }] },
      { id: "grp", type: "field_group", fields: [field({ id: "g1" })] },
    ]
    const { sm, ctrl } = newSM(fields)
    sm.selectFields(["a", "c1", "g1"])
    sm.bulkDelete()
    const remaining = ctrl.currentPage.fields
    expect(remaining.map((f) => f.id)).toEqual(["cols", "grp"])
    expect(remaining[0].columns[0].fields).toHaveLength(0)
    expect(remaining[1].fields).toHaveLength(0)
    expect(sm.isEmpty).toBe(true)
  })

  it("bulkDelete aborts when the user cancels the confirm", () => {
    vi.spyOn(window, "confirm").mockReturnValue(false)
    const fields = [field({ id: "a" })]
    const { sm, ctrl } = newSM(fields)
    sm.selectFields(["a"])
    sm.bulkDelete()
    expect(ctrl.currentPage.fields).toHaveLength(1)
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("bulkDelete is a no-op with an empty selection (count 0)", () => {
    const { sm, ctrl } = newSM([field({ id: "a" })])
    sm.bulkDelete()
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("bulkDelete keeps plain fields and tolerates containers with no children arrays", () => {
    vi.spyOn(window, "confirm").mockReturnValue(true)
    const fields = [
      field({ id: "keep" }),                                            // plain kept field → `return f`
      { id: "cols", field_type: "columns", columns: [{}] },            // column w/o fields → `col.fields || []`
      { id: "grp", type: "field_group" },                              // group w/o fields → `f.fields || []`
      field({ id: "gone" }),
    ]
    const { sm, ctrl } = newSM(fields)
    sm.selectFields(["gone"])
    sm.bulkDelete()
    expect(ctrl.currentPage.fields.map((f) => f.id)).toEqual(["keep", "cols", "grp"])
  })
})

describe("SelectionManager — groupIntoSection", () => {
  it("inserts a new section header before the moved fields, at end of current section", () => {
    const fields = [
      field({ id: "a" }),
      field({ id: "b" }),
      { id: "sec2", field_type: "section", property_type: "layout", label: "Two" },
      field({ id: "c" }),
    ]
    const { sm, ctrl } = newSM(fields)
    ctrl.fieldManager.createField = vi.fn(() => ({ id: "newsec", field_type: "section", property_type: "layout", label: "New Section" }))
    sm.selectFields(["a", "b"])
    sm.groupIntoSection()

    const ids = ctrl.currentPage.fields.map((f) => f.id)
    // New unlabeled section header precedes the moved a,b; boundary sec2 preserved.
    expect(ids).toEqual(["newsec", "a", "b", "sec2", "c"])
    const header = ctrl.currentPage.fields.find((f) => f.id === "newsec")
    expect(header.label).toBe("")
    // order reindexed
    expect(ctrl.currentPage.fields.map((f) => f.order)).toEqual([0, 1, 2, 3, 4])
  })

  it("appends the section header at the page end when no later section header exists (boundary null)", () => {
    const fields = [field({ id: "a" }), field({ id: "b" }), field({ id: "c" })]
    const { sm, ctrl } = newSM(fields)
    ctrl.fieldManager.createField = vi.fn(() => ({ id: "newsec", field_type: "section", property_type: "layout", label: "New Section" }))
    sm.selectFields(["b", "c"])
    sm.groupIntoSection()
    const ids = ctrl.currentPage.fields.map((f) => f.id)
    expect(ids).toEqual(["a", "newsec", "b", "c"])
  })

  it("is a no-op when the selection is only nested fields (no top-level match, firstIdx -1)", () => {
    const fields = [{ id: "cols", field_type: "columns", columns: [{ fields: [field({ id: "c1" })] }] }]
    const { sm, ctrl } = newSM(fields)
    ctrl.fieldManager.createField = vi.fn()
    sm.selectFields(["c1"]) // c1 is nested, not a top-level field
    sm.groupIntoSection()
    expect(ctrl.fieldManager.createField).not.toHaveBeenCalled()
  })

  it("is a no-op with an empty selection", () => {
    const { sm, ctrl } = newSM([field({ id: "a" })])
    sm.groupIntoSection()
    expect(ctrl.fieldManager.createField).not.toHaveBeenCalled()
  })
})

describe("SelectionManager — move-to-page modal", () => {
  function withModalTarget(ctrl) {
    ctrl.hasMoveToPageModalTarget = true
    ctrl.moveToPageModalTarget = document.createElement("div")
  }

  it("openMoveToPageModal renders a radio per page and escapes names", () => {
    const pages = [
      { id: "p1", name: "Home" },
      { id: "p2", name: "<b>Evil</b>" },
    ]
    const { sm, ctrl } = newSM([field({ id: "a" })], { configuration: { pages, rules: [], calculations: [] } })
    ctrl.activePageValue = "p1"
    withModalTarget(ctrl)
    sm.selectField("a")
    sm.openMoveToPageModal()
    const html = ctrl.moveToPageModalTarget.innerHTML
    expect(html).toContain('value="p1"')
    expect(html).toContain('value="p2"')
    expect(html).toContain("&lt;b&gt;Evil&lt;/b&gt;")
    expect(html).not.toContain("<b>Evil</b>")
  })

  it("pluralizes the field count and tolerates missing pages config (`pages || []`)", () => {
    const { sm, ctrl } = newSM([field({ id: "a" }), field({ id: "b" })], { configuration: { rules: [], calculations: [] } })
    ctrl.configuration.pages = undefined // exercise the `|| []` fallback
    withModalTarget(ctrl)
    sm.selectFields(["a", "b"])
    sm.openMoveToPageModal()
    expect(ctrl.moveToPageModalTarget.innerHTML).toContain("Move 2 fields")
  })

  it("confirmMoveToPage is a no-op without a modal target, and when the new-page name is blank", () => {
    const { sm, ctrl } = newSM([field({ id: "a" })], { configuration: { pages: [{ id: "p1", name: "P1", fields: [] }], rules: [], calculations: [] } })
    ctrl.activePageValue = "p1"
    sm.selectField("a")
    // no moveToPageModalTarget → early return
    ctrl.moveToPageModalTarget = undefined
    sm.confirmMoveToPage()
    expect(ctrl.pageManager.moveFieldsToPage).not.toHaveBeenCalled()

    // blank new-page name (no radio) → early return
    withModalTarget(ctrl)
    ctrl.moveToPageModalTarget.innerHTML = '<input data-move-new-page-name value="   ">'
    sm.confirmMoveToPage()
    expect(ctrl.pageManager.moveFieldsToPage).not.toHaveBeenCalled()
    expect(ctrl.configuration.pages).toHaveLength(1) // no page created
  })

  it("openMoveToPageModal is a no-op when the selection is empty", () => {
    const { sm, ctrl } = newSM([field({ id: "a" })])
    withModalTarget(ctrl)
    sm.openMoveToPageModal()
    expect(ctrl.moveToPageModalTarget.innerHTML).toBe("")
  })

  it("confirmMoveToPage moves to a chosen existing page", () => {
    const pages = [{ id: "p1", name: "P1", fields: [] }, { id: "p2", name: "P2", fields: [] }]
    const { sm, ctrl } = newSM([field({ id: "a" })], { configuration: { pages, rules: [], calculations: [] } })
    ctrl.activePageValue = "p1"
    withModalTarget(ctrl)
    ctrl.moveToPageModalTarget.innerHTML =
      '<input type="radio" name="move_target_page" value="p2" checked>'
    sm.selectField("a")
    sm.confirmMoveToPage()
    expect(ctrl.pageManager.moveFieldsToPage).toHaveBeenCalledWith(["a"], "p2")
  })

  it("confirmMoveToPage creates a new page from the name input when no radio is chosen", () => {
    const pages = [{ id: "p1", name: "P1", fields: [] }]
    const { sm, ctrl } = newSM([field({ id: "a" })], { configuration: { pages, rules: [], calculations: [] } })
    ctrl.activePageValue = "p1"
    withModalTarget(ctrl)
    ctrl.moveToPageModalTarget.innerHTML =
      '<input data-move-new-page-name value="Fresh Page">'
    sm.selectField("a")
    sm.confirmMoveToPage()
    expect(ctrl.configuration.pages).toHaveLength(2)
    const created = ctrl.configuration.pages[1]
    expect(created.name).toBe("Fresh Page")
    expect(ctrl.pageManager.moveFieldsToPage).toHaveBeenCalledWith(["a"], created.id)
  })

  it("closeMoveToPageModal clears the modal target", () => {
    const { sm, ctrl } = newSM([field({ id: "a" })])
    withModalTarget(ctrl)
    ctrl.moveToPageModalTarget.innerHTML = "<div>x</div>"
    sm.closeMoveToPageModal()
    expect(ctrl.moveToPageModalTarget.innerHTML).toBe("")
  })

  it("closeMoveToPageModalOnBackdrop only closes when the click misses the content", () => {
    const { sm, ctrl } = newSM([field({ id: "a" })])
    withModalTarget(ctrl)
    ctrl.moveToPageModalTarget.innerHTML = "seed"
    const inside = document.createElement("div")
    inside.setAttribute("data-move-modal-content", "")
    sm.closeMoveToPageModalOnBackdrop({ target: inside })
    expect(ctrl.moveToPageModalTarget.innerHTML).toBe("seed")

    const outside = document.createElement("div")
    sm.closeMoveToPageModalOnBackdrop({ target: outside })
    expect(ctrl.moveToPageModalTarget.innerHTML).toBe("")
  })
})

describe("SelectionManager — _updatePanel", () => {
  function withActionBar(ctrl) {
    ctrl.hasFloatingActionBarTarget = true
    ctrl.floatingActionBarTarget = document.createElement("div")
    ctrl.floatingActionBarTarget.classList.add("hidden")
    ctrl.hasSelectionCountTarget = true
    ctrl.selectionCountTarget = document.createElement("span")
  }

  describe("with a floating action bar target", () => {
    it("multi-select reveals the bar, writes the count, and hides the property panel", () => {
      const { sm, ctrl } = newSM([field({ id: "a" }), field({ id: "b" })])
      withActionBar(ctrl)
      sm.selectFields(["a", "b"])
      expect(ctrl.floatingActionBarTarget.classList.contains("hidden")).toBe(false)
      expect(ctrl.selectionCountTarget.textContent).toBe("2 fields selected")
      expect(ctrl.propertyManager.hideFloatingPanel).toHaveBeenCalled()
      expect(ctrl.propertyManager.enableToolbarWidthForMulti).toHaveBeenCalled()
    })

    it("single-select hides the bar and shows the floating property panel", () => {
      const { sm, ctrl } = newSM([field({ id: "a" })])
      withActionBar(ctrl)
      ctrl.floatingActionBarTarget.classList.remove("hidden")
      sm.selectField("a")
      expect(ctrl.floatingActionBarTarget.classList.contains("hidden")).toBe(true)
      expect(ctrl.propertyManager.showFloatingPanel).toHaveBeenCalledWith("a")
    })

    it("single-select with showPanel=false hides the bar and the panel", () => {
      const { sm, ctrl } = newSM([field({ id: "a" })])
      withActionBar(ctrl)
      sm.selectField("a", { showPanel: false })
      expect(ctrl.propertyManager.showFloatingPanel).not.toHaveBeenCalled()
      expect(ctrl.propertyManager.hideFloatingPanel).toHaveBeenCalled()
    })

    it("omits the count text when no selection-count target exists", () => {
      const { sm, ctrl } = newSM([field({ id: "a" }), field({ id: "b" })])
      withActionBar(ctrl)
      ctrl.hasSelectionCountTarget = false
      expect(() => sm.selectFields(["a", "b"])).not.toThrow()
    })
  })

  describe("without a floating action bar target", () => {
    it("empty selection hides the property panel (isEmpty branch)", () => {
      const { sm, ctrl } = newSM([field({ id: "a" })])
      sm.selectFields([]) // empty → _updatePanel isEmpty
      expect(ctrl.propertyManager.hideFloatingPanel).toHaveBeenCalled()
    })

    it("single-select with showPanel=false hides the panel (isSingleSelect, !showPanel)", () => {
      const { sm, ctrl } = newSM([field({ id: "a" })])
      sm.selectField("a", { showPanel: false })
      expect(ctrl.propertyManager.hideFloatingPanel).toHaveBeenCalled()
      expect(ctrl.propertyManager.showFloatingPanel).not.toHaveBeenCalled()
    })

    it("multi-select shows the multi-select toolbar", () => {
      const { sm, ctrl } = newSM([field({ id: "a" }), field({ id: "b" })])
      sm.selectFields(["a", "b"])
      expect(ctrl.propertyManager.showMultiSelectToolbar).toHaveBeenCalledWith(2)
    })
  })
})

describe("SelectionManager — rubber band overlay lifecycle (structural)", () => {
  it("startRubberBand ignores non-left buttons and clicks on field cards", () => {
    const { sm } = newSM([field({ id: "a" })])
    const card = document.createElement("div")
    card.className = "field-card"
    sm.startRubberBand({ button: 0, target: card, clientX: 1, clientY: 1 })
    expect(sm._rubberBandActive).toBeFalsy()

    const bg = document.createElement("div")
    sm.startRubberBand({ button: 2, target: bg, clientX: 1, clientY: 1 })
    expect(sm._rubberBandActive).toBeFalsy()
  })

  it("startRubberBand on the background activates and creates a hidden overlay", () => {
    const { sm } = newSM([field({ id: "a" })])
    const bg = document.createElement("div")
    document.body.appendChild(bg)
    sm.startRubberBand({ button: 0, target: bg, clientX: 5, clientY: 5 })
    expect(sm._rubberBandActive).toBe(true)
    expect(sm._rubberBandEl).toBeTruthy()
    expect(sm._rubberBandEl.style.display).toBe("none")
    sm.cleanupRubberBand()
    expect(sm._rubberBandEl).toBeNull()
  })

  it("startRubberBand ignores clicks on a non-canvas page-builder target", () => {
    const { sm } = newSM([field({ id: "a" })])
    const el = document.createElement("div")
    el.setAttribute("data-page-builder-target", "sidebar")
    document.body.appendChild(el)
    sm.startRubberBand({ button: 0, target: el, clientX: 1, clientY: 1 })
    expect(sm._rubberBandActive).toBeFalsy()
  })

  it("startRubberBand proceeds when the target is the canvasArea itself", () => {
    const { sm } = newSM([field({ id: "a" })])
    const canvas = document.createElement("div")
    canvas.setAttribute("data-page-builder-target", "canvasArea")
    document.body.appendChild(canvas)
    sm.startRubberBand({ button: 0, target: canvas, clientX: 5, clientY: 5 })
    expect(sm._rubberBandActive).toBe(true)
    sm.cleanupRubberBand()
  })

  it("endRubberBand is a no-op when no band is active", () => {
    const { sm } = newSM([field({ id: "a" })])
    expect(() => sm.endRubberBand({})).not.toThrow()
    expect(sm._rubberBandActive).toBeFalsy()
  })
})

describe("SelectionManager — rubber band geometry (stubbed rects)", () => {
  // happy-dom zeroes getBoundingClientRect; the COVERAGE brief explicitly allows
  // stubbing rects to exercise geometry branches, so we install fixed rects.
  function stubRect(el, r) {
    Object.defineProperty(el, "getBoundingClientRect", {
      configurable: true,
      value: () => ({ left: r.x, top: r.y, right: r.x + r.w, bottom: r.y + r.h, width: r.w, height: r.h, x: r.x, y: r.y }),
    })
  }
  function withStubbedCards(ctrl, specs) {
    const container = document.createElement("div")
    specs.forEach(({ id, rect }) => {
      const card = document.createElement("div")
      card.className = "field-card"
      card.dataset.fieldId = id
      stubRect(card, rect)
      container.appendChild(card)
    })
    ctrl.hasFieldsContainerTarget = true
    ctrl.fieldsContainerTarget = container
    return container
  }

  it("_rectsIntersect detects overlap and each disjoint direction", () => {
    const { sm } = newSM()
    const a = { x: 0, y: 0, w: 10, h: 10 }
    expect(sm._rectsIntersect(a, { x: 5, y: 5, w: 10, h: 10 })).toBe(true)
    expect(sm._rectsIntersect(a, { x: 20, y: 0, w: 5, h: 5 })).toBe(false) // b right of a
    expect(sm._rectsIntersect(a, { x: -20, y: 0, w: 5, h: 5 })).toBe(false) // b left of a
    expect(sm._rectsIntersect(a, { x: 0, y: 20, w: 5, h: 5 })).toBe(false) // b below a
    expect(sm._rectsIntersect(a, { x: 0, y: -20, w: 5, h: 5 })).toBe(false) // b above a
  })

  it("updateRubberBand bails when inactive, and when the drag is under the 5px threshold", () => {
    const { sm } = newSM()
    sm.updateRubberBand({ clientX: 100, clientY: 100 }) // inactive → return
    sm._rubberBandActive = true
    sm._rubberBandStart = { x: 0, y: 0 }
    sm._rubberBandEl = document.createElement("div")
    sm.updateRubberBand({ clientX: 3, clientY: 3 }) // < 5px → return, stays hidden
    expect(sm._rubberBandEl.style.display).toBe("")
  })

  it("updateRubberBand draws the band and highlights intersecting cards", () => {
    const { sm, ctrl } = newSM()
    withStubbedCards(ctrl, [
      { id: "hit", rect: { x: 10, y: 10, w: 20, h: 20 } },
      { id: "miss", rect: { x: 500, y: 500, w: 10, h: 10 } },
    ])
    sm._rubberBandActive = true
    sm._rubberBandStart = { x: 0, y: 0 }
    sm._rubberBandEl = document.createElement("div")
    sm.updateRubberBand({ clientX: 100, clientY: 100 })
    expect(sm._rubberBandEl.style.display).toBe("block")
    expect(sm._rubberBandEl.style.width).toBe("100px")
    const hit = ctrl.fieldsContainerTarget.querySelector("[data-field-id='hit']")
    const miss = ctrl.fieldsContainerTarget.querySelector("[data-field-id='miss']")
    expect(hit.classList.contains("ring-2")).toBe(true)
    expect(miss.classList.contains("ring-2")).toBe(false)
  })

  it("_highlightIntersecting / _selectIntersecting are no-ops without a container target", () => {
    const { sm } = newSM()
    expect(() => sm._highlightIntersecting({ x: 0, y: 0, w: 1, h: 1 })).not.toThrow()
    expect(() => sm._selectIntersecting({ x: 0, y: 0, w: 1, h: 1 })).not.toThrow()
  })

  it("endRubberBand selects the cards intersecting a visible band", () => {
    const { sm, ctrl } = newSM([field({ id: "hit" }), field({ id: "miss" })])
    withStubbedCards(ctrl, [
      { id: "hit", rect: { x: 0, y: 0, w: 50, h: 50 } },
      { id: "miss", rect: { x: 900, y: 900, w: 10, h: 10 } },
    ])
    sm._rubberBandActive = true
    sm._rubberBandStart = { x: 0, y: 0 }
    sm._rubberBandEl = document.createElement("div")
    sm._rubberBandEl.style.display = "block"
    stubRect(sm._rubberBandEl, { x: 0, y: 0, w: 100, h: 100 })
    sm.endRubberBand({})
    expect(sm.getSelectedFieldIds()).toEqual(["hit"])
    expect(sm.selectionAnchorId).toBe("hit")
    expect(sm._rubberBandActive).toBe(false)
  })

  it("endRubberBand skips selection when the band never became visible (too small)", () => {
    const { sm, ctrl } = newSM([field({ id: "a" })])
    withStubbedCards(ctrl, [{ id: "a", rect: { x: 0, y: 0, w: 10, h: 10 } }])
    sm._rubberBandActive = true
    sm._rubberBandEl = document.createElement("div")
    sm._rubberBandEl.style.display = "none" // never shown
    stubRect(sm._rubberBandEl, { x: 0, y: 0, w: 2, h: 2 })
    sm.endRubberBand({})
    expect(sm.getSelectedFieldIds()).toEqual([])
  })
})
