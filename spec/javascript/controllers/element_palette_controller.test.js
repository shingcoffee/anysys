import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/element_palette_controller"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

// A fake flowchart-canvas sibling supplies customerId and (optionally) a
// flowchartCanvas facade the palette talks to.
const html = `
  <div>
    <div data-controller="flowchart-canvas" data-flowchart-canvas-customer-id-value="42" data-flowchart-canvas-urls-value='{"list":"/42/admin/maintenance/flowcharts.json"}'></div>
    <div data-flowchart-canvas-target="canvasContainer"></div>
    <div data-controller="element-palette" data-element-palette-current-flowchart-id-value="5">
      <div data-element-palette-target="basicElements">
        <div data-drag-source="true" data-flowchart-element="start">Start</div>
      </div>
      <input data-element-palette-target="searchInput" data-action="input->element-palette#searchFlowcharts">
      <div data-element-palette-target="flowchartsPlaceholder">loading</div>
      <div data-element-palette-target="flowchartsList"></div>
    </div>
  </div>`

const flowcharts = [
  { id: 1, name: "Onboarding", description: "welcome flow" },
  { id: 2, name: "Checkout", description: "payment" },
]

const listEl = (el) => el.querySelector("[data-element-palette-target='flowchartsList']")
const canvasEl = () => document.querySelector('[data-controller*="flowchart-canvas"]')

describe("element-palette controller", () => {
  let application, element, ctrl
  beforeEach(async () => {
    globalThis.fetch = vi.fn(() => Promise.resolve({ ok: true, json: () => Promise.resolve([]) }))
    ;({ application, element } = await mountController("element-palette", Controller, html))
    ctrl = controllerFor(application, element, "element-palette")
    ctrl.flowchartsData = flowcharts
  })
  afterEach(() => vi.restoreAllMocks())

  describe("connect / _loadFlowcharts", () => {
    it("fetches flowcharts for the current customer, excluding the current flowchart", () => {
      expect(globalThis.fetch).toHaveBeenCalledWith("/42/admin/maintenance/flowcharts.json?except_id=5")
    })
  })

  describe("_renderFlowcharts", () => {
    it("renders one item per flowchart and hides the placeholder", () => {
      ctrl._renderFlowcharts(flowcharts)
      expect(listEl(element).querySelectorAll("[data-flowchart-element='subflow']").length).toBe(2)
      expect(element.querySelector("[data-element-palette-target='flowchartsPlaceholder']").style.display).toBe("none")
    })

    it("shows a 'No other flows' message for an empty list", () => {
      ctrl._renderFlowcharts([])
      expect(listEl(element).textContent).toContain("No other flows")
    })

    it("wires drag data attributes onto each subflow item", () => {
      ctrl._renderFlowcharts([flowcharts[0]])
      const item = listEl(element).querySelector("[data-flowchart-element='subflow']")
      expect(item.dataset.flowchartId).toBe("1")
      expect(item.dataset.label).toBe("Onboarding")
      expect(item.dataset.elementId).toBe("flow_1")
    })
  })

  describe("searchFlowcharts", () => {
    it("filters via fuzzy match on name/description", () => {
      ctrl.searchFlowcharts({ target: { value: "check" } })
      const items = listEl(element).querySelectorAll("[data-flowchart-element='subflow']")
      expect(items.length).toBe(1)
      expect(items[0].dataset.label).toBe("Checkout")
    })

    it("empty search restores the full list", () => {
      ctrl.searchFlowcharts({ target: { value: "check" } })
      ctrl.searchFlowcharts({ target: { value: "  " } })
      expect(listEl(element).querySelectorAll("[data-flowchart-element='subflow']").length).toBe(2)
    })
  })

  describe("_calculateOptimalPosition", () => {
    it("returns the default start position when the canvas is empty", () => {
      expect(ctrl._calculateOptimalPosition(null)).toEqual({ x: 400, y: 80 })
      expect(ctrl._calculateOptimalPosition({ elements: [] })).toEqual({ x: 400, y: 80 })
    })

    it("places the new element a grid-aligned distance below the last one", () => {
      const canvas = { elements: [{ x: 100, y: 200, height: 45 }] }
      // 45/2 + 50 + 45/2 = 95 -> round(95/15)*15 = 90
      expect(ctrl._calculateOptimalPosition(canvas)).toEqual({ x: 100, y: 290 })
    })
  })

  describe("_dispatchElementDrop", () => {
    it("dispatches an elementDrop CustomEvent on the canvas element", () => {
      const spy = vi.fn()
      canvasEl().addEventListener("elementDrop", spy)
      ctrl._dispatchElementDrop("decision", 10, 20, { flowchartId: "9" }, true)
      expect(spy).toHaveBeenCalledOnce()
      expect(spy.mock.calls[0][0].detail).toMatchObject({
        elementType: "decision",
        x: 10,
        y: 20,
        isDoubleClick: true,
      })
    })
  })

  describe("_updateStartElementState", () => {
    it("disables the Start palette item when the canvas already has a Start element", () => {
      canvasEl().flowchartCanvas = { hasStartElement: () => true }
      ctrl._updateStartElementState()
      const start = element.querySelector('[data-flowchart-element="start"]')
      expect(start.draggable).toBe(false)
      expect(start.classList.contains("opacity-50")).toBe(true)
    })

    it("enables the Start item when the canvas has no Start element", () => {
      canvasEl().flowchartCanvas = { hasStartElement: () => false }
      ctrl._updateStartElementState()
      const start = element.querySelector('[data-flowchart-element="start"]')
      expect(start.draggable).toBe(true)
      expect(start.classList.contains("cursor-grab")).toBe(true)
    })
  })

  // ===================
  // Extended coverage: disconnect, drag/drop, double-click, scroll/feedback,
  // error rendering, drop-position math.
  // ===================

  const basicHtml = `
    <div data-element-palette-target="basicElements">
      <div data-drag-source="true" data-flowchart-element="start">Start</div>
    </div>
    <input data-element-palette-target="searchInput" data-action="input->element-palette#searchFlowcharts">
    <div data-element-palette-target="flowchartsPlaceholder">loading</div>
    <div data-element-palette-target="flowchartsList"></div>
  `

  const htmlNoCanvas = `
    <div>
      <div data-flowchart-canvas-target="canvasContainer"></div>
      <div data-controller="element-palette" data-element-palette-current-flowchart-id-value="5">
        ${basicHtml}
      </div>
    </div>`

  const htmlNoContainer = `
    <div>
      <div data-controller="flowchart-canvas" data-flowchart-canvas-customer-id-value="42" data-flowchart-canvas-urls-value='{"list":"/42/admin/maintenance/flowcharts.json"}'></div>
      <div data-controller="element-palette" data-element-palette-current-flowchart-id-value="5">
        ${basicHtml}
      </div>
    </div>`

  const htmlNoCustomerId = `
    <div>
      <div data-controller="flowchart-canvas"></div>
      <div data-flowchart-canvas-target="canvasContainer"></div>
      <div data-controller="element-palette" data-element-palette-current-flowchart-id-value="5">
        ${basicHtml}
      </div>
    </div>`

  const htmlNoCurrentId = `
    <div>
      <div data-controller="flowchart-canvas" data-flowchart-canvas-customer-id-value="42" data-flowchart-canvas-urls-value='{"list":"/42/admin/maintenance/flowcharts.json"}'></div>
      <div data-flowchart-canvas-target="canvasContainer"></div>
      <div data-controller="element-palette">
        ${basicHtml}
      </div>
    </div>`

  const htmlNoPlaceholder = `
    <div>
      <div data-controller="flowchart-canvas" data-flowchart-canvas-customer-id-value="42" data-flowchart-canvas-urls-value='{"list":"/42/admin/maintenance/flowcharts.json"}'></div>
      <div data-flowchart-canvas-target="canvasContainer"></div>
      <div data-controller="element-palette" data-element-palette-current-flowchart-id-value="5">
        <div data-element-palette-target="basicElements">
          <div data-drag-source="true" data-flowchart-element="start">Start</div>
        </div>
        <input data-element-palette-target="searchInput" data-action="input->element-palette#searchFlowcharts">
        <div data-element-palette-target="flowchartsList"></div>
      </div>
    </div>`

  const htmlNoList = `
    <div>
      <div data-controller="flowchart-canvas" data-flowchart-canvas-customer-id-value="42" data-flowchart-canvas-urls-value='{"list":"/42/admin/maintenance/flowcharts.json"}'></div>
      <div data-flowchart-canvas-target="canvasContainer"></div>
      <div data-controller="element-palette" data-element-palette-current-flowchart-id-value="5">
        <div data-element-palette-target="basicElements">
          <div data-drag-source="true" data-flowchart-element="start">Start</div>
        </div>
        <input data-element-palette-target="searchInput" data-action="input->element-palette#searchFlowcharts">
        <div data-element-palette-target="flowchartsPlaceholder">loading</div>
      </div>
    </div>`

  async function mount(html) {
    const mounted = await mountController("element-palette", Controller, html)
    return { ...mounted, ctrl: controllerFor(mounted.application, mounted.element, "element-palette") }
  }

  describe("disconnect / _removeCanvasChangeListener", () => {
    it("removes the flowchartChanged listener from the canvas element on disconnect", async () => {
      const canvas = canvasEl()
      const spy = vi.spyOn(canvas, "removeEventListener")
      element.remove()
      await tick()
      expect(spy).toHaveBeenCalledWith("flowchartChanged", expect.any(Function))
    })

    it("is a no-op when there is no canvas element (both operands false)", async () => {
      const { ctrl: aloneCtrl } = await mount(htmlNoCanvas)
      expect(() => aloneCtrl._removeCanvasChangeListener()).not.toThrow()
    })

    it("is a no-op when a canvas element exists but no bound listener was captured", async () => {
      const { ctrl: c } = await mount(html)
      delete c._boundUpdateStartElementState
      expect(() => c._removeCanvasChangeListener()).not.toThrow()
    })
  })

  describe("_setupDropZone (line 99 branch)", () => {
    it("does not throw when the canvas container target is missing", async () => {
      await expect(mount(htmlNoContainer)).resolves.toBeTruthy()
    })
  })

  describe("_handleDoubleClick", () => {
    it("returns early when the event target has no ancestor flowchart-element", () => {
      const stray = document.createElement("span")
      const evt = { preventDefault: vi.fn(), stopPropagation: vi.fn(), target: stray }
      expect(() => ctrl._handleDoubleClick(evt)).not.toThrow()
      expect(evt.preventDefault).toHaveBeenCalled()
      expect(evt.stopPropagation).toHaveBeenCalled()
    })

    it("returns early when there is no canvas element or container", async () => {
      const { ctrl: c, element: el } = await mount(htmlNoCanvas)
      const start = el.querySelector('[data-flowchart-element="start"]')
      const evt = { preventDefault: vi.fn(), stopPropagation: vi.fn(), target: start }
      expect(() => c._handleDoubleClick(evt)).not.toThrow()
    })

    it("dispatches an elementDrop at the default position, shows feedback, and scrolls", () => {
      const container = document.querySelector('[data-flowchart-canvas-target="canvasContainer"]')
      container.scrollTo = vi.fn()
      const start = element.querySelector('[data-flowchart-element="start"]')
      const spy = vi.fn()
      canvasEl().addEventListener("elementDrop", spy)

      const evt = { preventDefault: vi.fn(), stopPropagation: vi.fn(), target: start }
      ctrl._handleDoubleClick(evt)

      expect(spy).toHaveBeenCalledOnce()
      expect(spy.mock.calls[0][0].detail).toMatchObject({
        elementType: "start",
        x: 400,
        y: 80,
        isDoubleClick: true,
        customElementData: null,
      })
      expect(start.classList.contains("ring-2")).toBe(true)
    })

    it("includes sub-flow custom data when the target carries a flowchartId", () => {
      const container = document.querySelector('[data-flowchart-canvas-target="canvasContainer"]')
      container.scrollTo = vi.fn()
      ctrl._renderFlowcharts([flowcharts[0]])
      const item = listEl(element).querySelector("[data-flowchart-element='subflow']")
      const spy = vi.fn()
      canvasEl().addEventListener("elementDrop", spy)

      const evt = { preventDefault: vi.fn(), stopPropagation: vi.fn(), target: item }
      ctrl._handleDoubleClick(evt)

      expect(spy.mock.calls[0][0].detail.customElementData).toEqual({
        name: "Sub-flow: Onboarding",
        flowchartId: "1",
      })
    })
  })

  describe("scroll-into-view", () => {
    it("does not own scroll-into-view — the canvas _scrollToElement path does", () => {
      expect(ctrl._scrollToPosition).toBeUndefined()
    })
  })

  describe("_showClickFeedback", () => {
    it("applies a ring highlight and removes it after 150ms", () => {
      vi.useFakeTimers()
      const start = element.querySelector('[data-flowchart-element="start"]')
      ctrl._showClickFeedback(start)
      expect(start.classList.contains("ring-2")).toBe(true)
      expect(start.classList.contains("scale-95")).toBe(true)
      vi.advanceTimersByTime(150)
      expect(start.classList.contains("ring-2")).toBe(false)
      expect(start.classList.contains("scale-95")).toBe(false)
      vi.useRealTimers()
    })
  })

  describe("_handleDragStart / _handleDragEnd", () => {
    it("returns early from dragstart when there is no ancestor flowchart-element", () => {
      const stray = document.createElement("span")
      const evt = { target: stray, dataTransfer: { setData: vi.fn() } }
      expect(() => ctrl._handleDragStart(evt)).not.toThrow()
      expect(evt.dataTransfer.setData).not.toHaveBeenCalled()
    })

    it("sets drag payload, cursor/opacity and the dragging-element body class", () => {
      const start = element.querySelector('[data-flowchart-element="start"]')
      const dataTransfer = { setData: vi.fn(), effectAllowed: "" }
      ctrl._handleDragStart({ target: start, dataTransfer })

      expect(dataTransfer.setData).toHaveBeenCalledWith(
        "application/json",
        JSON.stringify({ elementType: "start", elementId: undefined, label: undefined })
      )
      expect(dataTransfer.effectAllowed).toBe("copy")
      expect(start.style.opacity).toBe("0.5")
      expect(start.style.cursor).toBe("grabbing")
      expect(document.body.classList.contains("dragging-element")).toBe(true)
    })

    it("includes flowchart reference data for sub-flow drag items", () => {
      ctrl._renderFlowcharts([flowcharts[0]])
      const item = listEl(element).querySelector("[data-flowchart-element='subflow']")
      const dataTransfer = { setData: vi.fn(), effectAllowed: "" }
      ctrl._handleDragStart({ target: item, dataTransfer })

      const payload = JSON.parse(dataTransfer.setData.mock.calls[0][1])
      expect(payload.flowchartId).toBe("1")
      expect(payload.flowchartName).toBe("Onboarding")
    })

    it("returns early from dragend when there is no ancestor flowchart-element (still clears drag state)", () => {
      document.body.classList.add("dragging-element")
      const dropZone = document.querySelector('[data-flowchart-canvas-target="canvasContainer"]')
      dropZone.classList.add("drop-zone-active")
      const stray = document.createElement("span")

      ctrl._handleDragEnd({ target: stray })

      expect(document.body.classList.contains("dragging-element")).toBe(false)
      expect(dropZone.classList.contains("drop-zone-active")).toBe(false)
    })

    it("resets opacity/cursor on dragend for a real flowchart-element target", () => {
      const start = element.querySelector('[data-flowchart-element="start"]')
      start.style.opacity = "0.5"
      start.style.cursor = "grabbing"
      document.body.classList.add("dragging-element")

      ctrl._handleDragEnd({ target: start })

      expect(start.style.opacity).toBe("")
      expect(start.style.cursor).toBe("grab")
      expect(document.body.classList.contains("dragging-element")).toBe(false)
    })
  })

  describe("_handleMouseEnter / _handleMouseLeave", () => {
    it("scales up on mouseenter and resets on mouseleave for a flowchart-element target", () => {
      const start = element.querySelector('[data-flowchart-element="start"]')
      ctrl._handleMouseEnter({ target: start })
      expect(start.style.transform).toBe("scale(1.05)")
      ctrl._handleMouseLeave({ target: start })
      expect(start.style.transform).toBe("")
    })

    it("is a no-op for a target with no ancestor flowchart-element", () => {
      const stray = document.createElement("span")
      expect(() => ctrl._handleMouseEnter({ target: stray })).not.toThrow()
      expect(() => ctrl._handleMouseLeave({ target: stray })).not.toThrow()
    })
  })

  describe("_handleDragOver", () => {
    it("highlights the drop target when the canvas facade is ready", () => {
      const highlightDropTargetAt = vi.fn()
      canvasEl().flowchartCanvas = { highlightDropTargetAt }
      const evt = { preventDefault: vi.fn(), dataTransfer: { dropEffect: "" }, clientX: 3, clientY: 4 }

      ctrl._handleDragOver(evt)

      expect(evt.preventDefault).toHaveBeenCalled()
      expect(evt.dataTransfer.dropEffect).toBe("copy")
      expect(highlightDropTargetAt).toHaveBeenCalledWith(3, 4)
    })

    it("does not throw when the canvas facade is not ready", () => {
      canvasEl().flowchartCanvas = undefined
      const evt = { preventDefault: vi.fn(), dataTransfer: { dropEffect: "" }, clientX: 3, clientY: 4 }
      expect(() => ctrl._handleDragOver(evt)).not.toThrow()
    })
  })

  describe("_handleDragEnter / _handleDragLeave / drop-zone highlight", () => {
    it("adds the drop-zone-active class on dragenter", () => {
      const zone = document.querySelector('[data-flowchart-canvas-target="canvasContainer"]')
      ctrl._handleDragEnter({ preventDefault: vi.fn(), currentTarget: zone })
      expect(zone.classList.contains("drop-zone-active")).toBe(true)
    })

    it("removes the highlight and clears the canvas highlight when leaving to an unrelated element", () => {
      const zone = document.querySelector('[data-flowchart-canvas-target="canvasContainer"]')
      zone.classList.add("drop-zone-active")
      const clearExternalDropHighlight = vi.fn()
      canvasEl().flowchartCanvas = { clearExternalDropHighlight }
      const outsider = document.createElement("div")

      ctrl._handleDragLeave({ currentTarget: zone, relatedTarget: outsider })

      expect(zone.classList.contains("drop-zone-active")).toBe(false)
      expect(clearExternalDropHighlight).toHaveBeenCalled()
    })

    it("does nothing when leaving to a related target still inside the drop zone", () => {
      const zone = document.querySelector('[data-flowchart-canvas-target="canvasContainer"]')
      const child = document.createElement("span")
      zone.appendChild(child)
      zone.classList.add("drop-zone-active")
      const clearExternalDropHighlight = vi.fn()
      canvasEl().flowchartCanvas = { clearExternalDropHighlight }

      ctrl._handleDragLeave({ currentTarget: zone, relatedTarget: child })

      expect(zone.classList.contains("drop-zone-active")).toBe(true)
      expect(clearExternalDropHighlight).not.toHaveBeenCalled()
    })

    it("tolerates a missing canvas facade on dragleave", () => {
      const zone = document.querySelector('[data-flowchart-canvas-target="canvasContainer"]')
      canvasEl().flowchartCanvas = undefined
      const outsider = document.createElement("div")
      expect(() => ctrl._handleDragLeave({ currentTarget: zone, relatedTarget: outsider })).not.toThrow()
    })
  })

  describe("_handleDrop", () => {
    it("dispatches elementDrop at the computed position and shows a success indicator (no canvas facade)", () => {
      canvasEl().flowchartCanvas = undefined
      const container = document.querySelector('[data-flowchart-canvas-target="canvasContainer"]')
      const spy = vi.fn()
      canvasEl().addEventListener("elementDrop", spy)
      const dataTransfer = { getData: vi.fn(() => JSON.stringify({ elementType: "decision" })) }
      const evt = { preventDefault: vi.fn(), dataTransfer, clientX: 5, clientY: 5 }

      ctrl._handleDrop(evt)

      expect(evt.preventDefault).toHaveBeenCalled()
      expect(spy).toHaveBeenCalledOnce()
      expect(spy.mock.calls[0][0].detail).toMatchObject({
        elementType: "decision",
        customElementData: null,
        isDoubleClick: false,
        dropTarget: null,
      })
      expect(container.querySelector(".drop-success-animation")).toBeTruthy()
    })

    it("uses the canvas facade's drop target and clears its highlight when present", () => {
      const getExternalDropTarget = vi.fn(() => ({ id: "n1" }))
      const clearExternalDropHighlight = vi.fn()
      canvasEl().flowchartCanvas = { getExternalDropTarget, clearExternalDropHighlight }
      const spy = vi.fn()
      canvasEl().addEventListener("elementDrop", spy)
      const dataTransfer = {
        getData: vi.fn(() => JSON.stringify({ elementType: "subflow", flowchartId: "9", flowchartName: "Sub" })),
      }
      const evt = { preventDefault: vi.fn(), dataTransfer, clientX: 5, clientY: 5 }

      ctrl._handleDrop(evt)

      expect(clearExternalDropHighlight).toHaveBeenCalled()
      expect(spy.mock.calls[0][0].detail).toMatchObject({
        elementType: "subflow",
        customElementData: { name: "Sub-flow: Sub", flowchartId: "9" },
        dropTarget: { id: "n1" },
      })
    })

    it("logs and swallows errors when the drag payload is not valid JSON", () => {
      const errSpy = vi.spyOn(console, "error").mockImplementation(() => {})
      const spy = vi.fn()
      canvasEl().addEventListener("elementDrop", spy)
      const dataTransfer = { getData: vi.fn(() => "not-json{") }
      const evt = { preventDefault: vi.fn(), dataTransfer, clientX: 5, clientY: 5 }

      expect(() => ctrl._handleDrop(evt)).not.toThrow()

      expect(spy).not.toHaveBeenCalled()
      expect(errSpy).toHaveBeenCalledWith("[element-palette] Failed to handle element drop:", expect.any(Error))
    })
  })

  describe("_dispatchElementDrop (no canvas element)", () => {
    it("does not throw when there is no canvas element to dispatch on", async () => {
      const { ctrl: c } = await mount(htmlNoCanvas)
      expect(() => c._dispatchElementDrop("start", 1, 2)).not.toThrow()
    })
  })

  describe("_getDropPosition", () => {
    it("uses the canvas zoom/pan manager to convert client coordinates when available", () => {
      const clientToSVG = vi.fn(() => ({ x: 11, y: 22 }))
      canvasEl().flowchartCanvas = { zoomPanManager: { clientToSVG } }
      const pos = ctrl._getDropPosition({ clientX: 1, clientY: 2 })
      expect(clientToSVG).toHaveBeenCalledWith(1, 2)
      expect(pos).toEqual({ x: 11, y: 22 })
    })

    it("falls back to container-relative math when there is no zoom/pan manager", () => {
      canvasEl().flowchartCanvas = undefined
      const container = document.querySelector('[data-flowchart-canvas-target="canvasContainer"]')
      Object.defineProperty(container, "getBoundingClientRect", {
        value: () => ({ x: 0, y: 0, width: 50, height: 50, top: 10, left: 20, right: 70, bottom: 60 }),
      })
      container.scrollLeft = 5
      container.scrollTop = 7

      const pos = ctrl._getDropPosition({ clientX: 100, clientY: 200 })

      expect(pos).toEqual({ x: 100 - 20 + 5, y: 200 - 10 + 7 })
    })

    it("falls back to a fixed default when there is no canvas container at all", async () => {
      const { ctrl: c } = await mount(htmlNoContainer)
      const pos = c._getDropPosition({ clientX: 100, clientY: 200 })
      expect(pos).toEqual({ x: 100, y: 100 })
    })
  })

  describe("_showDropSuccess", () => {
    it("does nothing when the canvas container is missing", async () => {
      const { ctrl: c } = await mount(htmlNoContainer)
      expect(() => c._showDropSuccess({ x: 1, y: 1 })).not.toThrow()
    })

    it("renders a positioned indicator and removes it after 1s", () => {
      vi.useFakeTimers()
      const container = document.querySelector('[data-flowchart-canvas-target="canvasContainer"]')
      Object.defineProperty(container, "getBoundingClientRect", {
        value: () => ({ left: 10, top: 20, width: 400, height: 300 }),
      })
      container.scrollLeft = 4
      container.scrollTop = 6
      ctrl._showDropSuccess({ clientX: 89, clientY: 111 })
      const indicator = container.querySelector(".drop-success-animation")
      expect(indicator).toBeTruthy()
      expect(indicator.style.left).toBe("58px") // 89 - 10 + 4 - 25
      expect(indicator.style.top).toBe("72px") // 111 - 20 + 6 - 25
      vi.advanceTimersByTime(1000)
      expect(container.querySelector(".drop-success-animation")).toBeFalsy()
      vi.useRealTimers()
    })
  })

  describe("_loadFlowcharts error paths", () => {
    it("shows 'No customer context' and skips the fetch when there is no customer id", async () => {
      globalThis.fetch = vi.fn(() => Promise.resolve({ ok: true, json: () => Promise.resolve([]) }))
      const { element: el } = await mount(htmlNoCustomerId)
      expect(globalThis.fetch).not.toHaveBeenCalled()
      expect(el.querySelector("[data-element-palette-target='flowchartsPlaceholder']").textContent).toBe(
        "No customer context"
      )
    })

    it("shows 'Failed to load flowcharts' when the response is not ok", async () => {
      globalThis.fetch = vi.fn(() => Promise.resolve({ ok: false }))
      const { element: el } = await mount(html)
      expect(el.querySelector("[data-element-palette-target='flowchartsPlaceholder']").textContent).toBe(
        "Failed to load flowcharts"
      )
    })

    it("shows 'No flowcharts available' and logs when fetch throws", async () => {
      const errSpy = vi.spyOn(console, "error").mockImplementation(() => {})
      globalThis.fetch = vi.fn(() => Promise.reject(new Error("network down")))
      const { element: el } = await mount(html)
      expect(el.querySelector("[data-element-palette-target='flowchartsPlaceholder']").textContent).toBe(
        "No flowcharts available"
      )
      expect(errSpy).toHaveBeenCalled()
    })

    it("requests the base URL (no except_id) when there is no current flowchart id", async () => {
      globalThis.fetch = vi.fn(() => Promise.resolve({ ok: true, json: () => Promise.resolve([]) }))
      await mount(htmlNoCurrentId)
      expect(globalThis.fetch).toHaveBeenCalledWith("/42/admin/maintenance/flowcharts.json")
    })

    it("_showFlowchartsError is a no-op when there is no placeholder target", async () => {
      const { ctrl: c } = await mount(htmlNoPlaceholder)
      expect(() => c._showFlowchartsError("whatever")).not.toThrow()
    })
  })

  describe("_renderFlowcharts (line 351 branch)", () => {
    it("returns early when there is no flowchartsList target", async () => {
      const { ctrl: c } = await mount(htmlNoList)
      expect(() => c._renderFlowcharts(flowcharts)).not.toThrow()
    })
  })

  describe("tooltip on flowchart items (description fallback + hover lifecycle)", () => {
    it("falls back to the flowchart name when there is no description", () => {
      ctrl._renderFlowcharts([{ id: 3, name: "NoDescFlow" }])
      const item = listEl(element).querySelector("[data-flowchart-element='subflow']")
      const wrapper = item.parentElement

      wrapper.dispatchEvent(new Event("mouseenter"))
      const tooltip = document.body.querySelector(".fixed.px-2\\.5")
      expect(tooltip.textContent).toBe("NoDescFlow")

      wrapper.dispatchEvent(new Event("mouseleave"))
      expect(document.body.querySelector(".fixed.px-2\\.5")).toBeFalsy()
    })

    it("shows the description as tooltip text when present, and a second mouseleave is a safe no-op", () => {
      ctrl._renderFlowcharts([flowcharts[0]])
      const item = listEl(element).querySelector("[data-flowchart-element='subflow']")
      const wrapper = item.parentElement

      wrapper.dispatchEvent(new Event("mouseenter"))
      expect(document.body.querySelector(".fixed.px-2\\.5").textContent).toBe("welcome flow")
      wrapper.dispatchEvent(new Event("mouseleave"))
      expect(() => wrapper.dispatchEvent(new Event("mouseleave"))).not.toThrow()
    })
  })

  describe("searchFlowcharts (line 447 branch: description fallback)", () => {
    it("matches on name alone when a flowchart has no description", () => {
      ctrl.flowchartsData = [{ id: 4, name: "Zephyr" }]
      ctrl.searchFlowcharts({ target: { value: "zephyr" } })
      const items = listEl(element).querySelectorAll("[data-flowchart-element='subflow']")
      expect(items.length).toBe(1)
      expect(items[0].dataset.label).toBe("Zephyr")
    })
  })
})

describe("P5-8 cleanup — palette drop-zone listeners, drop timer, unused param", () => {
  let application, element, ctrl
  beforeEach(async () => {
    globalThis.fetch = vi.fn(() => Promise.resolve({ ok: true, json: () => Promise.resolve([]) }))
    ;({ application, element } = await mountController("element-palette", Controller, html))
    ctrl = controllerFor(application, element, "element-palette")
  })
  afterEach(() => vi.restoreAllMocks())

  it("takes only the canvas argument for _calculateOptimalPosition", () => {
    expect(ctrl._calculateOptimalPosition.length).toBe(1)
  })

  it("removes canvas drop-zone listeners on disconnect with the same handlers", async () => {
    const container = document.querySelector('[data-flowchart-canvas-target="canvasContainer"]')
    const over = ctrl._boundHandleDragOver
    const drop = ctrl._boundHandleDrop
    const enter = ctrl._boundHandleDragEnter
    const leave = ctrl._boundHandleDragLeave
    expect(over).toEqual(expect.any(Function))
    expect(drop).toEqual(expect.any(Function))
    expect(enter).toEqual(expect.any(Function))
    expect(leave).toEqual(expect.any(Function))

    const remove = vi.spyOn(container, "removeEventListener")
    element.remove()
    await tick()
    expect(remove).toHaveBeenCalledWith("dragover", over)
    expect(remove).toHaveBeenCalledWith("drop", drop)
    expect(remove).toHaveBeenCalledWith("dragenter", enter)
    expect(remove).toHaveBeenCalledWith("dragleave", leave)
  })

  it("does not highlight a drop target after disconnect when dragover is dispatched", async () => {
    const highlight = vi.fn()
    canvasEl().flowchartCanvas = {
      highlightDropTargetAt: highlight,
      zoomPanManager: { clientToSVG: () => ({ x: 1, y: 2 }) },
    }
    const container = document.querySelector('[data-flowchart-canvas-target="canvasContainer"]')
    element.remove()
    await tick()

    const evt = new Event("dragover", { bubbles: true, cancelable: true })
    evt.dataTransfer = { dropEffect: "" }
    evt.clientX = 10
    evt.clientY = 20
    container.dispatchEvent(evt)
    expect(highlight).not.toHaveBeenCalled()
  })

  it("disconnect is safe when no drop zone was attached", () => {
    ctrl._dropZone = null
    expect(() => ctrl.disconnect()).not.toThrow()
  })

  it("clears a pending drop-indicator timer before showing another indicator", () => {
    vi.useFakeTimers()
    try {
      const container = document.querySelector('[data-flowchart-canvas-target="canvasContainer"]')
      Object.defineProperty(container, "getBoundingClientRect", {
        value: () => ({ left: 10, top: 20, width: 400, height: 300 }),
      })
      ctrl._showDropSuccess({ clientX: 89, clientY: 111 })
      expect(container.querySelectorAll(".drop-success-animation").length).toBe(1)
      ctrl._showDropSuccess({ clientX: 100, clientY: 120 })
      expect(container.querySelectorAll(".drop-success-animation").length).toBe(1)
      vi.advanceTimersByTime(1000)
      expect(container.querySelector(".drop-success-animation")).toBeFalsy()
    } finally {
      vi.useRealTimers()
    }
  })

  it("clears the drop-indicator timer on disconnect so advancing fake timers does nothing", () => {
    vi.useFakeTimers()
    try {
      const container = document.querySelector('[data-flowchart-canvas-target="canvasContainer"]')
      Object.defineProperty(container, "getBoundingClientRect", {
        value: () => ({ left: 10, top: 20, width: 400, height: 300 }),
      })
      ctrl._showDropSuccess({ clientX: 89, clientY: 111 })
      expect(container.querySelector(".drop-success-animation")).toBeTruthy()

      ctrl.disconnect()
      const removeChild = vi.spyOn(container, "removeChild")
      vi.advanceTimersByTime(1000)
      expect(removeChild).not.toHaveBeenCalled()
    } finally {
      vi.useRealTimers()
    }
  })
})

describe("P5-4 element-palette — canMutate guard", () => {
  let application, element, ctrl
  beforeEach(async () => {
    globalThis.fetch = vi.fn(() => Promise.resolve({ ok: true, json: () => Promise.resolve([]) }))
    ;({ application, element } = await mountController("element-palette", Controller, html))
    ctrl = controllerFor(application, element, "element-palette")
    ctrl.flowchartsData = flowcharts
  })
  afterEach(() => vi.restoreAllMocks())

  it("ignores double-click and drop when the canvas cannot mutate", () => {
    canvasEl().flowchartCanvas = { canMutate: () => false }
    const spy = vi.fn()
    canvasEl().addEventListener("elementDrop", spy)
    const start = element.querySelector('[data-flowchart-element="start"]')
    ctrl._handleDoubleClick({ preventDefault: vi.fn(), stopPropagation: vi.fn(), target: start })
    ctrl._handleDrop({
      preventDefault: vi.fn(),
      dataTransfer: { getData: () => JSON.stringify({ elementType: "process" }) },
      clientX: 5,
      clientY: 5,
    })
    expect(spy).not.toHaveBeenCalled()
  })

  it("disables palette dragging and hover/drop feedback when read-only or previewing, and restores when mutable", () => {
    const proc = document.createElement("div")
    proc.dataset.dragSource = "true"
    proc.dataset.flowchartElement = "process"
    element.querySelector("[data-element-palette-target='basicElements']").appendChild(proc)

    canvasEl().dataset.flowchartCanvasReadOnlyValue = "true"
    canvasEl().dispatchEvent(new CustomEvent("flowchartMutabilityChanged", { detail: { canMutate: false } }))
    expect(proc.draggable).toBe(false)
    expect(proc.classList.contains("opacity-50")).toBe(true)

    const prevent = vi.fn()
    ctrl._handleDragStart({ preventDefault: prevent, target: proc })
    expect(prevent).toHaveBeenCalled()
    ctrl._handleMouseEnter({ target: proc })
    expect(proc.style.transform).toBe("")
    ctrl._handleDragOver({ preventDefault: vi.fn(), dataTransfer: {} })
    ctrl._handleDragEnter({ preventDefault: vi.fn(), currentTarget: document.createElement("div") })

    delete canvasEl().dataset.flowchartCanvasReadOnlyValue
    canvasEl().flowchartCanvas = { canMutate: () => true, hasStartElement: () => false }
    canvasEl().dispatchEvent(new CustomEvent("flowchartMutabilityChanged", { detail: { canMutate: true } }))
    expect(proc.draggable).toBe(true)
    expect(proc.classList.contains("opacity-50")).toBe(false)

    // _renderFlowcharts tolerates a flowchart item wrapper without an inner [data-drag-source]
    vi.spyOn(ctrl, "_createFlowchartItem").mockReturnValueOnce(document.createElement("div"))
    ctrl._renderFlowcharts([flowcharts[0]])
  })
})
