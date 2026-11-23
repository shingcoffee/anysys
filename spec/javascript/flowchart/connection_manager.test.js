import { describe, it, expect, vi } from "vitest"
import { ConnectionManagerMixin } from "flowchart/connection_manager"

// The ConnectionManagerMixin is applied to FlowchartCanvas.prototype. Its
// rendering/handle methods touch SVG layers (Tier C — Playwright), but the
// connection-model logic (dedup, port vs cardinal detection, decision-branch
// derivation, property merge) is pure data over `connections`/`elements`.
// We build a fake canvas that assigns the mixin and stubs only the DOM-facing
// collaborators so the model logic runs unmocked.
//
// NOTE: SVG rendering (_renderConnection, _setConnectionStyle, endpoint/handle
// creation, startInlineLabelEdit) requires real layout + getTotalLength/
// getPointAtLength and is out of scope for happy-dom — covered by Playwright.

const makeCanvas = (over = {}) =>
  Object.assign({}, ConnectionManagerMixin, {
    connections: [],
    elements: [],
    selectedConnectionId: null,
    _renderConnection: vi.fn(),
    _hideConnectionEndpointHandles: vi.fn(),
    updateConnections: vi.fn(),
    updateElementPosition: vi.fn(),
    emitStructureChanged: vi.fn(),
    onBeforeChange: vi.fn(),
    onchange: vi.fn(),
    ...over,
  })

const proc = (id, x = 0, y = 0) => ({ id, type: "process", x, y, width: 80, height: 40, properties: {} })

describe("createConnection", () => {
  it("refuses to connect an element to itself", () => {
    const c = makeCanvas()
    expect(c.createConnection(proc("a"), proc("a"), "bottom", "top")).toBeNull()
  })

  it("refuses a duplicate edge in the same direction", () => {
    const c = makeCanvas({ connections: [{ id: "x", from: "a", to: "b" }] })
    expect(c.createConnection(proc("a"), proc("b"), "bottom", "top")).toBeNull()
  })

  it("allows A→B and B→A as distinct edges", () => {
    const c = makeCanvas({ connections: [{ id: "x", from: "a", to: "b" }] })
    const reverse = c.createConnection(proc("b"), proc("a"), "bottom", "top")
    expect(reverse).toMatchObject({ from: "b", to: "a" })
    expect(c.connections).toHaveLength(2)
  })

  it("_rejectsDirectedEdge is the shared Start/End gate", () => {
    const c = makeCanvas({ onToast: vi.fn() })
    const start = { id: "s", type: "start", x: 0, y: 0, width: 80, height: 40, properties: {} }
    const end = { id: "e", type: "end", x: 0, y: 0, width: 80, height: 40, properties: {} }
    expect(c._rejectsDirectedEdge(proc("a"), start)).toBe(true)
    expect(c._rejectsDirectedEdge(end, proc("a"))).toBe(true)
    expect(c._rejectsDirectedEdge(proc("a"), proc("b"))).toBe(false)
  })

  it("rejects a connection into Start and toasts the label", () => {
    const c = makeCanvas({ onToast: vi.fn(), labels: { connectionIntoStartRejected: "A Start element cannot have incoming connections" } })
    const start = { id: "s", type: "start", x: 0, y: 0, width: 80, height: 40, properties: {} }
    expect(c.createConnection(proc("a"), start, "bottom", "top")).toBeNull()
    expect(c.onToast).toHaveBeenCalledWith("A Start element cannot have incoming connections")
    expect(c.connections).toHaveLength(0)
  })

  it("rejects a connection out of End and toasts the label", () => {
    const c = makeCanvas({ onToast: vi.fn(), labels: { connectionOutOfEndRejected: "An End element cannot have outgoing connections" } })
    const end = { id: "e", type: "end", x: 0, y: 0, width: 80, height: 40, properties: {} }
    expect(c.createConnection(end, proc("a"), "bottom", "top")).toBeNull()
    expect(c.onToast).toHaveBeenCalledWith("An End element cannot have outgoing connections")
    expect(c.connections).toHaveLength(0)
  })

  it("skips the Start/End rejection toast when the threaded label is missing", () => {
    const c = makeCanvas({ onToast: vi.fn() })
    const start = { id: "s", type: "start", x: 0, y: 0, width: 80, height: 40, properties: {} }
    const end = { id: "e", type: "end", x: 0, y: 0, width: 80, height: 40, properties: {} }
    expect(c.createConnection(proc("a"), start, "bottom", "top")).toBeNull()
    expect(c.createConnection(end, proc("a"), "bottom", "top")).toBeNull()
    expect(c.onToast).not.toHaveBeenCalled()
    expect(c.connections).toHaveLength(0)
  })

  it("skips the Start/End rejection toast when the threaded label is blank", () => {
    const c = makeCanvas({
      onToast: vi.fn(),
      labels: { connectionIntoStartRejected: "", connectionOutOfEndRejected: "" },
    })
    const start = { id: "s", type: "start", x: 0, y: 0, width: 80, height: 40, properties: {} }
    const end = { id: "e", type: "end", x: 0, y: 0, width: 80, height: 40, properties: {} }
    expect(c._rejectsDirectedEdge(proc("a"), start)).toBe(true)
    expect(c._rejectsDirectedEdge(end, proc("a"))).toBe(true)
    expect(c.onToast).not.toHaveBeenCalled()
  })

  it("rejects a Start/End pair without toasting when onToast is absent", () => {
    const c = makeCanvas({
      labels: {
        connectionIntoStartRejected: "A Start element cannot have incoming connections",
        connectionOutOfEndRejected: "An End element cannot have outgoing connections",
      },
    })
    const start = { id: "s", type: "start", x: 0, y: 0, width: 80, height: 40, properties: {} }
    const end = { id: "e", type: "end", x: 0, y: 0, width: 80, height: 40, properties: {} }
    expect(c._rejectsDirectedEdge(proc("a"), start)).toBe(true)
    expect(c._rejectsDirectedEdge(end, proc("a"))).toBe(true)
  })

  it("stores an explicit matchValue from options", () => {
    const c = makeCanvas()
    const conn = c.createConnection(proc("a"), proc("b"), "bottom", "top", { matchValue: "true", label: "true" })
    expect(conn.matchValue).toBe("true")
    expect(conn.label).toBe("true")
  })

  it("stores cardinal positions and leaves ports null", () => {
    const c = makeCanvas()
    const conn = c.createConnection(proc("a"), proc("b"), "right", "left")
    expect(conn).toMatchObject({
      from: "a", to: "b",
      fromPosition: "right", toPosition: "left",
      fromPort: null, toPort: null,
    })
    expect(c.connections).toContain(conn)
    expect(c._renderConnection).toHaveBeenCalledWith(conn)
  })

  it("detects port_ handles and stores them as ports (position null)", () => {
    const c = makeCanvas()
    const conn = c.createConnection(proc("a"), proc("b"), "port_2", "top")
    expect(conn.fromPort).toBe("port_2")
    expect(conn.fromPosition).toBeNull()
    expect(conn.toPosition).toBe("top")
  })

  it("defaults missing positions to bottom/top", () => {
    const c = makeCanvas()
    const conn = c.createConnection(proc("a"), proc("b"), null, null)
    expect(conn.fromPosition).toBe("bottom")
    expect(conn.toPosition).toBe("top")
  })

  it("carries label and defaults properties", () => {
    const c = makeCanvas()
    const conn = c.createConnection(proc("a"), proc("b"), "bottom", "top", { label: "Go" })
    expect(conn.label).toBe("Go")
    expect(conn.properties).toEqual({ description: "" })
  })

  it("auto-derives decision branches unless skipBranchSync is set", () => {
    const c = makeCanvas({ _syncDecisionBranches: vi.fn() })
    const dec = { id: "d", type: "decision", x: 0, y: 0, width: 80, height: 60, properties: {} }
    c.createConnection(dec, proc("b"), "bottom", "top")
    expect(c._syncDecisionBranches).toHaveBeenCalledWith(dec, "b")

    c._syncDecisionBranches.mockClear()
    c.createConnection(dec, proc("c"), "bottom", "top", { skipBranchSync: true })
    expect(c._syncDecisionBranches).not.toHaveBeenCalled()
  })

  it("does not add route metadata to an ordinary connection", () => {
    const c = makeCanvas()
    const conn = c.createConnection(proc("a"), proc("b"), "bottom", "top")
    expect(conn).not.toHaveProperty("matchValue")
  })
})

describe("deleteConnection", () => {
  it("removes the connection and refreshes", () => {
    const c = makeCanvas({ connections: [{ id: "x", from: "a", to: "b" }], elements: [proc("a")] })
    c.deleteConnection("x")
    expect(c.connections).toHaveLength(0)
    expect(c._hideConnectionEndpointHandles).toHaveBeenCalled()
    expect(c.updateConnections).toHaveBeenCalled()
  })

  it("is a no-op for an unknown id", () => {
    const c = makeCanvas({ connections: [{ id: "x", from: "a", to: "b" }] })
    c.deleteConnection("nope")
    expect(c.connections).toHaveLength(1)
    expect(c.updateConnections).not.toHaveBeenCalled()
  })

  it("re-syncs branches when the deleted edge left a decision", () => {
    const dec = { id: "d", type: "decision", properties: {} }
    const c = makeCanvas({
      connections: [{ id: "x", from: "d", to: "b" }],
      elements: [dec],
      _syncDecisionBranches: vi.fn(),
    })
    c.deleteConnection("x")
    expect(c._syncDecisionBranches).toHaveBeenCalledWith(dec)
  })
})

describe("updateConnectionProperties", () => {
  it("updates label and merges properties, then re-renders", () => {
    const conn = { id: "x", label: "old", properties: { description: "d", priority: 1 } }
    const c = makeCanvas({ connections: [conn] })
    c.updateConnectionProperties("x", "new", { priority: 5 })
    expect(conn.label).toBe("new")
    expect(conn.properties).toEqual({ description: "d", priority: 5 })
    expect(c.onBeforeChange).toHaveBeenCalledOnce()
    expect(c.updateConnections).toHaveBeenCalled()
    expect(c.onchange).toHaveBeenCalledOnce()
  })

  it("keeps the existing label when newLabel is undefined", () => {
    const conn = { id: "x", label: "keep", properties: {} }
    const c = makeCanvas({ connections: [conn] })
    c.updateConnectionProperties("x", undefined, { a: 1 })
    expect(conn.label).toBe("keep")
    expect(conn.properties).toEqual({ a: 1 })
  })

  it("is a no-op for an unknown connection", () => {
    const c = makeCanvas()
    c.updateConnectionProperties("nope", "x")
    expect(c.onBeforeChange).not.toHaveBeenCalled()
    expect(c.updateConnections).not.toHaveBeenCalled()
    expect(c.onchange).not.toHaveBeenCalled()
  })
})

describe("_syncDecisionBranches", () => {
  it("numbers outgoing ports and does not invent match values", () => {
    const dec = { id: "d", type: "decision", x: 0, y: 0, width: 80, height: 60, properties: {} }
    const conns = [
      { id: "c0", from: "d", to: "a" },
      { id: "c1", from: "d", to: "b", matchValue: "kept" },
      { id: "c2", from: "d", to: "c" },
    ]
    const c = makeCanvas({
      connections: conns,
      elements: [dec, proc("a"), proc("b"), proc("c")],
      labels: { branchFallbackNameFormat: "Branch {index}" },
    })
    c._syncDecisionBranches(dec)

    expect(conns.map((cn) => cn.fromPort)).toEqual(["port_0", "port_1", "port_2"])
    expect(conns.map((cn) => cn.label)).toEqual(["Branch 1", "Branch 2", "Branch 3"])
    expect(conns[1].matchValue).toBe("kept")
    expect(conns[0].matchValue).toBeUndefined()
    expect(dec.properties).toEqual({})
    expect(c.emitStructureChanged).toHaveBeenCalledWith({ elementId: "d" })
  })

  it("preserves an existing connection label", () => {
    const dec = { id: "d", type: "decision", x: 0, y: 0, width: 80, height: 60, properties: {} }
    const conns = [{ id: "c0", from: "d", to: "a", label: "Approved" }, { id: "c1", from: "d", to: "b" }]
    const c = makeCanvas({
      connections: conns,
      elements: [dec, proc("a"), proc("b")],
      labels: { branchFallbackNameFormat: "B{index}" },
    })
    c._syncDecisionBranches(dec)
    expect(conns[0].label).toBe("Approved")
    expect(conns[1].label).toBe("B2")
  })

  it("leaves a blank label blank when no translated format is installed", () => {
    const dec = { id: "d", type: "decision", properties: null }
    const conns = [{ id: "c0", from: "d", to: "a" }]
    const c = makeCanvas({ connections: conns, elements: [dec, proc("a")] })
    c._syncDecisionBranches(dec)
    expect(conns[0].label).toBeUndefined()
    expect(dec.properties).toBeNull()
  })

  it("ignores non-decision elements", () => {
    const c = makeCanvas()
    expect(() => c._syncDecisionBranches(proc("a"))).not.toThrow()
    expect(c.emitStructureChanged).not.toHaveBeenCalled()
  })

  it("inserts a new branch drawn from port_k at index k+1 so earlier branches keep their port", () => {
    const dec = { id: "d", type: "decision", x: 0, y: 0, width: 80, height: 60, properties: {} }
    const conns = [
      { id: "c0", from: "d", to: "yes", fromPort: "port_0", label: "Yes" },
      { id: "c1", from: "d", to: "no", fromPort: "port_1", label: "No" },
      { id: "fresh", from: "d", to: "new", fromPort: "port_0" },
    ]
    const c = makeCanvas({
      connections: conns,
      elements: [dec, proc("yes"), proc("no"), proc("new")],
      labels: { branchFallbackNameFormat: "Branch {index}" },
    })
    c._syncDecisionBranches(dec, "new")
    expect(conns.find((cn) => cn.to === "yes")).toMatchObject({ fromPort: "port_0", label: "Yes" })
    expect(conns.find((cn) => cn.to === "new")).toMatchObject({ fromPort: "port_1", label: "Branch 2" })
    expect(conns.find((cn) => cn.to === "no")).toMatchObject({ fromPort: "port_2", label: "No" })
  })
})

// A DOM-backed host for the rendering/handle/selection methods. These touch
// real SVG layers (which happy-dom supports for element creation, classList,
// querySelector and dataset), so we build the layers and stub only the geometry
// collaborators (_getHandlePosition(s), _getPortRotation, _renderConnection).
const svgEl = (tag) => document.createElementNS("http://www.w3.org/2000/svg", tag)

function makeDomCanvas(over = {}) {
  const connectionLayer = svgEl("g")
  const handleLayer = svgEl("g")
  const elementLayer = svgEl("g")
  const svg = svgEl("svg")
  svg.appendChild(connectionLayer)
  svg.appendChild(handleLayer)
  svg.appendChild(elementLayer)
  document.body.appendChild(svg)
  return Object.assign(Object.create(ConnectionManagerMixin), {
    connections: [],
    elements: [],
    selectedConnectionId: null,
    connectionLayer,
    handleLayer,
    elementLayer,
    svg,
    isDraggingConnectionEndpoint: false,
    isDrawingConnection: false,
    _clearSelection: vi.fn(),
    onConnectionSelected: null,
    onBeforeChange: vi.fn(),
    onchange: vi.fn(),
    _renderConnection: vi.fn(),
    _getHandlePosition: vi.fn(() => ({ x: 10, y: 20 })),
    _getHandlePositions: vi.fn(() => ({ top: { x: 1, y: 2 }, port_0: { x: 3, y: 4 } })),
    _getPortRotation: vi.fn(() => 0),
    ...over,
  })
}

// Build a rendered connection <g> with line + arrow children in the connection layer.
function renderGroup(canvas, connectionId) {
  const g = svgEl("g")
  g.setAttribute("data-connection-id", connectionId)
  const line = svgEl("path"); line.setAttribute("class", "connection-line")
  const arrow = svgEl("polygon"); arrow.setAttribute("class", "connection-arrow")
  g.appendChild(line); g.appendChild(arrow)
  canvas.connectionLayer.appendChild(g)
  return { g, line, arrow }
}

describe("removeConnection", () => {
  it("removes the connection and its rendered group + handles", () => {
    const c = makeDomCanvas({ connections: [{ id: "x", from: "a", to: "b" }] })
    renderGroup(c, "x")
    const h = svgEl("g"); h.setAttribute("data-connection-id", "x"); c.handleLayer.appendChild(h)
    c.removeConnection("x")
    expect(c.connections).toHaveLength(0)
    expect(c.connectionLayer.querySelector('[data-connection-id="x"]')).toBeNull()
    expect(c.handleLayer.querySelector('[data-connection-id="x"]')).toBeNull()
  })

  it("is a no-op for an unknown id", () => {
    const c = makeDomCanvas({ connections: [{ id: "x", from: "a", to: "b" }] })
    c.removeConnection("nope")
    expect(c.connections).toHaveLength(1)
  })
})

describe("updateConnections", () => {
  it("clears the layer and re-renders every connection", () => {
    const c = makeDomCanvas({ connections: [{ id: "a" }, { id: "b" }] })
    renderGroup(c, "stale")
    c.updateConnections()
    // stale child removed; _renderConnection called per connection
    expect(c.connectionLayer.querySelector('[data-connection-id="stale"]')).toBeNull()
    expect(c._renderConnection).toHaveBeenCalledTimes(2)
  })

  it("restores selection styling when the selected connection still exists", () => {
    const c = makeDomCanvas({
      connections: [{ id: "sel", from: "a", to: "b" }],
      selectedConnectionId: "sel",
      elements: [proc("a"), proc("b")],
    })
    renderGroup(c, "sel")
    c._renderConnection.mockImplementation((conn) => renderGroup(c, conn.id))
    c.updateConnections()
    expect(c.handleLayer.querySelector('[data-connection-endpoint]')).not.toBeNull()
  })

  it("drops the selection when the selected connection was removed", () => {
    const c = makeDomCanvas({ connections: [{ id: "other" }], selectedConnectionId: "gone" })
    c.updateConnections()
    expect(c.selectedConnectionId).toBeNull()
  })
})

describe("selectConnection / clearConnectionSelection", () => {
  it("styles the newly selected connection, shows handles, and notifies", () => {
    const conn = { id: "x", from: "a", to: "b" }
    const c = makeDomCanvas({ connections: [conn], elements: [proc("a"), proc("b")], onConnectionSelected: vi.fn() })
    const { line } = renderGroup(c, "x")
    c.selectConnection("x")
    expect(c.selectedConnectionId).toBe("x")
    expect(line.getAttribute("stroke")).toBeTruthy()
    expect(c._clearSelection).toHaveBeenCalled()
    expect(c.onConnectionSelected).toHaveBeenCalledWith(conn)
    expect(c.handleLayer.querySelector('[data-connection-endpoint]')).not.toBeNull()
  })

  it("deselects a previously selected connection before selecting the new one", () => {
    const c = makeDomCanvas({
      connections: [{ id: "old", from: "a", to: "b" }, { id: "new", from: "a", to: "b" }],
      elements: [proc("a"), proc("b")],
      selectedConnectionId: "old",
    })
    renderGroup(c, "old"); renderGroup(c, "new")
    c.selectConnection("new")
    expect(c.selectedConnectionId).toBe("new")
  })

  it("selectConnection tolerates a missing connection (no notify)", () => {
    const c = makeDomCanvas({ connections: [], onConnectionSelected: vi.fn() })
    c.selectConnection("ghost")
    expect(c.onConnectionSelected).not.toHaveBeenCalled()
  })

  it("clearConnectionSelection resets styling and is a no-op when nothing is selected", () => {
    const c = makeDomCanvas({ connections: [{ id: "x" }], selectedConnectionId: "x" })
    renderGroup(c, "x")
    c.clearConnectionSelection()
    expect(c.selectedConnectionId).toBeNull()
    // second call: nothing selected -> early return
    c.clearConnectionSelection()
    expect(c.selectedConnectionId).toBeNull()
  })
})

describe("_setConnectionStyle", () => {
  it("is a no-op when the group is absent", () => {
    const c = makeDomCanvas()
    expect(() => c._setConnectionStyle("nope", "#000", 2)).not.toThrow()
  })

  it("tolerates a group missing line/arrow children", () => {
    const c = makeDomCanvas()
    const g = svgEl("g"); g.setAttribute("data-connection-id", "bare")
    c.connectionLayer.appendChild(g)
    expect(() => c._setConnectionStyle("bare", "#000", 2)).not.toThrow()
  })
})

describe("_showConnectionEndpointHandles", () => {
  it("does nothing for an unknown connection or a connection missing endpoints", () => {
    const c = makeDomCanvas({ connections: [{ id: "x", from: "a", to: "b" }], elements: [] })
    c._showConnectionEndpointHandles("x") // elements missing -> early return
    expect(c.handleLayer.querySelector('[data-connection-endpoint]')).toBeNull()
    c._showConnectionEndpointHandles("ghost") // no connection -> early return
    expect(c.handleLayer.querySelector('[data-connection-endpoint]')).toBeNull()
  })

  it("creates from/to endpoint handles whose hover listeners resize the circles", () => {
    const conn = { id: "x", from: "a", to: "b", fromPosition: "bottom", toPosition: "top" }
    const c = makeDomCanvas({ connections: [conn], elements: [proc("a"), proc("b")] })
    c._showConnectionEndpointHandles("x")
    const handles = c.handleLayer.querySelectorAll('[data-connection-endpoint]')
    expect(handles).toHaveLength(2)
    // Exercise hover enter/leave listeners on a handle group.
    const group = handles[0]
    group.dispatchEvent(new Event("mouseenter"))
    group.dispatchEvent(new Event("mouseleave"))
    // mouseleave while dragging keeps the enlarged size (branch coverage)
    c.isDraggingConnectionEndpoint = true
    group.dispatchEvent(new Event("mouseenter"))
    group.dispatchEvent(new Event("mouseleave"))
    expect(group.querySelector(".connection-endpoint-handle")).not.toBeNull()
  })

  it("falls back to bottom/top when the connection has no explicit port/position", () => {
    const conn = { id: "x", from: "a", to: "b" }
    const c = makeDomCanvas({ connections: [conn], elements: [proc("a"), proc("b")] })
    c._showConnectionEndpointHandles("x")
    expect(c._getHandlePosition).toHaveBeenCalledWith(expect.anything(), "bottom")
    expect(c._getHandlePosition).toHaveBeenCalledWith(expect.anything(), "top")
  })
})

describe("connection handles (element side)", () => {
  it("showConnectionHandles wraps a single element in an array and renders handles", () => {
    const c = makeDomCanvas()
    c.showConnectionHandles(proc("a"))
    expect(c.handleLayer.querySelectorAll('[data-handle-position]').length).toBeGreaterThan(0)
  })

  it("_createElementHandles adds arrows with hover listeners (dynamic + standard ports)", () => {
    const c = makeDomCanvas()
    // decision-like element gives it dynamic ports via hasDynamicPorts
    const dec = { id: "d", type: "decision", x: 0, y: 0, width: 80, height: 60, properties: { branches: [{}] } }
    c._createElementHandles(dec)
    const groups = c.handleLayer.querySelectorAll('[data-handle-position]')
    expect(groups.length).toBe(2)
    for (const g of groups) {
      g.dispatchEvent(new Event("mouseenter"))
      g.dispatchEvent(new Event("mouseleave"))
    }
    // mouseleave while drawing keeps the hover styling (branch coverage)
    c.isDrawingConnection = true
    for (const g of groups) g.dispatchEvent(new Event("mouseleave"))
    expect(groups.length).toBe(2)
  })

  it("_hideConnectionHandles clears element handles", () => {
    const c = makeDomCanvas()
    c._createElementHandles(proc("a"))
    c._hideConnectionHandles()
    expect(c.handleLayer.querySelector('[data-handle-position]')).toBeNull()
  })
})

describe("startInlineLabelEdit", () => {
  // Build a rendered connection whose path answers getTotalLength/getPointAtLength
  // (happy-dom lacks these SVG geometry methods, so we stub them on the node).
  function withPath(c, id, label = "") {
    const { g, line } = renderGroup(c, id)
    line.getTotalLength = () => 100
    line.getPointAtLength = () => ({ x: 50, y: 60 })
    c.connections.push({ id, from: "a", to: "b", label })
    return { g, line }
  }

  it("is a no-op when the connection, group, or path line is missing", () => {
    const c = makeDomCanvas()
    expect(() => c.startInlineLabelEdit("ghost")).not.toThrow() // no connection
    c.connections.push({ id: "x" })
    expect(() => c.startInlineLabelEdit("x")).not.toThrow() // no group
    const g = svgEl("g"); g.setAttribute("data-connection-id", "y"); c.connectionLayer.appendChild(g)
    c.connections.push({ id: "y" })
    expect(() => c.startInlineLabelEdit("y")).not.toThrow() // group without .connection-line
  })

  it("mounts an input at the path midpoint seeded with the current label", () => {
    const c = makeDomCanvas()
    withPath(c, "x", "Yes")
    c.startInlineLabelEdit("x")
    const input = c.connectionLayer.querySelector(".connection-inline-editor input")
    expect(input).not.toBeNull()
    expect(input.value).toBe("Yes")
    expect(c._inlineLabelEditor).not.toBeNull()
  })

  it("leaves the placeholder empty when the controller has not set canvas.labels (no inline English fallback)", () => {
    const c = makeDomCanvas()
    withPath(c, "x", "")
    c.startInlineLabelEdit("x")
    const input = c.connectionLayer.querySelector(".connection-inline-editor input")
    expect(input.placeholder).toBe("")
  })

  it("uses the translated placeholder threaded onto canvas.labels by the controller", () => {
    const c = makeDomCanvas({ labels: { connectionLabelPlaceholder: "标签…" } })
    withPath(c, "x", "")
    c.startInlineLabelEdit("x")
    const input = c.connectionLayer.querySelector(".connection-inline-editor input")
    expect(input.placeholder).toBe("标签…")
  })

  it("removes any previously open editor before opening a new one", () => {
    const c = makeDomCanvas()
    withPath(c, "x", "")
    c.startInlineLabelEdit("x")
    const first = c._inlineLabelEditor
    c.startInlineLabelEdit("x")
    expect(first.isConnected).toBe(false)
  })

  it("Enter commits the trimmed label and re-renders (selected connection re-styled)", () => {
    const c = makeDomCanvas({ onConnectionSelected: vi.fn() })
    withPath(c, "x", "")
    c.selectedConnectionId = "x"
    c.updateConnections = vi.fn()
    c._showConnectionEndpointHandles = vi.fn()
    c._setConnectionStyle = vi.fn()
    c.startInlineLabelEdit("x")
    const input = c.connectionLayer.querySelector("input")
    input.value = "  Approved  "
    input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" }))
    expect(c.connections.find(k => k.id === "x").label).toBe("Approved")
    expect(c.onConnectionSelected).toHaveBeenCalled()
    expect(c._inlineLabelEditor).toBeNull()
  })

  it("Escape cancels without changing the label", () => {
    const c = makeDomCanvas()
    withPath(c, "x", "Keep")
    c.startInlineLabelEdit("x")
    const input = c.connectionLayer.querySelector("input")
    input.value = "changed"
    input.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }))
    expect(c.connections.find(k => k.id === "x").label).toBe("Keep")
    expect(c._inlineLabelEditor).toBeNull()
  })

  it("empty input commits a null label", () => {
    const c = makeDomCanvas()
    withPath(c, "x", "old")
    c.updateConnections = vi.fn()
    c.startInlineLabelEdit("x")
    const input = c.connectionLayer.querySelector("input")
    input.value = "   "
    input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" }))
    expect(c.connections.find(k => k.id === "x").label).toBeNull()
  })

  it("blur commits after a tick when the editor is still open", async () => {
    const c = makeDomCanvas()
    withPath(c, "x", "")
    c.updateConnections = vi.fn()
    c.startInlineLabelEdit("x")
    const input = c.connectionLayer.querySelector("input")
    input.value = "Blurred"
    input.dispatchEvent(new Event("blur"))
    await new Promise(r => setTimeout(r, 0))
    expect(c.connections.find(k => k.id === "x").label).toBe("Blurred")
  })

  it("an unchanged label closes the editor without change hooks or reopening the sidebar", async () => {
    const c = makeDomCanvas({ onConnectionSelected: vi.fn(), onBeforeChange: vi.fn(), onchange: vi.fn() })
    withPath(c, "x", "")
    c.updateConnections = vi.fn()
    c.startInlineLabelEdit("x")
    const input = c.connectionLayer.querySelector("input")
    input.dispatchEvent(new Event("blur"))
    await new Promise(r => setTimeout(r, 0))
    expect(c._inlineLabelEditor).toBeNull()
    expect(c.connections.find(k => k.id === "x").label).toBe("")
    expect(c.onBeforeChange).not.toHaveBeenCalled()
    expect(c.onchange).not.toHaveBeenCalled()
    expect(c.onConnectionSelected).not.toHaveBeenCalled()
  })

  it("blur is a no-op once the editor was already removed", async () => {
    const c = makeDomCanvas()
    withPath(c, "x", "orig")
    c.startInlineLabelEdit("x")
    const input = c.connectionLayer.querySelector("input")
    c._removeInlineLabelEditor()
    input.dispatchEvent(new Event("blur"))
    await new Promise(r => setTimeout(r, 0))
    expect(c.connections.find(k => k.id === "x").label).toBe("orig")
  })
})

describe("createConnection / updateConnectionProperties — branch fill", () => {
  it("stores a toPort when toPosition is a port_ handle", () => {
    const c = makeCanvas()
    const conn = c.createConnection(proc("a"), proc("b"), "bottom", "port_3")
    expect(conn.toPort).toBe("port_3")
    expect(conn.toPosition).toBeNull()
  })

  it("initializes properties when the connection had none", () => {
    const conn = { id: "x", label: "l" } // no properties key
    const c = makeCanvas({ connections: [conn] })
    c.updateConnectionProperties("x", undefined, { a: 1 })
    expect(conn.properties).toEqual({ a: 1 })
  })
})

describe("showConnectionHandles — array input", () => {
  it("renders handles for an array of elements without re-wrapping", () => {
    const c = makeDomCanvas()
    c.showConnectionHandles([proc("a"), proc("b")])
    expect(c.handleLayer.querySelectorAll('[data-handle-position]').length).toBe(4)
  })
})

describe("P5-4 startInlineLabelEdit — canMutate guard", () => {
  it("does not mount an editor when the canvas cannot mutate", () => {
    const c = makeDomCanvas({ canMutate: () => false })
    c.connections.push({ id: "x", from: "a", to: "b", label: "Yes" })
    c.startInlineLabelEdit("x")
    expect(c.connectionLayer.querySelector(".connection-inline-editor")).toBeNull()
    expect(c._inlineLabelEditor).toBeFalsy()
  })

  it("suppresses endpoint handles in selectConnection, updateConnections, and commitEdit when canMutate is false", () => {
    const c = makeDomCanvas({ onConnectionSelected: vi.fn() })
    c.connections.push({ id: "x", from: "a", to: "b", label: "Old" })
    const g = document.createElementNS("http://www.w3.org/2000/svg", "g")
    g.setAttribute("data-connection-id", "x")
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path")
    path.setAttribute("class", "connection-line")
    path.getTotalLength = () => 100
    path.getPointAtLength = () => ({ x: 50, y: 50 })
    g.appendChild(path)
    c.connectionLayer.appendChild(g)
    c._showConnectionEndpointHandles = vi.fn()

    // Commit inline edit while selected, flipping canMutate to false right before Enter
    c.selectedConnectionId = "x"
    c.startInlineLabelEdit("x")
    const input = c.connectionLayer.querySelector("input")
    input.value = "Updated"
    c.canMutate = () => false
    input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }))
    expect(c._showConnectionEndpointHandles).not.toHaveBeenCalled()
    expect(c.onConnectionSelected).toHaveBeenCalled()

    // selectConnection and updateConnections also skip endpoint handles when !canMutate
    c.selectConnection("x")
    c.updateConnections()
    expect(c._showConnectionEndpointHandles).not.toHaveBeenCalled()
  })
})
