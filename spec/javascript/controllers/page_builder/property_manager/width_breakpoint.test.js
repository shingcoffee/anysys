import { describe, it, expect, vi } from "vitest"
import { PropertyManager } from "controllers/page_builder/property_manager"
import { makeCtrl, field } from "../../../support/page_builder.js"

function wbCtrl(fields = [], selected = []) {
  const ctrl = makeCtrl({ currentPage: { id: "p1", fields } })
  ctrl.selectedFieldId = null
  ctrl.selectionManager.getSelectedFields = vi.fn(() => selected)
  ctrl.selectionManager.updateVisuals = vi.fn()
  return ctrl
}
function newPM(fields = [], selected = []) {
  const ctrl = wbCtrl(fields, selected)
  return { pm: new PropertyManager(ctrl), ctrl }
}
function widthButtons(widths) {
  return widths.map((w) => {
    const b = document.createElement("button")
    b.dataset.width = w
    return b
  })
}

describe("WidthBreakpointMixin.setFieldWidth", () => {
  it("applies desktop width + explicit flag to each selected field", () => {
    const f1 = field({ id: "a", width: "full" })
    const f2 = field({ id: "b", width: "full" })
    const { pm, ctrl } = newPM([f1, f2], [f1, f2])
    pm.setFieldWidth({ currentTarget: { dataset: { width: "half" } } })
    expect(f1.width).toBe("half")
    expect(f1.width_explicit).toBe(true)
    expect(f2.width).toBe("half")
    expect(ctrl.fieldManager.renderFields).toHaveBeenCalled()
    expect(ctrl.selectionManager.updateVisuals).toHaveBeenCalled() // multi-select path
    expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
  })

  it("writes a responsive width for a non-desktop breakpoint", () => {
    const f1 = field({ id: "a", width: "full" })
    const { pm, ctrl } = newPM([f1], [f1])
    // single-selection non-desktop path calls _syncWidthButtonsForBreakpoint,
    // which reads the floating panel — provide it.
    ctrl.floatingPanelTarget = document.createElement("div")
    ctrl.toolbarWidthBtnTargets = []
    pm._activeBreakpoint = "mobile"
    pm.setFieldWidth({ currentTarget: { dataset: { width: "third" } } })
    expect(f1.responsive_widths).toEqual({ mobile: "third" })
    expect(f1.width).toBe("full") // untouched
  })

  it("debounces the undo save across rapid changes", () => {
    const f1 = field({ id: "a" })
    const { pm, ctrl } = newPM([f1], [f1])
    pm.setFieldWidth({ currentTarget: { dataset: { width: "half" } } })
    pm.setFieldWidth({ currentTarget: { dataset: { width: "third" } } })
    expect(ctrl.undoRedoManager.saveState).toHaveBeenCalledTimes(1)
  })

  it("is a no-op with no width or empty selection", () => {
    const { pm, ctrl } = newPM([], [])
    pm.setFieldWidth({ currentTarget: { dataset: {} } })
    pm.setFieldWidth({ currentTarget: { dataset: { width: "half" } } })
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })
})

describe("WidthBreakpointMixin — toolbar width state", () => {
  function withToolbar(ctrl, widths = ["quarter", "half", "full"]) {
    ctrl.hasToolbarWidthGroupTarget = true
    ctrl.toolbarWidthGroupTarget = document.createElement("div")
    ctrl.toolbarWidthGroupTarget.classList.add("opacity-30", "cursor-not-allowed")
    ctrl.toolbarWidthBtnTargets = widthButtons(widths)
  }

  it("syncToolbarWidth defaults to 'full' when the field has no width", () => {
    const { pm, ctrl } = newPM()
    withToolbar(ctrl)
    pm.syncToolbarWidth({ id: "a" })
    const fullBtn = ctrl.toolbarWidthBtnTargets.find((b) => b.dataset.width === "full")
    expect(fullBtn.classList.contains("text-indigo-600")).toBe(true)
  })

  it("syncToolbarWidth highlights the active width button and enables the group", () => {
    const { pm, ctrl } = newPM()
    withToolbar(ctrl)
    pm.syncToolbarWidth(field({ id: "a", width: "half" }))
    expect(ctrl.toolbarWidthGroupTarget.classList.contains("opacity-30")).toBe(false)
    const halfBtn = ctrl.toolbarWidthBtnTargets.find((b) => b.dataset.width === "half")
    expect(halfBtn.classList.contains("text-indigo-600")).toBe(true)
    const fullBtn = ctrl.toolbarWidthBtnTargets.find((b) => b.dataset.width === "full")
    expect(fullBtn.classList.contains("text-gray-400")).toBe(true)
  })

  it("resetToolbarWidth disables the group and dims all buttons", () => {
    const { pm, ctrl } = newPM()
    withToolbar(ctrl)
    ctrl.toolbarWidthGroupTarget.classList.remove("opacity-30", "cursor-not-allowed")
    pm.resetToolbarWidth()
    expect(ctrl.toolbarWidthGroupTarget.classList.contains("opacity-30")).toBe(true)
    expect(ctrl.toolbarWidthBtnTargets.every((b) => b.classList.contains("text-gray-400"))).toBe(true)
  })

  it("enableToolbarWidthForMulti enables the group without highlighting a width", () => {
    const { pm, ctrl } = newPM()
    withToolbar(ctrl)
    ctrl.toolbarWidthBtnTargets[0].classList.add("text-indigo-600", "bg-indigo-50")
    pm.enableToolbarWidthForMulti()
    expect(ctrl.toolbarWidthGroupTarget.classList.contains("opacity-30")).toBe(false)
    expect(ctrl.toolbarWidthBtnTargets.every((b) => !b.classList.contains("text-indigo-600"))).toBe(true)
  })

  it("syncToolbarWidth / resetToolbarWidth are no-ops without the toolbar group target", () => {
    const { pm } = newPM()
    expect(() => { pm.syncToolbarWidth(field({ id: "a" })); pm.resetToolbarWidth() }).not.toThrow()
  })

  it("enableToolbarWidthForMulti is a no-op without the toolbar group target", () => {
    const { pm } = newPM()
    expect(() => pm.enableToolbarWidthForMulti()).not.toThrow()
  })
})

describe("WidthBreakpointMixin.switchBreakpoint", () => {
  function withPanel(ctrl) {
    const panel = document.createElement("div")
    const selector = document.createElement("div")
    selector.setAttribute("data-page-builder-target", "breakpointSelector")
    const dBtn = document.createElement("button"); dBtn.dataset.breakpoint = "desktop"
    const mBtn = document.createElement("button"); mBtn.dataset.breakpoint = "mobile"
    selector.append(dBtn, mBtn)
    const resetLink = document.createElement("a")
    resetLink.setAttribute("data-page-builder-target", "resetBreakpoint")
    panel.append(selector, resetLink)
    ctrl.floatingPanelTarget = panel
    ctrl.toolbarWidthBtnTargets = widthButtons(["quarter", "half", "full"])
    return { panel, dBtn, mBtn, resetLink }
  }

  it("marks the chosen breakpoint active and updates _activeBreakpoint", () => {
    const f = field({ id: "a", width: "half", responsive_widths: { mobile: "third" } })
    const { pm, ctrl } = newPM([f])
    ctrl.selectedFieldId = "a"
    const { mBtn, resetLink } = withPanel(ctrl)
    pm.switchBreakpoint({ currentTarget: mBtn })
    expect(pm._activeBreakpoint).toBe("mobile")
    expect(mBtn.classList.contains("bg-indigo-50")).toBe(true)
    // reset link visible because mobile has an override
    expect(resetLink.classList.contains("hidden")).toBe(false)
  })

  it("hides the reset link on mobile with no override, and falls back to 'full' width on desktop", () => {
    const f = field({ id: "a", responsive_widths: {} })
    delete f.width
    const { pm, ctrl } = newPM([f])
    ctrl.selectedFieldId = "a"
    const { mBtn, resetLink } = withPanel(ctrl)
    pm.switchBreakpoint({ currentTarget: mBtn })
    // no mobile override → resetLink stays hidden
    expect(resetLink.classList.contains("hidden")).toBe(true)

    const { panel: panel2, dBtn: desktopBtn, resetLink: resetLink2 } = withPanel(ctrl)
    ctrl.floatingPanelTarget = panel2
    pm.switchBreakpoint({ currentTarget: desktopBtn })
    expect(pm._activeBreakpoint).toBe("desktop")
    expect(resetLink2.classList.contains("hidden")).toBe(true) // desktop always hides the reset link
  })

  it("is a no-op-safe when there is no selected field or no matching breakpoint selector", () => {
    const { pm, ctrl } = newPM([])
    ctrl.selectedFieldId = "missing"
    ctrl.floatingPanelTarget = document.createElement("div") // no breakpointSelector inside
    expect(() => pm.switchBreakpoint({ currentTarget: { dataset: { breakpoint: "mobile" } } })).not.toThrow()
  })

  it("also updates matching width buttons inside the layout tab", () => {
    const f = field({ id: "a", width: "half" })
    const { pm, ctrl } = newPM([f])
    ctrl.selectedFieldId = "a"
    const { panel, dBtn } = withPanel(ctrl)
    const layoutTab = document.createElement("div")
    layoutTab.setAttribute("data-property-tab-content", "layout")
    const layoutBtn = document.createElement("button")
    layoutBtn.dataset.width = "half"
    layoutTab.appendChild(layoutBtn)
    panel.appendChild(layoutTab)
    pm.switchBreakpoint({ currentTarget: dBtn })
    expect(layoutBtn.classList.contains("border-indigo-500")).toBe(true)
  })
})

describe("WidthBreakpointMixin._syncWidthButtonsForBreakpoint", () => {
  it("uses the inherited width when no explicit width is passed (`width ||` false branch)", () => {
    const { pm, ctrl } = newPM()
    ctrl.toolbarWidthBtnTargets = widthButtons(["half", "full"])
    ctrl.floatingPanelTarget = document.createElement("div")
    pm._activeBreakpoint = "mobile"
    // width arg omitted → falls through to _inheritedWidth(field) → "half"
    pm._syncWidthButtonsForBreakpoint(field({ id: "a", width: "half" }))
    const halfBtn = ctrl.toolbarWidthBtnTargets.find((b) => b.dataset.width === "half")
    expect(halfBtn.classList.contains("text-indigo-600")).toBe(true)
  })
})

describe("WidthBreakpointMixin._inheritedWidth", () => {
  it("mobile inherits the tablet override when present", () => {
    const { pm } = newPM()
    pm._activeBreakpoint = "mobile"
    expect(pm._inheritedWidth({ width: "full", responsive_widths: { tablet: "half" } })).toBe("half")
  })
  it("falls back to the desktop width otherwise", () => {
    const { pm } = newPM()
    pm._activeBreakpoint = "tablet"
    expect(pm._inheritedWidth({ width: "third" })).toBe("third")
    expect(pm._inheritedWidth({})).toBe("full")
  })
})

describe("WidthBreakpointMixin.resetBreakpointWidth", () => {
  it("removes the active breakpoint override and re-renders", () => {
    const f = field({ id: "a", width: "full", responsive_widths: { mobile: "third", tablet: "half" } })
    const { pm, ctrl } = newPM([f])
    ctrl.selectedFieldId = "a"
    pm._activeBreakpoint = "mobile"
    pm.resetBreakpointWidth({ preventDefault: vi.fn() })
    expect(f.responsive_widths).toEqual({ tablet: "half" })
    expect(ctrl.fieldManager.renderFields).toHaveBeenCalled()
  })

  it("drops the responsive_widths object entirely once empty", () => {
    const f = field({ id: "a", width: "full", responsive_widths: { mobile: "third" } })
    const { pm, ctrl } = newPM([f])
    ctrl.selectedFieldId = "a"
    pm._activeBreakpoint = "mobile"
    pm.resetBreakpointWidth({ preventDefault: vi.fn() })
    expect(f.responsive_widths).toBeUndefined()
  })

  it("is a no-op on desktop or when there are no overrides", () => {
    const f = field({ id: "a", width: "full" })
    const { pm, ctrl } = newPM([f])
    ctrl.selectedFieldId = "a"
    pm._activeBreakpoint = "desktop"
    pm.resetBreakpointWidth({ preventDefault: vi.fn() })
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("is a no-op on desktop even when responsive_widths overrides exist", () => {
    const f = field({ id: "a", width: "full", responsive_widths: { mobile: "third" } })
    const { pm, ctrl } = newPM([f])
    ctrl.selectedFieldId = "a"
    pm._activeBreakpoint = "desktop"
    pm.resetBreakpointWidth({ preventDefault: vi.fn() })
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
    expect(f.responsive_widths).toEqual({ mobile: "third" }) // untouched
  })
})
