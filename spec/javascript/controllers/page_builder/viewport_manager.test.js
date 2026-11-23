import { describe, it, expect, beforeEach } from "vitest"
import { ViewportManager } from "controllers/page_builder/viewport_manager"
import { makeCtrl } from "../../support/page_builder.js"

const btn = (viewport) => {
  const b = document.createElement("button")
  b.dataset.viewport = viewport
  return b
}

describe("ViewportManager", () => {
  let ctrl, vm, canvasFrame, viewportSize, buttons

  beforeEach(() => {
    canvasFrame = document.createElement("div")
    viewportSize = document.createElement("span")
    buttons = [btn("mobile"), btn("tablet"), btn("desktop")]
    ctrl = makeCtrl({
      viewportValue: "desktop",
      hasCanvasFrameTarget: true,
      canvasFrameTarget: canvasFrame,
      hasViewportSizeTarget: true,
      viewportSizeTarget: viewportSize,
      viewportBtnTargets: buttons,
    })
    vm = new ViewportManager(ctrl)
  })

  describe("setViewport", () => {
    it("stores the viewport, updates UI, and re-renders fields", () => {
      const event = { currentTarget: btn("tablet") }
      vm.setViewport(event)
      expect(ctrl.viewportValue).toBe("tablet")
      expect(ctrl.fieldManager.renderFields).toHaveBeenCalled()
      expect(canvasFrame.dataset.viewport).toBe("tablet")
    })
  })

  describe("updateViewportUI", () => {
    it("applies the mobile max-width and label", () => {
      ctrl.viewportValue = "mobile"
      vm.updateViewportUI()
      expect(canvasFrame.style.maxWidth).toBe("375px")
      expect(canvasFrame.dataset.viewport).toBe("mobile")
      expect(viewportSize.textContent).toBe("375px")
    })

    it("desktop uses 800px frame but a 100% label", () => {
      ctrl.viewportValue = "desktop"
      vm.updateViewportUI()
      expect(canvasFrame.style.maxWidth).toBe("800px")
      expect(viewportSize.textContent).toBe("100%")
    })

    it("marks the active button and de-emphasizes the rest", () => {
      ctrl.viewportValue = "tablet"
      vm.updateViewportUI()
      const [mobileBtn, tabletBtn] = buttons
      expect(tabletBtn.classList.contains("bg-white")).toBe(true)
      expect(tabletBtn.classList.contains("text-gray-700")).toBe(true)
      expect(mobileBtn.classList.contains("text-gray-500")).toBe(true)
      expect(mobileBtn.classList.contains("bg-white")).toBe(false)
    })

    it("no-ops safely when targets are absent", () => {
      const bare = makeCtrl({ viewportValue: "mobile", viewportBtnTargets: [] })
      expect(() => new ViewportManager(bare).updateViewportUI()).not.toThrow()
    })
  })
})
