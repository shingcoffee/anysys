import { describe, it, expect, beforeEach, vi } from "vitest"
import { BaseManager } from "controllers/property_editor/base_manager"

// BaseManager is pure class logic over a controller reference — no real DOM
// layout needed. We hand it a plain fake controller.
const makeController = () => ({
  canvas: { id: "canvas" },
  currentElement: { id: "el_1" },
  formFieldsTarget: document.createElement("div"),
  formTarget: document.createElement("form"),
})

describe("BaseManager", () => {
  let controller, mgr
  beforeEach(() => {
    controller = makeController()
    mgr = new BaseManager(controller, "stepIndex")
  })

  it("initializes the named index to 0", () => {
    expect(mgr.stepIndex).toBe(0)
    expect(mgr.getIndex()).toBe(0)
  })

  it("exposes convenience getters that proxy the controller", () => {
    expect(mgr.canvas).toBe(controller.canvas)
    expect(mgr.currentElement).toBe(controller.currentElement)
    expect(mgr.formFieldsTarget).toBe(controller.formFieldsTarget)
  })

  it("getters reflect live controller mutations", () => {
    controller.canvas = null
    controller.currentElement = null
    expect(mgr.canvas).toBeNull()
    expect(mgr.currentElement).toBeNull()
  })

  describe("index management", () => {
    it("setIndex / getIndex round-trip", () => {
      mgr.setIndex(5)
      expect(mgr.getIndex()).toBe(5)
      expect(mgr.stepIndex).toBe(5)
    })

    it("incrementIndex advances by 1", () => {
      mgr.incrementIndex()
      mgr.incrementIndex()
      expect(mgr.getIndex()).toBe(2)
    })

    it("reset returns the index to 0", () => {
      mgr.setIndex(9)
      mgr.reset()
      expect(mgr.getIndex()).toBe(0)
    })

    it("honors a different index name", () => {
      const other = new BaseManager(controller, "branchIndex")
      expect(other.branchIndex).toBe(0)
      other.incrementIndex()
      expect(other.branchIndex).toBe(1)
      expect(other.getIndex()).toBe(1)
    })
  })

  describe("_dispatchEvent", () => {
    it("dispatches a bubbling CustomEvent on the form target", () => {
      const handler = vi.fn()
      controller.formTarget.addEventListener("branchAdded", handler)
      mgr._dispatchEvent("branchAdded")
      expect(handler).toHaveBeenCalledOnce()
      expect(handler.mock.calls[0][0].bubbles).toBe(true)
    })

    it("no-ops when the controller has no form target", () => {
      controller.formTarget = null
      expect(() => mgr._dispatchEvent("branchAdded")).not.toThrow()
    })
  })
})
