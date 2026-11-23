import { describe, it, expect, vi, beforeEach } from "vitest"
import { SerializationMixin } from "flowchart/canvas/serialization"

// SerializationMixin manipulates element/connection DATA and light SVG-layer DOM.
// getConfiguration / loadConfiguration / the pin caches / structure events are
// pure-ish; geometry helpers (_getSVGPoint via clientToSVG) are Tier C and not
// asserted here.

function makeHost(over = {}) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  const elementLayer = document.createElementNS("http://www.w3.org/2000/svg", "g")
  const connectionLayer = document.createElementNS("http://www.w3.org/2000/svg", "g")
  svg.appendChild(elementLayer)
  svg.appendChild(connectionLayer)
  document.body.appendChild(svg)

  const host = Object.assign(Object.create(SerializationMixin), {
    svg,
    elementLayer,
    connectionLayer,
    elements: [],
    connections: [],
    selectedElements: [],
    selectedConnectionId: null,
    stepPins: {},
    elementPins: {},
    connectionRouting: "orthogonal",
    _loadedMetadata: {},
    flowchartType: "custom",
    zoomPanManager: { resetZoom: vi.fn(), _updateViewBox: vi.fn(), clientToSVG: vi.fn(() => ({ x: 0, y: 0 })), panX: 0, panY: 0, viewWidth: 800, viewHeight: 600 },
    renderElement: vi.fn((el) => {
      const g = document.createElementNS("http://www.w3.org/2000/svg", "g")
      g.setAttribute("data-element-id", el.id)
      elementLayer.appendChild(g)
    }),
    updateConnections: vi.fn(),
    alignAllElements: vi.fn(),
    _hideConnectionHandles: vi.fn(),
    _hideConnectionEndpointHandles: vi.fn(),
    onToast: vi.fn(),
    ...over,
  })
  return host
}

describe("SerializationMixin.getConfiguration", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = makeHost() })

  it("serializes elements + connections + metadata", () => {
    host.elements = [{ id: "a", type: "start", x: 1, y: 2, properties: { foo: 1 } }]
    host.connections = [{ id: "c", from: "a", to: "a" }]
    const cfg = host.getConfiguration()
    expect(cfg.elements[0].id).toBe("a")
    expect(cfg.metadata.connectionRouting).toBe("orthogonal")
  })

  it("keeps the loaded created_at and is deep-equal across two calls with no edits", () => {
    host._loadedMetadata = { created_at: "2026-01-02T03:04:05.000Z", canvasWidth: 800 }
    host.elements = [{ id: "a", type: "start", x: 1, y: 2, properties: { foo: 1 } }]
    host.connections = [{ id: "c", from: "a", to: "a", properties: { description: "" } }]
    const first = host.getConfiguration()
    const second = host.getConfiguration()
    expect(first.metadata.created_at).toBe("2026-01-02T03:04:05.000Z")
    expect(second).toEqual(first)
  })

  it("drops runtime-expanded subflow elements and strips runtime-only props", () => {
    host.elements = [
      { id: "keep", type: "process", properties: { real: true, _originalSubflowData: {} } },
      { id: "drop", type: "process", properties: { _expandedFromSubflow: "sf1" } },
    ]
    const cfg = host.getConfiguration()
    expect(cfg.elements.map(e => e.id)).toEqual(["keep"])
    expect("_originalSubflowData" in cfg.elements[0].properties).toBe(false)
    expect(cfg.elements[0].properties.real).toBe(true)
  })

  it("filters connections to those between surviving elements and defaults properties", () => {
    host.elements = [{ id: "a", properties: {} }, { id: "b", properties: {} }]
    host.connections = [
      { id: "ok", from: "a", to: "b" },
      { id: "dangling", from: "a", to: "gone" },
    ]
    const cfg = host.getConfiguration()
    expect(cfg.connections.map(c => c.id)).toEqual(["ok"])
    expect(cfg.connections[0].properties).toEqual({ description: "" })
  })

  it("passes through preserved _loadedMetadata keys", () => {
    host._loadedMetadata = { canvasWidth: 999 }
    expect(host.getConfiguration().metadata.canvasWidth).toBe(999)
  })

  it("defaults properties to {} when an element has none", () => {
    host.elements = [{ id: "a" }]
    expect(host.getConfiguration().elements[0].properties).toEqual({})
  })

  it("preserves an existing connection's notes", () => {
    host.elements = [{ id: "a", properties: {} }, { id: "b", properties: {} }]
    host.connections = [{ id: "c", from: "a", to: "b", properties: { description: "keep" } }]
    const cfg = host.getConfiguration()
    expect(cfg.connections[0].properties).toEqual({ description: "keep" })
  })
})

describe("SerializationMixin.loadConfiguration", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = makeHost() })

  it("clears, then creates elements (rounded coords, merged defaults) and renders them", () => {
    host.loadConfiguration({
      elements: [{ id: "e1", type: "process", x: 10.6, y: 20.4, properties: { a: 1 } }],
      connections: [],
    })
    expect(host.elements).toHaveLength(1)
    expect(host.elements[0].x).toBe(11)
    expect(host.elements[0].y).toBe(20)
    // default { description: "" } merged under provided props
    expect(host.elements[0].properties).toMatchObject({ description: "", a: 1 })
    expect(host.renderElement).toHaveBeenCalledOnce()
  })

  it("parses a JSON string form", () => {
    host.loadConfiguration(JSON.stringify({ elements: [{ id: "x", type: "end", x: 0, y: 0 }] }))
    expect(host.elements[0].id).toBe("x")
  })

  it("migrates legacy 'bezier' routing to 'orthogonal'", () => {
    host.loadConfiguration({ elements: [], metadata: { connectionRouting: "bezier" } })
    expect(host.connectionRouting).toBe("orthogonal")
  })

  it("preserves a non-bezier saved routing mode", () => {
    host.loadConfiguration({ elements: [], metadata: { connectionRouting: "straight" } })
    expect(host.connectionRouting).toBe("straight")
  })

  it("backfills stable ids onto steps that lack them", () => {
    host.loadConfiguration({
      elements: [
        { id: "p", type: "process", x: 0, y: 0, properties: { steps: [{ action: "validate" }] } },
        { id: "p2", type: "process", x: 0, y: 100, properties: { steps: [{ id: "keep", action: "save" }] } },
      ],
    })
    expect(host.elements[0].properties.steps[0].id).toMatch(/^step_/)
    expect(host.elements[1].properties.steps[0].id).toBe("keep")
  })

  it("coerces a Subflow flowchartId to a number on load and save", () => {
    host.loadConfiguration({
      elements: [{ id: "sf", type: "subflow", x: 0, y: 0, properties: { flowchartId: "42" } }],
    })
    expect(host.elements[0].properties.flowchartId).toBe(42)
    expect(host.getConfiguration().elements[0].properties.flowchartId).toBe(42)
  })

  it("keeps an already-numeric Subflow flowchartId", () => {
    host.loadConfiguration({
      elements: [{ id: "sf", type: "subflow", x: 0, y: 0, properties: { flowchartId: 11 } }],
    })
    expect(host.elements[0].properties.flowchartId).toBe(11)
  })

  it("does not coerce a non-numeric Subflow flowchartId leftover", () => {
    host.loadConfiguration({
      elements: [{ id: "sf", type: "subflow", x: 0, y: 0, properties: { flowchartId: "abc" } }],
    })
    expect(host.elements[0].properties.flowchartId).toBe("abc")
  })

  it("fills a null connection description", () => {
    host.elements = [{ id: "a", properties: {} }, { id: "b", properties: {} }]
    host.connections = [{ id: "c", from: "a", to: "b", properties: { description: null } }]
    expect(host.getConfiguration().connections[0].properties).toEqual({ description: "" })
  })

  it("leaves a blank Subflow flowchartId alone and does not coerce other types", () => {
    host.loadConfiguration({
      elements: [
        { id: "sf", type: "subflow", x: 0, y: 0, properties: { flowchartId: "" } },
        { id: "p", type: "process", x: 0, y: 80, properties: { flowchartId: "9" } },
      ],
    })
    expect(host.elements[0].properties.flowchartId).toBe("")
    expect(host.elements[1].properties.flowchartId).toBe("9")
  })

  it("maps connections with default properties and aligns connected elements", () => {
    host.loadConfiguration({
      elements: [{ id: "a", type: "start", x: 0, y: 0 }, { id: "b", type: "end", x: 37, y: 100 }],
      connections: [{ id: "c", from: "a", to: "b" }],
    })
    expect(host.connections[0].properties).toEqual({ description: "" })
    expect(host.alignAllElements).toHaveBeenCalledOnce()
  })

  it("surfaces a toast + logs on malformed JSON instead of silently emptying", () => {
    const err = vi.spyOn(console, "error").mockImplementation(() => {})
    host.labels = { loadConfigFailedToast: "Failed to load flowchart configuration. Please reload the page." }
    host.loadConfiguration("{ not json")
    expect(err).toHaveBeenCalled()
    expect(host.onToast).toHaveBeenCalledWith("Failed to load flowchart configuration. Please reload the page.", "error")
    err.mockRestore()
  })

  // i18n seam: serialization.js reads the translated string from this.labels
  // (threaded by flowchart_canvas_controller.js, whose Stimulus value carries
  // the English default).
  it("uses this.labels.loadConfigFailedToast when present", () => {
    const err = vi.spyOn(console, "error").mockImplementation(() => {})
    host.labels = { loadConfigFailedToast: "加载失败，请刷新页面重试。" }
    host.loadConfiguration("{ not json")
    expect(host.onToast).toHaveBeenCalledWith("加载失败，请刷新页面重试。", "error")
    err.mockRestore()
  })

  it("records loaded metadata for round-tripping", () => {
    host.loadConfiguration({ elements: [], metadata: { custom: "keep-me" } })
    expect(host._loadedMetadata).toEqual({ custom: "keep-me" })
  })
})

describe("SerializationMixin — pin caches & iteration", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = makeHost() })

  it("set/get step pins, with an empty default", () => {
    expect(host.getStepPins("nope")).toEqual({ inputs: [], outputs: [] })
    host.setStepPins("s1", { inputs: [{ pin: "i" }], outputs: [] })
    expect(host.getStepPins("s1").inputs).toEqual([{ pin: "i" }])
  })

  it("set/get element pins, with an empty default", () => {
    expect(host.getElementPins("nope")).toEqual({ inputs: [], outputs: [] })
    host.setElementPins("e1", { inputs: [], outputs: [{ pin: "o" }] })
    expect(host.getElementPins("e1").outputs).toEqual([{ pin: "o" }])
  })

  it("iterateElements visits each element", () => {
    host.elements = [{ id: "a" }, { id: "b" }]
    const seen = []
    host.iterateElements(e => seen.push(e.id))
    expect(seen).toEqual(["a", "b"])
  })

  it("iterateStepActions visits (step, element) pairs across process elements", () => {
    host.elements = [
      { id: "a", properties: { steps: [{ id: "s1" }] } },
      { id: "a2", properties: { steps: [{ id: "s2" }] } },
      { id: "b", properties: {} },
    ]
    const pairs = []
    host.iterateStepActions((s, el) => pairs.push([s.id, el.id]))
    expect(pairs).toEqual([["s1", "a"], ["s2", "a2"]])
  })

  it("findStepById locates a step and its parent element (or null)", () => {
    host.elements = [{ id: "a", properties: { steps: [{ id: "s1" }] } }]
    expect(host.findStepById("s1")).toEqual({ step: { id: "s1" }, element: host.elements[0] })
    expect(host.findStepById("nope")).toBeNull()
    expect(host.findStepById(null)).toBeNull()
  })

  it("findStepById tolerates elements with no properties/steps", () => {
    host.elements = [{ id: "bare" }]
    expect(host.findStepById("s1")).toBeNull()
  })
})

describe("SerializationMixin — misc behaviors", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = makeHost() })

  it("emitStructureChanged dispatches a bubbling CustomEvent on the svg", () => {
    const handler = vi.fn()
    host.svg.addEventListener("flowchartStructureChanged", handler)
    host.emitStructureChanged({ elementId: "x" })
    expect(handler).toHaveBeenCalledOnce()
    expect(handler.mock.calls[0][0].detail).toEqual({ elementId: "x" })
  })

  it("emitStructureChanged is a no-op when there is no svg yet", () => {
    host.svg = null
    expect(() => host.emitStructureChanged()).not.toThrow()
  })

  it("_getSVGPoint delegates to zoomPanManager.clientToSVG with the event's client coords", () => {
    host.zoomPanManager.clientToSVG = vi.fn(() => ({ x: 12, y: 34 }))
    const point = host._getSVGPoint({ clientX: 5, clientY: 6 })
    expect(host.zoomPanManager.clientToSVG).toHaveBeenCalledWith(5, 6)
    expect(point).toEqual({ x: 12, y: 34 })
  })

  it("_updateConnectionsVisually delegates to updateConnections", () => {
    host._updateConnectionsVisually()
    expect(host.updateConnections).toHaveBeenCalledOnce()
  })

  it("autoLayout delegates to layoutManager.autoLayout", () => {
    host.layoutManager = { autoLayout: vi.fn() }
    host.autoLayout()
    expect(host.layoutManager.autoLayout).toHaveBeenCalledOnce()
  })

  it("cycleConnectionRouting toggles straight<->orthogonal and updates connections", () => {
    host.connectionRouting = "straight"
    host.cycleConnectionRouting()
    expect(host.connectionRouting).toBe("orthogonal")
    host.cycleConnectionRouting()
    expect(host.connectionRouting).toBe("straight")
    expect(host.updateConnections).toHaveBeenCalledTimes(2)
  })

  it("_findElementAtPoint returns the top-most element under a point (data hit-test)", () => {
    host.elements = [
      { id: "a", x: 100, y: 100, width: 100, height: 45 },
      { id: "b", x: 100, y: 100, width: 100, height: 45 }, // overlaps, later => on top
    ]
    expect(host._findElementAtPoint(100, 100).id).toBe("b")
    expect(host._findElementAtPoint(1000, 1000)).toBeNull()
  })

  it("clear empties data, wipes layers, and resets zoom", () => {
    host.elements = [{ id: "a" }]
    host.connections = [{ id: "c" }]
    host.selectedElements = [{ id: "a" }]
    host.elementLayer.appendChild(document.createElementNS("http://www.w3.org/2000/svg", "g"))
    host.clear()
    expect(host.elements).toEqual([])
    expect(host.connections).toEqual([])
    expect(host.selectedElements).toEqual([])
    expect(host.elementLayer.childNodes).toHaveLength(0)
    expect(host.zoomPanManager.resetZoom).toHaveBeenCalled()
  })

  it("destroy removes in-progress interaction nodes and detaches key handlers", () => {
    const line = document.createElementNS("http://www.w3.org/2000/svg", "line")
    const dragLine = document.createElementNS("http://www.w3.org/2000/svg", "line")
    const overlay = document.createElementNS("http://www.w3.org/2000/svg", "g")
    host.svg.append(line, dragLine, overlay)
    host.connectionLine = line
    host.connectionDragLine = dragLine
    host._traceOverlayLayer = overlay
    host._keyDownHandler = () => {}
    host._keyUpHandler = () => {}
    host.destroy()
    expect(host.connectionLine).toBeNull()
    expect(host.connectionDragLine).toBeNull()
    expect(host._traceOverlayLayer).toBeNull()
    expect(line.parentNode).toBeNull()
    expect(dragLine.parentNode).toBeNull()
    expect(overlay.parentNode).toBeNull()
  })

  it("destroy tolerates absent in-progress interaction nodes", () => {
    expect(() => host.destroy()).not.toThrow()
  })

  it("render() is a no-op", () => {
    expect(host.render()).toBeUndefined()
  })

  it("_scrollToElement pans when the element is out of view", () => {
    const zpm = host.zoomPanManager
    zpm.panX = 0; zpm.panY = 0; zpm.viewWidth = 100; zpm.viewHeight = 100
    host._scrollToElement({ x: 500, y: 500, width: 100, height: 45 })
    expect(zpm._updateViewBox).toHaveBeenCalled()
    expect(zpm.panX).toBeGreaterThan(0)
    expect(zpm.panY).toBeGreaterThan(0)
  })
})

describe("SerializationMixin.replaceGraph", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = makeHost() })

  it("clears and re-renders elements and connections without resetZoom, align, or metadata writes", () => {
    host._loadedMetadata = { created_at: "keep-me" }
    host.elements = [{ id: "old" }]
    host.connections = [{ id: "old-c" }]
    host.selectedElements = [{ id: "old" }]
    host.elementLayer.appendChild(document.createElementNS("http://www.w3.org/2000/svg", "g"))
    const order = []
    host.onBeforeChange = () => order.push("before")
    host.onchange = () => order.push("after")
    const incoming = [{ id: "d1", type: "decision" }, { id: "p1", type: "process" }]
    const incomingConns = [{ id: "c1", from: "d1", to: "p1" }]
    host.replaceGraph(incoming, incomingConns)
    expect(order).toEqual(["before", "after"])
    expect(host.elements).toEqual(incoming)
    expect(host.connections).toEqual(incomingConns)
    expect(host.elements).not.toBe(incoming)
    expect(host.renderElement).toHaveBeenCalledTimes(2)
    expect(host.updateConnections).toHaveBeenCalledTimes(1)
    expect(host.zoomPanManager.resetZoom).not.toHaveBeenCalled()
    expect(host._loadedMetadata).toEqual({ created_at: "keep-me" })
    expect(host.selectedElements).toEqual([])
    expect(host._hideConnectionHandles).toHaveBeenCalled()
    expect(host._hideConnectionEndpointHandles).toHaveBeenCalled()
  })

  it("defaults missing arrays to empty and still fires the change pair", () => {
    host.onBeforeChange = vi.fn()
    host.onchange = vi.fn()
    host.replaceGraph()
    expect(host.elements).toEqual([])
    expect(host.connections).toEqual([])
    expect(host.onBeforeChange).toHaveBeenCalledTimes(1)
    expect(host.onchange).toHaveBeenCalledTimes(1)
    expect(host.renderElement).not.toHaveBeenCalled()
  })

  it("removes leftover resize handles after replaceGraph", () => {
    const handleLayer = document.createElementNS("http://www.w3.org/2000/svg", "g")
    const handle = document.createElementNS("http://www.w3.org/2000/svg", "rect")
    handle.setAttribute("data-resize-handle", "bottom-right")
    handleLayer.appendChild(handle)
    host.svg.appendChild(handleLayer)
    host.handleLayer = handleLayer
    host.hideResizeHandles = function () {
      this.handleLayer.querySelectorAll("[data-resize-handle]").forEach((node) => node.remove())
    }
    expect(handleLayer.querySelectorAll("[data-resize-handle]")).toHaveLength(1)
    host.replaceGraph([], [])
    expect(handleLayer.querySelectorAll("[data-resize-handle]")).toHaveLength(0)
  })
})

describe("SerializationMixin.restoreGraph", () => {
  let host
  beforeEach(() => {
    document.body.innerHTML = ""
    host = makeHost({
      _setElementSelected: vi.fn(),
      showConnectionHandles: vi.fn(),
      showResizeHandles: vi.fn(),
      hideResizeHandles: vi.fn(),
      onSelectionChanged: vi.fn(),
      alignAllElements: vi.fn(),
    })
  })

  const snapshot = () => ({
    elements: [
      { id: "b", type: "process", x: 10, y: 20, width: 100, height: 45, label: "B", properties: {} },
      { id: "a", type: "start", x: 10, y: 120, width: 100, height: 45, label: "A", properties: {} },
    ],
    connections: [{ id: "c1", from: "b", to: "a", fromPort: null, label: null, properties: {} }],
  })

  it("swaps the graph silently: no hooks, no zoom reset, no realign, metadata and routing kept", () => {
    host._loadedMetadata = { created_at: "keep-me" }
    host.connectionRouting = "straight"
    host.elements = [{ id: "old" }]
    host.connections = [{ id: "old-c" }]
    host.elementLayer.appendChild(document.createElementNS("http://www.w3.org/2000/svg", "g"))
    host.connectionLayer.appendChild(document.createElementNS("http://www.w3.org/2000/svg", "g"))
    host.onBeforeChange = vi.fn()
    host.onchange = vi.fn()
    const data = snapshot()

    host.restoreGraph(data)

    expect(host.elements).toEqual(data.elements)
    expect(host.elements).not.toBe(data.elements)
    expect(host.elements.map(e => e.id)).toEqual(["b", "a"])
    expect(host.elements[0].properties).toEqual({}) // no defaults merged
    expect(host.connections).toEqual(data.connections)
    expect(host.connections[0].properties).toEqual({}) // no description backfill
    expect(host.connectionLayer.childNodes).toHaveLength(0)
    expect(host.elementLayer.querySelectorAll("[data-element-id]")).toHaveLength(2)
    expect(host.elementLayer.childNodes).toHaveLength(2)
    expect(host.updateConnections).toHaveBeenCalledTimes(1)
    expect(host.alignAllElements).not.toHaveBeenCalled()
    expect(host.zoomPanManager.resetZoom).not.toHaveBeenCalled()
    expect(host.onBeforeChange).not.toHaveBeenCalled()
    expect(host.onchange).not.toHaveBeenCalled()
    expect(host._loadedMetadata).toEqual({ created_at: "keep-me" })
    expect(host.connectionRouting).toBe("straight")
  })

  it("keeps a single surviving selection on the new element objects with handles", () => {
    host.selectedElements = [{ id: "a" }]
    host.restoreGraph(snapshot())
    expect(host.selectedElements).toEqual([host.elements[1]])
    expect(host.selectedElements[0]).toBe(host.elements[1])
    expect(host._setElementSelected).toHaveBeenCalledWith(host.elements[1], true)
    expect(host.showConnectionHandles).toHaveBeenCalledWith(host.selectedElements)
    expect(host.showResizeHandles).toHaveBeenCalledWith(host.elements[1])
    expect(host.hideResizeHandles).not.toHaveBeenCalled()
    expect(host.onSelectionChanged).not.toHaveBeenCalled()
  })

  it("drops selected elements that no longer exist and notifies the selection change", () => {
    host.selectedElements = [{ id: "a" }, { id: "b" }, { id: "gone" }]
    host.restoreGraph(snapshot())
    expect(host.selectedElements.map(e => e.id)).toEqual(["b", "a"])
    expect(host.showConnectionHandles).toHaveBeenCalledWith(host.selectedElements)
    expect(host.showResizeHandles).not.toHaveBeenCalled()
    expect(host.hideResizeHandles).toHaveBeenCalled()
    expect(host.onSelectionChanged).toHaveBeenCalledTimes(1)
  })

  it("hides element handles when nothing stays selected", () => {
    host.selectedElements = [{ id: "gone" }]
    host.restoreGraph(snapshot())
    expect(host.selectedElements).toEqual([])
    expect(host._hideConnectionHandles).toHaveBeenCalled()
    expect(host.showConnectionHandles).not.toHaveBeenCalled()
    expect(host.hideResizeHandles).toHaveBeenCalled()
    expect(host.onSelectionChanged).toHaveBeenCalledTimes(1)
  })

  it("refreshes connection endpoint handles before re-rendering connections, keeping the connection selection", () => {
    const order = []
    host.selectedConnectionId = "c1"
    host._hideConnectionEndpointHandles = vi.fn(() => order.push("hideEndpoints"))
    host.updateConnections = vi.fn(() => order.push("updateConnections"))
    host.restoreGraph(snapshot())
    expect(order).toEqual(["hideEndpoints", "updateConnections"])
    expect(host.selectedConnectionId).toBe("c1")
  })

  it("drops a selected connection that is no longer in the snapshot", () => {
    host.selectedConnectionId = "gone"
    host.restoreGraph(snapshot())
    expect(host.selectedConnectionId).toBeNull()
  })

  it("defaults a missing graph to empty and tolerates absent optional resize/selection hooks", () => {
    delete host.showResizeHandles
    delete host.hideResizeHandles
    delete host.onSelectionChanged
    host.selectedElements = [{ id: "gone" }]
    expect(() => host.restoreGraph()).not.toThrow()
    expect(host.elements).toEqual([])
    expect(host.connections).toEqual([])

    host.restoreGraph({ elements: [{ id: "x", type: "process" }] })
    host.selectedElements = [host.elements[0]]
    expect(() => host.restoreGraph({ elements: [{ id: "x", type: "process" }] })).not.toThrow()
    expect(host.connections).toEqual([])
  })
})

describe("P5-4 SerializationMixin — canMutate guard", () => {
  it("cycleConnectionRouting is a no-op when canMutate is false", () => {
    const host = makeHost({ canMutate: () => false, connectionRouting: "straight" })
    host.cycleConnectionRouting()
    expect(host.connectionRouting).toBe("straight")
    expect(host.updateConnections).not.toHaveBeenCalled()
  })

  it("restoreGraph hides handles when canMutate is false even if an element stays selected", () => {
    const host = makeHost({
      canMutate: () => false,
      selectedElements: [{ id: "a" }],
      _setElementSelected: vi.fn(),
      showConnectionHandles: vi.fn(),
      showResizeHandles: vi.fn(),
      _hideConnectionHandles: vi.fn(),
      hideResizeHandles: vi.fn(),
    })
    host.restoreGraph({ elements: [{ id: "a", type: "process" }], connections: [] })
    expect(host.showConnectionHandles).not.toHaveBeenCalled()
    expect(host.showResizeHandles).not.toHaveBeenCalled()
    expect(host._hideConnectionHandles).toHaveBeenCalled()
    expect(host.hideResizeHandles).toHaveBeenCalled()
  })
})
