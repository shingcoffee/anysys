// NOTE: the drag-to-resize path (_onMouseMove) requires real pointer coordinates
// and measured `element.offsetWidth`, which happy-dom returns as 0 — it is covered
// by Playwright (spec/e2e), not here. These tests cover the non-geometry logic:
// value defaults, localStorage width restoration, clamping, and connect/disconnect
// wiring.
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/panel_resize_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = (attrs = "") => `<div data-controller="panel-resize" ${attrs}></div>`

describe("panel-resize controller", () => {
  beforeEach(() => localStorage.clear())
  afterEach(() => vi.restoreAllMocks())

  describe("value defaults", () => {
    it("uses documented defaults when no values are set", async () => {
      const { application, element } = await mountController("panel-resize", Controller, html())
      const ctrl = controllerFor(application, element, "panel-resize")
      expect(ctrl.minWidthValue).toBe(400)
      expect(ctrl.maxWidthValue).toBe(700)
      expect(ctrl.defaultWidthValue).toBe(500)
      expect(ctrl.storageKeyValue).toBe("flowchart_property_panel_width")
    })

    it("honors explicitly provided values", async () => {
      const { application, element } = await mountController(
        "panel-resize",
        Controller,
        html('data-panel-resize-min-width-value="200" data-panel-resize-max-width-value="900" data-panel-resize-storage-key-value="k"')
      )
      const ctrl = controllerFor(application, element, "panel-resize")
      expect(ctrl.minWidthValue).toBe(200)
      expect(ctrl.maxWidthValue).toBe(900)
      expect(ctrl.storageKeyValue).toBe("k")
    })
  })

  describe("_restoreWidth on connect", () => {
    it("falls back to defaultWidth when localStorage is empty", async () => {
      const { element } = await mountController("panel-resize", Controller, html())
      expect(element.style.width).toBe("500px")
    })

    it("restores a saved width within range", async () => {
      localStorage.setItem("flowchart_property_panel_width", "620")
      const { element } = await mountController("panel-resize", Controller, html())
      expect(element.style.width).toBe("620px")
    })

    it("clamps a saved width above max down to maxWidth", async () => {
      localStorage.setItem("flowchart_property_panel_width", "5000")
      const { element } = await mountController("panel-resize", Controller, html())
      expect(element.style.width).toBe("700px")
    })

    it("clamps a saved width below min up to minWidth", async () => {
      localStorage.setItem("flowchart_property_panel_width", "10")
      const { element } = await mountController("panel-resize", Controller, html())
      expect(element.style.width).toBe("400px")
    })

    it("uses defaultWidth when the saved value is non-numeric", async () => {
      localStorage.setItem("flowchart_property_panel_width", "not-a-number")
      const { element } = await mountController("panel-resize", Controller, html())
      expect(element.style.width).toBe("500px")
    })
  })

  describe("_clampWidth", () => {
    it("clamps within [min, max]", async () => {
      const { application, element } = await mountController("panel-resize", Controller, html())
      const ctrl = controllerFor(application, element, "panel-resize")
      expect(ctrl._clampWidth(100)).toBe(400)
      expect(ctrl._clampWidth(550)).toBe(550)
      expect(ctrl._clampWidth(9999)).toBe(700)
    })
  })

  describe("startResize wiring (non-geometry)", () => {
    it("sets drag body styles and registers document listeners", async () => {
      const { application, element } = await mountController("panel-resize", Controller, html())
      const ctrl = controllerFor(application, element, "panel-resize")
      const addSpy = vi.spyOn(document, "addEventListener")
      let prevented = false
      ctrl.startResize({ preventDefault: () => (prevented = true), clientX: 123 })
      expect(prevented).toBe(true)
      expect(document.body.style.userSelect).toBe("none")
      expect(document.body.style.cursor).toBe("col-resize")
      expect(ctrl.startX).toBe(123)
      const events = addSpy.mock.calls.map((c) => c[0])
      expect(events).toContain("mousemove")
      expect(events).toContain("mouseup")
      // Clean up the document listeners this test registered.
      ctrl._onMouseUp()
    })

    it("_onMouseUp resets body styles and persists width to localStorage", async () => {
      const { application, element } = await mountController("panel-resize", Controller, html())
      const ctrl = controllerFor(application, element, "panel-resize")
      ctrl.startResize({ preventDefault() {}, clientX: 0 })
      ctrl._onMouseUp()
      expect(document.body.style.userSelect).toBe("")
      expect(document.body.style.cursor).toBe("")
      // offsetWidth is 0 in happy-dom, so the persisted value is "0" — we assert a
      // value was written under the storage key, not its geometry.
      expect(localStorage.getItem("flowchart_property_panel_width")).not.toBeNull()
    })

    it("_onMouseMove clamps the new width from the drag delta (no real layout needed)", async () => {
      const { application, element } = await mountController("panel-resize", Controller, html())
      const ctrl = controllerFor(application, element, "panel-resize")
      // startWidth = offsetWidth (0 in happy-dom); startX from the mousedown event.
      ctrl.startResize({ preventDefault() {}, clientX: 500 })
      // Drag left to 400: delta = 500 - 400 = 100 → newWidth = 0 + 100 = 100 → clamps up to min 400.
      ctrl._onMouseMove({ clientX: 400 })
      expect(element.style.width).toBe("400px")
      ctrl._onMouseUp()
    })

    it("disconnect removes the document-level listeners", async () => {
      const { application, element } = await mountController("panel-resize", Controller, html())
      const ctrl = controllerFor(application, element, "panel-resize")
      const removeSpy = vi.spyOn(document, "removeEventListener")
      ctrl.disconnect()
      const events = removeSpy.mock.calls.map((c) => c[0])
      expect(events).toContain("mousemove")
      expect(events).toContain("mouseup")
    })

    it("clears inline width on mobile viewports (< 640px) and restores when crossing sm", async () => {
      let matches = true
      let listener = null
      vi.spyOn(window, "matchMedia").mockImplementation(() => ({
        get matches() { return matches },
        addEventListener: (_type, fn) => { listener = fn },
        removeEventListener: vi.fn(),
      }))
      localStorage.setItem("flowchart_property_panel_width", "480")
      const { application, element } = await mountController("panel-resize", Controller, html())
      const ctrl = controllerFor(application, element, "panel-resize")
      expect(element.style.width).toBe("")

      matches = false
      listener()
      expect(element.style.width).toBe("480px")
      ctrl.disconnect()
    })

    it("tolerates environments without window.matchMedia", async () => {
      const orig = window.matchMedia
      window.matchMedia = undefined
      try {
        const { element } = await mountController("panel-resize", Controller, html())
        expect(element.style.width).toBe("500px")
      } finally {
        window.matchMedia = orig
      }
    })
  })
})
