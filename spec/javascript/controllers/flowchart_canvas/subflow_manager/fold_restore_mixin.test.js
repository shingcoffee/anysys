import { describe, it, expect, vi } from "vitest"
import { FoldRestoreMixin } from "controllers/flowchart_canvas/subflow_manager/fold_restore_mixin"
import { ExpansionMixin } from "controllers/flowchart_canvas/subflow_manager/expansion_mixin"
import { CanvasStateMixin } from "controllers/flowchart_canvas/subflow_manager/canvas_state_mixin"
import { makeCanvas, makeController, mixinHost } from "../../../support/flowchart.js"

function host(canvasOverrides = {}, controllerOverrides = {}) {
  const canvas = makeCanvas(canvasOverrides)
  const controller = makeController(canvas, controllerOverrides)
  const h = mixinHost([FoldRestoreMixin, ExpansionMixin, CanvasStateMixin], { controller, expandedSubflows: {} })
  return { h, canvas, controller }
}

describe("FoldRestoreMixin.foldSubflow", () => {
  it("no-ops for an unknown subflow id", () => {
    const { h, canvas } = host()
    h.foldSubflow("nope")
    expect(canvas.renderElement).not.toHaveBeenCalled()
  })

  it("restores the stored collapsed graph when folding the last expansion", () => {
    const stored = { elements: [{ id: "SF", type: "subflow", x: 12, y: 34 }], connections: [{ id: "c1" }] }
    const start = { id: "SF_sub_s", type: "start", x: 30, y: 40, properties: { varMappings: [{ v: 2 }] } }
    const { h, canvas, controller } = host({ elements: [start], connections: [] })
    canvas.previewMode = true
    controller._collapsedPreviewConfiguration = stored
    h.expandedSubflows.SF = {
      elements: [start],
      originalElement: { id: "SF", type: "subflow", x: 30, y: 40, properties: { flowchartId: "fc-1" } },
      incomingConnections: [],
      outgoingConnections: [],
      startElementId: "SF_sub_s",
      endElementId: "SF_sub_e",
    }

    h.foldSubflow("SF")

    expect(canvas.restoreGraph).toHaveBeenCalledWith(stored)
    expect(canvas.previewMode).toBe(false)
    expect(controller._collapsedPreviewConfiguration).toBeNull()
    expect(h.expandedSubflows.SF).toBeUndefined()
    expect(controller.hasUnsavedChanges).toBe(false)
    expect(controller._dispatchConfigurationChange).not.toHaveBeenCalled()
  })

  it("folds an intermediate expansion from the expand-time snapshot without live copy-back", () => {
    const start = { id: "SF_sub_s", type: "start", x: 30, y: 40, properties: { varMappings: [{ v: 2 }] } }
    const end = { id: "SF_sub_e", type: "end", x: 30, y: 200, properties: { signalWiring: [{ s: 1 }], dataMappings: [{ d: 1 }] } }
    const childEl = { id: "child", x: 30, y: 260 }
    const originalElement = {
      id: "SF", type: "subflow", x: 18, y: 22, width: 100, height: 45,
      label: "Sub", properties: { flowchartId: "fc-1", varMappings: [{ v: "stored" }] },
    }
    const { h, canvas, controller } = host({
      elements: [start, end, childEl],
      connections: [
        { id: "in1_to_start", from: "p", to: "SF_sub_s" },
        { id: "SF_conn_ce", from: "SF_sub_s", to: "SF_sub_e" },
        { id: "out1_from_end", from: "SF_sub_e", to: "child" },
      ],
    })
    canvas.previewMode = true
    ;[start, end].forEach(e => canvas.renderElement(e))
    h.expandedSubflows.SF = {
      elements: [start, end],
      originalElement,
      incomingConnections: [{ id: "in1", from: "p", to: "SF" }],
      outgoingConnections: [{ id: "out1", from: "SF", to: "child", fromPosition: "bottom", toPosition: "top" }],
      startElementId: "SF_sub_s",
      endElementId: "SF_sub_e",
    }
    h.expandedSubflows.OTHER = { elements: [], originalElement: { id: "OTHER" } }

    h.foldSubflow("SF")

    expect(canvas.restoreGraph).not.toHaveBeenCalled()
    expect(canvas.previewMode).toBe(true)
    const restored = canvas.elements.find(e => e.id === "SF")
    expect(restored.properties.varMappings).toEqual([{ v: "stored" }])
    expect(restored.properties.signalWiring).toBeUndefined()
    expect(restored.x).toBe(18)
    expect(restored.y).toBe(22)
    expect(canvas.connections.some(c => c.to === "SF" && c.from === "p")).toBe(true)
    expect(canvas.connections.some(c => c.from === "SF" && c.to === "child")).toBe(true)
    expect(h.expandedSubflows.SF).toBeUndefined()
    expect(h.expandedSubflows.OTHER).toBeTruthy()
    expect(controller.hasUnsavedChanges).toBe(false)
    expect(controller._dispatchConfigurationChange).not.toHaveBeenCalled()
  })

  it("defaults missing original properties to {} on an intermediate fold", () => {
    const start = { id: "SF_sub_s", type: "start", x: 0, y: 0, properties: {} }
    const { h, canvas } = host({ elements: [start], connections: [] })
    canvas.renderElement(start)
    h.expandedSubflows.SF = {
      elements: [start],
      originalElement: { id: "SF", type: "subflow", x: 4, y: 5 },
      incomingConnections: [],
      outgoingConnections: [],
    }
    h.expandedSubflows.OTHER = { elements: [] }
    h.foldSubflow("SF")
    expect(canvas.elements.find(e => e.id === "SF").properties).toEqual({})
  })
})

describe("FoldRestoreMixin.restoreExpandedSubflowsFromConfiguration", () => {
  it("no-ops when no element is tagged with _expandedFromSubflow", () => {
    const { h, canvas } = host({ elements: [{ id: "a", properties: {} }] })
    h.restoreExpandedSubflowsFromConfiguration()
    expect(canvas.updateConnections).not.toHaveBeenCalled()
  })

  it("folds a persisted-expanded group back into a single subflow element", () => {
    const start = {
      id: "SF_sub_s", type: "start", x: 15, y: 25,
      properties: {
        _expandedFromSubflow: "SF",
        _originalSubflowData: { label: "MySub", flowchartId: "fc-9", width: 111, height: 55 },
        varMappings: [{ v: 1 }],
      },
    }
    const end = {
      id: "SF_sub_e", type: "end", x: 15, y: 200,
      properties: { _expandedFromSubflow: "SF", signalWiring: [{ s: 1 }], dataMappings: [{ d: 1 }] },
    }
    const child = { id: "child", x: 15, y: 260 }
    const { h, canvas } = host({
      elements: [start, end, child],
      connections: [
        { id: "in1_to_start", from: "p", to: "SF_sub_s" },
        { id: "out1_from_end", from: "SF_sub_e", to: "child" },
      ],
    })
    ;[start, end].forEach(e => canvas.renderElement(e))

    h.restoreExpandedSubflowsFromConfiguration()

    const subflow = canvas.elements.find(e => e.id === "SF")
    expect(subflow).toBeTruthy()
    expect(subflow.type).toBe("subflow")
    expect(subflow.label).toBe("MySub")
    expect(subflow.width).toBe(111)
    expect(subflow.properties.flowchartId).toBe("fc-9")
    expect(subflow.properties.signalWiring).toEqual([{ s: 1 }])
    expect(subflow.properties.varMappings).toEqual([{ v: 1 }])
    // inner elements removed
    expect(canvas.elements.some(e => e.id === "SF_sub_s")).toBe(false)
    // connections rebased onto the subflow id (ids stripped of _to_start/_from_end)
    expect(canvas.connections.some(c => c.id === "in1" && c.to === "SF")).toBe(true)
    expect(canvas.connections.some(c => c.id === "out1" && c.from === "SF")).toBe(true)
    expect(canvas.updateConnections).toHaveBeenCalled()
  })

  it("skips a group that has no start element", () => {
    const end = { id: "SF_sub_e", type: "end", properties: { _expandedFromSubflow: "SF" } }
    const { h, canvas } = host({ elements: [end], connections: [] })
    h.restoreExpandedSubflowsFromConfiguration()
    expect(canvas.elements.find(e => e.id === "SF")).toBeUndefined()
  })

  it("uses default dimensions/label and empty wiring when the start has no original data and there is no end", () => {
    // start tagged for restore but WITHOUT _originalSubflowData and WITHOUT a
    // matching end element: exercises the `|| {}` originalData fallback, the
    // `endElement ? ... : []` false arm, the signalWiring-undefined else branch,
    // and the width/height/label defaults.
    const start = { id: "SF_sub_s", type: "start", x: 12, y: 34, properties: { _expandedFromSubflow: "SF" } }
    const { h, canvas } = host({ elements: [start], connections: [] })
    canvas.renderElement(start)

    h.restoreExpandedSubflowsFromConfiguration()

    const subflow = canvas.elements.find(e => e.id === "SF")
    expect(subflow).toMatchObject({ type: "subflow", x: 12, y: 34, width: 100, height: 45, label: "Subflow" })
    expect(subflow.properties.flowchartId).toBeUndefined()
    expect(subflow.properties.signalWiring).toEqual([])
    expect(subflow.properties.dataMappings).toEqual([])
  })

  it("labels a restored subflow without original data from the translated default labels (P5-6)", () => {
    const start = { id: "SF_sub_s", type: "start", x: 0, y: 0, properties: { _expandedFromSubflow: "SF" } }
    const { h, canvas } = host(
      { elements: [start], connections: [] },
      { elementDefaultLabelsValue: { subflow: "子流程" } }
    )
    canvas.renderElement(start)
    h.restoreExpandedSubflowsFromConfiguration()
    expect(canvas.elements.find(e => e.id === "SF").label).toBe("子流程")
  })

  it("defaults dataMappings to [] when the persisted end element has signalWiring but no dataMappings", () => {
    const start = {
      id: "SF_sub_s", type: "start", x: 0, y: 0,
      properties: { _expandedFromSubflow: "SF", _originalSubflowData: { flowchartId: "fc-1" } },
    }
    const end = {
      id: "SF_sub_e", type: "end", x: 0, y: 100,
      properties: { _expandedFromSubflow: "SF", signalWiring: [{ s: 1 }] },
    }
    const { h, canvas } = host({ elements: [start, end], connections: [] })
    ;[start, end].forEach(e => canvas.renderElement(e))

    h.restoreExpandedSubflowsFromConfiguration()

    const subflow = canvas.elements.find(e => e.id === "SF")
    expect(subflow.properties.signalWiring).toEqual([{ s: 1 }])
    expect(subflow.properties.dataMappings).toEqual([])
  })
})
