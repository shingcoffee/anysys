import { describe, it, expect, beforeEach, vi } from "vitest"
import { CanvasStateMixin } from "controllers/flowchart_canvas/subflow_manager/canvas_state_mixin"
import { makeCanvas, makeController, mixinHost } from "../../../support/flowchart.js"

function host(canvasOverrides = {}) {
  const canvas = makeCanvas(canvasOverrides)
  const controller = makeController(canvas)
  const h = mixinHost(CanvasStateMixin, { controller, expandedSubflows: {} })
  return { h, canvas, controller }
}

describe("CanvasStateMixin.captureCompleteCanvasState", () => {
  it("deep-copies elements (incl. properties), connections and expandedSubflows", () => {
    const { h, canvas } = host()
    canvas.elements = [{ id: "a", x: 1, properties: { k: 1 } }, { id: "b", x: 2 }]
    canvas.connections = [{ id: "c", from: "a", to: "b" }]
    h.expandedSubflows = { s1: { startElementId: "a" } }

    const snap = h.captureCompleteCanvasState()

    // Mutating source must not affect the snapshot (proves the deep copy).
    canvas.elements[0].properties.k = 99
    canvas.connections[0].from = "zzz"
    expect(snap.elements[0].properties).toEqual({ k: 1 })
    expect(snap.elements[1].properties).toEqual({}) // missing properties -> {}
    expect(snap.connections[0].from).toBe("a")
    expect(snap.expandedSubflows).toEqual({ s1: { startElementId: "a" } })
  })
})

describe("CanvasStateMixin.restoreCompleteCanvasState", () => {
  it("no-ops on a falsy saved state", () => {
    const { h, canvas } = host()
    h.restoreCompleteCanvasState(null)
    expect(canvas.renderElement).not.toHaveBeenCalled()
  })

  it("clears the layers, restores arrays and re-renders each element/connection", () => {
    const { h, canvas } = host()
    // Pre-existing DOM children in the layers should be cleared.
    canvas.elementLayer.appendChild(document.createElementNS("http://www.w3.org/2000/svg", "g"))
    canvas.connectionLayer.appendChild(document.createElementNS("http://www.w3.org/2000/svg", "g"))

    const saved = {
      elements: [{ id: "a", properties: { k: 1 } }, { id: "b" }],
      connections: [{ id: "c", from: "a", to: "b" }],
      expandedSubflows: {},
    }
    h.restoreCompleteCanvasState(saved)

    expect(canvas.elements.map(e => e.id)).toEqual(["a", "b"])
    expect(canvas.connections).toEqual([{ id: "c", from: "a", to: "b" }])
    expect(canvas.renderElement).toHaveBeenCalledTimes(2)
    expect(canvas.updateConnections).toHaveBeenCalled()
    // Old connectionLayer child was removed before re-render.
    expect(canvas.connectionLayer.childElementCount).toBe(0)
  })

  it("re-attaches a fold icon for each active expansion's start element", () => {
    const { h, canvas } = host()
    const addSpy = vi.spyOn(h, "addFoldIconToElement")
    const saved = {
      elements: [{ id: "start-1", type: "start" }],
      connections: [],
      expandedSubflows: { "sub-9": { startElementId: "start-1" } },
    }
    h.restoreCompleteCanvasState(saved)
    expect(addSpy).toHaveBeenCalledWith(expect.objectContaining({ id: "start-1" }), "sub-9")
  })
})

describe("CanvasStateMixin.addFoldIconToElement", () => {
  beforeEach(() => { document.body.innerHTML = "" })

  it("appends a fold-icon <g> (circle + arrow) into the element's group once", () => {
    const { h, canvas } = host()
    const el = { id: "start-1", width: 120 }
    canvas.renderElement(el) // creates the [data-element-id] group

    h.addFoldIconToElement(el, "sub-1")
    const group = canvas.elementLayer.querySelector('[data-element-id="start-1"]')
    const icons = group.querySelectorAll(".fold-icon")
    expect(icons.length).toBe(1)
    expect(icons[0].getAttribute("data-fold-subflow")).toBe("sub-1")
    expect(icons[0].querySelector("circle")).toBeTruthy()
    expect(icons[0].querySelector("path")).toBeTruthy()

    // Idempotent: second call does not add a duplicate icon.
    h.addFoldIconToElement(el, "sub-1")
    expect(group.querySelectorAll(".fold-icon").length).toBe(1)
  })

  it("does nothing when the element group is not in the DOM", () => {
    const { h } = host()
    expect(() => h.addFoldIconToElement({ id: "missing", width: 10 }, "s")).not.toThrow()
  })

  it("wires hover handlers that swap the circle fill/radius on enter and leave", () => {
    const { h, canvas } = host()
    const el = { id: "start-3", width: 100 }
    canvas.renderElement(el)
    h.addFoldIconToElement(el, "sub-3")

    const icon = canvas.elementLayer.querySelector(".fold-icon")
    const circle = icon.querySelector("circle")

    icon.dispatchEvent(new Event("mouseenter"))
    expect(circle.getAttribute("fill")).toBe("#0891b2")
    expect(circle.getAttribute("r")).toBe("12")

    icon.dispatchEvent(new Event("mouseleave"))
    expect(circle.getAttribute("fill")).toBe("#06b6d4")
    expect(circle.getAttribute("r")).toBe("10")
  })

  it("wires a click handler that folds the subflow (stopPropagation)", () => {
    const { h, canvas } = host()
    const el = { id: "start-2", width: 100 }
    canvas.renderElement(el)
    h.foldSubflow = vi.fn()
    h.addFoldIconToElement(el, "sub-2")

    const icon = canvas.elementLayer.querySelector(".fold-icon")
    const evt = new Event("click", { bubbles: true })
    const stop = vi.spyOn(evt, "stopPropagation")
    icon.dispatchEvent(evt)
    expect(stop).toHaveBeenCalled()
    expect(h.foldSubflow).toHaveBeenCalledWith("sub-2")
  })
})

describe("CanvasStateMixin.shiftElementAndSubTreeDirect", () => {
  it("shifts the element and its subtree by a rounded delta and updates connections", () => {
    const child = { id: "child", x: 10, y: 10 }
    const canvas = makeCanvas({
      elements: [{ id: "main", x: 100, y: 100 }, child],
      _getSubTreeElements: vi.fn(() => [{ id: "child" }]),
    })
    const controller = makeController(canvas)
    const h = mixinHost(CanvasStateMixin, { controller, expandedSubflows: {} })
    const main = canvas.elements[0]

    h.shiftElementAndSubTreeDirect(main, 5.4, -3.6)
    expect(main.x).toBe(105) // 100 + 5.4 rounded
    expect(main.y).toBe(96)  // 100 - 3.6 rounded
    expect(child.x).toBe(15)
    expect(child.y).toBe(6)
    expect(canvas.updateElementPosition).toHaveBeenCalledTimes(2)
    expect(canvas.updateConnections).toHaveBeenCalled()
  })

  it("treats the subtree as empty when the canvas has no _getSubTreeElements helper", () => {
    const canvas = makeCanvas({ elements: [{ id: "main", x: 100, y: 100 }] })
    canvas._getSubTreeElements = undefined
    const controller = makeController(canvas)
    const h = mixinHost(CanvasStateMixin, { controller, expandedSubflows: {} })
    const main = canvas.elements[0]

    h.shiftElementAndSubTreeDirect(main, 2, 2)
    expect(main.x).toBe(102)
    expect(main.y).toBe(102)
    // Only the main element is repositioned — no subtree walk happened.
    expect(canvas.updateElementPosition).toHaveBeenCalledTimes(1)
  })

  it("no-ops without a canvas", () => {
    const controller = { canvas: null }
    const h = mixinHost(CanvasStateMixin, { controller, expandedSubflows: {} })
    expect(() => h.shiftElementAndSubTreeDirect({ x: 0, y: 0 }, 1, 1)).not.toThrow()
  })
})
