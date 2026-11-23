import { describe, it, expect, vi, beforeEach } from "vitest"
import { ExternalDropMixin } from "flowchart/canvas/external_drop"
import { ElementManagementMixin } from "flowchart/canvas/element_management"

// Hit-testing, nearest-element, drop-side, and relative-position math all run on
// element DATA coordinates (no real layout), so they're fully unit-testable.
// The highlight/indicator paths touch light SVG DOM (classList, guideLayer).

function makeHost(over = {}) {
  const elementLayer = document.createElementNS("http://www.w3.org/2000/svg", "g")
  const guideLayer = document.createElementNS("http://www.w3.org/2000/svg", "g")
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  svg.appendChild(elementLayer)
  svg.appendChild(guideLayer)
  document.body.appendChild(svg)
  const host = Object.assign(Object.create(ExternalDropMixin), {
    elements: [],
    connections: [],
    elementLayer,
    guideLayer,
    svg,
    flowchartType: "custom",
    externalDropTarget: null,
    onToast: vi.fn(),
    onBeforeChange: vi.fn(),
    onchange: vi.fn(),
    createConnection: vi.fn(),
    removeConnection: vi.fn(),
    updateConnections: vi.fn(),
    updateElementPosition: vi.fn(),
    alignChildElements: vi.fn(),
    shiftElementAndSubTree: vi.fn((element, dx, dy) => { element.x += dx; element.y += dy }),
    _portToCardinal: vi.fn((position) => (["top", "bottom", "left", "right"].includes(position) ? position : "bottom")),
    _getOppositePosition: (side) => ({ top: "bottom", bottom: "top", left: "right", right: "left" }[side]),
    _scrollToElement: vi.fn(),
    _newElementLabel: ElementManagementMixin._newElementLabel,
    renderElement: vi.fn(function (el) {
      const g = document.createElementNS("http://www.w3.org/2000/svg", "g")
      g.setAttribute("data-element-id", el.id)
      this.elementLayer.appendChild(g)
    }),
    ...over,
  })
  return host
}

const el = (id, x, y, w = 100, h = 45) => ({ id, x, y, width: w, height: h })

describe("ExternalDropMixin — hit testing", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = makeHost() })

  it("getElementAtPosition returns the top-most element containing the point", () => {
    host.elements = [el("a", 100, 100), el("b", 100, 100)]
    expect(host.getElementAtPosition(100, 100).id).toBe("b")
    expect(host.getElementAtPosition(1000, 1000)).toBeNull()
  })

  it("getElementAtPosition honors the margin", () => {
    host.elements = [el("a", 100, 100)] // right edge at x=150
    expect(host.getElementAtPosition(160, 100)).toBeNull()
    expect(host.getElementAtPosition(160, 100, 20)).not.toBeNull()
  })

  it("getNearestElement returns the closest element within maxDistance, else null", () => {
    host.elements = [el("a", 0, 0), el("far", 1000, 1000)]
    expect(host.getNearestElement(10, 0, 100).id).toBe("a")
    expect(host.getNearestElement(5000, 5000, 100)).toBeNull()
  })

  it("hasStartElement reflects the presence of a start element", () => {
    expect(host.hasStartElement()).toBe(false)
    host.elements = [el("s", 0, 0)]; host.elements[0].type = "start"
    expect(host.hasStartElement()).toBe(true)
  })

  it("getExternalDropTarget returns the currently tracked drop target", () => {
    expect(host.getExternalDropTarget()).toBeNull()
    host.externalDropTarget = { id: "t" }
    expect(host.getExternalDropTarget()).toEqual({ id: "t" })
  })
})

describe("ExternalDropMixin.getDropSide (vertical bias)", () => {
  const host = Object.create(ExternalDropMixin)
  const e = el("t", 0, 0, 100, 45) // hw=50, hh=22.5

  it("returns top/bottom for near-vertical offsets", () => {
    expect(host.getDropSide(e, 0, -30)).toBe("top")
    expect(host.getDropSide(e, 0, 30)).toBe("bottom")
  })

  it("returns left/right only for strongly horizontal offsets", () => {
    expect(host.getDropSide(e, -60, 0)).toBe("left")
    expect(host.getDropSide(e, 60, 0)).toBe("right")
  })

  it("prefers vertical when the offset is ambiguous (2x bias)", () => {
    // normX = 30/50 = 0.6 ; normY = 5/22.5 = 0.222 ; 0.222*2=0.444 < 0.6 -> horizontal
    expect(host.getDropSide(e, 30, 5)).toBe("right")
    // but a slightly larger vertical component flips it to vertical
    expect(host.getDropSide(e, 10, 10)).toBe("bottom")
  })
})

describe("ExternalDropMixin.getConnectionOnSide", () => {
  let host
  beforeEach(() => { host = makeHost() })

  it("finds an incoming connection landing on the given side", () => {
    host.elements = [el("a", 0, 0), el("b", 0, 100)]
    host.connections = [{ id: "c", from: "a", to: "b", fromPosition: "bottom", toPosition: "top" }]
    const info = host.getConnectionOnSide(host.elements[1], "top")
    expect(info).toMatchObject({ isIncoming: true })
    expect(info.otherElement.id).toBe("a")
  })

  it("finds an outgoing connection leaving the given side", () => {
    host.elements = [el("a", 0, 0), el("b", 0, 100)]
    host.connections = [{ id: "c", from: "a", to: "b", fromPosition: "bottom", toPosition: "top" }]
    const info = host.getConnectionOnSide(host.elements[0], "bottom")
    expect(info).toMatchObject({ isIncoming: false })
    expect(info.otherElement.id).toBe("b")
  })

  it("returns null when no connection uses that side", () => {
    host.elements = [el("a", 0, 0)]
    expect(host.getConnectionOnSide(host.elements[0], "left")).toBeNull()
  })

  it("defaults a position-less incoming connection to the top side", () => {
    host.elements = [el("a", 0, 0), el("b", 0, 100)]
    host.connections = [{ id: "c", from: "a", to: "b" }] // no toPosition -> defaults "top"
    expect(host.getConnectionOnSide(host.elements[1], "top")).toMatchObject({ isIncoming: true })
  })

  it("defaults a position-less outgoing connection to the bottom side", () => {
    host.elements = [el("a", 0, 0), el("b", 0, 100)]
    host.connections = [{ id: "c", from: "a", to: "b" }] // no fromPosition -> defaults "bottom"
    expect(host.getConnectionOnSide(host.elements[0], "bottom")).toMatchObject({ isIncoming: false })
  })
})

describe("ExternalDropMixin — highlight + indicator DOM", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = makeHost() })

  it("highlightDropTargetAt marks the target group and stores it", () => {
    const t = el("t", 100, 100)
    host.elements = [t]
    host.renderElement(t)
    host.highlightDropTargetAt(100, 100)
    expect(host.externalDropTarget.id).toBe("t")
    const group = host.elementLayer.querySelector('[data-element-id="t"]')
    expect(group.classList.contains("drop-target-highlight")).toBe(true)
    // a side indicator was placed in the guide layer
    expect(host.guideLayer.querySelector(".drop-side-indicator")).not.toBeNull()
  })

  it("clearExternalDropHighlight removes the highlight + indicator", () => {
    const t = el("t", 100, 100)
    host.elements = [t]
    host.renderElement(t)
    host.highlightDropTargetAt(100, 100)
    host.clearExternalDropHighlight()
    expect(host.externalDropTarget).toBeNull()
    expect(host.elementLayer.querySelector(".drop-target-highlight")).toBeNull()
    expect(host.guideLayer.querySelector(".drop-side-indicator")).toBeNull()
  })

  it("highlightDropTargetAt with no nearby element clears any indicator", () => {
    host.elements = [el("t", 100, 100)]
    host.renderElement(host.elements[0])
    host.highlightDropTargetAt(5000, 5000)
    expect(host.externalDropTarget).toBeNull()
    expect(host.guideLayer.querySelector(".drop-side-indicator")).toBeNull()
  })
})

describe("ExternalDropMixin.getDropSide — zero-dimension fallback", () => {
  const host = Object.create(ExternalDropMixin)
  it("uses the || 1 divisor when the element has zero width/height", () => {
    const zero = el("z", 0, 0, 0, 0) // hw=0, hh=0 -> normX/normY use `|| 1`
    // relX=5, relY=1 -> normX=5, normY=1; 1*2 < 5 -> horizontal right
    expect(host.getDropSide(zero, 5, 1)).toBe("right")
  })
})

describe("ExternalDropMixin._showDropSideIndicator — all sides", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = makeHost() })

  it.each(["top", "bottom", "left", "right"])("places an indicator on the %s side", (side) => {
    host._showDropSideIndicator(el("t", 100, 100), side)
    const ind = host.guideLayer.querySelector(".drop-side-indicator")
    expect(ind).not.toBeNull()
    expect(ind.querySelector("polygon")).not.toBeNull()
    expect(ind.querySelector("circle")).not.toBeNull()
  })
})

describe("ExternalDropMixin.highlightDropTargetAt — target transitions", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = makeHost() })

  it("clears the previous highlight when the target changes to a different element", () => {
    const a = el("a", 100, 100), b = el("b", 400, 400)
    host.elements = [a, b]
    host.renderElement(a); host.renderElement(b)
    host.highlightDropTargetAt(100, 100)
    expect(host.externalDropTarget.id).toBe("a")
    // move onto b: previous "a" highlight is cleared, "b" becomes target
    host.highlightDropTargetAt(400, 400)
    expect(host.externalDropTarget.id).toBe("b")
    expect(host.elementLayer.querySelector('[data-element-id="a"]').classList.contains("drop-target-highlight")).toBe(false)
    expect(host.elementLayer.querySelector('[data-element-id="b"]').classList.contains("drop-target-highlight")).toBe(true)
  })

  it("updates glow intensity when the cursor moves within the same target", () => {
    const a = el("a", 100, 100)
    host.elements = [a]
    host.renderElement(a)
    host.highlightDropTargetAt(100, 100)
    const group = host.elementLayer.querySelector('[data-element-id="a"]')
    const first = group.style.getPropertyValue("--drop-glow-intensity")
    // same target, different offset -> takes the else branch and rewrites intensity
    host.highlightDropTargetAt(120, 110)
    expect(host.externalDropTarget.id).toBe("a")
    expect(group.style.getPropertyValue("--drop-glow-intensity")).not.toBe("")
    expect(first).not.toBe("")
  })
})

describe("ExternalDropMixin._reconnectAfterInsert (with existing connection)", () => {
  let host
  beforeEach(() => { host = makeHost() })

  it("re-wires an incoming connection through the inserted element (vertical)", () => {
    const other = el("o", 999, 0)      // different x -> alignment branch fires
    const target = el("t", 200, 200)
    const newEl = el("n", 200, 110)
    const connection = { id: "c", fromPosition: "bottom", toPosition: "top" }
    const info = { connection, isIncoming: true, otherElement: other }
    host._reconnectAfterInsert(newEl, target, "top", info)
    expect(other.x).toBe(200)
    expect(host.updateElementPosition).toHaveBeenCalledWith(other)
    expect(host.removeConnection).toHaveBeenCalledWith("c")
    expect(host.createConnection).toHaveBeenCalledWith(other, newEl, "bottom", "top")
    expect(host.createConnection).toHaveBeenCalledWith(newEl, target, "bottom", "top")
    expect(host.alignChildElements).toHaveBeenCalledWith(target)
    expect(host.alignChildElements).toHaveBeenCalledWith(newEl)
    expect(host.updateConnections).toHaveBeenCalled()
  })

  it("re-wires an outgoing connection through the inserted element (horizontal)", () => {
    const other = el("o", 0, 999)      // different y -> horizontal alignment branch
    const target = el("t", 200, 200)
    const newEl = el("n", 350, 200)
    const connection = { id: "c" } // missing fromPosition/toPosition -> defaults
    const info = { connection, isIncoming: false, otherElement: other }
    host._reconnectAfterInsert(newEl, target, "right", info)
    expect(other.y).toBe(200)
    expect(host.createConnection).toHaveBeenCalledWith(target, newEl, "bottom", "left")
    expect(host.createConnection).toHaveBeenCalledWith(newEl, other, "right", "top")
  })

  it("leaves an already-aligned far end in place", () => {
    const other = el("o", 200, 0)
    const target = el("t", 200, 200)
    const newEl = el("n", 200, 110)
    host._reconnectAfterInsert(newEl, target, "top", {
      connection: { id: "c", fromPosition: "bottom", toPosition: "top" }, isIncoming: true, otherElement: other,
    })
    const sideways = el("s", 0, 200)
    host._reconnectAfterInsert(el("n2", 100, 200), target, "left", {
      connection: { id: "c2", fromPosition: "left", toPosition: "right" }, isIncoming: false, otherElement: sideways,
    })
    expect(host.updateElementPosition).not.toHaveBeenCalled()
  })

  it("keeps metadata on the upstream edge when inserting on an incoming connection", () => {
    const other = el("o", 200, 0)
    const target = el("t", 200, 200)
    const newEl = el("n", 200, 110)
    const connection = {
      id: "c",
      fromPort: "port_0",
      fromPosition: null,
      toPosition: "top",
      label: "true",
      matchValue: "true",
      properties: { description: "yes-branch", priority: 2 },
    }
    host._reconnectAfterInsert(newEl, target, "top", { connection, isIncoming: true, otherElement: other })
    expect(host.createConnection).toHaveBeenCalledWith(
      other,
      newEl,
      "port_0",
      "top",
      expect.objectContaining({
        label: "true",
        matchValue: "true",
        properties: { description: "yes-branch", priority: 2 },
      })
    )
    // The decision's port id stays on the decision; the new box leaves from the matching side.
    expect(host._portToCardinal).toHaveBeenCalledWith("port_0", other)
    expect(host.createConnection).toHaveBeenCalledWith(newEl, target, "bottom", "top")
  })

  it("keeps fromPort/label/matchValue/properties on the upstream edge of a decision insert", () => {
    const child = Object.assign(el("child", 200, 300), { type: "process" })
    const decision = Object.assign(el("dec", 200, 100), { type: "decision" })
    const inserted = Object.assign(el("ins", 200, 200), { type: "process" })
    const connection = {
      id: "c",
      from: "dec",
      to: "child",
      fromPort: "port_0",
      fromPosition: null,
      toPosition: "top",
      label: "true",
      matchValue: "true",
      properties: { description: "yes-branch", priority: 2 },
    }
    const info = { connection, isIncoming: false, otherElement: child }
    host._reconnectAfterInsert(inserted, decision, "bottom", info)
    expect(host.removeConnection).toHaveBeenCalledWith("c")
    expect(host.createConnection).toHaveBeenCalledWith(
      decision,
      inserted,
      "port_0",
      "top",
      expect.objectContaining({
        label: "true",
        matchValue: "true",
        properties: { description: "yes-branch", priority: 2 },
      })
    )
  })
})

describe("ExternalDropMixin._reconnectAfterInsert — live decision branches", () => {
  it("carries the decision branch label and match value onto the inserted connection", async () => {
    const { ConnectionManagerMixin } = await import("flowchart/connection_manager")
    const child = Object.assign(el("child", 200, 300), { type: "process", properties: {} })
    const decision = Object.assign(el("dec", 200, 100), {
      type: "decision",
      properties: {},
    })
    const inserted = Object.assign(el("ins", 200, 200), { type: "process", properties: {} })
    const connection = {
      id: "c",
      from: "dec",
      to: "child",
      fromPort: "port_0",
      fromPosition: null,
      toPosition: "top",
      label: "true",
      matchValue: "true",
      properties: { description: "yes-branch", priority: 2 },
    }
    const host = makeHost({
      elements: [decision, child, inserted],
      connections: [connection],
    })
    Object.assign(host, {
      createConnection: ConnectionManagerMixin.createConnection,
      _rejectsDirectedEdge: ConnectionManagerMixin._rejectsDirectedEdge,
      _syncDecisionBranches: ConnectionManagerMixin._syncDecisionBranches,
      _alignConnectionElements: ConnectionManagerMixin._alignConnectionElements,
      _alignAcross: ConnectionManagerMixin._alignAcross,
      _connectionOrientation: ConnectionManagerMixin._connectionOrientation,
      _alignNewBranchToRow: ConnectionManagerMixin._alignNewBranchToRow,
      _renderConnection: () => {},
      emitStructureChanged: () => {},
      removeConnection(id) { this.connections = this.connections.filter(c => c.id !== id) },
    })
    host._reconnectAfterInsert(inserted, decision, "bottom", {
      connection, isIncoming: false, otherElement: child,
    })
    const upstream = host.connections.find((c) => c.from === "dec" && c.to === "ins")
    expect(upstream).toMatchObject({
      fromPort: "port_0",
      label: "true",
      matchValue: "true",
      properties: { description: "yes-branch", priority: 2 },
    })
    expect(decision.properties).toEqual({})
  })
})

describe("ExternalDropMixin.addElementRelativeTo", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = makeHost() })

  it("blocks a second Start element", () => {
    host.elements = [Object.assign(el("s", 0, 0), { type: "start" })]
    const out = host.addElementRelativeTo({ type: "start" }, host.elements[0], 0, -30)
    expect(out).toBeNull()
    expect(host.onToast).toHaveBeenCalled()
  })

  it("inserts a new element below the target and connects them (no prior connection)", () => {
    const target = el("t", 200, 200)
    host.elements = [target]
    host.renderElement(target)
    const out = host.addElementRelativeTo({ type: "process" }, target, 200, 230) // bottom drop
    expect(out).toMatchObject({ type: "process" })
    expect(host.elements).toContain(out)
    expect(out.x).toBe(200) // in line with the target
    expect(out.y).toBe(290) // target.y + snap(22.5 + 50 + 22.5)
    expect(host.shiftElementAndSubTree).not.toHaveBeenCalled()
    expect(host.createConnection).toHaveBeenCalledWith(target, out, "bottom", "top")
    expect(host.updateConnections).toHaveBeenCalled()
  })

  it("inserts to the side (horizontal) using explicit id/label/properties", () => {
    const target = el("t", 200, 200)
    host.elements = [target]
    host.renderElement(target)
    const out = host.addElementRelativeTo(
      { id: "given", type: "process", label: "Named", properties: { a: 1 } }, target, 260, 200) // right drop
    expect(out.id).toBe("given")
    expect(out.label).toBe("Named")
    expect(out.x).toBe(350) // target.x + snap(50 + 50 + 50)
    expect(out.y).toBe(200) // in line with the target
    expect(host._scrollToElement).toHaveBeenCalledWith(out)
    expect(host.onchange).toHaveBeenCalled()
  })

  it("re-wires through an existing incoming connection on drop", () => {
    const parent = el("p", 200, 100)
    const target = el("t", 200, 200)
    host.elements = [parent, target]
    host.renderElement(parent); host.renderElement(target)
    host.connections = [{ id: "c", from: "p", to: "t", fromPosition: "bottom", toPosition: "top" }]
    const sibling = el("keep", 400, 400)
    host.elements.push(sibling)
    const out = host.addElementRelativeTo({ type: "process" }, target, 200, 170) // top drop -> incoming side
    expect(out).toMatchObject({ x: 200, y: 200 }) // the gap the target vacated
    expect(host.shiftElementAndSubTree).toHaveBeenCalledWith(target, 0, 90)
    expect(target.y).toBe(290)
    expect(sibling.x).toBe(400)
    expect(sibling.y).toBe(400)
    expect(parent.x).toBe(200)
    expect(parent.y).toBe(100)
    expect(host.removeConnection).toHaveBeenCalledWith("c")
  })

  it("pushes the existing child away when dropped on an outgoing side", () => {
    const target = el("t", 200, 200)
    const child = el("c", 200, 300)
    host.elements = [target, child]
    host.connections = [{ id: "c", from: "t", to: "c", fromPosition: "bottom", toPosition: "top" }]
    const out = host.addElementRelativeTo({ type: "process" }, target, 200, 230)
    expect(host.shiftElementAndSubTree).toHaveBeenCalledWith(child, 0, 90)
    expect(child.y).toBe(390)
    expect(out).toMatchObject({ x: 200, y: 290 })
  })

  it("falls back to the type as label when no label or default label exists", () => {
    const target = el("t", 200, 200)
    host.elements = [target]
    host.renderElement(target)
    const out = host.addElementRelativeTo({ type: "totally_unknown_type" }, target, 200, 230)
    expect(out.label).toBe("totally_unknown_type")
  })

  // i18n seam: external_drop.js reads translated strings from this.labels
  // (threaded by flowchart_canvas_controller.js), falling back to English
  // when omitted (as every other test in this describe block exercises).
  it("uses this.labels.elementDefaultLabels for the seeded label when present", () => {
    const target = el("t", 200, 200)
    host.elements = [target]
    host.renderElement(target)
    host.labels = { elementDefaultLabels: { process: "流程" } }
    const out = host.addElementRelativeTo({ type: "process" }, target, 200, 230)
    expect(out.label).toBe("流程")
  })

  it("uses this.labels.onlyOneStartAllowedToast for the single-Start toast when present", () => {
    host.elements = [Object.assign(el("s", 0, 0), { type: "start" })]
    host.labels = { onlyOneStartAllowedToast: "只能有一个开始元素" }
    host.addElementRelativeTo({ type: "start" }, host.elements[0], 0, -30)
    expect(host.onToast).toHaveBeenCalledWith("只能有一个开始元素", "warning")
  })
})

describe("P5-4 ExternalDropMixin — canMutate guard", () => {
  it("addElementRelativeTo and insertElementOnConnection no-op when canMutate is false", () => {
    const host = makeHost({
      canMutate: () => false,
      isReadOnly: false,
      _connectionMidpoint: vi.fn(() => ({ x: 200, y: 160 })),
    })
    const target = el("t", 200, 200)
    host.elements = [target]
    host.connections = [{ id: "c", from: "a", to: "t" }]
    expect(host.addElementRelativeTo({ type: "process" }, target, 200, 230)).toBeNull()
    expect(host.insertElementOnConnection("c", "process")).toBeNull()
    expect(host.onBeforeChange).not.toHaveBeenCalled()
  })
})

describe("ExternalDropMixin.insertElementOnConnection", () => {
  let host
  beforeEach(() => {
    document.body.innerHTML = ""
    host = makeHost({
      isReadOnly: false,
      _connectionMidpoint: vi.fn(() => ({ x: 200, y: 160 })),
      _portToCardinal: vi.fn(() => "bottom"),
      _selectElement: vi.fn(),
      onElementDoubleClick: vi.fn(),
      emitStructureChanged: vi.fn(),
    })
  })

  it("returns null when read-only, missing, or an endpoint is gone", () => {
    host.isReadOnly = true
    expect(host.insertElementOnConnection("c", "process")).toBeNull()
    host.isReadOnly = false
    expect(host.insertElementOnConnection("gone", "process")).toBeNull()
    host.connections = [{ id: "c", from: "a", to: "missing" }]
    host.elements = [el("a", 0, 0)]
    expect(host.insertElementOnConnection("c", "process")).toBeNull()
    host.connections = [{ id: "c", from: "missing", to: "b" }]
    host.elements = [el("b", 0, 0)]
    expect(host.insertElementOnConnection("c", "process")).toBeNull()
    expect(host.onBeforeChange).not.toHaveBeenCalled()
  })

  it("inserts next to A, pushes B away, rewires A→new→B, selects it, and opens the editor as one undo entry", () => {
    const from = Object.assign(el("a", 200, 100), { type: "decision" })
    const to = el("b", 200, 220)
    const connection = {
      id: "c",
      from: "a",
      to: "b",
      fromPort: "port_0",
      fromPosition: null,
      toPosition: "top",
      label: "Yes",
      matchValue: "true",
      properties: { description: "yes-branch" },
    }
    host.elements = [from, to]
    host.connections = [connection]
    const created = host.insertElementOnConnection("c", "process")

    expect(created).toMatchObject({ type: "process", x: 200, y: 190 })
    expect(host.shiftElementAndSubTree).toHaveBeenCalledWith(to, 0, 90)
    expect(to.y).toBe(310)
    expect(host.onBeforeChange).toHaveBeenCalledOnce()
    expect(host.removeConnection).toHaveBeenCalledWith("c")
    expect(host.createConnection).toHaveBeenCalledWith(
      from,
      created,
      "port_0",
      "top",
      expect.objectContaining({ label: "Yes", matchValue: "true", properties: { description: "yes-branch" } })
    )
    expect(host.createConnection).toHaveBeenCalledWith(created, to, "bottom", "top")
    expect(host._selectElement).toHaveBeenCalledWith(created)
    expect(host.onElementDoubleClick).toHaveBeenCalledWith(created)
    expect(host.onchange).toHaveBeenCalledOnce()
    expect(host.emitStructureChanged).toHaveBeenCalledWith({ elementId: created.id })
  })

  it("falls back to the bottom port when the split connection has no from handle", () => {
    const from = el("a", 200, 100)
    const to = el("b", 200, 220)
    host.elements = [from, to]
    host.connections = [{ id: "c", from: "a", to: "b" }]
    host.insertElementOnConnection("c", "process")
    expect(host._portToCardinal).toHaveBeenCalledWith("bottom", from)
  })
})

describe("P5-5 ExternalDropMixin — unique default labels", () => {
  let host
  beforeEach(() => {
    document.body.innerHTML = ""
    host = makeHost({
      _connectionMidpoint: vi.fn(() => ({ x: 200, y: 160 })),
      _portToCardinal: vi.fn(() => "bottom"),
      _selectElement: vi.fn(),
    })
  })

  it("numbers an insert-next-to element whose default label is taken", () => {
    host.labels = { elementDefaultLabels: { process: "Process" } }
    const target = Object.assign(el("t", 200, 200), { type: "process", label: "Process" })
    host.elements = [target, Object.assign(el("p2", 400, 400), { label: "Process 2" })]
    expect(host.addElementRelativeTo({ type: "process" }, target, 200, 230).label).toBe("Process 3")
  })

  it("numbers an edge \"+\" insert with the translated format", () => {
    const from = Object.assign(el("a", 200, 100), { label: "流程" })
    host.elements = [from, el("b", 200, 220)]
    host.connections = [{ id: "c", from: "a", to: "b" }]
    host.labels = { elementDefaultLabels: { process: "流程" }, uniqueLabelFormat: "{label}（{n}）" }
    expect(host.insertElementOnConnection("c", "process").label).toBe("流程（2）")
  })
})
