import { describe, it, expect, vi, beforeEach } from "vitest"
import { ElementManagementMixin } from "flowchart/canvas/element_management"
import { ElementRendererMixin } from "flowchart/element_renderer"
import { snapToGrid } from "utils"
import { DEFAULT_LABELS, GRID_SIZE } from "flowchart/constants"

// ElementManagementMixin does element CRUD over the elements/connections DATA
// arrays plus light DOM (rendered group removal). Connection creation, rendering,
// selection, and scrolling are stubbed. Position math (snapToGrid, GRID_SIZE=15,
// DEFAULT width 100 / height 45 / spacing 50) is exercised for real.

function makeHost(over = {}) {
  const elementLayer = document.createElementNS("http://www.w3.org/2000/svg", "g")
  document.body.appendChild(elementLayer)
  const host = Object.assign(Object.create(ElementManagementMixin), {
    elements: [],
    connections: [],
    selectedElements: [],
    elementLayer,
    flowchartType: "custom",
    labels: { elementDefaultLabels: { ...DEFAULT_LABELS } },
    onToast: vi.fn(),
    onBeforeChange: vi.fn(),
    onchange: vi.fn(),
    onElementSelected: vi.fn(),
    createConnection: vi.fn(),
    updateConnections: vi.fn(),
    _scrollToElement: vi.fn(),
    emitStructureChanged: vi.fn(),
    _clearSelection: vi.fn(),
    _addToSelection: vi.fn(),
    _hideConnectionHandles: vi.fn(),
    _createLabel: vi.fn(() => document.createElementNS("http://www.w3.org/2000/svg", "text")),
    hasStartElement() { return this.elements.some(e => e.type === "start") },
    renderElement: vi.fn(function (el) {
      const g = document.createElementNS("http://www.w3.org/2000/svg", "g")
      g.setAttribute("data-element-id", el.id)
      this.elementLayer.appendChild(g)
    }),
    ...over,
  })
  return host
}

describe("ElementManagementMixin.addElement", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = makeHost() })

  it("creates a defaulted element and renders it", () => {
    const el = host.addElement({ type: "process" })
    expect(el).toMatchObject({ type: "process", width: 100, height: 45, label: "Process" })
    expect(el.id).toMatch(/^el_/)
    expect(host.elements).toContain(el)
    expect(host.renderElement).toHaveBeenCalledOnce()
    expect(host.onchange).toHaveBeenCalled()
  })

  it("enforces the single-Start constraint", () => {
    host.labels = { onlyOneStartAllowedToast: "Only one Start element allowed per flowchart" }
    host.elements = [{ id: "s", type: "start" }]
    const el = host.addElement({ type: "start" })
    expect(el).toBeNull()
    expect(host.onToast).toHaveBeenCalledWith("Only one Start element allowed per flowchart", "warning")
    expect(host.onBeforeChange).not.toHaveBeenCalled()
  })

  it("auto-connects a new element below the previous one", () => {
    const first = host.addElement({ type: "start" })
    host.createConnection.mockClear()
    const second = host.addElement({ type: "process" })
    expect(host.createConnection).toHaveBeenCalledWith(first, second, "bottom", "top")
  })

  it("honors an explicit finite drop position (snapped to grid)", () => {
    const el = host.addElement({ type: "process", x: 47, y: 91 })
    // snapToGrid(47,15)=45, snapToGrid(91,15)=90
    expect(el.x).toBe(45)
    expect(el.y).toBe(90)
  })

  it("does not auto-connect a positioned drop even when another element already exists", () => {
    host.addElement({ type: "start" })
    host.createConnection.mockClear()
    host.addElement({ type: "process", x: 60, y: 90 })
    expect(host.createConnection).not.toHaveBeenCalled()
  })

  it("does not auto-connect a double-click append from an End", () => {
    host.addElement({ type: "end" })
    host.createConnection.mockClear()
    host.addElement({ type: "process" })
    expect(host.createConnection).not.toHaveBeenCalled()
  })

  it("auto-connects a double-click append from a Decision that has no branch yet", () => {
    const decision = host.addElement({ type: "decision" })
    host.createConnection.mockClear()
    const next = host.addElement({ type: "process" })
    expect(host.createConnection).toHaveBeenCalledWith(decision, next, "bottom", "top")
  })

  it("does not auto-connect a double-click append from a Decision that already has a branch", () => {
    const decision = host.addElement({ type: "decision" })
    host.connections = [{ id: "c1", from: decision.id, to: "elsewhere" }]
    host.createConnection.mockClear()
    host.addElement({ type: "process" })
    expect(host.createConnection).not.toHaveBeenCalled()
  })

  it("does not auto-connect a double-click append from an element that already has an outgoing edge", () => {
    const first = host.addElement({ type: "start" })
    const second = host.addElement({ type: "process" })
    host.connections = [{ id: "c1", from: second.id, to: first.id }]
    host.createConnection.mockClear()
    host.addElement({ type: "process" })
    expect(host.createConnection).not.toHaveBeenCalled()
  })

  it("stacks below the previous element using center-to-center spacing", () => {
    host.elements = [{ id: "prev", type: "process", x: 200, y: 100, width: 100, height: 45 }]
    const el = host.addElement({ type: "process" })
    // centerToCenter = 45/2 + 50 + 45/2 = 95 -> y = snap(100+95)=snap(195)=195; x = snap(200)=195? 200/15=13.33 ->13*15=195
    expect(el.x).toBe(195)
    expect(el.y).toBe(195)
  })

  it("uses an explicit label instead of the type default when given", () => {
    const el = host.addElement({ type: "process", label: "Custom Name" })
    expect(el.label).toBe("Custom Name")
  })

  // i18n seam: element_management.js reads translated strings from
  // this.labels (threaded by flowchart_canvas_controller.js, whose Stimulus
  // value defaults to the English DEFAULT_LABELS that makeHost mirrors).
  it("uses this.labels.elementDefaultLabels for the seeded label when present", () => {
    host.labels = { elementDefaultLabels: { process: "流程" } }
    const el = host.addElement({ type: "process" })
    expect(el.label).toBe("流程")
  })

  it("falls back to the type key when the translated label map has no entry", () => {
    host.labels = { elementDefaultLabels: {} }
    expect(host.addElement({ type: "process" }).label).toBe("process")
  })

  it("falls back to the type key when no labels are threaded", () => {
    host.labels = undefined
    expect(host.addElement({ type: "process" }).label).toBe("process")
  })

  it("uses this.labels.onlyOneStartAllowedToast for the single-Start toast when present", () => {
    host.labels = { onlyOneStartAllowedToast: "只能有一个开始元素" }
    host.elements = [{ id: "s", type: "start" }]
    host.addElement({ type: "start" })
    expect(host.onToast).toHaveBeenCalledWith("只能有一个开始元素", "warning")
  })

  it("uses the retained Subflow default label", () => {
    const el = host.addElement({ type: "subflow" })
    expect(el.label).toBe("Subflow")
  })

  it("rejects unsupported structural element types", () => {
    expect(host.addElement({ type: "join" })).toBeNull()
    expect(host.renderElement).not.toHaveBeenCalled()
  })
})

describe("ElementManagementMixin._shouldAutoConnect", () => {
  it("returns false for a missing source", () => {
    const host = makeHost()
    expect(host._shouldAutoConnect(null)).toBe(false)
  })
})

describe("ElementManagementMixin._autoConnectElements", () => {
  let host
  beforeEach(() => { host = makeHost() })

  it("uses bottom->top for vertically-separated elements", () => {
    host._autoConnectElements({ x: 0, y: 0 }, { x: 0, y: 100 })
    expect(host.createConnection).toHaveBeenCalledWith({ x: 0, y: 0 }, { x: 0, y: 100 }, "bottom", "top")
  })

  it("uses side ports when the two elements are roughly level", () => {
    const from = { x: 0, y: 0 }, to = { x: 100, y: 10 }
    host._autoConnectElements(from, to)
    expect(host.createConnection).toHaveBeenCalledWith(from, to, "right", "left")
  })

  it("mirrors side ports when the target is to the left (roughly level)", () => {
    const from = { x: 100, y: 0 }, to = { x: 0, y: 10 }
    host._autoConnectElements(from, to)
    expect(host.createConnection).toHaveBeenCalledWith(from, to, "left", "right")
  })
})

describe("ElementManagementMixin._deleteElement", () => {
  let host
  beforeEach(() => {
    document.body.innerHTML = ""
    host = makeHost()
  })

  it("removes the element, its group, and connected edges", () => {
    const a = { id: "a", type: "process", properties: {} }
    const b = { id: "b", type: "process", properties: {} }
    host.elements = [a, b]
    host.connections = [{ id: "c1", from: "a", to: "b" }, { id: "c2", from: "b", to: "a" }]
    host.renderElement(a)
    host._deleteElement(a)
    expect(host.elements).toEqual([b])
    expect(host.elementLayer.querySelector('[data-element-id="a"]')).toBeNull()
    expect(host.connections).toEqual([])
    expect(host.updateConnections).toHaveBeenCalled()
  })

  it("no-ops for an element not on the canvas", () => {
    host.elements = [{ id: "a" }]
    expect(() => host._deleteElement({ id: "missing" })).not.toThrow()
    expect(host.elements).toHaveLength(1)
  })

  it("also removes the element from selectedElements when it was selected", () => {
    const a = { id: "a", type: "process", properties: {} }
    host.elements = [a]
    host.selectedElements = [a]
    host._deleteElement(a)
    expect(host.selectedElements).toEqual([])
  })
})

describe("ElementManagementMixin._pasteElements", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = makeHost() })

  it("ignores a null paste result", () => {
    expect(() => host._pasteElements(null)).not.toThrow()
    expect(host.onBeforeChange).not.toHaveBeenCalled()
  })

  it("adds pasted elements + connections and selects them", () => {
    const els = [{ id: "n1", type: "process" }, { id: "n2", type: "process" }]
    host._pasteElements({ elements: els, connections: [{ id: "c", from: "n1", to: "n2" }] })
    expect(host.elements).toEqual(els)
    expect(host.connections).toHaveLength(1)
    expect(host._addToSelection).toHaveBeenCalledTimes(2)
    expect(host.onElementSelected).toHaveBeenCalledWith(els[1])
  })

  it("drops pasted Start elements (and their edges) when a Start already exists", () => {
    host.elements = [{ id: "existing", type: "start" }]
    host._pasteElements({
      elements: [{ id: "s2", type: "start" }, { id: "p", type: "process" }],
      connections: [{ id: "c", from: "s2", to: "p" }],
    })
    // Only the process element got added (its Start-linked connection dropped too).
    expect(host.elements.map(e => e.id)).toEqual(["existing", "p"])
    expect(host.connections).toEqual([])
  })

  it("drops a connection whose TARGET (not source) is a dropped Start element", () => {
    host.elements = [{ id: "existing", type: "start" }]
    host._pasteElements({
      elements: [{ id: "s2", type: "start" }, { id: "p", type: "process" }],
      connections: [{ id: "c", from: "p", to: "s2" }],
    })
    expect(host.connections).toEqual([])
  })

  it("is a no-op when every pasted element was a dropped Start (nothing left to paste)", () => {
    host.elements = [{ id: "existing", type: "start" }]
    host._pasteElements({
      elements: [{ id: "s2", type: "start" }],
      connections: [],
    })
    expect(host.elements).toEqual([{ id: "existing", type: "start" }])
    expect(host.onBeforeChange).not.toHaveBeenCalled()
  })

  it("drops unsupported structural elements and their connections from paste payloads", () => {
    host._pasteElements({
      elements: [{ id: "legacy", type: "join" }, { id: "p", type: "process" }],
      connections: [{ id: "c", from: "legacy", to: "p" }],
    })

    expect(host.elements.map(e => e.id)).toEqual(["p"])
    expect(host.connections).toEqual([])
    expect(host.renderElement).toHaveBeenCalledOnce()
  })
})

describe("ElementManagementMixin.updateElementProperties", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = makeHost() })

  it("merges properties, updates label, and emits change", () => {
    const el = { id: "e", label: "Old", properties: { a: 1 } }
    host.elements = [el]
    host.renderElement(el)
    const out = host.updateElementProperties("e", "New", { b: 2 })
    expect(out).toBe(el)
    expect(el.label).toBe("New")
    expect(el.properties).toEqual({ a: 1, b: 2 })
    expect(host.onchange).toHaveBeenCalled()
    expect(host.emitStructureChanged).toHaveBeenCalledWith({ elementId: "e" })
  })

  it("keeps the existing label when newLabel is undefined", () => {
    const el = { id: "e", label: "Keep", properties: {} }
    host.elements = [el]
    host.renderElement(el)
    host.updateElementProperties("e", undefined, { x: 1 })
    expect(el.label).toBe("Keep")
  })

  it("returns undefined for an unknown element", () => {
    expect(host.updateElementProperties("missing", "x")).toBeUndefined()
  })

  it("replaces properties entirely when replaceProperties is true", () => {
    const el = { id: "e", label: "Keep", properties: { a: 1, b: 2 } }
    host.elements = [el]
    host.renderElement(el)
    host.updateElementProperties("e", undefined, { c: 3 }, true)
    expect(el.properties).toEqual({ c: 3 })
  })

  it("_rerenderElement no-ops when the element was never rendered (no group in the DOM)", () => {
    const el = { id: "unrendered", label: "X", properties: {} }
    host.elements = [el]
    // Deliberately skip host.renderElement(el) so no group exists.
    expect(() => host.updateElementProperties("unrendered", "Y")).not.toThrow()
    expect(host.renderElement).not.toHaveBeenCalled()
  })
})

describe("P5-6 ElementManagementMixin._rerenderElement — whole-group redraw after an edit", () => {
  const SVG = "http://www.w3.org/2000/svg"
  let host

  function renderedHost() {
    const elementLayer = document.createElementNS(SVG, "g")
    document.body.appendChild(elementLayer)
    const proto = { ...ElementRendererMixin, ...ElementManagementMixin }
    return Object.assign(Object.create(proto), {
      elements: [],
      connections: [],
      selectedElements: [],
      elementLayer,
      isDragging: false,
      onBeforeChange: vi.fn(),
      onchange: vi.fn(),
      emitStructureChanged: vi.fn(),
    })
  }

  const element = (over = {}) => ({ id: "e1", type: "process", label: "Old", x: 100, y: 100, width: 100, height: 45, properties: {}, ...over })
  const groupOf = (id) => host.elementLayer.querySelector(`[data-element-id="${id}"]`)

  beforeEach(() => { document.body.innerHTML = ""; host = renderedHost() })

  it("redraws fill, comment dot and size, not just the label", () => {
    const el = element()
    host.elements = [el]
    host.renderElement(el)
    const before = groupOf("e1")

    host.updateElementProperties("e1", "New", { style: { fill: "#ff0000", stroke: "#00ff00" }, comments: "note" })
    const after = groupOf("e1")

    expect(after).not.toBe(before)
    expect(host.elementLayer.querySelectorAll('[data-element-id="e1"]')).toHaveLength(1)
    expect(after.querySelector("text").textContent).toBe("New")
    expect(after.querySelector("rect").getAttribute("fill")).toBe("#ff0000")
    expect(after.querySelector("circle")).not.toBeNull()
    expect(host.onchange).toHaveBeenCalled()
  })

  it("keeps the stacking position, the selection class and the validation ring", () => {
    const first = element({ id: "a" })
    const middle = element({ id: "b" })
    const last = element({ id: "c" })
    host.elements = [first, middle, last]
    host.elements.forEach(el => host.renderElement(el))
    groupOf("b").classList.add("selected", "search-highlight")
    host.setValidationState("b", "warning")

    host.updateElementProperties("b", "Renamed")

    const ids = Array.from(host.elementLayer.children).map(g => g.getAttribute("data-element-id"))
    expect(ids).toEqual(["a", "b", "c"])
    const group = groupOf("b")
    expect(group.classList.contains("selected")).toBe(true)
    expect(group.classList.contains("search-highlight")).toBe(true)
    const rings = group.querySelectorAll("[data-validation-ring]")
    expect(rings).toHaveLength(1)
    expect(rings[0].dataset.validationSeverity).toBe("warning")
  })

  it("keeps an attached subflow fold icon and leaves an unmarked group unclassed", () => {
    const el = element()
    host.elements = [el]
    host.renderElement(el)
    const foldIcon = document.createElementNS(SVG, "g")
    foldIcon.setAttribute("class", "fold-icon")
    groupOf("e1").appendChild(foldIcon)

    host.updateElementProperties("e1", "New")

    const group = groupOf("e1")
    expect(group.contains(foldIcon)).toBe(true)
    expect(group.hasAttribute("class")).toBe(false)
    expect(group.querySelector("[data-validation-ring]")).toBeNull()
  })
})

describe("P5-4 ElementManagementMixin — canMutate guard", () => {
  it("addElement and _pasteElements no-op when canMutate is false", () => {
    const host = makeHost({ canMutate: () => false })
    expect(host.addElement({ type: "process" })).toBeNull()
    host._pasteElements({ elements: [{ id: "n1", type: "process" }], connections: [] })
    expect(host.elements).toEqual([])
    expect(host.onBeforeChange).not.toHaveBeenCalled()
  })
})

describe("P5-5 ElementManagementMixin — unique default labels", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = makeHost() })

  it("numbers a palette-added element whose default label is already used", () => {
    expect(host.addElement({ type: "end", x: 0, y: 0 }).label).toBe("End")
    expect(host.addElement({ type: "end", x: 0, y: 90 }).label).toBe("End 2")
    expect(host.addElement({ type: "end", x: 0, y: 180 }).label).toBe("End 3")
  })

  it("numbers a requested label too, with the translated format", () => {
    host.labels = { uniqueLabelFormat: "{label}（{n}）" }
    host.elements = [{ id: "sf", type: "subflow", label: "子流程：账单" }]
    expect(host.addElement({ type: "subflow", label: "子流程：账单", x: 0, y: 0 }).label).toBe("子流程：账单（2）")
  })
})
