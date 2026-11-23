// NOTE: _showPopover-style positioning is absent here; ZoomManager is DOM-structural
// (class toggles, innerHTML) and does not depend on measured layout, so it is fully
// unit-testable in happy-dom.
import { describe, it, expect, beforeEach } from "vitest"
import { ZoomManager } from "controllers/page_builder/zoom_manager"
import { makeCtrl } from "../../support/page_builder.js"

describe("ZoomManager", () => {
  let ctrl, zm, fieldsContainer, zoomLevel

  beforeEach(() => {
    fieldsContainer = document.createElement("div")
    zoomLevel = document.createElement("span")
    ctrl = makeCtrl({
      hasFieldsContainerTarget: true,
      fieldsContainerTarget: fieldsContainer,
      hasZoomLevelTarget: true,
      zoomLevelTarget: zoomLevel,
    })
    zm = new ZoomManager(ctrl)
  })

  describe("zoom in/out/reset", () => {
    it("starts at 100%", () => {
      expect(zm.currentZoom).toBe(100)
    })

    it("zoomIn steps up through the discrete levels", () => {
      zm.zoomIn()
      expect(zm.currentZoom).toBe(125)
      expect(fieldsContainer.style.transform).toBe("scale(1.25)")
      expect(zoomLevel.textContent).toBe("125%")
    })

    it("zoomIn caps at 150%", () => {
      zm.zoomIn() // 125
      zm.zoomIn() // 150
      zm.zoomIn() // stays
      expect(zm.currentZoom).toBe(150)
    })

    it("zoomOut steps down and floors at 50%", () => {
      zm.zoomOut() // 75
      zm.zoomOut() // 50
      zm.zoomOut() // stays
      expect(zm.currentZoom).toBe(50)
      expect(fieldsContainer.style.transform).toBe("scale(0.5)")
    })

    it("zoomReset returns to 100%", () => {
      zm.zoomIn()
      zm.zoomReset()
      expect(zm.currentZoom).toBe(100)
      expect(zoomLevel.textContent).toBe("100%")
    })

    it("_applyZoom no-ops without a fields container", () => {
      const bare = makeCtrl({})
      const z = new ZoomManager(bare)
      expect(() => z.zoomIn()).not.toThrow()
    })
  })

  describe("mini map", () => {
    let miniMap, canvas
    beforeEach(() => {
      miniMap = document.createElement("div")
      canvas = document.createElement("div")
      ctrl.hasMiniMapTarget = true
      ctrl.miniMapTarget = miniMap
      ctrl.hasMiniMapCanvasTarget = true
      ctrl.miniMapCanvasTarget = canvas
      ctrl.currentPage.fields = [
        { property_type: "layout" },
        { property_type: "string" },
      ]
    })

    it("toggles visibility and renders blocks when shown", () => {
      zm.toggleMiniMap()
      expect(zm.miniMapVisible).toBe(true)
      expect(miniMap.classList.contains("hidden")).toBe(false)
      // one block per field + the viewport indicator div
      expect(canvas.querySelectorAll("div").length).toBe(3)
    })

    it("hides again on the second toggle", () => {
      zm.toggleMiniMap()
      zm.toggleMiniMap()
      expect(zm.miniMapVisible).toBe(false)
      expect(miniMap.classList.contains("hidden")).toBe(true)
    })

    it("_renderMiniMap no-ops without a mini map canvas target", () => {
      ctrl.hasMiniMapCanvasTarget = false
      expect(() => zm.toggleMiniMap()).not.toThrow()
      expect(canvas.innerHTML).toBe("")
    })

    it("_renderMiniMap falls back to an empty array when currentPageFields is unset", () => {
      ctrl.currentPage.fields = undefined
      zm.toggleMiniMap()
      // no field blocks, just the viewport indicator div
      expect(canvas.querySelectorAll("div").length).toBe(1)
    })
  })

  describe("canvas search", () => {
    let canvasArea, fieldsC, searchCount
    beforeEach(() => {
      canvasArea = document.createElement("div")
      fieldsC = document.createElement("div")
      searchCount = document.createElement("span")
      fieldsC.innerHTML =
        `<div class="field-card">Email address</div>` +
        `<div class="field-card">Phone number</div>`
      ctrl.hasCanvasAreaTarget = true
      ctrl.canvasAreaTarget = canvasArea
      ctrl.hasFieldsContainerTarget = true
      ctrl.fieldsContainerTarget = fieldsC
      ctrl.hasSearchCountTarget = true
      ctrl.searchCountTarget = searchCount
    })

    it("openSearch no-ops without a canvas area target", () => {
      ctrl.hasCanvasAreaTarget = false
      expect(() => zm.openSearch()).not.toThrow()
      expect(canvasArea.querySelectorAll(".canvas-search-bar").length).toBe(0)
    })

    it("openSearch injects a single search bar and re-uses it", () => {
      zm.openSearch()
      expect(canvasArea.querySelectorAll(".canvas-search-bar").length).toBe(1)
      zm.closeSearch()
      zm.openSearch()
      expect(canvasArea.querySelectorAll(".canvas-search-bar").length).toBe(1)
    })

    it("filterSearch dims non-matching cards and reports the count", () => {
      const event = { target: { value: "email" } }
      zm.filterSearch(event)
      const cards = fieldsC.querySelectorAll(".field-card")
      expect(cards[0].style.opacity).toBe("1")
      expect(cards[1].style.opacity).toBe("0.3")
      expect(searchCount.textContent).toBe("1 of 2")
    })

    it("filterSearch with a blank query restores full opacity", () => {
      zm.filterSearch({ target: { value: "email" } })
      zm.filterSearch({ target: { value: "  " } })
      const cards = fieldsC.querySelectorAll(".field-card")
      expect(cards[0].style.opacity).toBe("1")
      expect(cards[1].style.opacity).toBe("1")
      expect(searchCount.textContent).toBe("")
    })

    it("searchKeydown Escape closes the search bar", () => {
      zm.openSearch()
      const preventDefault = () => {}
      zm.searchKeydown({ key: "Escape", preventDefault })
      const bar = canvasArea.querySelector(".canvas-search-bar")
      expect(bar.classList.contains("hidden")).toBe(true)
    })
  })
})
