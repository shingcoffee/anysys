import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Controller as StimulusController } from "@hotwired/stimulus"
import Controller from "controllers/page_toolbar_controller"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

// The toolbar reacts to events emitted by a sibling page-canvas element. We
// render a page-canvas element but do NOT register the page-canvas controller,
// so _getCanvasController() returns null (save/undo/redo become safe no-ops)
// while the DOM element still receives the custom events the toolbar listens to.
const html = `
  <div>
    <div data-controller="page-canvas"></div>
    <div data-controller="page-toolbar">
      <span data-page-toolbar-target="saveStatus"></span>
      <button data-page-toolbar-target="undoButton"></button>
      <button data-page-toolbar-target="redoButton"></button>
    </div>
  </div>`

async function mount() {
  const { application, element } = await mountController("page-toolbar", Controller, html)
  const ctrl = controllerFor(application, element, "page-toolbar")
  const canvas = document.querySelector('[data-controller="page-canvas"]')
  const status = element.querySelector('[data-page-toolbar-target="saveStatus"]')
  const undoBtn = element.querySelector('[data-page-toolbar-target="undoButton"]')
  const redoBtn = element.querySelector('[data-page-toolbar-target="redoButton"]')
  return { application, ctrl, canvas, status, undoBtn, redoBtn }
}

describe("page-toolbar controller", () => {
  afterEach(() => { document.querySelectorAll(".fixed.top-4").forEach(n => n.remove()) })

  it("initializes to the saved state with undo/redo disabled", async () => {
    const { status, undoBtn, redoBtn } = await mount()
    expect(status.textContent).toBe("All changes saved")
    expect(status.className).toContain("text-green-600")
    expect(undoBtn.disabled).toBe(true)
    expect(redoBtn.disabled).toBe(true)
    expect(undoBtn.classList.contains("opacity-50")).toBe(true)
  })

  it("shows 'Unsaved changes' when the canvas emits pageChanged", async () => {
    const { canvas, status } = await mount()
    canvas.dispatchEvent(new CustomEvent("pageChanged", { detail: { hasUnsavedChanges: true } }))
    expect(status.textContent).toBe("Unsaved changes")
    expect(status.className).toContain("text-amber-600")
  })

  it("defaults hasUnsavedChanges to true when pageChanged omits detail", async () => {
    const { canvas, ctrl, status } = await mount()
    canvas.dispatchEvent(new CustomEvent("pageChanged", { detail: {} }))
    expect(ctrl.hasUnsavedChanges).toBe(true)
    expect(status.textContent).toBe("Unsaved changes")
  })

  it("shows success + a notification when the canvas emits pageSaved", async () => {
    const { canvas, ctrl, status } = await mount()
    ctrl.hasUnsavedChanges = true
    canvas.dispatchEvent(new CustomEvent("pageSaved"))
    expect(ctrl.hasUnsavedChanges).toBe(false)
    expect(status.textContent).toBe("Saved successfully")
    const note = document.querySelector(".fixed.top-4")
    expect(note).toBeTruthy()
    expect(note.textContent).toBe("Page saved successfully")
    expect(note.className).toContain("bg-green-100")
  })

  it("shows 'Save failed' and joins error messages on pageSaveError", async () => {
    const { canvas, status } = await mount()
    canvas.dispatchEvent(new CustomEvent("pageSaveError", { detail: { errors: ["a", "b"] } }))
    expect(status.textContent).toBe("Save failed")
    expect(status.className).toContain("text-red-600")
    const note = document.querySelector(".fixed.top-4")
    expect(note.textContent).toBe("a, b")
    expect(note.className).toContain("bg-red-100")
  })

  it("falls back to a generic error message when errors is empty", async () => {
    const { canvas } = await mount()
    canvas.dispatchEvent(new CustomEvent("pageSaveError", { detail: { errors: [] } }))
    expect(document.querySelector(".fixed.top-4").textContent).toBe("Failed to save page")
  })

  it("toggles button disabled state on undoRedoStateChanged", async () => {
    const { canvas, undoBtn, redoBtn } = await mount()
    canvas.dispatchEvent(new CustomEvent("undoRedoStateChanged", { detail: { canUndo: true, canRedo: false } }))
    expect(undoBtn.disabled).toBe(false)
    expect(undoBtn.classList.contains("opacity-50")).toBe(false)
    expect(redoBtn.disabled).toBe(true)
    expect(redoBtn.classList.contains("cursor-not-allowed")).toBe(true)
  })

  it("save/undo/redo are safe no-ops when no page-canvas controller is registered", async () => {
    const { ctrl } = await mount()
    const evt = { preventDefault: vi.fn() }
    expect(() => ctrl.save(evt)).not.toThrow()
    expect(() => ctrl.undo(evt)).not.toThrow()
    expect(() => ctrl.redo(evt)).not.toThrow()
    expect(evt.preventDefault).toHaveBeenCalledTimes(3)
  })

  it("unbinds canvas listeners on disconnect", async () => {
    const { ctrl, canvas, status } = await mount()
    ctrl.disconnect()
    canvas.dispatchEvent(new CustomEvent("pageChanged", { detail: { hasUnsavedChanges: true } }))
    // After disconnect the handler no longer runs, so status is unchanged.
    expect(status.textContent).toBe("All changes saved")
  })

  describe("with a registered page-canvas controller", () => {
    let saveMock, undoMock, redoMock
    async function mountWithCanvas() {
      saveMock = vi.fn().mockResolvedValue(true)
      undoMock = vi.fn()
      redoMock = vi.fn()
      class Canvas extends StimulusController {
        save() { return saveMock() }
        undo() { undoMock() }
        redo() { redoMock() }
      }
      const m = await mount()
      m.application.register("page-canvas", Canvas)
      await tick()
      return m
    }

    it("save() shows the saving status and delegates to the canvas", async () => {
      const { ctrl, status } = await mountWithCanvas()
      ctrl.save({ preventDefault() {} })
      expect(status.textContent).toBe("Saving...")
      expect(status.className).toContain("text-blue-600")
      await tick()
      expect(saveMock).toHaveBeenCalled()
    })

    it("save() shows an error when the canvas reports failure", async () => {
      const { ctrl, status } = await mountWithCanvas()
      saveMock.mockResolvedValue(false)
      ctrl.save({ preventDefault() {} })
      await tick()
      expect(status.textContent).toBe("Save failed")
      expect(status.className).toContain("text-red-600")
    })

    it("undo() and redo() delegate to the canvas controller", async () => {
      const { ctrl } = await mountWithCanvas()
      ctrl.undo({ preventDefault() {} })
      ctrl.redo({ preventDefault() {} })
      expect(undoMock).toHaveBeenCalled()
      expect(redoMock).toHaveBeenCalled()
    })
  })

  it("returns no canvas controller when there is no page-canvas element", async () => {
    const bare = `
      <div data-controller="page-toolbar">
        <span data-page-toolbar-target="saveStatus"></span>
      </div>`
    const { application, element } = await mountController("page-toolbar", Controller, bare)
    const ctrl = controllerFor(application, element, "page-toolbar")
    expect(ctrl.canvasElement).toBeNull()
    expect(ctrl._getCanvasController()).toBeNull()
    // disconnect with no canvas element is a safe no-op
    expect(() => ctrl.disconnect()).not.toThrow()
  })

  it("tolerates missing detail on pageSaveError and undoRedoStateChanged", async () => {
    const { canvas, status, undoBtn, redoBtn } = await mount()
    canvas.dispatchEvent(new CustomEvent("pageSaveError", { detail: {} }))
    expect(status.textContent).toBe("Save failed")
    expect(document.querySelector(".fixed.top-4").textContent).toBe("Failed to save page")
    canvas.dispatchEvent(new CustomEvent("undoRedoStateChanged", { detail: {} }))
    expect(undoBtn.disabled).toBe(true)
    expect(redoBtn.disabled).toBe(true)
  })

  it("UI-update helpers are safe no-ops without a saveStatus target", async () => {
    const bare = `
      <div>
        <div data-controller="page-canvas"></div>
        <div data-controller="page-toolbar"></div>
      </div>`
    const { application, element } = await mountController("page-toolbar", Controller, bare)
    const ctrl = controllerFor(application, element, "page-toolbar")
    expect(ctrl.hasSaveStatusTarget).toBe(false)
    expect(() => ctrl._showSaving()).not.toThrow()
    // pageSaved still fires a notification even without the status target
    const canvas = element.parentElement.querySelector('[data-controller="page-canvas"]')
    canvas.dispatchEvent(new CustomEvent("pageSaved"))
    expect(document.querySelector(".fixed.top-4").textContent).toBe("Page saved successfully")
    canvas.dispatchEvent(new CustomEvent("pageSaveError", { detail: { errors: ["x"] } }))
  })

  it("_getNotificationColorClass falls back to info for unknown types", async () => {
    const { ctrl } = await mount()
    expect(ctrl._getNotificationColorClass("mystery")).toContain("bg-blue-100")
  })

  it("auto-dismisses the notification after its timeouts", async () => {
    const { ctrl } = await mount()
    vi.useFakeTimers()
    try {
      ctrl._showNotification("hello", "info")
      const note = document.querySelector(".fixed.top-4")
      expect(note).toBeTruthy()
      vi.advanceTimersByTime(5000)
      expect(note.style.transform).toBe("translateX(100%)")
      expect(note.style.opacity).toBe("0")
      vi.advanceTimersByTime(300)
      expect(document.querySelector(".fixed.top-4")).toBeNull()
    } finally {
      vi.useRealTimers()
    }
  })
})
