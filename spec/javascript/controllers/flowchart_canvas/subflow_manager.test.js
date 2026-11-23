import { describe, it, expect, vi } from "vitest"
import { SubflowManager } from "controllers/flowchart_canvas/subflow_manager"
import { makeCanvas, makeController } from "../../support/flowchart.js"

function newManager(canvasOverrides = {}, controllerOverrides = {}) {
  const canvas = makeCanvas(canvasOverrides)
  const controller = makeController(canvas, controllerOverrides)
  return { mgr: new SubflowManager(controller), canvas, controller }
}

describe("SubflowManager — construction & mixin wiring", () => {
  it("initializes empty expandedSubflows and mixes in expand/fold/state methods", () => {
    const { mgr } = newManager()
    expect(mgr.expandedSubflows).toEqual({})
    expect(typeof mgr.expandSubflow).toBe("function")
    expect(typeof mgr.foldSubflow).toBe("function")
    expect(typeof mgr.captureCompleteCanvasState).toBe("function")
  })
})

describe("SubflowManager.toggleSubflowExpansion", () => {
  it("no-ops when the subflow element has no flowchartId", async () => {
    const { mgr } = newManager()
    const spy = vi.spyOn(mgr, "expandSubflow")
    await mgr.toggleSubflowExpansion({ id: "SF", properties: {} })
    expect(spy).not.toHaveBeenCalled()
  })

  it("expands when a flowchartId is present", async () => {
    const { mgr } = newManager()
    const spy = vi.spyOn(mgr, "expandSubflow").mockResolvedValue(undefined)
    const el = { id: "SF", properties: { flowchartId: "fc-1" } }
    await mgr.toggleSubflowExpansion(el)
    expect(spy).toHaveBeenCalledWith(el)
  })
})

describe("SubflowManager.expandSubflow / expandSubflowForSave", () => {
  it("delegates to _expandSubflowInternal with the right option flags", async () => {
    const { mgr } = newManager()
    const spy = vi.spyOn(mgr, "_expandSubflowInternal").mockResolvedValue(undefined)
    const el = { id: "SF" }

    await mgr.expandSubflow(el)
    expect(spy).toHaveBeenCalledWith(el, { checkInvokeActivity: true, dispatchEvents: true })

    await mgr.expandSubflowForSave(el)
    expect(spy).toHaveBeenCalledWith(el, { checkInvokeActivity: false, dispatchEvents: false })
  })
})

describe("SubflowManager.expandAllSubflowsForSave", () => {
  it("expands every subflow element that has a flowchartId", async () => {
    const { mgr, canvas } = newManager({
      elements: [
        { id: "SF1", type: "subflow", properties: { flowchartId: "a" } },
        { id: "P", type: "process", properties: {} },
        { id: "SF2", type: "subflow", properties: { flowchartId: "b" } },
        { id: "SF3", type: "subflow", properties: {} }, // no flowchartId -> skipped
      ],
    })
    const spy = vi.spyOn(mgr, "expandSubflowForSave").mockResolvedValue(undefined)
    await mgr.expandAllSubflowsForSave()
    expect(spy).toHaveBeenCalledTimes(2)
    expect(spy.mock.calls.map(c => c[0].id)).toEqual(["SF1", "SF2"])
  })

  it("returns early when there are no subflow elements", async () => {
    const { mgr } = newManager({ elements: [{ id: "P", type: "process", properties: {} }] })
    const spy = vi.spyOn(mgr, "expandSubflowForSave")
    await mgr.expandAllSubflowsForSave()
    expect(spy).not.toHaveBeenCalled()
  })
})
