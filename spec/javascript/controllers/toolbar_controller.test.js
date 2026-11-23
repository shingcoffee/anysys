import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/toolbar_controller"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

// The toolbar delegates almost everything to a sibling flowchart-canvas
// controller. We don't register a real canvas controller; instead we stub
// _getCanvasController to observe delegation, and drive the canvas custom
// events directly for the status UI.
const html = ({ readOnly = false, omit = [], attrs = "" } = {}) => {
  const has = (name) => !omit.includes(name)
  return `<div data-controller="flowchart-canvas">` +
  `<div data-controller="toolbar" ${readOnly ? 'data-toolbar-read-only-value="true"' : ""} ${attrs}>` +
  (has("saveDot") ? `<span data-toolbar-target="saveDot"></span>` : "") +
  (has("undoButton") ? `<button data-toolbar-target="undoButton"></button>` : "") +
  (has("redoButton") ? `<button data-toolbar-target="redoButton"></button>` : "") +
  `<span data-toolbar-target="zoomLevel"></span>` +
  (has("overflowMenu") ? `<div data-toolbar-target="overflowMenu" class="hidden"></div>` : "") +
  `</div></div>`
}

// A toolbar mounted with no flowchart-canvas ancestor at all — exercises the
// `?.` / `if (this.canvasElement)` false branches.
const soloHtml = () =>
  `<div data-controller="toolbar">` +
  `<span data-toolbar-target="saveDot"></span>` +
  `<button data-toolbar-target="undoButton"></button>` +
  `<button data-toolbar-target="redoButton"></button>` +
  `<span data-toolbar-target="zoomLevel"></span>` +
  `<div data-toolbar-target="overflowMenu" class="hidden"></div>` +
  `</div>`

const prevent = { preventDefault() {} }

describe("toolbar controller", () => {
  let application, element, ctrl
  beforeEach(async () => {
    ;({ application, element } = await mountController("toolbar", Controller, html()))
    ctrl = controllerFor(application, element, "toolbar")
  })
  afterEach(() => vi.restoreAllMocks())

  it("initializes save dot hidden and undo/redo disabled on connect", () => {
    expect(element.querySelector("[data-toolbar-target='saveDot']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-toolbar-target='undoButton']").disabled).toBe(true)
    expect(element.querySelector("[data-toolbar-target='redoButton']").disabled).toBe(true)
  })

  it("delegates undo/redo/zoom/clear/export/layout actions to the canvas controller", () => {
    const canvas = {
      undo: vi.fn(), redo: vi.fn(), zoomIn: vi.fn(), zoomOut: vi.fn(), fitToContent: vi.fn(), save: vi.fn(),
      clear: vi.fn(), exportSVG: vi.fn(), exportPNG: vi.fn(), autoLayout: vi.fn(), cycleConnectionRouting: vi.fn(),
    }
    ctrl._getCanvasController = () => canvas
    ctrl.undo(prevent); ctrl.redo(prevent); ctrl.zoomIn(prevent); ctrl.zoomOut(prevent); ctrl.fitToContent(prevent)
    ctrl.clear(prevent); ctrl.exportSVG(prevent); ctrl.exportPNG(prevent); ctrl.autoLayout(prevent); ctrl.cycleConnectionRouting(prevent)
    expect(canvas.undo).toHaveBeenCalled()
    expect(canvas.redo).toHaveBeenCalled()
    expect(canvas.zoomIn).toHaveBeenCalled()
    expect(canvas.zoomOut).toHaveBeenCalled()
    expect(canvas.fitToContent).toHaveBeenCalled()
    expect(canvas.clear).toHaveBeenCalled()
    expect(canvas.exportSVG).toHaveBeenCalled()
    expect(canvas.exportPNG).toHaveBeenCalled()
    expect(canvas.autoLayout).toHaveBeenCalled()
    expect(canvas.cycleConnectionRouting).toHaveBeenCalled()
  })

  it("delegate actions no-op when there is no canvas controller", () => {
    ctrl._getCanvasController = () => null
    expect(() => {
      ctrl.undo(prevent); ctrl.redo(prevent); ctrl.zoomIn(prevent); ctrl.zoomOut(prevent); ctrl.fitToContent(prevent)
      ctrl.clear(prevent); ctrl.exportSVG(prevent); ctrl.exportPNG(prevent); ctrl.autoLayout(prevent); ctrl.cycleConnectionRouting(prevent)
    }).not.toThrow()
  })

  it("save() shows the saving dot and calls canvas.save()", () => {
    const canvas = { save: vi.fn() }
    ctrl._getCanvasController = () => canvas
    ctrl.save(prevent)
    expect(canvas.save).toHaveBeenCalledOnce()
    expect(element.querySelector("[data-toolbar-target='saveDot']").className).toContain("bg-blue-500")
  })

  it("save() on a read-only flowchart shows an error and does NOT call the canvas", async () => {
    const { application: app, element: el } = await mountController("toolbar", Controller, html({ readOnly: true }))
    const c = controllerFor(app, el, "toolbar")
    const canvas = { save: vi.fn() }
    c._getCanvasController = () => canvas
    c.save(prevent)
    expect(canvas.save).not.toHaveBeenCalled()
    const toast = document.querySelector(".fixed.top-4.right-4")
    expect(toast).not.toBeNull()
    expect(toast.textContent).toContain("Cannot save a launched flowchart")
  })

  it("flowchartChanged event marks unsaved and shows the amber dot", () => {
    // The controller binds this listener to the closest flowchart-canvas
    // element (canvasElement), not to its own element — dispatch there,
    // same as the zoomChanged test below.
    element.closest("[data-controller~='flowchart-canvas']")
      .dispatchEvent(new CustomEvent("flowchartChanged", { detail: { hasUnsavedChanges: true } }))
    expect(ctrl.hasUnsavedChanges).toBe(true)
    expect(element.querySelector("[data-toolbar-target='saveDot']").className).toContain("bg-amber-500")
  })

  it("undoRedoStateChanged toggles the button disabled + opacity classes", () => {
    element.closest("[data-controller~='flowchart-canvas']")
      .dispatchEvent(new CustomEvent("undoRedoStateChanged", { detail: { canUndo: true, canRedo: false } }))
    const undo = element.querySelector("[data-toolbar-target='undoButton']")
    const redo = element.querySelector("[data-toolbar-target='redoButton']")
    expect(undo.disabled).toBe(false)
    expect(undo.classList.contains("opacity-50")).toBe(false)
    expect(redo.disabled).toBe(true)
    expect(redo.classList.contains("opacity-50")).toBe(true)
  })

  it("zoomChanged event updates the zoom label", () => {
    element.closest("[data-controller~='flowchart-canvas']")
      .dispatchEvent(new CustomEvent("zoomChanged", { detail: { percent: 150 } }))
    expect(element.querySelector("[data-toolbar-target='zoomLevel']").textContent).toBe("150%")
  })

  it("toggleOverflow shows and closeOverflow hides the menu", async () => {
    const menu = element.querySelector("[data-toolbar-target='overflowMenu']")
    ctrl.toggleOverflow({ preventDefault() {}, currentTarget: document.createElement("button") })
    expect(menu.classList.contains("hidden")).toBe(false)
    // toggleOverflow registers its outside-click listener via setTimeout(fn, 0).
    // Flush it before closeOverflow() runs, otherwise the pending timeout later
    // reads `this._overflowCloseHandler` (by then nulled out by closeOverflow)
    // and registers a `null` click listener on `document` — a real bug in the
    // controller (see _overflowCloseHandler test below) that leaks a null
    // listener onto the shared happy-dom `document` and breaks later tests.
    await tick()
    ctrl.closeOverflow()
    expect(menu.classList.contains("hidden")).toBe(true)
  })

  it("_getNotificationColorClass maps types with an info fallback", () => {
    expect(ctrl._getNotificationColorClass("success")).toContain("green")
    expect(ctrl._getNotificationColorClass("error")).toContain("red")
    expect(ctrl._getNotificationColorClass("nonsense")).toContain("blue")
  })

  it("save() no-ops (no _showSaving) when there is no sibling canvas controller", () => {
    // Real (unstubbed) _getCanvasController: no flowchart-canvas controller
    // is registered on this application, so the lookup returns null.
    const dot = element.querySelector("[data-toolbar-target='saveDot']")
    const before = dot.className
    ctrl.save(prevent)
    expect(dot.className).toBe(before)
  })

  it("_getCanvasController returns null without throwing (real Stimulus lookup, no canvas controller registered)", () => {
    expect(ctrl._getCanvasController()).toBeNull()
  })

  it("flowchartChanged with no event.detail falls back hasUnsavedChanges to true; explicit false is honored", () => {
    const canvasEl = element.closest("[data-controller~='flowchart-canvas']")
    canvasEl.dispatchEvent(new CustomEvent("flowchartChanged"))
    expect(ctrl.hasUnsavedChanges).toBe(true)

    canvasEl.dispatchEvent(new CustomEvent("flowchartChanged", { detail: { hasUnsavedChanges: false } }))
    expect(ctrl.hasUnsavedChanges).toBe(false)
    expect(element.querySelector("[data-toolbar-target='saveDot']").classList.contains("hidden")).toBe(true)
  })

  it("undoRedoStateChanged with no event.detail falls both flags back to false", () => {
    const canvasEl = element.closest("[data-controller~='flowchart-canvas']")
    canvasEl.dispatchEvent(new CustomEvent("undoRedoStateChanged"))
    const undo = element.querySelector("[data-toolbar-target='undoButton']")
    const redo = element.querySelector("[data-toolbar-target='redoButton']")
    expect(undo.disabled).toBe(true)
    expect(redo.disabled).toBe(true)
  })

  it("flowchartSaved event marks saved, shows the green dot, and toasts success", () => {
    ctrl.hasUnsavedChanges = true
    const canvasEl = element.closest("[data-controller~='flowchart-canvas']")
    canvasEl.dispatchEvent(new CustomEvent("flowchartSaved"))
    expect(ctrl.hasUnsavedChanges).toBe(false)
    expect(element.querySelector("[data-toolbar-target='saveDot']").className).toContain("bg-green-500")
    const toast = document.querySelector(".fixed.top-4.right-4")
    expect(toast.textContent).toContain("Flowchart saved successfully")
  })

  it("keeps the save dot visible when flowchartSaved carries unsaved changes", () => {
    const canvasEl = element.closest("[data-controller~='flowchart-canvas']")
    canvasEl.dispatchEvent(new CustomEvent("flowchartSaved", { detail: { hasUnsavedChanges: true } }))
    expect(ctrl.hasUnsavedChanges).toBe(true)
    expect(element.querySelector("[data-toolbar-target='saveDot']").className).toContain("bg-green-500")
  })

  it("flowchartSaveError event shows the red dot and joins server error messages", () => {
    const canvasEl = element.closest("[data-controller~='flowchart-canvas']")
    canvasEl.dispatchEvent(new CustomEvent("flowchartSaveError", { detail: { errors: ["Name is required", "Bad node"] } }))
    expect(element.querySelector("[data-toolbar-target='saveDot']").className).toContain("bg-red-500")
    const toast = document.querySelector(".fixed.top-4.right-4")
    expect(toast.textContent).toBe("Name is required, Bad node")
  })

  it("flowchartSaveError with no errors falls back to a generic message", () => {
    const canvasEl = element.closest("[data-controller~='flowchart-canvas']")
    canvasEl.dispatchEvent(new CustomEvent("flowchartSaveError"))
    const toast = document.querySelector(".fixed.top-4.right-4")
    expect(toast.textContent).toBe("Failed to save flowchart")
  })

  it("a conflict save error only turns the dot red — the editor banner carries the message", () => {
    document.querySelectorAll(".fixed.top-4.right-4").forEach((n) => n.remove())
    const canvasEl = element.closest("[data-controller~='flowchart-canvas']")
    canvasEl.dispatchEvent(new CustomEvent("flowchartSaveError", { detail: { status: "conflict", errors: ["Saved elsewhere"] } }))
    expect(element.querySelector("[data-toolbar-target='saveDot']").className).toContain("bg-red-500")
    expect(document.querySelector(".fixed.top-4.right-4")).toBeNull()
  })

  it("_overflowCloseHandler closes the menu on an outside click but ignores clicks inside the menu or on the toggle button", async () => {
    const menu = element.querySelector("[data-toolbar-target='overflowMenu']")
    const toggleButton = document.createElement("button")
    element.appendChild(toggleButton)

    ctrl.toggleOverflow({ preventDefault() {}, currentTarget: toggleButton })
    expect(menu.classList.contains("hidden")).toBe(false)
    // The outside-click listener is registered via setTimeout(fn, 0) — flush it.
    await tick()

    const insideEl = document.createElement("span")
    menu.appendChild(insideEl)
    insideEl.dispatchEvent(new Event("click", { bubbles: true }))
    expect(menu.classList.contains("hidden")).toBe(false)

    toggleButton.dispatchEvent(new Event("click", { bubbles: true }))
    expect(menu.classList.contains("hidden")).toBe(false)

    document.body.dispatchEvent(new Event("click", { bubbles: true }))
    expect(menu.classList.contains("hidden")).toBe(true)
  })

  it("disconnect() unbinds canvas listeners and removes a pending overflow-close handler", () => {
    const removeSpy = vi.spyOn(document, "removeEventListener")
    ctrl._overflowCloseHandler = () => {}
    expect(() => ctrl.disconnect()).not.toThrow()
    expect(removeSpy).toHaveBeenCalledWith("click", expect.any(Function))
  })

  it("disconnect() is a no-op for the overflow handler cleanup when none is pending", () => {
    ctrl._overflowCloseHandler = null
    expect(() => ctrl.disconnect()).not.toThrow()
  })

  it("_showNotification auto-dismisses: slides out after 5s then removes itself after another 300ms", () => {
    vi.useFakeTimers()
    try {
      ctrl._showNotification("Hello", "info")
      const notification = document.querySelector(".fixed.top-4.right-4")
      expect(notification).not.toBeNull()

      vi.advanceTimersByTime(5000)
      expect(notification.style.transform).toBe("translateX(100%)")
      expect(notification.style.opacity).toBe("0")
      expect(document.body.contains(notification)).toBe(true)

      vi.advanceTimersByTime(300)
      expect(document.body.contains(notification)).toBe(false)
    } finally {
      vi.useRealTimers()
    }
  })
})

describe("toolbar controller — server-passed toast text", () => {
  const attrs = [
    'data-toolbar-read-only-save-message-value="只读"',
    'data-toolbar-saved-message-value="已保存"',
    'data-toolbar-save-failed-message-value="保存失败"',
    'data-toolbar-error-separator-value="；"',
  ].join(" ")
  const lastToast = () => [...document.querySelectorAll(".fixed.top-4.right-4")].pop().textContent

  beforeEach(() => document.querySelectorAll(".fixed.top-4.right-4").forEach((n) => n.remove()))

  it("toasts the translated success, fallback and joined-error messages", async () => {
    const { element } = await mountController("toolbar", Controller, html({ attrs }))
    const canvasEl = element.closest("[data-controller~='flowchart-canvas']")
    canvasEl.dispatchEvent(new CustomEvent("flowchartSaved"))
    expect(lastToast()).toBe("已保存")
    canvasEl.dispatchEvent(new CustomEvent("flowchartSaveError"))
    expect(lastToast()).toBe("保存失败")
    canvasEl.dispatchEvent(new CustomEvent("flowchartSaveError", { detail: { errors: ["甲", "乙"] } }))
    expect(lastToast()).toBe("甲；乙")
  })

  it("toasts the translated read-only message", async () => {
    const { application, element } = await mountController("toolbar", Controller, html({ readOnly: true, attrs }))
    controllerFor(application, element, "toolbar").save(prevent)
    expect(lastToast()).toBe("只读")
  })
})

describe("toolbar controller — target-missing guards", () => {
  it("toggleOverflow no-ops without an overflowMenu target", async () => {
    const { element, application } = await mountController("toolbar", Controller, html({ omit: ["overflowMenu"] }))
    const ctrl = controllerFor(application, element, "toolbar")
    expect(ctrl.hasOverflowMenuTarget).toBe(false)
    expect(() => ctrl.toggleOverflow(prevent)).not.toThrow()
  })

  it("_updateSaveStatus / _showSaving / _showSaveSuccess / _showSaveError no-op without a saveDot target", async () => {
    const { element, application } = await mountController("toolbar", Controller, html({ omit: ["saveDot"] }))
    const ctrl = controllerFor(application, element, "toolbar")
    expect(ctrl.hasSaveDotTarget).toBe(false)
    expect(() => ctrl._updateSaveStatus()).not.toThrow()
    expect(() => ctrl._showSaving()).not.toThrow()
    expect(() => ctrl._showSaveSuccess()).not.toThrow()
    expect(() => ctrl._showSaveError(["boom"])).not.toThrow()
    // The notification is still shown even without a save dot.
    expect(document.querySelector(".fixed.top-4.right-4")).not.toBeNull()
  })

  it("_updateUndoRedoButtons no-ops per-button when undo/redo targets are absent", async () => {
    const { element, application } = await mountController("toolbar", Controller, html({ omit: ["undoButton", "redoButton"] }))
    const ctrl = controllerFor(application, element, "toolbar")
    expect(ctrl.hasUndoButtonTarget).toBe(false)
    expect(ctrl.hasRedoButtonTarget).toBe(false)
    expect(() => ctrl._updateUndoRedoButtons(true, true)).not.toThrow()
  })
})

describe("toolbar controller — mounted without a flowchart-canvas ancestor", () => {
  it("connect()/disconnect() tolerate a missing canvasElement (optional-chaining false branches)", async () => {
    const { element, application } = await mountController("toolbar", Controller, soloHtml())
    const ctrl = controllerFor(application, element, "toolbar")
    expect(ctrl.canvasElement).toBeNull()
    expect(ctrl._getCanvasController()).toBeNull()
    expect(() => ctrl.disconnect()).not.toThrow()
  })
})

describe("P5-8 cleanup — overflow handler and status timer", () => {
  let application, element, ctrl
  beforeEach(async () => {
    ;({ application, element } = await mountController("toolbar", Controller, html()))
    ctrl = controllerFor(application, element, "toolbar")
  })
  afterEach(() => vi.restoreAllMocks())

  it("removes the overflow document handler when toggling the menu closed", async () => {
    const menu = element.querySelector("[data-toolbar-target='overflowMenu']")
    const toggleButton = document.createElement("button")
    element.appendChild(toggleButton)

    ctrl.toggleOverflow({ preventDefault() {}, currentTarget: toggleButton })
    expect(menu.classList.contains("hidden")).toBe(false)
    await tick()
    const handler = ctrl._overflowCloseHandler
    expect(handler).toEqual(expect.any(Function))

    const remove = vi.spyOn(document, "removeEventListener")
    ctrl.toggleOverflow({ preventDefault() {}, currentTarget: toggleButton })
    expect(menu.classList.contains("hidden")).toBe(true)
    expect(remove).toHaveBeenCalledWith("click", handler)
    expect(ctrl._overflowCloseHandler).toBeNull()

    document.body.dispatchEvent(new Event("click", { bubbles: true }))
    expect(menu.classList.contains("hidden")).toBe(true)
  })

  it("does not attach the overflow handler after disconnect if the attach timeout has not fired", () => {
    vi.useFakeTimers()
    try {
      const toggleButton = document.createElement("button")
      ctrl.toggleOverflow({ preventDefault() {}, currentTarget: toggleButton })
      const add = vi.spyOn(document, "addEventListener")
      ctrl.disconnect()
      vi.advanceTimersByTime(0)
      expect(add).not.toHaveBeenCalledWith("click", expect.any(Function))
    } finally {
      vi.useRealTimers()
    }
  })

  it("clears the save-status timer on disconnect so advancing fake timers does not update the dot", () => {
    vi.useFakeTimers()
    try {
      ctrl.hasUnsavedChanges = false
      ctrl._showSaveSuccess()
      const update = vi.spyOn(ctrl, "_updateSaveStatus")
      ctrl.disconnect()
      vi.advanceTimersByTime(3000)
      expect(update).not.toHaveBeenCalled()
    } finally {
      vi.useRealTimers()
    }
  })

  it("resets the save dot when the success status timer fires", () => {
    vi.useFakeTimers()
    try {
      ctrl.hasUnsavedChanges = false
      ctrl._showSaveSuccess()
      expect(element.querySelector("[data-toolbar-target='saveDot']").className).toContain("bg-green-500")
      vi.advanceTimersByTime(3000)
      expect(element.querySelector("[data-toolbar-target='saveDot']").classList.contains("hidden")).toBe(true)
      expect(ctrl._statusTimer).toBeNull()
    } finally {
      vi.useRealTimers()
    }
  })

  it("clears a pending save-status timer before scheduling another", () => {
    vi.useFakeTimers()
    try {
      ctrl._showSaveSuccess()
      const first = ctrl._statusTimer
      expect(first).toBeTruthy()
      ctrl._showSaveError([], { toast: false })
      expect(ctrl._statusTimer).toBeTruthy()
      expect(ctrl._statusTimer).not.toBe(first)
      vi.advanceTimersByTime(3000)
      expect(element.querySelector("[data-toolbar-target='saveDot']").className).toContain("bg-red-500")
      vi.advanceTimersByTime(2000)
      expect(element.querySelector("[data-toolbar-target='saveDot']").classList.contains("hidden")).toBe(true)
    } finally {
      vi.useRealTimers()
    }
  })

  it("updates saveButton and mutatingAction targets on readOnly and flowchartMutabilityChanged", async () => {
    const richHtml = (ro) => `
      <div data-controller="flowchart-canvas">
        <div data-controller="toolbar" ${ro ? 'data-toolbar-read-only-value="true"' : ""}>
          <button data-toolbar-target="saveButton"></button>
          <button data-toolbar-target="mutatingAction"></button>
          <span data-toolbar-target="zoomLevel"></span>
        </div>
      </div>`
    const { element: roEl } = await mountController("toolbar", Controller, richHtml(true))
    const roSave = roEl.querySelector("[data-toolbar-target='saveButton']")
    const roMut = roEl.querySelector("[data-toolbar-target='mutatingAction']")
    expect(roSave.classList.contains("opacity-50")).toBe(true)
    expect(roSave.getAttribute("aria-disabled")).toBe("true")
    expect(roMut.disabled).toBe(true)

    const { element: rwEl } = await mountController("toolbar", Controller, richHtml(false))
    const rwSave = rwEl.querySelector("[data-toolbar-target='saveButton']")
    const rwMut = rwEl.querySelector("[data-toolbar-target='mutatingAction']")
    expect(rwSave.getAttribute("aria-disabled")).toBeNull()
    expect(rwMut.disabled).toBe(false)

    const canvasRoot = rwEl.closest("[data-controller='flowchart-canvas']")
    canvasRoot.dispatchEvent(new CustomEvent("flowchartMutabilityChanged", { detail: { canMutate: false } }))
    expect(rwMut.disabled).toBe(true)
    expect(rwSave.getAttribute("aria-disabled")).toBeNull()

    canvasRoot.dispatchEvent(new CustomEvent("flowchartMutabilityChanged", {}))
    expect(rwMut.disabled).toBe(false)
  })
})
