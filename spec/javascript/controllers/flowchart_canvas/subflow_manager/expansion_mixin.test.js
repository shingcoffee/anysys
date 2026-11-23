import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { ExpansionMixin } from "controllers/flowchart_canvas/subflow_manager/expansion_mixin"
import { CanvasStateMixin } from "controllers/flowchart_canvas/subflow_manager/canvas_state_mixin"
import { makeCanvas, makeController, mixinHost } from "../../../support/flowchart.js"
import { PositionCalculator } from "controllers/flowchart_canvas/position_calculator"

function host(canvasOverrides = {}, controllerOverrides = {}) {
  const canvas = makeCanvas(canvasOverrides)
  const controller = makeController(canvas, {
    urlsValue: { list: "/42/admin/maintenance/flowcharts.json" },
    ...controllerOverrides,
  })
  // shiftElementAndSubTreeDirect (used by position adjusts) lives in CanvasStateMixin.
  const h = mixinHost([ExpansionMixin, CanvasStateMixin], { controller, expandedSubflows: {} })
  return { h, canvas, controller }
}

describe("ExpansionMixin._extractKeywordParamsFromSubflow", () => {
  it("collects unique keyword params from process steps (string and object forms)", () => {
    const { h } = host()
    const subflowElements = [
      { type: "start" },
      { type: "process", properties: { steps: [
        { keywordParams: ["a", "b"] },
        { keywordParams: [{ value: "b" }, { value: "c" }] },
      ] } },
      { type: "process", properties: { steps: [{ keywordParams: ["a", "d"] }] } },
      { type: "end" },
    ]
    expect(h._extractKeywordParamsFromSubflow(subflowElements)).toEqual(["a", "b", "c", "d"])
  })

  it("returns an empty array when there are no process steps", () => {
    const { h } = host()
    expect(h._extractKeywordParamsFromSubflow([{ type: "start" }])).toEqual([])
  })

  it("tolerates process elements without steps and steps without keywordParams", () => {
    const { h } = host()
    const subflowElements = [
      { type: "process", properties: {} },                 // no steps -> [] (line 388)
      { type: "process", properties: { steps: [{}] } },    // step without keywordParams -> [] (line 390)
    ]
    expect(h._extractKeywordParamsFromSubflow(subflowElements)).toEqual([])
  })

  it("keeps an object keyword param that has no `value` field (falls back to the object)", () => {
    const { h } = host()
    const paramObj = { name: "x" } // no `value` -> `param.value || param` yields the object
    const result = h._extractKeywordParamsFromSubflow([
      { type: "process", properties: { steps: [{ keywordParams: [paramObj] }] } },
    ])
    expect(result).toEqual([paramObj])
  })
})

describe("ExpansionMixin._createInternalConnections", () => {
  it("namespaces connection ids/endpoints under the subflow and defaults positions", () => {
    const { h, canvas } = host()
    h._createInternalConnections([{ id: "c1", from: "n1", to: "n2" }], "SF", canvas)
    expect(canvas.connections).toEqual([{
      id: "SF_conn_c1", from: "SF_sub_n1", to: "SF_sub_n2",
      fromPosition: "bottom", toPosition: "top",
    }])
  })

  it("no-ops for empty/missing connections", () => {
    const { h, canvas } = host()
    h._createInternalConnections(undefined, "SF", canvas)
    h._createInternalConnections([], "SF", canvas)
    expect(canvas.connections).toEqual([])
  })
})

describe("ExpansionMixin._reconnectIncomingConnections", () => {
  it("rewires each incoming connection to the start element on its top port", () => {
    const { h, canvas } = host()
    h._reconnectIncomingConnections([{ id: "in1", from: "p", to: "SF", fromPosition: "right" }], { id: "start" }, canvas)
    expect(canvas.connections[0]).toEqual({
      id: "in1_to_start", from: "p", to: "start", fromPosition: "right", toPosition: "top",
    })
  })

  it("does nothing when there is no start element", () => {
    const { h, canvas } = host()
    h._reconnectIncomingConnections([{ id: "in1" }], null, canvas)
    expect(canvas.connections).toEqual([])
  })

  it("defaults the source port to bottom when the incoming connection has none", () => {
    const { h, canvas } = host()
    h._reconnectIncomingConnections([{ id: "in1", from: "p", to: "SF" }], { id: "start" }, canvas)
    expect(canvas.connections[0].fromPosition).toBe("bottom")
  })
})

describe("ExpansionMixin._reconnectOutgoingConnections & _adjustChildElementPosition", () => {
  it("returns an empty map when there is no end element", () => {
    const { h, canvas } = host()
    expect(h._reconnectOutgoingConnections([{ id: "o" }], null, canvas)).toEqual({})
  })

  it("captures child positions, shifts overlapping children and rewires from the end element", () => {
    // Child overlaps the end element (its top is above end+spacing) and sits on a
    // different x → calculateChildShiftForExpansion returns a non-zero shift, so
    // shiftElementAndSubTreeDirect runs (covers the `shift !== 0` branch).
    const child = { id: "child", x: 200, y: 0, height: 45 }
    const canvas = makeCanvas({ elements: [child] })
    const controller = makeController(canvas)
    const h = mixinHost([ExpansionMixin, CanvasStateMixin], { controller, expandedSubflows: {} })
    const endEl = { id: "end", x: 0, y: 0, height: 45 }

    const positions = h._reconnectOutgoingConnections(
      [{ id: "o1", to: "child", toPosition: "top" }],
      endEl,
      canvas,
    )

    expect(positions.child).toEqual({ x: 200, y: 0 }) // original captured before the shift
    expect(canvas.updateElementPosition).toHaveBeenCalled()   // child was shifted
    const rewired = canvas.connections.find(c => c.id === "o1_from_end")
    expect(rewired).toMatchObject({ from: "end", to: "child", fromPosition: "bottom", toPosition: "top" })
  })

  it("_adjustChildElementPositionForFold shifts when the fold calculator returns a delta", () => {
    const child = { id: "child", x: 200, y: 0, height: 45 }
    const { h } = host({ elements: [child] })
    h.shiftElementAndSubTreeDirect = vi.fn()
    const spy = vi.spyOn(PositionCalculator, "calculateChildShiftForFold").mockReturnValue({ shiftX: 4, shiftY: 0 })
    h._adjustChildElementPositionForFold({ id: "restored" }, child, {})
    expect(h.shiftElementAndSubTreeDirect).toHaveBeenCalledWith(child, 4, 0)
    spy.mockRestore()
  })

  it("_adjustChildElementPositionForFold skips a zero shift", () => {
    const child = { id: "child", x: 0, y: 1000, height: 45 }
    const { h } = host({ elements: [child] })
    h.shiftElementAndSubTreeDirect = vi.fn()
    const spy = vi.spyOn(PositionCalculator, "calculateChildShiftForFold").mockReturnValue({ shiftX: 0, shiftY: 0 })
    h._adjustChildElementPositionForFold({ id: "restored" }, child, {})
    expect(h.shiftElementAndSubTreeDirect).not.toHaveBeenCalled()
    spy.mockRestore()
  })

  it("skips the shift for a child already clear of the end element and ignores unknown targets", () => {
    // Child sits far below and on the same x → zero shift (covers the false side
    // of the `shift !== 0` guard). A second connection targets a missing element.
    const child = { id: "child", x: 0, y: 1000, height: 45 }
    const canvas = makeCanvas({ elements: [child] })
    canvas._getSubTreeElements = undefined // covers the `? : []` fallback in _captureSubtreePositions
    const controller = makeController(canvas)
    const h = mixinHost([ExpansionMixin, CanvasStateMixin], { controller, expandedSubflows: {} })
    const endEl = { id: "end", x: 0, y: 0, height: 45 }

    const positions = h._reconnectOutgoingConnections(
      [{ id: "o1", to: "child" }, { id: "o2", to: "ghost" }],
      endEl,
      canvas,
    )

    expect(positions.child).toEqual({ x: 0, y: 1000 })
    expect(positions.ghost).toBeUndefined()          // unknown target skipped (line 296 false)
    expect(canvas.updateElementPosition).not.toHaveBeenCalled() // no shift happened
    // both connections still rewired, defaulting the target port
    expect(canvas.connections.find(c => c.id === "o1_from_end").toPosition).toBe("top")
    expect(canvas.connections.find(c => c.id === "o2_from_end")).toBeTruthy()
  })
})

describe("ExpansionMixin._getParentInfo", () => {
  it("pulls parent outputs and detects an invoke_activity process step", () => {
    const parent = { id: "p", type: "process", properties: { outputs: ["o1"], steps: [{ action: "invoke_activity" }] } }
    const { h, canvas } = host({ elements: [parent] })
    const info = h._getParentInfo([{ from: "p", to: "SF" }], canvas, true)
    expect(info.parentOutputs).toEqual(["o1"])
    expect(info.parentHasInvokeActivity).toBe(true)
  })

  it("skips the invoke_activity check when disabled", () => {
    const parent = { id: "p", type: "process", properties: { steps: [{ action: "invoke_activity" }] } }
    const { h, canvas } = host({ elements: [parent] })
    const info = h._getParentInfo([{ from: "p" }], canvas, false)
    expect(info.parentHasInvokeActivity).toBe(false)
  })

  it("returns defaults when there are no incoming connections", () => {
    const { h, canvas } = host()
    expect(h._getParentInfo([], canvas, true)).toEqual({ parentOutputs: [], parentHasInvokeActivity: false })
  })

  it("does not scan steps when the parent element isn't a process (check enabled)", () => {
    const parent = { id: "p", type: "decision", properties: { steps: [{ action: "invoke_activity" }] } }
    const { h, canvas } = host({ elements: [parent] })
    const info = h._getParentInfo([{ from: "p", to: "SF" }], canvas, true)
    expect(info.parentHasInvokeActivity).toBe(false)
  })

  it("returns defaults when the incoming connection's parent isn't on the canvas", () => {
    const { h, canvas } = host({ elements: [] })
    const info = h._getParentInfo([{ from: "ghost", to: "SF" }], canvas, true)
    expect(info).toEqual({ parentOutputs: [], parentHasInvokeActivity: false })
  })

  it("treats a process parent with no steps as having no invoke_activity", () => {
    const parent = { id: "p", type: "process", properties: { outputs: ["o1"] } } // no steps -> `|| []`
    const { h, canvas } = host({ elements: [parent] })
    const info = h._getParentInfo([{ from: "p", to: "SF" }], canvas, true)
    expect(info.parentOutputs).toEqual(["o1"])
    expect(info.parentHasInvokeActivity).toBe(false)
  })
})

describe("ExpansionMixin._createExpandedElements", () => {
  it("clones subflow nodes with namespaced ids, applied offset and rendered", () => {
    const { h, canvas } = host()
    const subflowElement = { id: "SF", label: "MySub", width: 120, height: 60, properties: { varMappings: [{ v: 1 }], signalWiring: [{ s: 1 }], dataMappings: [{ d: 1 }] } }
    const subflowElements = [
      { id: "s", type: "start", x: 10, y: 20 },
      { id: "e", type: "end", x: 10, y: 200 },
    ]
    const result = h._createExpandedElements(subflowElements, subflowElement, "fc-77", 5, 7, ["o"], false, canvas)

    expect(result.map(e => e.id)).toEqual(["SF_sub_s", "SF_sub_e"])
    expect(result[0].x).toBe(15) // 10 + offsetX
    expect(result[0].y).toBe(27) // 20 + offsetY
    // start element carries the original subflow data + copied varMappings
    expect(result[0].properties._originalSubflowData).toMatchObject({ label: "MySub", flowchartId: "fc-77", width: 120, height: 60 })
    expect(result[0].properties.varMappings).toEqual([{ v: 1 }])
    // end element receives deep-cloned signalWiring + dataMappings
    expect(result[1].properties.signalWiring).toEqual([{ s: 1 }])
    expect(result[1].properties.dataMappings).toEqual([{ d: 1 }])
    // every clone tags its origin and is pushed + rendered
    expect(result.every(e => e.properties._expandedFromSubflow === "SF")).toBe(true)
    expect(canvas.elements.map(e => e.id)).toEqual(["SF_sub_s", "SF_sub_e"])
    expect(canvas.renderElement).toHaveBeenCalledTimes(2)
  })
})

describe("ExpansionMixin._captureSubtreePositions & _removeSubflowElement", () => {
  it("captures the element position and its subtree (without overwriting)", () => {
    const child = { id: "c1", x: 5, y: 6 }
    const canvas = makeCanvas({
      elements: [child, { id: "gc", x: 9, y: 9 }],
      _getSubTreeElements: vi.fn(() => [{ id: "gc" }]),
    })
    const controller = makeController(canvas)
    const h = mixinHost(ExpansionMixin, { controller, expandedSubflows: {} })
    const positions = { c1: { x: 100, y: 100 } } // pre-existing entry must be kept
    h._captureSubtreePositions(child, canvas, positions)
    expect(positions.c1).toEqual({ x: 100, y: 100 })
    expect(positions.gc).toEqual({ x: 9, y: 9 })
  })

  it("_removeSubflowElement drops the element, its connections and its DOM group", () => {
    const sub = { id: "SF" }
    const canvas = makeCanvas({
      elements: [sub, { id: "other" }],
      connections: [{ from: "SF", to: "other" }, { from: "other", to: "SF" }, { from: "x", to: "y" }],
    })
    canvas.renderElement(sub)
    const controller = makeController(canvas)
    const h = mixinHost(ExpansionMixin, { controller, expandedSubflows: {} })

    h._removeSubflowElement(sub)
    expect(canvas.elements.map(e => e.id)).toEqual(["other"])
    expect(canvas.connections).toEqual([{ from: "x", to: "y" }])
    expect(canvas.elementLayer.querySelector('[data-element-id="SF"]')).toBeNull()
  })
})

describe("ExpansionMixin._fetchSubflowConfiguration", () => {
  afterEach(() => vi.unstubAllGlobals())

  it("returns null when the list URL cannot be derived", async () => {
    const { h } = host({}, { urlsValue: {} })
    expect(await h._fetchSubflowConfiguration("fc-1")).toBeNull()
  })

  it("GETs the flowchart JSON and returns the configuration object", async () => {
    const cfg = { elements: [{ id: "s" }], connections: [] }
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => ({ configuration: cfg }) })))
    const { h } = host({}, { customerIdValue: "42" })
    const result = await h._fetchSubflowConfiguration("fc-1")
    expect(fetch).toHaveBeenCalledWith("/42/admin/maintenance/flowcharts/fc-1.json", expect.objectContaining({ method: "GET" }))
    expect(result).toEqual(cfg)
  })

  it("parses a stringified configuration payload", async () => {
    const cfg = { elements: [], connections: [] }
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => ({ configuration: JSON.stringify(cfg) }) })))
    const { h } = host()
    expect(await h._fetchSubflowConfiguration("fc-1")).toEqual(cfg)
  })

  it("returns null on a non-ok response", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 404 })))
    const err = vi.spyOn(console, "error").mockImplementation(() => {})
    const { h } = host()
    expect(await h._fetchSubflowConfiguration("fc-1")).toBeNull()
    err.mockRestore()
  })

  it("returns null when the stringified configuration is invalid JSON", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => ({ configuration: "{bad" }) })))
    const err = vi.spyOn(console, "error").mockImplementation(() => {})
    const { h } = host()
    expect(await h._fetchSubflowConfiguration("fc-1")).toBeNull()
    err.mockRestore()
  })
})

describe("ExpansionMixin._expandSubflowInternal", () => {
  afterEach(() => vi.unstubAllGlobals())

  it("returns immediately when the subflow has no flowchartId", async () => {
    const { h } = host()
    await h._expandSubflowInternal({ id: "SF", properties: {} })
    expect(Object.keys(h.expandedSubflows)).toEqual([])
  })

  it("refuses to expand a self-referencing subflow and toasts an error", async () => {
    const { h, canvas } = host({}, { idValue: "fc-self" })
    await h._expandSubflowInternal({ id: "SF", properties: { flowchartId: "fc-self" } })
    expect(canvas.onToast).toHaveBeenCalledWith(expect.stringContaining("self-reference"), "error")
    expect(Object.keys(h.expandedSubflows)).toEqual([])
  })

  it("takes the self-reference toast from the subflowSelfReferenceToast value (P5-6)", async () => {
    const { h, canvas } = host({}, { idValue: "fc-self", subflowSelfReferenceToastValue: "无法展开：子流程引用了当前流程图（自引用）。" })
    await h._expandSubflowInternal({ id: "SF", properties: { flowchartId: "fc-self" } })
    expect(canvas.onToast).toHaveBeenCalledWith("无法展开：子流程引用了当前流程图（自引用）。", "error")
  })

  it("expands: fetches config, inlines elements, records expanded state and dispatches change", async () => {
    const cfg = {
      elements: [
        { id: "s", type: "start", x: 0, y: 0 },
        { id: "e", type: "end", x: 0, y: 100 },
      ],
      connections: [{ id: "ce", from: "s", to: "e" }],
    }
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => ({ configuration: cfg }) })))

    const subflow = { id: "SF", x: 50, y: 50, width: 100, height: 45, label: "Sub", properties: { flowchartId: "fc-child" } }
    const { h, canvas, controller } = host(
      { elements: [subflow], connections: [] },
      { idValue: "fc-parent" },
    )
    canvas.renderElement(subflow)

    await h._expandSubflowInternal(subflow, { checkInvokeActivity: true, dispatchEvents: true })

    // original subflow removed, inlined start/end present
    expect(canvas.elements.map(e => e.id).sort()).toEqual(["SF_sub_e", "SF_sub_s"])
    expect(h.expandedSubflows.SF).toMatchObject({ startElementId: "SF_sub_s", endElementId: "SF_sub_e" })
    expect(canvas.previewMode).toBe(true)
    expect(controller._collapsedPreviewConfiguration).toBeTruthy()
    expect(controller.hasUnsavedChanges).toBe(false)
    expect(controller._dispatchConfigurationChange).not.toHaveBeenCalled()
    // fold icon attached to the start element's group
    expect(canvas.elementLayer.querySelector('[data-element-id="SF_sub_s"] .fold-icon')).toBeTruthy()
  })

  it("enters preview only on the first expansion", async () => {
    const cfg = { elements: [{ id: "s", type: "start", x: 0, y: 0 }], connections: [] }
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => ({ configuration: cfg }) })))
    const first = { id: "SF1", x: 0, y: 0, width: 100, height: 45, properties: { flowchartId: "fc-a" } }
    const second = { id: "SF2", x: 200, y: 0, width: 100, height: 45, properties: { flowchartId: "fc-b" } }
    const { h, canvas, controller } = host(
      { elements: [first, second], connections: [] },
      { idValue: "fc-parent" },
    )
    const enter = vi.spyOn(controller, "_enterPreviewMode")
    canvas.renderElement(first)
    canvas.renderElement(second)

    await h._expandSubflowInternal(first)
    await h._expandSubflowInternal(second)

    expect(enter).toHaveBeenCalledTimes(1)
    expect(canvas.previewMode).toBe(true)
  })

  it("bails out quietly when the fetched configuration is empty", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => ({ configuration: { elements: [] } }) })))
    const subflow = { id: "SF", properties: { flowchartId: "fc-child" } }
    const { h } = host({ elements: [subflow] })
    await h._expandSubflowInternal(subflow)
    expect(h.expandedSubflows.SF).toBeUndefined()
  })

  it("falls back to the first/last element when the subflow has no explicit start/end", async () => {
    const cfg = {
      elements: [
        { id: "p1", type: "process", x: 0, y: 0 },
        { id: "p2", type: "process", x: 0, y: 100 },
      ],
      connections: [],
    }
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => ({ configuration: cfg }) })))
    const subflow = { id: "SF", x: 0, y: 0, width: 100, height: 45, properties: { flowchartId: "fc-child" } }
    const { h, canvas } = host({ elements: [subflow], connections: [] }, { idValue: "fc-parent" })
    canvas.renderElement(subflow)

    await h._expandSubflowInternal(subflow)

    // start falls back to the first inlined element, end to the last
    expect(h.expandedSubflows.SF).toMatchObject({ startElementId: "SF_sub_p1", endElementId: "SF_sub_p2" })
  })

  it("logs and swallows an error raised mid-expansion (fetch rejection)", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => { throw new Error("network down") }))
    const err = vi.spyOn(console, "error").mockImplementation(() => {})
    const subflow = { id: "SF", properties: { flowchartId: "fc-child" } }
    const { h } = host({ elements: [subflow] }, { idValue: "fc-parent" })

    await h._expandSubflowInternal(subflow)

    expect(err).toHaveBeenCalledWith("SubflowManager: Failed to expand subflow", expect.any(Error))
    expect(h.expandedSubflows.SF).toBeUndefined()
    err.mockRestore()
  })
})
