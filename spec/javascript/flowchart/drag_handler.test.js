import { describe, it, expect, vi, beforeEach } from "vitest"
import { DragHandlerMixin } from "flowchart/drag_handler"
import { ConnectionManagerMixin } from "flowchart/connection_manager"

function makeHost(over = {}) {
  const elementLayer = document.createElementNS("http://www.w3.org/2000/svg", "g")
  const guideLayer = document.createElementNS("http://www.w3.org/2000/svg", "g")
  document.body.appendChild(elementLayer)
  return Object.assign(Object.create(DragHandlerMixin), {
    elements: [],
    connections: [],
    selectedElements: [],
    elementLayer,
    guideLayer,
    isDragging: false,
    draggedElement: null,
    draggedElements: null,
    draggedSubTree: null,
    dragStartPosition: null,
    dragOffset: { x: 0, y: 0 },
    dropTargetElement: null,
    onBeforeChange: vi.fn(),
    onchange: vi.fn(),
    updateElementPosition: vi.fn(),
    updateConnections: vi.fn(),
    alignAllElements: vi.fn(),
    alignElementWithParent: vi.fn(),
    alignChildElements: vi.fn(),
    _connectionOrientation: ConnectionManagerMixin._connectionOrientation,
    _portToCardinal: ConnectionManagerMixin._portToCardinal,
    _getOppositePosition: ConnectionManagerMixin._getOppositePosition,
    showConnectionHandles: vi.fn(),
    _selectElement: vi.fn(),
    _isElementSelected: vi.fn(() => false),
    _hideElementTooltip: vi.fn(),
    _hideAlignmentGuides: vi.fn(),
    _hideDropSideIndicator: vi.fn(),
    _clearDropTargetHighlight: vi.fn(),
    _syncDecisionBranches: vi.fn(),
    _getSVGPoint: vi.fn(() => ({ x: 0, y: 0 })),
    ...over,
  })
}

const box = (id, x, y, type = "process") => ({
  id, type, x, y, width: 100, height: 45, properties: {},
})

describe("DragHandlerMixin._finishSingleElementDrag", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = makeHost() })

  it("neither moves nor reconnects after a 3px jitter even when a drop target is set", () => {
    const dragged = box("a", 103, 100)
    const target = box("b", 100, 200)
    host.draggedElement = dragged
    host.dragStartPosition = { x: 100, y: 100 }
    host.dropTargetElement = target
    host.elements = [dragged, target]
    const reconnect = vi.spyOn(host, "_reconnectElement")
    host._finishSingleElementDrag()
    expect(dragged.x).toBe(100)
    expect(dragged.y).toBe(100)
    expect(reconnect).not.toHaveBeenCalled()
    expect(host.onchange).not.toHaveBeenCalled()
  })

  it("reconnects after a 9px drag onto a drop target", () => {
    const dragged = box("a", 109, 100)
    const target = box("b", 100, 200)
    host.draggedElement = dragged
    host.dragStartPosition = { x: 100, y: 100 }
    host.dropTargetElement = target
    host.elements = [dragged, target]
    const reconnect = vi.spyOn(host, "_reconnectElement").mockImplementation(() => {})
    host._finishSingleElementDrag()
    expect(reconnect).toHaveBeenCalledWith(dragged, target)
    expect(host.onchange).toHaveBeenCalled()
  })
})

describe("DragHandlerMixin._reconnectElement insert-between", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = makeHost() })

  it("keeps fromPort/label/matchValue/properties on the upstream decision edge", () => {
    const decision = box("dec", 200, 100, "decision")
    const child = box("child", 200, 300)
    const dragged = box("ins", 200, 200)
    host.elements = [decision, child, dragged]
    host.connections = [{
      id: "c1",
      from: "dec",
      to: "child",
      fromPort: "port_0",
      fromPosition: null,
      toPosition: "top",
      label: "true",
      matchValue: "true",
      properties: { description: "yes-branch", priority: 2 },
    }]
    vi.spyOn(host, "_calculateBestConnectionPositions").mockReturnValue({
      fromPosition: "bottom",
      toPosition: "top",
    })
    vi.spyOn(host, "shiftElementAndSubTree").mockImplementation(() => {})
    host._reconnectElement(dragged, decision)

    const upstream = host.connections.find((c) => c.from === "dec" && c.to === "ins")
    expect(upstream).toMatchObject({
      fromPort: "port_0",
      label: "true",
      matchValue: "true",
      properties: { description: "yes-branch", priority: 2 },
    })
    const downstream = host.connections.find((c) => c.from === "ins" && c.to === "child")
    expect(downstream).toBeTruthy()
    expect(host._syncDecisionBranches).toHaveBeenCalledWith(decision, "ins")
  })

  it("keeps metadata when inserting between a decision and its child from above", () => {
    const decision = box("dec", 200, 100, "decision")
    const child = box("child", 200, 300)
    const dragged = box("ins", 200, 180)
    host.elements = [decision, child, dragged]
    host.connections = [{
      id: "c1",
      from: "dec",
      to: "child",
      fromPort: "port_0",
      fromPosition: null,
      toPosition: "top",
      label: "true",
      matchValue: "true",
      properties: { description: "yes-branch", priority: 2 },
    }]
    vi.spyOn(host, "_calculateBestConnectionPositions").mockReturnValue({
      fromPosition: "top",
      toPosition: "bottom",
    })
    vi.spyOn(host, "shiftElementAndSubTree").mockImplementation(() => {})
    host._reconnectElement(dragged, child)

    const upstream = host.connections.find((c) => c.from === "dec" && c.to === "ins")
    expect(upstream).toMatchObject({
      fromPort: "port_0",
      label: "true",
      matchValue: "true",
      properties: { description: "yes-branch", priority: 2 },
    })
    expect(host._syncDecisionBranches).toHaveBeenCalledWith(decision, "ins")
  })
})

function renderGroup(host, id) {
  const g = document.createElementNS("http://www.w3.org/2000/svg", "g")
  g.setAttribute("data-element-id", id)
  host.elementLayer.appendChild(g)
  return g
}

function liveHost(over = {}) {
  const host = makeHost({
    getDropSide: vi.fn(() => "bottom"),
    _showDropSideIndicator: vi.fn(),
    _hideAlignmentGuides: DragHandlerMixin._hideAlignmentGuides,
    _hideDropSideIndicator: vi.fn(),
    _clearDropTargetHighlight: DragHandlerMixin._clearDropTargetHighlight,
    _setDropHighlight: DragHandlerMixin._setDropHighlight,
    _bindDocumentDragListeners: vi.fn(),
    _unbindDocumentDragListeners: vi.fn(),
    _rejectsDirectedEdge: ConnectionManagerMixin._rejectsDirectedEdge,
    onToast: vi.fn(),
    labels: {
      connectionIntoStartRejected: "A Start element cannot have incoming connections",
      connectionOutOfEndRejected: "An End element cannot have outgoing connections",
    },
    ...over,
  })
  return host
}

describe("DragHandlerMixin._startDrag / _endDrag", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = liveHost() })

  it("starts a single-element drag, dims the group, and records the offset", () => {
    const el = box("a", 40, 60)
    host.elements = [el]
    const g = renderGroup(host, "a")
    host._getSVGPoint.mockReturnValue({ x: 50, y: 80 })
    host._startDrag(el, { clientX: 1, clientY: 2 })
    expect(host.isDragging).toBe(true)
    expect(host.draggedElement).toBe(el)
    expect(host.dragStartPosition).toEqual({ x: 40, y: 60 })
    expect(host.dragOffset).toEqual({ x: 10, y: 20 })
    expect(g.style.opacity).toBe("0.7")
    expect(host.draggedElements).toBeNull()
    expect(host._selectElement).toHaveBeenCalledWith(el)
    expect(host._bindDocumentDragListeners).toHaveBeenCalled()
  })

  it("does not start a drag when canMutate is false", () => {
    const el = box("a", 40, 60)
    host.elements = [el]
    host.canMutate = () => false
    host._startDrag(el, { clientX: 1, clientY: 2 })
    expect(host.isDragging).toBe(false)
    expect(host._bindDocumentDragListeners).not.toHaveBeenCalled()
  })

  it("cancel refreshes connections when _updateConnectionsVisually is present", () => {
    const el = box("a", 40, 60)
    host.elements = [el]
    host.draggedElement = el
    host.dragStartPosition = { x: 10, y: 20 }
    host.isDragging = true
    host._updateConnectionsVisually = vi.fn()
    host._cleanupDragState = vi.fn()
    host._cancelElementDrag()
    expect(host._updateConnectionsVisually).toHaveBeenCalled()
    expect(el.x).toBe(10)
  })

  it("records the dragged element's sub-tree for a single-element drag", () => {
    const a = box("a", 0, 0)
    const b = box("b", 0, 100)
    host.elements = [a, b]
    host.connections = [{ from: "a", to: "b" }]
    host._startDrag(a, {})
    expect(host.draggedSubTree).toEqual([{ id: "b", originalX: 0, originalY: 100 }])
  })

  it("starts a multi-select drag without walking the subtree", () => {
    const a = box("a", 0, 0)
    const b = box("b", 30, 30)
    host.elements = [a, b]
    host.selectedElements = [a, b]
    host._isElementSelected.mockReturnValue(true)
    host._startDrag(a, {})
    expect(host.draggedElements).toHaveLength(2)
    expect(host.draggedSubTree).toBeNull()
    expect(host._selectElement).not.toHaveBeenCalled()
  })

  it("tolerates a missing rendered group", () => {
    const el = box("ghost", 0, 0)
    host.elements = [el]
    expect(() => host._startDrag(el, {})).not.toThrow()
    expect(host.isDragging).toBe(true)
  })

  it("_endDrag is a no-op without a dragged element", () => {
    const finish = vi.spyOn(host, "_finishSingleElementDrag")
    host._endDrag()
    expect(finish).not.toHaveBeenCalled()
  })

  it("_endDrag finishes a single-element drag then cleans up", () => {
    const a = box("a", 109, 124)
    host.draggedElement = a
    host.dragStartPosition = { x: 100, y: 100 }
    host.draggedElements = null
    host.elements = [a]
    host._endDrag()
    expect(a.x).toBe(105)
    expect(host.isDragging).toBe(false)
  })

  it("_endDrag finishes a multi-element drag then cleans up", () => {
    const a = box("a", 16, 16)
    const b = box("b", 40, 40)
    host.draggedElement = a
    host.dragStartPosition = { x: 0, y: 0 }
    host.draggedElements = [
      { element: a, startX: 0, startY: 0 },
      { element: b, startX: 30, startY: 30 },
    ]
    host.selectedElements = [a]
    renderGroup(host, "a")
    host._endDrag()
    expect(a.x).toBe(15)
    expect(b.x).toBe(45)
    expect(host.alignAllElements).toHaveBeenCalled()
    expect(host.onchange).toHaveBeenCalled()
    expect(host.isDragging).toBe(false)
    expect(host.draggedElement).toBeNull()
    expect(host.showConnectionHandles).toHaveBeenCalledWith([a])
  })
})

describe("DragHandlerMixin._finishSingleElementDrag branches", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = liveHost() })

  it("restores a moved subtree on a sub-threshold drag, skipping missing children", () => {
    const dragged = box("a", 104, 100)
    const child = box("c", 200, 200)
    host.draggedElement = dragged
    host.dragStartPosition = { x: 100, y: 100 }
    host.draggedSubTree = [
      { id: "c", originalX: 10, originalY: 20 },
      { id: "missing", originalX: 1, originalY: 2 },
    ]
    host.elements = [dragged, child]
    host._finishSingleElementDrag()
    expect(dragged.x).toBe(100)
    expect(dragged.y).toBe(100)
    expect(child.x).toBe(10)
    expect(child.y).toBe(20)
    expect(host.updateConnections).toHaveBeenCalled()
    expect(host.onchange).not.toHaveBeenCalled()
  })

  it("snaps a free-moved element without a parent to the grid and realigns its children", () => {
    const dragged = box("a", 109, 124)
    host.draggedElement = dragged
    host.dragStartPosition = { x: 100, y: 100 }
    host.elements = [dragged]
    host._finishSingleElementDrag()
    expect(dragged.x).toBe(105) // snapToGrid(109, 15)
    expect(dragged.y).toBe(120) // snapToGrid(124, 15)
    expect(host.alignChildElements).toHaveBeenCalledWith(dragged)
    expect(host.onchange).toHaveBeenCalled()
  })

  it("carries the sub-tree by the anchor's final delta", () => {
    const dragged = box("a", 109, 124)
    const child = box("c", 0, 0)
    host.draggedElement = dragged
    host.dragStartPosition = { x: 100, y: 100 }
    host.draggedSubTree = [{ id: "c", originalX: 100, originalY: 200 }]
    host.elements = [dragged, child]
    host._finishSingleElementDrag()
    expect(child).toMatchObject({ x: 105, y: 220 })
  })

  it("aligns X with a vertical parent and Y with a horizontal parent", () => {
    const parent = box("p", 300, 10)
    const dragged = box("a", 109, 200)
    host.draggedElement = dragged
    host.dragStartPosition = { x: 100, y: 100 }
    host.elements = [parent, dragged]
    host.connections = [{ id: "c", from: "p", to: "a", fromPosition: "bottom", toPosition: "top" }]
    host._finishSingleElementDrag()
    expect(dragged.x).toBe(300)
    expect(dragged.y).toBe(195) // snap(200)

    dragged.x = 200
    dragged.y = 109
    host.dragStartPosition = { x: 100, y: 100 }
    host.connections = [{ id: "c", from: "p", to: "a", fromPosition: "right", toPosition: "left" }]
    host._finishSingleElementDrag()
    expect(dragged.x).toBe(195) // snap(200)
    expect(dragged.y).toBe(10)
  })

  it("falls back to grid snap when the parent connection is diagonal or the parent is missing", () => {
    const dragged = box("a", 109, 124)
    host.draggedElement = dragged
    host.dragStartPosition = { x: 100, y: 100 }
    host.elements = [dragged]
    host.connections = [{ id: "c", from: "ghost", to: "a", fromPosition: "bottom", toPosition: "top" }]
    host._finishSingleElementDrag()
    expect(dragged).toMatchObject({ x: 105, y: 120 })

    dragged.x = 109
    dragged.y = 124
    host.dragStartPosition = { x: 100, y: 100 }
    host.elements = [box("p", 0, 0), dragged]
    host.connections = [{ id: "c", from: "p", to: "a", fromPosition: "right", toPosition: "top" }]
    host._finishSingleElementDrag()
    expect(dragged).toMatchObject({ x: 105, y: 120 })
  })

  it("places an element dropped onto a target next to it and aligns it with its new parent", () => {
    const dragged = box("a", 110, 190)
    const target = box("t", 100, 100)
    host.draggedElement = dragged
    host.dragStartPosition = { x: 400, y: 400 }
    host.dropTargetElement = target
    host.elements = [dragged, target]
    vi.spyOn(host, "_reconnectElement").mockImplementation(() => {})
    host._finishSingleElementDrag()
    expect(dragged).toMatchObject({ x: 100, y: 195 }) // snap(100 + 22.5 + 50 + 22.5)
    expect(host.alignElementWithParent).toHaveBeenCalledWith(dragged)
    expect(host.alignChildElements).toHaveBeenCalledWith(dragged)
  })

  it("syncs decision branches when the drop target is a decision", () => {
    const dragged = box("a", 200, 200)
    const target = box("d", 200, 80, "decision")
    host.draggedElement = dragged
    host.dragStartPosition = { x: 100, y: 100 }
    host.dropTargetElement = target
    host.elements = [dragged, target]
    vi.spyOn(host, "_reconnectElement").mockImplementation(() => {})
    host._finishSingleElementDrag()
    expect(host._syncDecisionBranches).toHaveBeenCalledWith(target, "a")
    expect(host.alignElementWithParent).toHaveBeenCalledWith(dragged)
    expect(host.dropTargetElement).toBeNull()
  })
})

describe("DragHandlerMixin movement helpers", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = liveHost() })

  it("_updateSubTreePositions no-ops without a subtree and skips missing children", () => {
    host._updateSubTreePositions(10, 10)
    expect(host.updateElementPosition).not.toHaveBeenCalled()
    const child = box("c", 0, 0)
    host.elements = [child]
    host.draggedSubTree = [
      { id: "c", originalX: 5, originalY: 6 },
      { id: "gone", originalX: 1, originalY: 2 },
    ]
    host._updateSubTreePositions(10, 20)
    expect(child).toMatchObject({ x: 15, y: 26 })
  })

  it("_moveElementVisually writes x/y", () => {
    const el = box("a", 0, 0)
    host._moveElementVisually(el, 8, 9)
    expect(el).toMatchObject({ x: 8, y: 9 })
  })

  it("_moveSubTreeVisually no-ops without a start or subtree, else follows the anchor", () => {
    host._moveSubTreeVisually(10, 10)
    host.draggedSubTree = [{ id: "c", originalX: 0, originalY: 0 }]
    host._moveSubTreeVisually(10, 10)
    expect(host.updateElementPosition).not.toHaveBeenCalled()
    host.dragStartPosition = { x: 0, y: 0 }
    const child = box("c", 0, 0)
    host.elements = [child]
    host.draggedSubTree = [{ id: "c", originalX: 2, originalY: 3 }]
    host._moveSubTreeVisually(12, 13)
    expect(child).toMatchObject({ x: 14, y: 16 })
  })

  it("_cleanupDragState restores opacity and skips handle refresh when nothing is selected", () => {
    const el = box("a", 0, 0)
    host.draggedElement = el
    host.selectedElements = []
    renderGroup(host, "a").style.opacity = "0.7"
    host._cleanupDragState()
    expect(host.elementLayer.querySelector('[data-element-id="a"]').style.opacity).toBe("")
    expect(host.showConnectionHandles).not.toHaveBeenCalled()
  })

  it("_cleanupDragState tolerates a missing group", () => {
    host.draggedElement = box("ghost", 0, 0)
    expect(() => host._cleanupDragState()).not.toThrow()
  })

  it("_cancelElementDrag is a no-op when not dragging", () => {
    host.isDragging = false
    host._cancelElementDrag()
    expect(host._unbindDocumentDragListeners).not.toHaveBeenCalled()
  })

  it("_cancelElementDrag restores a multi-select group", () => {
    const a = box("a", 50, 50)
    const b = box("b", 80, 80)
    host.isDragging = true
    host.draggedElement = a
    host.draggedElements = [
      { element: a, startX: 10, startY: 20 },
      { element: b, startX: 30, startY: 40 },
    ]
    host._cancelElementDrag()
    expect(a).toMatchObject({ x: 10, y: 20 })
    expect(b).toMatchObject({ x: 30, y: 40 })
    expect(host.isDragging).toBe(false)
    expect(host._unbindDocumentDragListeners).toHaveBeenCalled()
  })

  it("_cancelElementDrag restores a single element and its subtree, skipping missing children", () => {
    const a = box("a", 50, 50)
    const c = box("c", 90, 90)
    host.elements = [a, c]
    host.isDragging = true
    host.draggedElement = a
    host.dragStartPosition = { x: 10, y: 20 }
    host.draggedSubTree = [
      { id: "c", originalX: 1, originalY: 2 },
      { id: "gone", originalX: 0, originalY: 0 },
    ]
    host._cancelElementDrag()
    expect(a).toMatchObject({ x: 10, y: 20 })
    expect(c).toMatchObject({ x: 1, y: 2 })
    expect(host.isDragging).toBe(false)
    expect(host.draggedSubTree).toBeNull()
  })
})

describe("DragHandlerMixin._getSubTreeElements / _getDraggedGroupExtent", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = liveHost() })

  it("walks children, skips cycles back to the root, and ignores dangling edges", () => {
    const a = box("a", 0, 0)
    const b = box("b", 10, 80)
    const c = box("c", 10, 160)
    host.elements = [a, b, c]
    host.connections = [
      { from: "a", to: "b" },
      { from: "b", to: "c" },
      { from: "c", to: "a" }, // cycle back to root
      { from: "a", to: "ghost" },
      { from: "other", to: "b" },
    ]
    const tree = host._getSubTreeElements("a")
    expect(tree.map((t) => t.id)).toEqual(["b", "c"])
    expect(host._getSubTreeElements("a", new Set(["a"]))).toEqual([])
  })

  it("measures vertical and horizontal extents, ignoring missing subtree ids", () => {
    const a = box("a", 100, 100)
    const below = box("b", 100, 200)
    const right = box("c", 220, 100)
    host.elements = [a, below, right]
    host.connections = [{ from: "a", to: "b" }, { from: "a", to: "c" }]
    expect(host._getDraggedGroupExtent(a, "bottom")).toBe((200 + 22.5) - 100)
    expect(host._getDraggedGroupExtent(a, "top")).toBe(a.height / 2)
    expect(host._getDraggedGroupExtent(a, "right")).toBe((220 + 50) - 100)
    expect(host._getDraggedGroupExtent(a, "left")).toBe(a.width / 2)

    vi.spyOn(host, "_getSubTreeElements").mockReturnValue([{ id: "gone" }])
    expect(host._getDraggedGroupExtent(a, "bottom")).toBe(a.height / 2)
  })
})

describe("DragHandlerMixin drop-target helpers", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = liveHost() })

  it("_findDropTargetElement prefers a direct hit and excludes the dragged subtree", () => {
    const dragged = box("a", 0, 0)
    const child = box("child", 400, 400)
    const hit = box("hit", 100, 100)
    host.draggedElement = dragged
    host.elements = [dragged, child, hit]
    expect(host._findDropTargetElement(100, 100).id).toBe("hit")
    expect(host._findDropTargetElement(0, 0)).toBeNull()
    expect(host._findDropTargetElement(400, 400).id).toBe("child")
    host.draggedSubTree = [{ id: "child" }]
    expect(host._findDropTargetElement(400, 400)).toBeNull()
  })

  it("_findDropTargetElement falls back to the nearest port within 80px", () => {
    const far = box("far", 0, 0)
    host.elements = [far]
    // top port of far is (0, -22.5); a point 70px above that is still within 80
    expect(host._findDropTargetElement(0, -90).id).toBe("far")
    expect(host._findDropTargetElement(1000, 1000)).toBeNull()
  })

  it("_highlightDropTarget switches, updates, and clears targets", () => {
    const a = box("a", 0, 0)
    const b = box("b", 200, 0)
    host.elements = [a, b]
    renderGroup(host, "a")
    renderGroup(host, "b")
    host._highlightDropTarget(200, 0)
    expect(host.dropTargetElement.id).toBe("b")
    host._highlightDropTarget(200, 5) // same target
    expect(host.dropTargetElement.id).toBe("b")
    host._highlightDropTarget(0, 0) // switch
    expect(host.dropTargetElement.id).toBe("a")
    vi.spyOn(host, "_findDropTargetElement").mockReturnValue(null)
    host._highlightDropTarget(999, 999)
    expect(host.dropTargetElement).toBeNull()
  })

  it("_clearDropTargetHighlight no-ops without a target and clears an existing one", () => {
    host._clearDropTargetHighlight()
    expect(host._hideDropSideIndicator).toHaveBeenCalled()
    const el = box("a", 0, 0)
    host.dropTargetElement = el
    renderGroup(host, "a")
    host._clearDropTargetHighlight()
    expect(host.dropTargetElement).toBeNull()
  })

  it("_setDropHighlight is a no-op when the group is missing", () => {
    expect(() => host._setDropHighlight(box("ghost", 0, 0), true)).not.toThrow()
  })

  it("_getParentConnection finds the incoming edge", () => {
    host.connections = [{ id: "c", to: "a" }]
    expect(host._getParentConnection("a").id).toBe("c")
    expect(host._getParentConnection("z")).toBeUndefined()
  })
})

describe("DragHandlerMixin._reconnectElement remaining branches", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = liveHost() })

  it("removes an old parent edge and a pre-existing direct edge before reconnecting", () => {
    const parent = box("p", 0, 0)
    const dragged = box("d", 0, 120)
    host.elements = [parent, dragged]
    host.connections = [
      { id: "old", from: "x", to: "d" },
      { id: "direct", from: "p", to: "d" },
    ]
    host._reconnectElement(dragged, parent)
    expect(host.connections.some((c) => c.id === "old" || c.id === "direct")).toBe(false)
    expect(host.connections.some((c) => c.from === "p" && c.to === "d")).toBe(true)
  })

  it("preserves a reverse-direction A→B edge when dropping B onto A", () => {
    const parent = box("p", 0, 0)
    const dragged = box("d", 0, 120)
    host.elements = [parent, dragged]
    host.connections = [{ id: "rev", from: "d", to: "p" }]
    host._reconnectElement(dragged, parent)
    expect(host.connections.some((c) => c.id === "rev" && c.from === "d" && c.to === "p")).toBe(true)
    expect(host.connections.some((c) => c.from === "p" && c.to === "d")).toBe(true)
  })

  it("rejects dropping a Start onto another element and leaves the graph unchanged", () => {
    const parent = box("p", 0, 0)
    const start = box("s", 0, 120, "start")
    const existing = [{ id: "keep", from: "x", to: "s" }]
    host.elements = [parent, start]
    host.connections = existing.map((c) => ({ ...c }))
    host._reconnectElement(start, parent)
    expect(host.connections).toEqual(existing)
    expect(host.onToast).toHaveBeenCalledWith("A Start element cannot have incoming connections")
    expect(host.updateConnections).not.toHaveBeenCalled()
  })

  it("rejects dropping an element onto an End and leaves the graph unchanged", () => {
    const end = box("e", 0, 0, "end")
    const dragged = box("d", 0, 120)
    const existing = [{ id: "keep", from: "x", to: "d" }]
    host.elements = [end, dragged]
    host.connections = existing.map((c) => ({ ...c }))
    host._reconnectElement(dragged, end)
    expect(host.connections).toEqual(existing)
    expect(host.onToast).toHaveBeenCalledWith("An End element cannot have outgoing connections")
    expect(host.updateConnections).not.toHaveBeenCalled()
  })

  it("rejects insert-between that would create an incoming Start edge", () => {
    const parent = box("p", 200, 200)
    const child = box("c", 200, 320)
    const start = box("s", 200, 260, "start")
    const existing = [{ id: "edge", from: "p", to: "c", fromPosition: "bottom", toPosition: "top" }]
    host.elements = [parent, child, start]
    host.connections = existing.map((c) => ({ ...c }))
    vi.spyOn(host, "_calculateBestConnectionPositions").mockReturnValue({
      fromPosition: "bottom",
      toPosition: "top",
    })
    host._reconnectElement(start, parent)
    expect(host.connections).toEqual(existing)
    expect(host.onToast).toHaveBeenCalledWith("A Start element cannot have incoming connections")
    expect(host.updateConnections).not.toHaveBeenCalled()
  })

  it("rejects insert-between that would create an outgoing End edge", () => {
    const parent = box("p", 200, 200)
    const child = box("c", 200, 320)
    const end = box("e", 200, 260, "end")
    const existing = [{ id: "edge", from: "p", to: "c", fromPosition: "bottom", toPosition: "top" }]
    host.elements = [parent, child, end]
    host.connections = existing.map((c) => ({ ...c }))
    vi.spyOn(host, "_calculateBestConnectionPositions").mockReturnValue({
      fromPosition: "bottom",
      toPosition: "top",
    })
    host._reconnectElement(end, parent)
    expect(host.connections).toEqual(existing)
    expect(host.onToast).toHaveBeenCalledWith("An End element cannot have outgoing connections")
    expect(host.updateConnections).not.toHaveBeenCalled()
  })

  it("rejects an incoming insert that would connect into Start", () => {
    const child = box("c", 200, 200)
    const start = box("s", 200, 140, "start")
    const grand = box("g", 200, 40)
    const existing = [{ id: "edge", from: "g", to: "c", fromPosition: "bottom", toPosition: "top" }]
    host.elements = [child, start, grand]
    host.connections = existing.map((c) => ({ ...c }))
    vi.spyOn(host, "_calculateBestConnectionPositions").mockReturnValue({
      fromPosition: "top",
      toPosition: "bottom",
    })
    host._reconnectElement(start, child)
    expect(host.connections).toEqual(existing)
    expect(host.onToast).toHaveBeenCalledWith("A Start element cannot have incoming connections")
    expect(host.updateConnections).not.toHaveBeenCalled()
  })

  it("rejects an incoming insert that would connect out of End", () => {
    const child = box("c", 200, 200)
    const end = box("e", 200, 140, "end")
    const grand = box("g", 200, 40)
    const existing = [{ id: "edge", from: "g", to: "c", fromPosition: "bottom", toPosition: "top" }]
    host.elements = [child, end, grand]
    host.connections = existing.map((c) => ({ ...c }))
    vi.spyOn(host, "_calculateBestConnectionPositions").mockReturnValue({
      fromPosition: "top",
      toPosition: "bottom",
    })
    host._reconnectElement(end, child)
    expect(host.connections).toEqual(existing)
    expect(host.onToast).toHaveBeenCalledWith("An End element cannot have outgoing connections")
    expect(host.updateConnections).not.toHaveBeenCalled()
  })

  it("inserts on each outgoing drop side and skips a dangling child id", () => {
    const parent = box("p", 200, 200)
    const child = box("c", 200, 320)
    const dragged = box("d", 200, 260)
    host.elements = [parent, child, dragged]
    for (const side of ["bottom", "top", "right", "left"]) {
      host.connections = [{
        id: "edge",
        from: "p",
        to: "c",
        fromPosition: side,
        toPosition: "top",
      }]
      vi.spyOn(host, "_calculateBestConnectionPositions").mockReturnValue({
        fromPosition: side,
        toPosition: "top",
      })
      host._reconnectElement(dragged, parent)
      expect(host.connections.some((c) => c.from === "p" && c.to === "d")).toBe(true)
      host._calculateBestConnectionPositions.mockRestore()
    }

    host.connections = [{ id: "ghost", from: "p", to: "missing", fromPosition: "bottom" }]
    vi.spyOn(host, "_calculateBestConnectionPositions").mockReturnValue({
      fromPosition: "bottom",
      toPosition: "top",
    })
    host._reconnectElement(dragged, parent)
    expect(host.connections.some((c) => c.from === "p" && c.to === "d")).toBe(true)
  })

  it("inserts on each incoming drop side and skips a dangling grandparent", () => {
    const child = box("c", 200, 200)
    const dragged = box("d", 200, 140)
    const grand = box("g", 200, 40)
    host.elements = [child, dragged, grand]
    for (const side of ["top", "bottom", "left", "right"]) {
      host.connections = [{
        id: "edge",
        from: "g",
        to: "c",
        fromPosition: "bottom",
        toPosition: side,
      }]
      vi.spyOn(host, "_calculateBestConnectionPositions").mockReturnValue({
        fromPosition: side,
        toPosition: "top",
      })
      host._reconnectElement(dragged, child)
      expect(host.connections.some((c) => c.from === "g" && c.to === "d")).toBe(true)
      host._calculateBestConnectionPositions.mockRestore()
    }

    host.connections = [{ id: "ghost", from: "missing", to: "c", toPosition: "top" }]
    vi.spyOn(host, "_calculateBestConnectionPositions").mockReturnValue({
      fromPosition: "top",
      toPosition: "bottom",
    })
    host._reconnectElement(dragged, child)
    expect(host.connections.some((c) => c.from === "c" && c.to === "d")).toBe(true)
  })

  it("pushes the existing child and its sub-tree away to make room for an outgoing insert", () => {
    const parent = box("p", 0, 0)
    const child = box("c", 0, 120)
    const grandChild = box("gc", 0, 240)
    const dragged = box("d", 0, 60)
    host.elements = [parent, child, grandChild, dragged]
    host.connections = [
      { id: "edge", from: "p", to: "c", fromPosition: "bottom", toPosition: "top" },
      { id: "down", from: "c", to: "gc", fromPosition: "bottom", toPosition: "top" },
    ]
    vi.spyOn(host, "_calculateBestConnectionPositions").mockReturnValue({ fromPosition: "bottom", toPosition: "top" })
    host._reconnectElement(dragged, parent)
    // gap = snap(22.5 dragged extent + 50 spacing + 22.5 child half-height) = 90
    expect(child.y).toBe(210)
    expect(grandChild.y).toBe(330)
    expect(host.connections.some((c) => c.from === "d" && c.to === "c")).toBe(true)
  })

  it("pushes the drop target away from its parent for an incoming insert", () => {
    const grand = box("g", 0, 0)
    const target = box("t", 0, 120)
    const dragged = box("d", 0, 60)
    host.elements = [grand, target, dragged]
    host.connections = [{ id: "edge", from: "g", to: "t", fromPosition: "bottom", toPosition: "top" }]
    vi.spyOn(host, "_calculateBestConnectionPositions").mockReturnValue({ fromPosition: "top", toPosition: "bottom" })
    host._reconnectElement(dragged, target)
    expect(target.y).toBe(210)
    expect(host.connections.some((c) => c.from === "g" && c.to === "d")).toBe(true)
    expect(host.connections.some((c) => c.from === "d" && c.to === "t")).toBe(true)
  })

  it("treats a position-less incoming edge as landing on top", () => {
    const grand = box("g", 0, 0)
    const child = box("c", 0, 120)
    const dragged = box("d", 0, 60)
    host.elements = [grand, child, dragged]
    host.connections = [{ id: "edge", from: "g", to: "c" }] // no toPosition/fromPosition
    vi.spyOn(host, "_calculateBestConnectionPositions").mockReturnValue({
      fromPosition: "top",
      toPosition: "bottom",
    })
    host._reconnectElement(dragged, child)
    const upstream = host.connections.find((c) => c.from === "g" && c.to === "d")
    expect(upstream).toBeTruthy()
    expect(upstream.fromPosition).toBe("bottom")
  })

  it("omits blank matchValue/label when carrying an upstream edge", () => {
    const parent = box("p", 0, 0)
    const child = box("c", 0, 120)
    const dragged = box("d", 0, 60)
    host.elements = [parent, child, dragged]
    host.connections = [{
      id: "edge",
      from: "p",
      to: "c",
      fromPosition: "bottom",
      label: "",
      matchValue: "",
    }]
    vi.spyOn(host, "_calculateBestConnectionPositions").mockReturnValue({
      fromPosition: "bottom",
      toPosition: "top",
    })
    host._reconnectElement(dragged, parent)
    const upstream = host.connections.find((c) => c.from === "p" && c.to === "d")
    expect(upstream.label).toBeUndefined()
    expect(upstream.matchValue).toBeUndefined()
  })
})

describe("DragHandlerMixin geometry helpers", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = liveHost() })

  it("_calculateBestConnectionPositions covers all four sides", () => {
    const from = box("a", 0, 0)
    expect(host._calculateBestConnectionPositions(from, box("b", 0, 50))).toEqual({ fromPosition: "bottom", toPosition: "top" })
    expect(host._calculateBestConnectionPositions(from, box("b", 0, -50))).toEqual({ fromPosition: "top", toPosition: "bottom" })
    expect(host._calculateBestConnectionPositions(from, box("b", 50, 0))).toEqual({ fromPosition: "right", toPosition: "left" })
    expect(host._calculateBestConnectionPositions(from, box("b", -50, 0))).toEqual({ fromPosition: "left", toPosition: "right" })
  })

  it("_calculateDropPosition places above/below and left/right of the target, in line with it", () => {
    const target = box("t", 100, 100)
    const dropped = box("d", 0, 0)
    expect(host._calculateDropPosition(target, dropped, { x: 100, y: 200 })).toEqual({ x: 100, y: 195 })
    expect(host._calculateDropPosition(target, dropped, { x: 100, y: 0 })).toEqual({ x: 100, y: 0 })
    expect(host._calculateDropPosition(target, dropped, { x: 200, y: 100 })).toEqual({ x: 255, y: 100 })
    expect(host._calculateDropPosition(target, dropped, { x: 0, y: 100 })).toEqual({ x: -45, y: 100 })
  })

  it("_showAlignmentGuides draws matching vertical and horizontal guides", () => {
    const a = box("a", 0, 0)
    const b = box("b", 4, 4)
    host.elements = [a, b]
    host._showAlignmentGuides(a, 4, 4)
    expect(host.guideLayer.childNodes.length).toBe(2)
    host._hideAlignmentGuides()
    expect(host.guideLayer.childNodes.length).toBe(0)
  })

  it("shiftElementAndSubTree snaps the delta and moves descendants, skipping missing ids", () => {
    const a = box("a", 0, 0)
    const b = box("b", 15, 15)
    host.elements = [a, b]
    host.connections = [{ from: "a", to: "b" }, { from: "a", to: "ghost" }]
    host.shiftElementAndSubTree(a, 16, 16)
    expect(a.x).toBe(15)
    expect(a.y).toBe(15)
    expect(b.x).toBe(30)
    expect(b.y).toBe(30)
  })
})
