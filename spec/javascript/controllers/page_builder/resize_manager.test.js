import { describe, it, expect, beforeEach, vi, afterEach } from "vitest"
import { ResizeManager } from "controllers/page_builder/resize_manager"
import { makeCtrl, field } from "../../support/page_builder.js"

// NOTE: the width-snapping core of _handleMouseMove derives the target column
// count from live pointer coordinates vs card geometry (getBoundingClientRect),
// which happy-dom reports as zeroed rects — the snap RESULT is meaningless in
// unit-land and is covered by Playwright (spec/e2e). We test the resize
// lifecycle wiring (flags, listeners, saveState/markDirty), the overlay/tooltip
// DOM helpers, and the early-return guards — never a fake-geometry snap outcome.

function rmCtrl(fields = []) {
  const ctrl = makeCtrl({ currentPage: { id: "p1", fields } })
  ctrl.fieldsContainerTarget = document.createElement("div")
  ctrl.hasFieldsContainerTarget = true
  ctrl.propertyManager = { syncToolbarWidth: vi.fn() }
  return ctrl
}

function newRM(fields = []) {
  const ctrl = rmCtrl(fields)
  return { rm: new ResizeManager(ctrl), ctrl }
}

describe("ResizeManager — construction", () => {
  it("starts idle", () => {
    const { rm } = newRM()
    expect(rm.isResizing).toBe(false)
    expect(rm.resizingFieldId).toBeNull()
    expect(rm.tooltip).toBeNull()
  })
})

describe("ResizeManager.startResize", () => {
  afterEach(() => vi.restoreAllMocks())

  it("engages resize, records the field id, saves state, and wires listeners", () => {
    const { rm, ctrl } = newRM([field({ id: "f1" })])
    const card = document.createElement("div")
    card.dataset.fieldId = "f1"
    const handle = document.createElement("div")
    card.appendChild(handle)
    ctrl.fieldsContainerTarget.appendChild(card)

    const addSpy = vi.spyOn(document, "addEventListener")
    const event = {
      currentTarget: handle, clientX: 100,
      preventDefault: vi.fn(), stopPropagation: vi.fn(),
    }
    rm.startResize(event)

    expect(event.preventDefault).toHaveBeenCalled()
    expect(rm.isResizing).toBe(true)
    expect(rm.resizingFieldId).toBe("f1")
    expect(rm.startX).toBe(100)
    expect(ctrl.saveState).toHaveBeenCalled()
    expect(addSpy).toHaveBeenCalledWith("mousemove", expect.any(Function))
    expect(addSpy).toHaveBeenCalledWith("mouseup", expect.any(Function))
    // overlay + tooltip created
    expect(ctrl.fieldsContainerTarget.querySelector(".resize-grid-overlay")).toBeTruthy()
    expect(rm.tooltip).toBeTruthy()

    rm._handleMouseUp({}) // cleanup listeners/DOM
  })

  it("is a no-op when the handle is not inside a field card", () => {
    const { rm } = newRM()
    const event = {
      currentTarget: document.createElement("div"),
      preventDefault: vi.fn(), stopPropagation: vi.fn(),
    }
    rm.startResize(event)
    expect(rm.isResizing).toBe(false)
  })

  it("wires bound document listeners that delegate to _handleMouseMove/_handleMouseUp", () => {
    const { rm, ctrl } = newRM([field({ id: "f1" })])
    const card = document.createElement("div")
    card.dataset.fieldId = "f1"
    ctrl.fieldsContainerTarget.appendChild(card)
    rm.startResize({ currentTarget: card, clientX: 0, preventDefault: vi.fn(), stopPropagation: vi.fn() })

    const moveSpy = vi.spyOn(rm, "_handleMouseMove")
    // dispatch a REAL document event so the addEventListener-registered
    // closures (rm._onMouseMove/_onMouseUp) actually run, not just the
    // underlying handler methods.
    document.dispatchEvent(new MouseEvent("mousemove", { clientX: 5, clientY: 5 }))
    expect(moveSpy).toHaveBeenCalled()

    const upSpy = vi.spyOn(rm, "_handleMouseUp")
    document.dispatchEvent(new MouseEvent("mouseup"))
    expect(upSpy).toHaveBeenCalled()
  })
})

describe("ResizeManager._handleMouseMove guards", () => {
  it("does nothing when not resizing", () => {
    const { rm, ctrl } = newRM([field({ id: "f1" })])
    rm._handleMouseMove({ clientX: 10, clientY: 10 })
    expect(ctrl.fieldManager.renderFields).not.toHaveBeenCalled()
  })

  it("does nothing when the resizing card is gone from the DOM", () => {
    const { rm, ctrl } = newRM([field({ id: "f1" })])
    rm.isResizing = true
    rm.resizingFieldId = "missing"
    rm.colWidth = 10
    rm._handleMouseMove({ clientX: 10, clientY: 10 })
    expect(ctrl.fieldManager.renderFields).not.toHaveBeenCalled()
  })

  // cardLeft is always 0 in happy-dom (zeroed getBoundingClientRect), so with a
  // fixed colWidth the resulting `cols` (and therefore the snapped width) is
  // deterministic: clientX 60 / colWidth 10 = 6 cols -> exactly the "half" snap point.
  function mount(ctrl, fieldId) {
    const card = document.createElement("div")
    card.dataset.fieldId = fieldId
    ctrl.fieldsContainerTarget.appendChild(card)
  }

  it("snaps the field width and re-renders when the snapped width differs (desktop)", () => {
    const f = field({ id: "f1", width: "full" })
    const { rm, ctrl } = newRM([f])
    mount(ctrl, "f1")
    rm.isResizing = true
    rm.resizingFieldId = "f1"
    rm.colWidth = 10
    rm._createTooltip()
    rm._handleMouseMove({ clientX: 60, clientY: 20 })
    expect(f.width).toBe("half")
    expect(f.width_explicit).toBe(true)
    expect(ctrl.fieldManager.renderFields).toHaveBeenCalled()
    expect(rm.tooltip.textContent).toBe("6/12 (Half)")
  })

  it("uses the server-provided localized snap label in the tooltip when present", () => {
    const f = field({ id: "f1", width: "full" })
    const { rm, ctrl } = newRM([f])
    ctrl.resizeSnapLabelsValue = { half: "半宽" }
    mount(ctrl, "f1")
    rm.isResizing = true
    rm.resizingFieldId = "f1"
    rm.colWidth = 10
    rm._createTooltip()
    rm._handleMouseMove({ clientX: 60, clientY: 20 })
    expect(rm.tooltip.textContent).toBe("6/12 (半宽)")
  })

  it("does not re-render when the snapped width already matches the current width", () => {
    const f = field({ id: "f1", width: "half" })
    const { rm, ctrl } = newRM([f])
    mount(ctrl, "f1")
    rm.isResizing = true
    rm.resizingFieldId = "f1"
    rm.colWidth = 10
    rm._handleMouseMove({ clientX: 60, clientY: 20 })
    expect(ctrl.fieldManager.renderFields).not.toHaveBeenCalled()
  })

  it("stores the snap under responsive_widths for a non-desktop viewport, initializing the map", () => {
    const f = field({ id: "f1", width: "full" })
    const { rm, ctrl } = newRM([f])
    ctrl.viewportValue = "mobile"
    mount(ctrl, "f1")
    rm.isResizing = true
    rm.resizingFieldId = "f1"
    rm.colWidth = 10
    rm._handleMouseMove({ clientX: 60, clientY: 20 })
    expect(f.responsive_widths).toEqual({ mobile: "half" })
    expect(f.width).toBe("full") // desktop width untouched
    expect(ctrl.fieldManager.renderFields).toHaveBeenCalled()
  })

  it("reuses an existing responsive_widths map for a non-desktop viewport", () => {
    const f = field({ id: "f1", width: "full", responsive_widths: { mobile: "quarter" } })
    const { rm, ctrl } = newRM([f])
    ctrl.viewportValue = "mobile"
    mount(ctrl, "f1")
    rm.isResizing = true
    rm.resizingFieldId = "f1"
    rm.colWidth = 10
    rm._handleMouseMove({ clientX: 60, clientY: 20 })
    expect(f.responsive_widths).toEqual({ mobile: "half" })
  })

  it("defaults to the desktop viewport when viewportValue is unset", () => {
    const f = field({ id: "f1", width: "full" })
    const { rm, ctrl } = newRM([f])
    ctrl.viewportValue = undefined
    mount(ctrl, "f1")
    rm.isResizing = true
    rm.resizingFieldId = "f1"
    rm.colWidth = 10
    rm._handleMouseMove({ clientX: 60, clientY: 20 })
    expect(f.width).toBe("half") // updated via the desktop branch, not responsive_widths
    expect(f.responsive_widths).toBeUndefined()
  })

  it("skips the width update entirely when the resizing field is no longer in currentPageFields", () => {
    const { rm, ctrl } = newRM([]) // no fields — resizingFieldId matches nothing
    mount(ctrl, "ghost")
    rm.isResizing = true
    rm.resizingFieldId = "ghost"
    rm.colWidth = 10
    expect(() => rm._handleMouseMove({ clientX: 60, clientY: 20 })).not.toThrow()
    expect(ctrl.fieldManager.renderFields).not.toHaveBeenCalled()
  })
})

describe("ResizeManager._handleMouseUp", () => {
  afterEach(() => vi.restoreAllMocks())

  it("clears state, removes listeners/overlay, syncs the toolbar, and marks dirty", () => {
    const f = field({ id: "f1" })
    const { rm, ctrl } = newRM([f])
    // enter resize so there is state to tear down
    const card = document.createElement("div")
    card.dataset.fieldId = "f1"
    const handle = document.createElement("div")
    card.appendChild(handle)
    ctrl.fieldsContainerTarget.appendChild(card)
    rm.startResize({ currentTarget: handle, clientX: 0, preventDefault: vi.fn(), stopPropagation: vi.fn() })

    const removeSpy = vi.spyOn(document, "removeEventListener")
    rm._handleMouseUp({})

    expect(rm.isResizing).toBe(false)
    expect(rm.resizingFieldId).toBeNull()
    expect(removeSpy).toHaveBeenCalledWith("mousemove", expect.any(Function))
    expect(ctrl.fieldsContainerTarget.querySelector(".resize-grid-overlay")).toBeNull()
    expect(rm.tooltip).toBeNull()
    expect(ctrl.propertyManager.syncToolbarWidth).toHaveBeenCalledWith(f)
    expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
  })

  it("is a no-op when not resizing", () => {
    const { rm, ctrl } = newRM([field({ id: "f1" })])
    rm._handleMouseUp({})
    expect(ctrl.saveManager.markDirty).not.toHaveBeenCalled()
  })
})

describe("ResizeManager — grid overlay + tooltip helpers", () => {
  it("_showGridLines appends a 12-cell overlay and _removeGridLines removes it", () => {
    const { rm, ctrl } = newRM()
    rm._showGridLines()
    const overlay = ctrl.fieldsContainerTarget.querySelector(".resize-grid-overlay")
    expect(overlay).toBeTruthy()
    expect(overlay.children).toHaveLength(12)
    rm._removeGridLines()
    expect(ctrl.fieldsContainerTarget.querySelector(".resize-grid-overlay")).toBeNull()
  })

  it("tooltip lifecycle: create → update text/position → remove", () => {
    const { rm } = newRM()
    rm._createTooltip()
    expect(document.body.contains(rm.tooltip)).toBe(true)
    rm._updateTooltip(50, 80, "6/12 (Half)")
    expect(rm.tooltip.textContent).toBe("6/12 (Half)")
    expect(rm.tooltip.style.left).toBe("62px")
    expect(rm.tooltip.style.top).toBe("52px")
    rm._removeTooltip()
    expect(rm.tooltip).toBeNull()
  })

  it("_updateTooltip is a no-op without a tooltip", () => {
    const { rm } = newRM()
    expect(() => rm._updateTooltip(1, 1, "x")).not.toThrow()
  })
})
