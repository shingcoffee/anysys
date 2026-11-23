import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { FlowchartCanvas } from "flowchart/canvas"
import { GRID_SIZE } from "flowchart/constants"

// FlowchartCanvas wires a live SVG canvas. In happy-dom we CAN construct it
// (SVG nodes + document listeners are supported) and assert its structural setup
// and keyboard-shortcut dispatch. Pointer/geometry engines (drag/resize/zoom math)
// depend on real layout (getBoundingClientRect) and are Playwright-covered — we
// only assert that shortcut handlers invoke the right callbacks, not pixel math.

function mountCanvas() {
  const container = document.createElement("div")
  const parent = document.createElement("div")
  parent.appendChild(container)
  document.body.appendChild(parent)
  return new FlowchartCanvas(container)
}

const keydown = (opts) => document.body.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, cancelable: true, ...opts }))
const keyup = (opts) => document.body.dispatchEvent(new KeyboardEvent("keyup", { bubbles: true, cancelable: true, ...opts }))

describe("FlowchartCanvas construction", () => {
  let canvas
  beforeEach(() => { document.body.innerHTML = ""; canvas = mountCanvas() })
  afterEach(() => canvas.destroy())

  it("replaces the container with an .flowchart-svg element", () => {
    expect(canvas.svg.tagName.toLowerCase()).toBe("svg")
    expect(canvas.svg.getAttribute("class")).toBe("flowchart-svg")
    expect(canvas.canvas).toBe(canvas.svg)
  })

  it("creates all named layers", () => {
    for (const name of ["grid", "connection", "element", "handle", "guide", "selection"]) {
      expect(canvas[`${name}Layer`]).toBeTruthy()
      expect(canvas.svg.querySelector(`.${name}-layer`)).toBe(canvas[`${name}Layer`])
    }
  })

  it("instantiates the sub-managers", () => {
    expect(canvas.zoomPanManager).toBeTruthy()
    expect(canvas.clipboardManager).toBeTruthy()
    expect(canvas.alignmentManager).toBeTruthy()
    expect(canvas.layoutManager).toBeTruthy()
  })

  it("initializes default data + state", () => {
    expect(canvas.elements).toEqual([])
    expect(canvas.connections).toEqual([])
    expect(canvas.selectedElements).toEqual([])
    expect(canvas.connectionRouting).toBe("orthogonal")
    expect(canvas.isReadOnly).toBe(false)
    expect(canvas.isDragging).toBe(false)
    expect(canvas.isDrawingConnection).toBe(false)
    expect(canvas.elementSchemas).toBeTruthy()
  })

  it("canMutate is false when read-only or previewing a subflow", () => {
    expect(canvas.canMutate()).toBe(true)
    canvas.previewMode = true
    expect(canvas.canMutate()).toBe(false)
    canvas.previewMode = false
    canvas.isReadOnly = true
    expect(canvas.canMutate()).toBe(false)
  })

  it("does not expose legacy Join drag alignment behavior", () => {
    expect(canvas._findNearestParentConnection).toBeUndefined()
  })
})

describe("FlowchartCanvas keyboard shortcuts", () => {
  let canvas
  beforeEach(() => { document.body.innerHTML = ""; canvas = mountCanvas() })
  afterEach(() => canvas.destroy())

  it("ignores shortcuts while typing in inputs", () => {
    canvas.onundo = vi.fn()
    const input = document.createElement("input")
    document.body.appendChild(input)
    input.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "z", ctrlKey: true }))
    expect(canvas.onundo).not.toHaveBeenCalled()
  })

  it("Ctrl+Z triggers undo, Ctrl+Y triggers redo", () => {
    canvas.onundo = vi.fn(); canvas.onredo = vi.fn()
    keydown({ key: "z", ctrlKey: true })
    keydown({ key: "y", ctrlKey: true })
    expect(canvas.onundo).toHaveBeenCalledOnce()
    expect(canvas.onredo).toHaveBeenCalledOnce()
  })

  it("Ctrl+Shift+Z also triggers redo", () => {
    canvas.onredo = vi.fn()
    keydown({ key: "z", ctrlKey: true, shiftKey: true })
    expect(canvas.onredo).toHaveBeenCalledOnce()
  })

  it("Ctrl+F requests search", () => {
    canvas.onSearchRequested = vi.fn()
    keydown({ key: "f", ctrlKey: true })
    expect(canvas.onSearchRequested).toHaveBeenCalledOnce()
  })

  it("Ctrl+S / Cmd+S request a save and suppress the browser's save dialog", () => {
    canvas.onSaveRequested = vi.fn()
    expect(keydown({ key: "s", ctrlKey: true })).toBe(false)
    expect(keydown({ key: "S", metaKey: true, shiftKey: true })).toBe(false)
    expect(canvas.onSaveRequested).toHaveBeenCalledTimes(2)
  })

  it("Ctrl+S saves even while typing in a field", () => {
    canvas.onSaveRequested = vi.fn()
    const input = document.createElement("input")
    document.body.appendChild(input)
    const event = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "s", ctrlKey: true })
    input.dispatchEvent(event)
    expect(event.defaultPrevented).toBe(true)
    expect(canvas.onSaveRequested).toHaveBeenCalledOnce()
  })

  it("Ctrl+S without a save callback still suppresses the dialog", () => {
    expect(keydown({ key: "s", ctrlKey: true })).toBe(false)
  })

  it("a plain S keystroke is not a save", () => {
    canvas.onSaveRequested = vi.fn()
    keydown({ key: "s" })
    expect(canvas.onSaveRequested).not.toHaveBeenCalled()
  })

  it("Ctrl+C copies when elements are selected", () => {
    canvas.selectedElements = [{ id: "a" }]
    const copy = vi.spyOn(canvas.clipboardManager, "copy").mockReturnValue(true)
    keydown({ key: "c", ctrlKey: true })
    expect(copy).toHaveBeenCalledOnce()
  })

  it("does not delete on Backspace when a sidebar button is focused", () => {
    canvas.selectedElements = [{ id: "a" }]
    const del = vi.spyOn(canvas, "_deleteSelectedElements").mockImplementation(() => {})
    const sidebar = document.createElement("aside")
    const button = document.createElement("button")
    sidebar.appendChild(button)
    document.body.appendChild(sidebar)
    button.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "Backspace" }))
    expect(del).not.toHaveBeenCalled()
  })

  it("does not preventDefault Space when a sidebar button is focused", () => {
    const sidebar = document.createElement("aside")
    const button = document.createElement("button")
    sidebar.appendChild(button)
    document.body.appendChild(sidebar)
    const event = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: " " })
    button.dispatchEvent(event)
    expect(event.defaultPrevented).toBe(false)
    expect(canvas.zoomPanManager.isSpaceHeld).toBe(false)
  })

  it("does not copy elements on Ctrl+C when focus is outside the canvas", () => {
    canvas.selectedElements = [{ id: "a" }]
    const copy = vi.spyOn(canvas.clipboardManager, "copy").mockReturnValue(true)
    const sidebar = document.createElement("aside")
    const button = document.createElement("button")
    sidebar.appendChild(button)
    document.body.appendChild(sidebar)
    button.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "c", ctrlKey: true }))
    expect(copy).not.toHaveBeenCalled()
  })

  it("treats a keydown whose target is inside the SVG as in-canvas", () => {
    canvas.selectedElements = [{ id: "a" }]
    const copy = vi.spyOn(canvas.clipboardManager, "copy").mockReturnValue(true)
    canvas.svg.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "c", ctrlKey: true }))
    expect(copy).toHaveBeenCalledOnce()
  })

  it("Ctrl+V pastes when the clipboard has content (and not read-only)", () => {
    vi.spyOn(canvas.clipboardManager, "hasContent", "get").mockReturnValue(true)
    vi.spyOn(canvas.clipboardManager, "paste").mockReturnValue(null)
    const paste = vi.spyOn(canvas, "_pasteElements")
    keydown({ key: "v", ctrlKey: true })
    expect(paste).toHaveBeenCalledOnce()
  })

  it("Ctrl+V is suppressed in read-only mode", () => {
    canvas.isReadOnly = true
    vi.spyOn(canvas.clipboardManager, "hasContent", "get").mockReturnValue(true)
    const paste = vi.spyOn(canvas, "_pasteElements")
    keydown({ key: "v", ctrlKey: true })
    expect(paste).not.toHaveBeenCalled()
  })

  it("Space enables pan mode; releasing it disables it", () => {
    keydown({ key: " " })
    expect(canvas.zoomPanManager.isSpaceHeld).toBe(true)
    expect(canvas.svg.style.cursor).toBe("grab")
    keyup({ key: " " })
    expect(canvas.zoomPanManager.isSpaceHeld).toBe(false)
    expect(canvas.svg.style.cursor).toBe("default")
  })

  it("Delete removes the selected connection through _handleDelete", () => {
    canvas.selectedConnectionId = "c1"
    canvas.onchange = vi.fn()
    const del = vi.spyOn(canvas, "deleteConnection").mockImplementation(() => {})
    keydown({ key: "Delete" })
    expect(del).toHaveBeenCalledWith("c1")
    expect(canvas.selectedConnectionId).toBeNull()
    expect(canvas.onchange).toHaveBeenCalled()
  })

  it("Delete removes selected elements when no connection is selected", () => {
    canvas.selectedElements = [{ id: "a" }]
    canvas.onchange = vi.fn()
    const del = vi.spyOn(canvas, "_deleteSelectedElements").mockImplementation(() => {})
    keydown({ key: "Backspace" })
    expect(del).toHaveBeenCalledOnce()
  })

  it("Delete is suppressed in read-only mode", () => {
    canvas.isReadOnly = true
    canvas.selectedElements = [{ id: "a" }]
    const del = vi.spyOn(canvas, "_deleteSelectedElements")
    keydown({ key: "Delete" })
    expect(del).not.toHaveBeenCalled()
  })

  it("Ctrl+= zooms in and reports the change", () => {
    canvas.onZoomChange = vi.fn()
    const zin = vi.spyOn(canvas.zoomPanManager, "zoomIn")
    keydown({ key: "=", ctrlKey: true })
    expect(zin).toHaveBeenCalled()
    expect(canvas.onZoomChange).toHaveBeenCalled()
  })

  it("Ctrl+- zooms out and reports the change", () => {
    canvas.onZoomChange = vi.fn()
    const zout = vi.spyOn(canvas.zoomPanManager, "zoomOut")
    keydown({ key: "-", ctrlKey: true })
    expect(zout).toHaveBeenCalled()
    expect(canvas.onZoomChange).toHaveBeenCalled()
  })

  it("Ctrl+0 fits to content and reports the change", () => {
    canvas.onZoomChange = vi.fn()
    const fit = vi.spyOn(canvas.zoomPanManager, "fitToContent")
    keydown({ key: "0", ctrlKey: true })
    expect(fit).toHaveBeenCalledWith(canvas.elements)
    expect(canvas.onZoomChange).toHaveBeenCalled()
  })

  it("Ctrl+D duplicates the selected elements", () => {
    canvas.selectedElements = [{ id: "a" }]
    vi.spyOn(canvas.clipboardManager, "duplicate").mockReturnValue([])
    const paste = vi.spyOn(canvas, "_pasteElements").mockImplementation(() => {})
    keydown({ key: "d", ctrlKey: true })
    expect(paste).toHaveBeenCalled()
  })

  it("Ctrl+D is suppressed in read-only mode", () => {
    canvas.isReadOnly = true
    canvas.selectedElements = [{ id: "a" }]
    const paste = vi.spyOn(canvas, "_pasteElements")
    keydown({ key: "d", ctrlKey: true })
    expect(paste).not.toHaveBeenCalled()
  })

  it("_handleDelete honors an onBeforeChange callback for connection + element deletes", () => {
    canvas.onBeforeChange = vi.fn(); canvas.onchange = vi.fn()
    canvas.selectedConnectionId = "c1"
    vi.spyOn(canvas, "deleteConnection").mockImplementation(() => {})
    keydown({ key: "Delete" })
    expect(canvas.onBeforeChange).toHaveBeenCalled()
    canvas.selectedConnectionId = null
    canvas.selectedElements = [{ id: "a" }]
    vi.spyOn(canvas, "_deleteSelectedElements").mockImplementation(() => {})
    keydown({ key: "Delete" })
    expect(canvas.onBeforeChange).toHaveBeenCalledTimes(2)
  })

  it("releasing space while panning ends the pan", () => {
    canvas.zoomPanManager.isSpaceHeld = true
    canvas.zoomPanManager.isPanning = true
    const end = vi.spyOn(canvas.zoomPanManager, "endPan")
    keyup({ key: " " })
    expect(end).toHaveBeenCalled()
  })

  it("wheel events reach the passive wheel listener", () => {
    const pan = vi.spyOn(canvas.zoomPanManager, "panBy").mockImplementation(() => {})
    canvas.svg.dispatchEvent(new WheelEvent("wheel", { deltaX: 2, deltaY: 3, cancelable: true }))
    expect(pan).toHaveBeenCalled()
  })
})

describe("FlowchartCanvas click routing", () => {
  let canvas
  beforeEach(() => { document.body.innerHTML = ""; canvas = mountCanvas() })
  afterEach(() => canvas.destroy())

  it("_handleClick fires onCanvasClick on empty-canvas clicks", () => {
    canvas.onCanvasClick = vi.fn()
    canvas._handleClick({ target: canvas.svg })
    expect(canvas.onCanvasClick).toHaveBeenCalledOnce()
  })

  it("_handleClick returns early when the target is a connection endpoint", () => {
    canvas.onCanvasClick = vi.fn()
    const ep = document.createElementNS("http://www.w3.org/2000/svg", "g")
    ep.setAttribute("data-connection-endpoint", "from")
    canvas.svg.appendChild(ep)
    canvas._handleClick({ target: ep })
    expect(canvas.onCanvasClick).not.toHaveBeenCalled()
  })

  it("_handleClick does not fire onCanvasClick when an element was clicked", () => {
    canvas.onCanvasClick = vi.fn()
    const g = document.createElementNS("http://www.w3.org/2000/svg", "g")
    g.setAttribute("data-element-id", "a")
    canvas.elementLayer.appendChild(g)
    canvas._handleClick({ target: g })
    expect(canvas.onCanvasClick).not.toHaveBeenCalled()
  })

  it("_findElementGroupByHandle resolves the group by parent element id", () => {
    const g = document.createElementNS("http://www.w3.org/2000/svg", "g")
    g.setAttribute("data-element-id", "a")
    canvas.elementLayer.appendChild(g)
    const handle = document.createElement("div")
    handle.dataset.parentElementId = "a"
    expect(canvas._findElementGroupByHandle(handle)).toBe(g)
    const bare = document.createElement("div")
    expect(canvas._findElementGroupByHandle(bare)).toBeNull()
  })
})

// Build a synthetic mouse-like event with a `target` that answers `closest`.
// happy-dom nodes support closest, so we build a real SVG element tree and pass
// a leaf node. For handler branches that don't depend on the DOM tree, a plain
// object with a closest() stub is simpler.
function svgNode(attrs = {}) {
  const n = document.createElementNS("http://www.w3.org/2000/svg", "g")
  for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, v)
  return n
}
// Event whose target.closest(sel) returns the node carrying that attribute.
function eventOn(node, extra = {}) {
  return { target: node, clientX: 0, clientY: 0, stopPropagation: vi.fn(), preventDefault: vi.fn(), ...extra }
}

describe("FlowchartCanvas._handleMouseDown routing", () => {
  let canvas
  beforeEach(() => { document.body.innerHTML = ""; canvas = mountCanvas() })
  afterEach(() => canvas.destroy())

  it("starts a pan when space is held", () => {
    canvas.zoomPanManager.isSpaceHeld = true
    const start = vi.spyOn(canvas.zoomPanManager, "startPan")
    canvas._handleMouseDown({ clientX: 5, clientY: 6, target: canvas.svg })
    expect(start).toHaveBeenCalledWith(5, 6)
  })

  it("routes to resize start when a resize handle is hit", () => {
    canvas.elements = [{ id: "e1" }]
    const handle = svgNode({ "data-resize-handle": "se", "data-resize-element-id": "e1" })
    canvas.svg.appendChild(handle)
    const start = vi.spyOn(canvas, "_handleResizeStart").mockImplementation(() => {})
    canvas._handleMouseDown(eventOn(handle))
    expect(start).toHaveBeenCalledWith(canvas.elements[0], "se", expect.anything())
  })

  it("ignores resize/endpoint/handle mousedown in read-only mode", () => {
    canvas.isReadOnly = true
    canvas.elements = [{ id: "e1" }]
    const handle = svgNode({ "data-resize-handle": "se", "data-resize-element-id": "e1" })
    canvas.svg.appendChild(handle)
    const start = vi.spyOn(canvas, "_handleResizeStart")
    canvas._handleMouseDown(eventOn(handle))
    expect(start).not.toHaveBeenCalled()
  })

  it("does nothing when a resize handle references an unknown element", () => {
    canvas.elements = []
    const handle = svgNode({ "data-resize-handle": "se", "data-resize-element-id": "ghost" })
    canvas.svg.appendChild(handle)
    const start = vi.spyOn(canvas, "_handleResizeStart")
    // falls through to canvas mousedown (no element) -> selection rect start
    const selRect = vi.spyOn(canvas, "_startSelectionRect").mockImplementation(() => {})
    canvas._handleMouseDown(eventOn(handle))
    expect(start).not.toHaveBeenCalled()
    expect(selRect).toHaveBeenCalled()
  })

  it("starts an endpoint drag when a connection endpoint is hit", () => {
    const ep = svgNode({ "data-connection-endpoint": "from", "data-connection-id": "c1" })
    canvas.svg.appendChild(ep)
    const start = vi.spyOn(canvas, "_startConnectionEndpointDrag").mockImplementation(() => {})
    canvas._handleMouseDown(eventOn(ep))
    expect(start).toHaveBeenCalledWith(ep)
  })

  it("starts a connection draw when an element handle is hit", () => {
    const group = svgNode({ "data-element-id": "e1" })
    const handle = svgNode({ "data-handle-position": "port_0" })
    group.appendChild(handle)
    canvas.svg.appendChild(group)
    const start = vi.spyOn(canvas, "_startConnectionDraw").mockImplementation(() => {})
    canvas._handleMouseDown(eventOn(handle))
    expect(start).toHaveBeenCalledWith(group, handle)
  })

  it("ignores an endpoint mousedown in read-only mode", () => {
    canvas.isReadOnly = true
    const ep = svgNode({ "data-connection-endpoint": "from", "data-connection-id": "c1" })
    canvas.svg.appendChild(ep)
    const start = vi.spyOn(canvas, "_startConnectionEndpointDrag")
    canvas._handleMouseDown(eventOn(ep))
    expect(start).not.toHaveBeenCalled()
  })

  it("ignores a handle mousedown in read-only mode", () => {
    canvas.isReadOnly = true
    const handle = svgNode({ "data-handle-position": "port_0" })
    canvas.svg.appendChild(handle)
    const start = vi.spyOn(canvas, "_startConnectionDraw")
    canvas._handleMouseDown(eventOn(handle))
    expect(start).not.toHaveBeenCalled()
  })

  it("resolves an element handle via _findElementGroupByHandle fallback", () => {
    canvas.elements = [{ id: "e1" }]
    const group = svgNode({ "data-element-id": "e1" })
    canvas.elementLayer.appendChild(group)
    // handle is NOT nested in the element group, but carries parent-element-id
    const handle = svgNode({ "data-handle-position": "port_0", "data-parent-element-id": "e1" })
    canvas.svg.appendChild(handle)
    const start = vi.spyOn(canvas, "_startConnectionDraw").mockImplementation(() => {})
    canvas._handleMouseDown(eventOn(handle))
    expect(start).toHaveBeenCalledWith(group, handle)
  })

  it("selects a connection when a connection body is hit", () => {
    const conn = svgNode({ "data-connection-id": "c1" })
    canvas.svg.appendChild(conn)
    const sel = vi.spyOn(canvas, "selectConnection").mockImplementation(() => {})
    canvas._handleMouseDown(eventOn(conn))
    expect(sel).toHaveBeenCalledWith("c1")
  })

  it("routes to element mousedown when an element is hit", () => {
    canvas.elements = [{ id: "e1" }]
    const group = svgNode({ "data-element-id": "e1" })
    canvas.svg.appendChild(group)
    const emd = vi.spyOn(canvas, "_handleElementMouseDown")
    const startDrag = vi.spyOn(canvas, "_startDrag").mockImplementation(() => {})
    canvas._handleMouseDown(eventOn(group))
    expect(emd).toHaveBeenCalledWith(group, expect.anything())
    expect(startDrag).toHaveBeenCalled()
  })

  it("routes to canvas mousedown on empty space", () => {
    const cmd = vi.spyOn(canvas, "_handleCanvasMouseDown")
    const selRect = vi.spyOn(canvas, "_startSelectionRect").mockImplementation(() => {})
    canvas._handleMouseDown(eventOn(canvas.svg))
    expect(cmd).toHaveBeenCalled()
    expect(selRect).toHaveBeenCalled()
  })
})

describe("FlowchartCanvas._handleElementMouseDown", () => {
  let canvas
  beforeEach(() => { document.body.innerHTML = ""; canvas = mountCanvas() })
  afterEach(() => canvas.destroy())

  it("does nothing for an unknown element id", () => {
    const clear = vi.spyOn(canvas, "_clearSelection")
    canvas._handleElementMouseDown({ dataset: { elementId: "ghost" } }, eventOn(canvas.svg))
    expect(clear).not.toHaveBeenCalled()
  })

  it("ctrl/meta click toggles selection without dragging", () => {
    canvas.elements = [{ id: "e1" }]
    const toggle = vi.spyOn(canvas, "_toggleElementSelection").mockImplementation(() => {})
    const startDrag = vi.spyOn(canvas, "_startDrag")
    canvas._handleElementMouseDown({ dataset: { elementId: "e1" } }, eventOn(canvas.svg, { ctrlKey: true }))
    expect(toggle).toHaveBeenCalledWith(canvas.elements[0])
    expect(startDrag).not.toHaveBeenCalled()
  })

  it("plain click on an unselected element clears + selects then drags", () => {
    canvas.elements = [{ id: "e1" }]
    vi.spyOn(canvas, "_isElementSelected").mockReturnValue(false)
    const clear = vi.spyOn(canvas, "_clearSelection").mockImplementation(() => {})
    const add = vi.spyOn(canvas, "_addToSelection").mockImplementation(() => {})
    const startDrag = vi.spyOn(canvas, "_startDrag").mockImplementation(() => {})
    canvas._handleElementMouseDown({ dataset: { elementId: "e1" } }, eventOn(canvas.svg))
    expect(clear).toHaveBeenCalled()
    expect(add).toHaveBeenCalledWith(canvas.elements[0])
    expect(startDrag).toHaveBeenCalled()
  })

  it("read-only click selects but does not drag", () => {
    canvas.isReadOnly = true
    canvas.elements = [{ id: "e1" }]
    vi.spyOn(canvas, "_isElementSelected").mockReturnValue(true)
    const startDrag = vi.spyOn(canvas, "_startDrag")
    canvas._handleElementMouseDown({ dataset: { elementId: "e1" } }, eventOn(canvas.svg))
    expect(startDrag).not.toHaveBeenCalled()
  })
})

describe("FlowchartCanvas._handleCanvasMouseDown", () => {
  let canvas
  beforeEach(() => { document.body.innerHTML = ""; canvas = mountCanvas() })
  afterEach(() => canvas.destroy())

  it("clears selection on a plain click and starts a selection rect", () => {
    const clear = vi.spyOn(canvas, "_clearSelection").mockImplementation(() => {})
    const selRect = vi.spyOn(canvas, "_startSelectionRect").mockImplementation(() => {})
    canvas._handleCanvasMouseDown(eventOn(canvas.svg))
    expect(clear).toHaveBeenCalled()
    expect(selRect).toHaveBeenCalled()
  })

  it("preserves selection when ctrl/meta is held", () => {
    const clear = vi.spyOn(canvas, "_clearSelection")
    vi.spyOn(canvas, "_startSelectionRect").mockImplementation(() => {})
    canvas._handleCanvasMouseDown(eventOn(canvas.svg, { metaKey: true }))
    expect(clear).not.toHaveBeenCalled()
  })
})

describe("FlowchartCanvas._handleMouseMove routing", () => {
  let canvas
  beforeEach(() => {
    document.body.innerHTML = ""; canvas = mountCanvas()
    vi.spyOn(canvas, "_getSVGPoint").mockReturnValue({ x: 3, y: 4 })
  })
  afterEach(() => canvas.destroy())

  it("updates the pan while panning", () => {
    canvas.zoomPanManager.isPanning = true
    const upd = vi.spyOn(canvas.zoomPanManager, "updatePan")
    canvas._handleMouseMove({ clientX: 1, clientY: 2 })
    expect(upd).toHaveBeenCalledWith(1, 2)
  })

  it("delegates to resize move while resizing", () => {
    canvas.isResizing = true
    const mv = vi.spyOn(canvas, "_handleResizeMove").mockImplementation(() => {})
    canvas._handleMouseMove({})
    expect(mv).toHaveBeenCalled()
  })

  it("updates the selection rect while selecting", () => {
    canvas.isSelecting = true
    const upd = vi.spyOn(canvas, "_updateSelectionRect").mockImplementation(() => {})
    canvas._handleMouseMove({})
    expect(upd).toHaveBeenCalledWith({ x: 3, y: 4 })
  })

  it("updates the endpoint drag + highlight while dragging an endpoint", () => {
    canvas.isDraggingConnectionEndpoint = true
    const upd = vi.spyOn(canvas, "_updateConnectionEndpointDrag").mockImplementation(() => {})
    const hi = vi.spyOn(canvas, "_highlightElementAtPoint").mockImplementation(() => {})
    canvas._handleMouseMove({})
    expect(upd).toHaveBeenCalledWith({ x: 3, y: 4 })
    expect(hi).toHaveBeenCalledWith(3, 4)
  })

  it("stretches the connection line while drawing a connection", () => {
    canvas.isDrawingConnection = true
    canvas.connectionLine = svgNode()
    canvas._handleMouseMove({})
    expect(canvas.connectionLine.getAttribute("x2")).toBe("3")
    expect(canvas.connectionLine.getAttribute("y2")).toBe("4")
  })

  it("moves the dragged element while dragging", () => {
    canvas.isDragging = true
    canvas.draggedElement = { id: "e1" }
    const dm = vi.spyOn(canvas, "_handleDragMove").mockImplementation(() => {})
    canvas._handleMouseMove({})
    expect(dm).toHaveBeenCalledWith({ x: 3, y: 4 })
  })
})

describe("FlowchartCanvas._handleDragMove", () => {
  let canvas
  beforeEach(() => { document.body.innerHTML = ""; canvas = mountCanvas() })
  afterEach(() => canvas.destroy())

  it("moves only the dragged element and shows guides", () => {
    canvas.draggedElement = { id: "e1" }
    canvas.dragOffset = { x: 1, y: 2 }
    const mv = vi.spyOn(canvas, "_moveElementVisually").mockImplementation(() => {})
    const hi = vi.spyOn(canvas, "_highlightDropTarget").mockImplementation(() => {})
    vi.spyOn(canvas, "_updateConnectionsVisually").mockImplementation(() => {})
    vi.spyOn(canvas, "_showAlignmentGuides").mockImplementation(() => {})
    canvas._handleDragMove({ x: 10, y: 20 })
    expect(mv).toHaveBeenCalledWith(canvas.draggedElement, 9, 18)
    expect(mv).toHaveBeenCalledTimes(1)
    expect(hi).toHaveBeenCalledWith(10, 20)
  })

  it("moves each element of a multi-element drag by the delta", () => {
    canvas.draggedElement = { id: "e1" }
    canvas.dragOffset = { x: 0, y: 0 }
    canvas.dragStartPosition = { x: 5, y: 5 }
    const a = { id: "a" }, b = { id: "b" }
    canvas.draggedElements = [
      { element: a, startX: 100, startY: 100 },
      { element: b, startX: 200, startY: 200 },
    ]
    const mv = vi.spyOn(canvas, "_moveElementVisually").mockImplementation(() => {})
    vi.spyOn(canvas, "_updateConnectionsVisually").mockImplementation(() => {})
    vi.spyOn(canvas, "_showAlignmentGuides").mockImplementation(() => {})
    // point (15,15) -> newX=15,newY=15 ; delta = 10,10
    canvas._handleDragMove({ x: 15, y: 15 })
    expect(mv).toHaveBeenCalledWith(a, 110, 110)
    expect(mv).toHaveBeenCalledWith(b, 210, 210)
  })
})

describe("FlowchartCanvas._handleMouseUp routing", () => {
  let canvas
  beforeEach(() => {
    document.body.innerHTML = ""; canvas = mountCanvas()
    vi.spyOn(canvas, "_getSVGPoint").mockReturnValue({ x: 3, y: 4 })
  })
  afterEach(() => canvas.destroy())

  it("ends a pan", () => {
    canvas.zoomPanManager.isPanning = true
    const end = vi.spyOn(canvas.zoomPanManager, "endPan")
    canvas._handleMouseUp({})
    expect(end).toHaveBeenCalled()
  })

  it("ends a resize", () => {
    canvas.isResizing = true
    const end = vi.spyOn(canvas, "_handleResizeEnd").mockImplementation(() => {})
    canvas._handleMouseUp({})
    expect(end).toHaveBeenCalled()
  })

  it("ends a selection rect and notifies selection changed", () => {
    canvas.isSelecting = true
    canvas.onSelectionChanged = vi.fn()
    const end = vi.spyOn(canvas, "_endSelectionRect").mockImplementation(() => {})
    canvas._handleMouseUp({})
    expect(end).toHaveBeenCalled()
    expect(canvas.onSelectionChanged).toHaveBeenCalled()
  })

  it("ends an endpoint drag", () => {
    canvas.isDraggingConnectionEndpoint = true
    const end = vi.spyOn(canvas, "_endConnectionEndpointDrag").mockImplementation(() => {})
    canvas._handleMouseUp({})
    expect(end).toHaveBeenCalledWith({ x: 3, y: 4 })
  })

  it("finishes a connection draw", () => {
    canvas.isDrawingConnection = true
    const fin = vi.spyOn(canvas, "_finishConnectionDraw").mockImplementation(() => {})
    canvas._handleMouseUp({})
    expect(fin).toHaveBeenCalledWith({ x: 3, y: 4 })
  })

  it("ends an element drag", () => {
    canvas.isDragging = true
    canvas.draggedElement = { id: "e1" }
    const end = vi.spyOn(canvas, "_endDrag").mockImplementation(() => {})
    canvas._handleMouseUp({})
    expect(end).toHaveBeenCalled()
  })
})

describe("FlowchartCanvas drag threshold and document listeners", () => {
  let canvas
  beforeEach(() => {
    document.body.innerHTML = ""
    canvas = mountCanvas()
    vi.spyOn(canvas, "updateElementPosition").mockImplementation(() => {})
    vi.spyOn(canvas, "updateConnections").mockImplementation(() => {})
    vi.spyOn(canvas, "_updateConnectionsVisually").mockImplementation(() => {})
    vi.spyOn(canvas, "_showAlignmentGuides").mockImplementation(() => {})
    vi.spyOn(canvas, "_hideAlignmentGuides").mockImplementation(() => {})
    vi.spyOn(canvas, "_selectElement").mockImplementation(() => {})
    vi.spyOn(canvas, "showConnectionHandles").mockImplementation(() => {})
  })
  afterEach(() => canvas.destroy())

  function seedElement(over = {}) {
    const element = { id: "e1", type: "process", x: 100, y: 100, width: 100, height: 45, ...over }
    canvas.elements = [element]
    const group = document.createElementNS("http://www.w3.org/2000/svg", "g")
    group.setAttribute("data-element-id", "e1")
    canvas.elementLayer.appendChild(group)
    return element
  }

  it("neither moves nor reconnects an element after a 3px mousedown/mouseup", () => {
    const element = seedElement()
    const other = { id: "e2", type: "process", x: 100, y: 200, width: 100, height: 45 }
    canvas.elements.push(other)
    const reconnect = vi.spyOn(canvas, "_reconnectElement")
    vi.spyOn(canvas, "_getSVGPoint").mockReturnValue({ x: 100, y: 100 })
    canvas._handleElementMouseDown({ dataset: { elementId: "e1" } }, { clientX: 0, clientY: 0, ctrlKey: false, metaKey: false, preventDefault() {}, stopPropagation() {} })
    canvas._getSVGPoint.mockReturnValue({ x: 103, y: 100 })
    canvas._handleMouseMove({ clientX: 3, clientY: 0 })
    canvas.dropTargetElement = other
    canvas._handleMouseUp({ clientX: 3, clientY: 0 })
    expect(element.x).toBe(100)
    expect(element.y).toBe(100)
    expect(reconnect).not.toHaveBeenCalled()
    expect(canvas.isDragging).toBe(false)
  })

  it("document drag listeners are idempotent to bind and unbind", () => {
    canvas._bindDocumentDragListeners()
    const firstMove = canvas._documentDragMoveHandler
    canvas._bindDocumentDragListeners()
    expect(canvas._documentDragMoveHandler).toBe(firstMove)
    canvas._unbindDocumentDragListeners()
    expect(canvas._documentDragMoveHandler).toBeNull()
    expect(() => canvas._unbindDocumentDragListeners()).not.toThrow()
  })

  it("ends a 9px drag when mouseup happens over the property sidebar", () => {
    const element = seedElement()
    vi.spyOn(canvas, "_getSVGPoint").mockReturnValue({ x: 100, y: 100 })
    canvas._handleElementMouseDown({ dataset: { elementId: "e1" } }, { clientX: 0, clientY: 0, ctrlKey: false, metaKey: false, preventDefault() {}, stopPropagation() {} })
    expect(canvas.isDragging).toBe(true)
    canvas._getSVGPoint.mockReturnValue({ x: 109, y: 100 })
    document.dispatchEvent(new MouseEvent("mousemove", { bubbles: true, clientX: 9, clientY: 0 }))
    const sidebar = document.createElement("aside")
    document.body.appendChild(sidebar)
    sidebar.dispatchEvent(new MouseEvent("mouseup", { bubbles: true, clientX: 9, clientY: 0 }))
    expect(canvas.isDragging).toBe(false)
    expect(canvas.draggedElement).toBeNull()
    expect(element.x).not.toBe(100)
  })

  it("destroy mid-drag unbinds document listeners so a later mouseup does not end the drag", () => {
    seedElement()
    vi.spyOn(canvas, "_getSVGPoint").mockReturnValue({ x: 100, y: 100 })
    canvas._handleElementMouseDown({ dataset: { elementId: "e1" } }, { clientX: 0, clientY: 0, ctrlKey: false, metaKey: false, preventDefault() {}, stopPropagation() {} })
    expect(canvas.isDragging).toBe(true)
    canvas.onchange = vi.fn()
    const end = vi.spyOn(canvas, "_endDrag")
    canvas.destroy()
    document.dispatchEvent(new MouseEvent("mouseup", { bubbles: true, clientX: 20, clientY: 0 }))
    expect(end).not.toHaveBeenCalled()
    expect(canvas.onchange).not.toHaveBeenCalled()
  })

  it("Escape mid-drag restores original positions and removes document listeners", () => {
    const element = seedElement()
    vi.spyOn(canvas, "_getSVGPoint").mockReturnValue({ x: 100, y: 100 })
    canvas._handleElementMouseDown({ dataset: { elementId: "e1" } }, { clientX: 0, clientY: 0, ctrlKey: false, metaKey: false, preventDefault() {}, stopPropagation() {} })
    canvas._getSVGPoint.mockReturnValue({ x: 140, y: 100 })
    document.dispatchEvent(new MouseEvent("mousemove", { bubbles: true, clientX: 40, clientY: 0 }))
    expect(element.x).not.toBe(100)
    expect(canvas._documentDragMoveHandler).toBeTruthy()
    keydown({ key: "Escape" })
    expect(element.x).toBe(100)
    expect(element.y).toBe(100)
    expect(canvas.isDragging).toBe(false)
    expect(canvas._documentDragMoveHandler).toBeNull()
  })

  it("Escape targeted at a button outside the canvas during a drag does not cancel the drag", () => {
    const element = seedElement()
    vi.spyOn(canvas, "_getSVGPoint").mockReturnValue({ x: 100, y: 100 })
    canvas._handleElementMouseDown({ dataset: { elementId: "e1" } }, { clientX: 0, clientY: 0, ctrlKey: false, metaKey: false, preventDefault() {}, stopPropagation() {} })
    canvas._getSVGPoint.mockReturnValue({ x: 140, y: 100 })
    document.dispatchEvent(new MouseEvent("mousemove", { bubbles: true, clientX: 40, clientY: 0 }))
    const movedX = element.x
    expect(movedX).not.toBe(100)
    const sidebar = document.createElement("aside")
    const button = document.createElement("button")
    sidebar.appendChild(button)
    document.body.appendChild(sidebar)
    button.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "Escape" }))
    expect(element.x).toBe(movedX)
    expect(canvas.isDragging).toBe(true)
    expect(canvas._documentDragMoveHandler).toBeTruthy()
  })

  it("Escape targeted at the SVG during a drag cancels the drag", () => {
    const element = seedElement()
    vi.spyOn(canvas, "_getSVGPoint").mockReturnValue({ x: 100, y: 100 })
    canvas._handleElementMouseDown({ dataset: { elementId: "e1" } }, { clientX: 0, clientY: 0, ctrlKey: false, metaKey: false, preventDefault() {}, stopPropagation() {} })
    canvas._getSVGPoint.mockReturnValue({ x: 140, y: 100 })
    document.dispatchEvent(new MouseEvent("mousemove", { bubbles: true, clientX: 40, clientY: 0 }))
    expect(element.x).not.toBe(100)
    canvas.svg.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "Escape" }))
    expect(element.x).toBe(100)
    expect(element.y).toBe(100)
    expect(canvas.isDragging).toBe(false)
    expect(canvas._documentDragMoveHandler).toBeNull()
  })
})

describe("FlowchartCanvas._handleDoubleClick", () => {
  let canvas
  beforeEach(() => { document.body.innerHTML = ""; canvas = mountCanvas() })
  afterEach(() => canvas.destroy())

  it("opens inline label edit for a connection double-click", () => {
    const conn = svgNode({ "data-connection-id": "c1" })
    canvas.svg.appendChild(conn)
    const sel = vi.spyOn(canvas, "selectConnection").mockImplementation(() => {})
    const edit = vi.spyOn(canvas, "startInlineLabelEdit").mockImplementation(() => {})
    canvas._handleDoubleClick(eventOn(conn))
    expect(sel).toHaveBeenCalledWith("c1")
    expect(edit).toHaveBeenCalledWith("c1")
  })

  it("fires onElementDoubleClick for a direct element hit", () => {
    canvas.elements = [{ id: "e1" }]
    canvas.onElementDoubleClick = vi.fn()
    const group = svgNode({ "data-element-id": "e1" })
    canvas.svg.appendChild(group)
    canvas._handleDoubleClick(eventOn(group))
    expect(canvas.onElementDoubleClick).toHaveBeenCalledWith(canvas.elements[0])
  })

  it("resolves the element via a handle overlay", () => {
    canvas.elements = [{ id: "e1" }]
    canvas.onElementDoubleClick = vi.fn()
    const handle = svgNode({ "data-parent-element-id": "e1" })
    canvas.svg.appendChild(handle)
    canvas._handleDoubleClick(eventOn(handle))
    expect(canvas.onElementDoubleClick).toHaveBeenCalledWith(canvas.elements[0])
  })

  it("resolves the element via a resize handle overlay", () => {
    canvas.elements = [{ id: "e1" }]
    canvas.onElementDoubleClick = vi.fn()
    const resize = svgNode({ "data-resize-element-id": "e1" })
    canvas.svg.appendChild(resize)
    canvas._handleDoubleClick(eventOn(resize))
    expect(canvas.onElementDoubleClick).toHaveBeenCalledWith(canvas.elements[0])
  })

  it("does nothing when onElementDoubleClick is not set", () => {
    canvas.elements = [{ id: "e1" }]
    canvas.onElementDoubleClick = null
    const group = svgNode({ "data-element-id": "e1" })
    canvas.svg.appendChild(group)
    expect(() => canvas._handleDoubleClick(eventOn(group))).not.toThrow()
  })

  it("does nothing when no element id can be resolved", () => {
    canvas.onElementDoubleClick = vi.fn()
    canvas._handleDoubleClick(eventOn(canvas.svg))
    expect(canvas.onElementDoubleClick).not.toHaveBeenCalled()
  })

  it("does nothing when the resolved element does not exist", () => {
    canvas.elements = []
    canvas.onElementDoubleClick = vi.fn()
    const group = svgNode({ "data-element-id": "ghost" })
    canvas.svg.appendChild(group)
    canvas._handleDoubleClick(eventOn(group))
    expect(canvas.onElementDoubleClick).not.toHaveBeenCalled()
  })
})

describe("FlowchartCanvas._handleWheel", () => {
  let canvas
  beforeEach(() => { document.body.innerHTML = ""; canvas = mountCanvas() })
  afterEach(() => canvas.destroy())

  it("zooms on ctrl/cmd + wheel and reports the zoom change", () => {
    canvas.onZoomChange = vi.fn()
    const zt = vi.spyOn(canvas.zoomPanManager, "zoomTo").mockImplementation(() => {})
    canvas._handleWheel({ preventDefault: vi.fn(), ctrlKey: true, deltaY: 120, clientX: 1, clientY: 2 })
    expect(zt).toHaveBeenCalled()
    expect(canvas.onZoomChange).toHaveBeenCalled()
  })

  it("zooms in on ctrl + wheel-up (negative deltaY)", () => {
    const zt = vi.spyOn(canvas.zoomPanManager, "zoomTo").mockImplementation(() => {})
    canvas._handleWheel({ preventDefault: vi.fn(), metaKey: true, deltaY: -120, clientX: 0, clientY: 0 })
    expect(zt).toHaveBeenCalled()
  })

  it("pans on a plain wheel", () => {
    const pan = vi.spyOn(canvas.zoomPanManager, "panBy").mockImplementation(() => {})
    canvas._handleWheel({ preventDefault: vi.fn(), deltaX: 5, deltaY: 10 })
    expect(pan).toHaveBeenCalledWith(-5, -10)
  })
})

describe("FlowchartCanvas connection draw", () => {
  let canvas
  beforeEach(() => {
    document.body.innerHTML = ""; canvas = mountCanvas()
    vi.spyOn(canvas, "_getHandlePosition").mockReturnValue({ x: 0, y: 0 })
  })
  afterEach(() => canvas.destroy())

  it("_startConnectionDraw creates a dashed line from the handle position", () => {
    canvas.elements = [{ id: "e1" }]
    const group = svgNode({ "data-element-id": "e1" })
    const handle = svgNode({ "data-handle-position": "port_0" })
    canvas._startConnectionDraw(group, handle)
    expect(canvas.isDrawingConnection).toBe(true)
    expect(canvas.connectionStartElement).toBe(canvas.elements[0])
    expect(canvas.connectionLine).not.toBeNull()
  })

  it("_startConnectionDraw is a no-op for an unknown element", () => {
    canvas.elements = []
    const group = svgNode({ "data-element-id": "ghost" })
    const handle = svgNode({ "data-handle-position": "port_0" })
    canvas._startConnectionDraw(group, handle)
    expect(canvas.isDrawingConnection).toBe(false)
  })

  it("_finishConnectionDraw creates a connection to a different target element", () => {
    canvas.connectionStartElement = { id: "e1" }
    canvas.connectionStartHandle = "bottom"
    canvas.onchange = vi.fn()
    canvas.onBeforeChange = vi.fn()
    const target = { id: "e2" }
    vi.spyOn(canvas, "_findElementAtPoint").mockReturnValue(target)
    vi.spyOn(canvas, "_getClosestHandlePosition").mockReturnValue("top")
    const create = vi.spyOn(canvas, "createConnection").mockReturnValue({ id: "c1" })
    const upd = vi.spyOn(canvas, "updateConnections").mockImplementation(() => {})
    canvas._finishConnectionDraw({ x: 1, y: 1 })
    expect(create).toHaveBeenCalledWith(canvas.connectionStartElement ?? { id: "e1" }, target, "bottom", "top")
    expect(upd).toHaveBeenCalled()
    expect(canvas.onchange).toHaveBeenCalled()
    expect(canvas.isDrawingConnection).toBe(false)
  })

  it("_finishConnectionDraw ignores a drop back onto the source element", () => {
    canvas.connectionStartElement = { id: "e1" }
    vi.spyOn(canvas, "_findElementAtPoint").mockReturnValue({ id: "e1" })
    const create = vi.spyOn(canvas, "createConnection")
    canvas._finishConnectionDraw({ x: 1, y: 1 })
    expect(create).not.toHaveBeenCalled()
  })

  it("_finishConnectionDraw with no createConnection result skips updateConnections", () => {
    canvas.connectionStartElement = { id: "e1" }
    canvas.connectionStartHandle = "bottom"
    canvas.onchange = vi.fn()
    vi.spyOn(canvas, "_findElementAtPoint").mockReturnValue({ id: "e2" })
    vi.spyOn(canvas, "_getClosestHandlePosition").mockReturnValue("top")
    vi.spyOn(canvas, "createConnection").mockReturnValue(null)
    const upd = vi.spyOn(canvas, "updateConnections").mockImplementation(() => {})
    canvas._finishConnectionDraw({ x: 1, y: 1 })
    expect(upd).not.toHaveBeenCalled()
  })

  it("_endConnectionDraw resets state and removes the temp line", () => {
    canvas.isDrawingConnection = true
    canvas.connectionLine = svgNode()
    canvas.connectionLayer.appendChild(canvas.connectionLine)
    vi.spyOn(canvas, "_hideConnectionHandles").mockImplementation(() => {})
    canvas._endConnectionDraw()
    expect(canvas.isDrawingConnection).toBe(false)
    expect(canvas.connectionLine).toBeNull()
  })
})

describe("FlowchartCanvas endpoint drag", () => {
  let canvas
  beforeEach(() => {
    document.body.innerHTML = ""; canvas = mountCanvas()
    vi.spyOn(canvas, "_getHandlePosition").mockReturnValue({ x: 0, y: 0 })
  })
  afterEach(() => canvas.destroy())

  it("_startConnectionEndpointDrag sets up drag state and the drag line", () => {
    const conn = { id: "c1", from: "e1", to: "e2", fromPosition: "bottom", toPosition: "top" }
    canvas.connections = [conn]
    canvas.elements = [{ id: "e1" }, { id: "e2" }]
    canvas.onBeforeChange = vi.fn()
    const group = svgNode({ "data-connection-id": "c1" })
    canvas.connectionLayer.appendChild(group)
    const ep = { dataset: { connectionId: "c1", connectionEndpoint: "from" } }
    canvas._startConnectionEndpointDrag(ep)
    expect(canvas.isDraggingConnectionEndpoint).toBe(true)
    expect(canvas.draggingConnection).toBe(conn)
    expect(canvas.connectionDragLine).not.toBeNull()
    expect(group.style.opacity).toBe("0.3")
    expect(canvas.svg.style.cursor).toBe("crosshair")
  })

  it("_startConnectionEndpointDrag is a no-op for an unknown connection", () => {
    canvas.connections = []
    canvas._startConnectionEndpointDrag({ dataset: { connectionId: "ghost", connectionEndpoint: "from" } })
    expect(canvas.isDraggingConnectionEndpoint).toBe(false)
  })

  it("_startConnectionEndpointDrag bails when a referenced element is missing", () => {
    const conn = { id: "c1", from: "e1", to: "missing" }
    canvas.connections = [conn]
    canvas.elements = [{ id: "e1" }]
    canvas.onBeforeChange = vi.fn()
    canvas._startConnectionEndpointDrag({ dataset: { connectionId: "c1", connectionEndpoint: "from" } })
    expect(canvas.connectionDragLine).toBeNull()
  })

  it("_startConnectionEndpointDrag handles the 'to' endpoint variant", () => {
    const conn = { id: "c1", from: "e1", to: "e2", fromPort: "port_0", toPort: "port_1" }
    canvas.connections = [conn]
    canvas.elements = [{ id: "e1" }, { id: "e2" }]
    canvas.onBeforeChange = vi.fn()
    canvas._startConnectionEndpointDrag({ dataset: { connectionId: "c1", connectionEndpoint: "to" } })
    expect(canvas.draggingEndpointType).toBe("to")
    expect(canvas.connectionDragLine).not.toBeNull()
  })

  it("_startConnectionEndpointDrag ('from') prefers explicit ports over positions", () => {
    // isFrom=true with ports set -> exercises the port side of both || fallbacks
    const conn = { id: "c1", from: "e1", to: "e2", fromPort: "port_1", toPort: "port_2" }
    canvas.connections = [conn]
    canvas.elements = [{ id: "e1" }, { id: "e2" }]
    canvas.onBeforeChange = vi.fn()
    canvas._startConnectionEndpointDrag({ dataset: { connectionId: "c1", connectionEndpoint: "from" } })
    expect(canvas.connectionDragLine).not.toBeNull()
  })

  it("_startConnectionEndpointDrag ('to') falls back to positions when ports are absent", () => {
    // isFrom=false with only positions -> exercises the position side of both || fallbacks
    const conn = { id: "c1", from: "e1", to: "e2", fromPosition: "bottom", toPosition: "top" }
    canvas.connections = [conn]
    canvas.elements = [{ id: "e1" }, { id: "e2" }]
    canvas.onBeforeChange = vi.fn()
    canvas._startConnectionEndpointDrag({ dataset: { connectionId: "c1", connectionEndpoint: "to" } })
    expect(canvas.connectionDragLine).not.toBeNull()
  })

  it("_updateConnectionEndpointDrag moves the correct endpoint (from vs to)", () => {
    canvas.connectionDragLine = svgNode()
    canvas.draggingEndpointType = "from"
    canvas._updateConnectionEndpointDrag({ x: 7, y: 8 })
    expect(canvas.connectionDragLine.getAttribute("x1")).toBe("7")
    expect(canvas.connectionDragLine.getAttribute("y1")).toBe("8")
    canvas.draggingEndpointType = "to"
    canvas._updateConnectionEndpointDrag({ x: 9, y: 10 })
    expect(canvas.connectionDragLine.getAttribute("x2")).toBe("9")
  })

  it("_updateConnectionEndpointDrag is a no-op without a drag line", () => {
    canvas.connectionDragLine = null
    expect(() => canvas._updateConnectionEndpointDrag({ x: 1, y: 1 })).not.toThrow()
  })

  it("_endConnectionEndpointDrag retargets the 'from' endpoint to a new element", () => {
    const conn = { id: "c1", from: "e1", to: "e2", fromPosition: "bottom", toPosition: "top" }
    canvas.connections = [conn]
    canvas.elements = [{ id: "e1", type: "process" }, { id: "e2", type: "process" }, { id: "e3", type: "process" }]
    canvas.draggingConnection = conn
    canvas.draggingEndpointType = "from"
    canvas.onchange = vi.fn()
    const group = svgNode({ "data-connection-id": "c1" })
    canvas.connectionLayer.appendChild(group)
    vi.spyOn(canvas, "_findElementAtPoint").mockReturnValue(canvas.elements[2])
    vi.spyOn(canvas, "_getClosestHandlePosition").mockReturnValue("port_5")
    vi.spyOn(canvas, "updateConnections").mockImplementation(() => {})
    vi.spyOn(canvas, "selectConnection").mockImplementation(() => {})
    canvas._endConnectionEndpointDrag({ x: 1, y: 1 })
    expect(conn.from).toBe("e3")
    expect(conn.fromPort).toBe("port_5")
    expect(canvas.isDraggingConnectionEndpoint).toBe(false)
    expect(canvas.svg.style.cursor).toBe("default")
  })

  it("_endConnectionEndpointDrag retargets 'from' to a cardinal position (non-port)", () => {
    const conn = { id: "c1", from: "e1", to: "e2" }
    canvas.connections = [conn]
    canvas.elements = [{ id: "e1", type: "process" }, { id: "e2", type: "process" }, { id: "e3", type: "process" }]
    canvas.draggingConnection = conn
    canvas.draggingEndpointType = "from"
    canvas.onchange = vi.fn()
    vi.spyOn(canvas, "_findElementAtPoint").mockReturnValue(canvas.elements[2])
    vi.spyOn(canvas, "_getClosestHandlePosition").mockReturnValue("left") // cardinal
    vi.spyOn(canvas, "updateConnections").mockImplementation(() => {})
    vi.spyOn(canvas, "selectConnection").mockImplementation(() => {})
    canvas._endConnectionEndpointDrag({ x: 1, y: 1 })
    expect(conn.fromPort).toBeNull()
    expect(conn.fromPosition).toBe("left")
  })

  it("_endConnectionEndpointDrag retargets 'to' to a port position", () => {
    const conn = { id: "c1", from: "e1", to: "e2" }
    canvas.connections = [conn]
    canvas.elements = [{ id: "e1", type: "process" }, { id: "e2", type: "process" }, { id: "e3", type: "process" }]
    canvas.draggingConnection = conn
    canvas.draggingEndpointType = "to"
    canvas.onchange = vi.fn()
    vi.spyOn(canvas, "_findElementAtPoint").mockReturnValue(canvas.elements[2])
    vi.spyOn(canvas, "_getClosestHandlePosition").mockReturnValue("port_2")
    vi.spyOn(canvas, "updateConnections").mockImplementation(() => {})
    vi.spyOn(canvas, "selectConnection").mockImplementation(() => {})
    canvas._endConnectionEndpointDrag({ x: 1, y: 1 })
    expect(conn.toPort).toBe("port_2")
    expect(conn.toPosition).toBeNull()
  })

  it("_endConnectionEndpointDrag rejects retargeting the 'to' endpoint onto a Start", () => {
    const conn = { id: "c1", from: "e1", to: "e2", fromPosition: "bottom", toPosition: "top" }
    canvas.connections = [conn]
    canvas.elements = [
      { id: "e1", type: "process" },
      { id: "e2", type: "process" },
      { id: "s", type: "start" },
    ]
    canvas.draggingConnection = conn
    canvas.draggingEndpointType = "to"
    canvas.onchange = vi.fn()
    canvas.onToast = vi.fn()
    canvas.labels = { connectionIntoStartRejected: "A Start element cannot have incoming connections" }
    vi.spyOn(canvas, "_findElementAtPoint").mockReturnValue(canvas.elements[2])
    const upd = vi.spyOn(canvas, "updateConnections").mockImplementation(() => {})
    canvas._endConnectionEndpointDrag({ x: 1, y: 1 })
    expect(conn.to).toBe("e2")
    expect(upd).not.toHaveBeenCalled()
    expect(canvas.onchange).not.toHaveBeenCalled()
    expect(canvas.onToast).toHaveBeenCalledWith("A Start element cannot have incoming connections")
  })

  it("_endConnectionEndpointDrag rejects retargeting the 'from' endpoint onto an End", () => {
    const conn = { id: "c1", from: "e1", to: "e2", fromPosition: "bottom", toPosition: "top" }
    canvas.connections = [conn]
    canvas.elements = [
      { id: "e1", type: "process" },
      { id: "e2", type: "process" },
      { id: "end", type: "end" },
    ]
    canvas.draggingConnection = conn
    canvas.draggingEndpointType = "from"
    canvas.onchange = vi.fn()
    canvas.onToast = vi.fn()
    canvas.labels = { connectionOutOfEndRejected: "An End element cannot have outgoing connections" }
    vi.spyOn(canvas, "_findElementAtPoint").mockReturnValue(canvas.elements[2])
    const upd = vi.spyOn(canvas, "updateConnections").mockImplementation(() => {})
    canvas._endConnectionEndpointDrag({ x: 1, y: 1 })
    expect(conn.from).toBe("e1")
    expect(upd).not.toHaveBeenCalled()
    expect(canvas.onchange).not.toHaveBeenCalled()
    expect(canvas.onToast).toHaveBeenCalledWith("An End element cannot have outgoing connections")
  })

  it("_endConnectionEndpointDrag allows a reverse-direction edge and still blocks a same-direction duplicate", () => {
    const conn = { id: "c1", from: "e1", to: "e2" }
    const reverse = { id: "c2", from: "e2", to: "e3" } // reverse of a would-be e3->e2
    canvas.connections = [conn, reverse]
    canvas.elements = [{ id: "e1" }, { id: "e2" }, { id: "e3" }]
    canvas.draggingConnection = conn
    canvas.draggingEndpointType = "from"
    vi.spyOn(canvas, "_findElementAtPoint").mockReturnValue(canvas.elements[2]) // e3
    vi.spyOn(canvas, "_getClosestHandlePosition").mockReturnValue("left")
    const upd = vi.spyOn(canvas, "updateConnections").mockImplementation(() => {})
    vi.spyOn(canvas, "selectConnection").mockImplementation(() => {})
    canvas._endConnectionEndpointDrag({ x: 1, y: 1 })
    expect(conn.from).toBe("e3")
    expect(upd).toHaveBeenCalled()

    const same = { id: "c3", from: "e4", to: "e2" }
    canvas.connections = [conn, same]
    canvas.elements = [{ id: "e1" }, { id: "e2" }, { id: "e3" }, { id: "e4" }]
    canvas.draggingConnection = conn
    canvas.draggingEndpointType = "from"
    canvas._findElementAtPoint.mockReturnValue(canvas.elements[3]) // e4
    upd.mockClear()
    canvas._endConnectionEndpointDrag({ x: 1, y: 1 })
    expect(conn.from).toBe("e3") // unchanged, same-direction duplicate blocked
    expect(upd).not.toHaveBeenCalled()
  })

  it("_endConnectionEndpointDrag retargets the 'to' endpoint and re-syncs decision branches", () => {
    const conn = { id: "c1", from: "d1", to: "e2", fromPort: "port_0", toPosition: "top" }
    canvas.connections = [conn]
    canvas.elements = [{ id: "d1", type: "decision" }, { id: "e2", type: "process" }, { id: "e3", type: "process" }]
    canvas.draggingConnection = conn
    canvas.draggingEndpointType = "to"
    canvas.onchange = vi.fn()
    const group = svgNode({ "data-connection-id": "c1" })
    canvas.connectionLayer.appendChild(group)
    vi.spyOn(canvas, "_findElementAtPoint").mockReturnValue(canvas.elements[2])
    vi.spyOn(canvas, "_getClosestHandlePosition").mockReturnValue("left")
    const sync = vi.spyOn(canvas, "_syncDecisionBranches").mockImplementation(() => {})
    vi.spyOn(canvas, "updateConnections").mockImplementation(() => {})
    vi.spyOn(canvas, "selectConnection").mockImplementation(() => {})
    canvas._endConnectionEndpointDrag({ x: 1, y: 1 })
    expect(conn.to).toBe("e3")
    expect(conn.toPosition).toBe("left")
    expect(sync).toHaveBeenCalled()
  })

  it("_endConnectionEndpointDrag re-syncs the OLD decision source when moving 'from' away", () => {
    // Moving the 'from' endpoint off a decision: previousFrom (the decision) is
    // re-synced with a null new-branch id, while the new source is not a decision.
    const conn = { id: "c1", from: "d1", to: "e2", fromPort: "port_0", toPosition: "top" }
    canvas.connections = [conn]
    canvas.elements = [{ id: "d1", type: "decision" }, { id: "e2", type: "process" }, { id: "e3", type: "process" }]
    canvas.draggingConnection = conn
    canvas.draggingEndpointType = "from"
    canvas.onchange = vi.fn()
    vi.spyOn(canvas, "_findElementAtPoint").mockReturnValue(canvas.elements[2]) // e3 (not a decision)
    vi.spyOn(canvas, "_getClosestHandlePosition").mockReturnValue("bottom")
    const sync = vi.spyOn(canvas, "_syncDecisionBranches").mockImplementation(() => {})
    vi.spyOn(canvas, "updateConnections").mockImplementation(() => {})
    vi.spyOn(canvas, "selectConnection").mockImplementation(() => {})
    canvas._endConnectionEndpointDrag({ x: 1, y: 1 })
    expect(conn.from).toBe("e3")
    // old decision d1 re-synced with null (it merely lost a branch)
    expect(sync).toHaveBeenCalledWith(canvas.elements[0], null)
  })

  it("_endConnectionEndpointDrag skips a retarget that would duplicate an edge", () => {
    const conn = { id: "c1", from: "e1", to: "e2" }
    const dup = { id: "c2", from: "e3", to: "e2" }
    canvas.connections = [conn, dup]
    canvas.elements = [{ id: "e1" }, { id: "e2" }, { id: "e3" }]
    canvas.draggingConnection = conn
    canvas.draggingEndpointType = "from"
    vi.spyOn(canvas, "_findElementAtPoint").mockReturnValue(canvas.elements[2]) // e3
    const upd = vi.spyOn(canvas, "updateConnections").mockImplementation(() => {})
    canvas._endConnectionEndpointDrag({ x: 1, y: 1 })
    expect(conn.from).toBe("e1") // unchanged
    expect(upd).not.toHaveBeenCalled()
  })

  it("_endConnectionEndpointDrag ignores a drop back onto the same other element", () => {
    const conn = { id: "c1", from: "e1", to: "e2" }
    canvas.connections = [conn]
    canvas.elements = [{ id: "e1" }, { id: "e2" }]
    canvas.draggingConnection = conn
    canvas.draggingEndpointType = "from"
    vi.spyOn(canvas, "_findElementAtPoint").mockReturnValue(canvas.elements[1]) // e2 == otherId
    canvas._endConnectionEndpointDrag({ x: 1, y: 1 })
    expect(conn.from).toBe("e1")
  })

  it("_endConnectionEndpointDrag with no target just resets state + restores opacity", () => {
    const conn = { id: "c1", from: "e1", to: "e2" }
    canvas.connections = [conn]
    canvas.draggingConnection = conn
    canvas.draggingEndpointType = "from"
    canvas.connectionDragLine = svgNode()
    const group = svgNode({ "data-connection-id": "c1" })
    canvas.connectionLayer.appendChild(group)
    vi.spyOn(canvas, "_findElementAtPoint").mockReturnValue(null)
    canvas._endConnectionEndpointDrag({ x: 1, y: 1 })
    expect(group.style.opacity).toBe("1")
    expect(canvas.isDraggingConnectionEndpoint).toBe(false)
  })
})

describe("FlowchartCanvas element highlight", () => {
  let canvas
  beforeEach(() => { document.body.innerHTML = ""; canvas = mountCanvas() })
  afterEach(() => canvas.destroy())

  it("_highlightElementAtPoint adds a highlight class to a valid target", () => {
    const conn = { id: "c1", from: "e1", to: "e2" }
    canvas.draggingConnection = conn
    canvas.draggingEndpointType = "from"
    const target = { id: "e3" }
    vi.spyOn(canvas, "_findElementAtPoint").mockReturnValue(target)
    const group = svgNode({ "data-element-id": "e3" })
    canvas.elementLayer.appendChild(group)
    canvas._highlightElementAtPoint(1, 1)
    expect(canvas.highlightedElement).toBe(target)
    expect(group.classList.contains("connection-target-highlight")).toBe(true)
  })

  it("_highlightElementAtPoint uses connection.from as 'other' for a 'to' endpoint drag", () => {
    const conn = { id: "c1", from: "e1", to: "e2" }
    canvas.draggingConnection = conn
    canvas.draggingEndpointType = "to"
    vi.spyOn(canvas, "_findElementAtPoint").mockReturnValue({ id: "e5" })
    const group = svgNode({ "data-element-id": "e5" })
    canvas.elementLayer.appendChild(group)
    canvas._highlightElementAtPoint(1, 1)
    expect(canvas.highlightedElement.id).toBe("e5")
  })

  it("_highlightElementAtPoint does nothing without a dragging connection", () => {
    canvas.draggingConnection = null
    vi.spyOn(canvas, "_findElementAtPoint").mockReturnValue({ id: "e5" })
    canvas._highlightElementAtPoint(1, 1)
    expect(canvas.highlightedElement).toBeNull()
  })

  it("_highlightElementAtPoint does not highlight the connection's other endpoint", () => {
    const conn = { id: "c1", from: "e1", to: "e2" }
    canvas.draggingConnection = conn
    canvas.draggingEndpointType = "from"
    vi.spyOn(canvas, "_findElementAtPoint").mockReturnValue({ id: "e2" }) // == other
    canvas._highlightElementAtPoint(1, 1)
    expect(canvas.highlightedElement).toBeNull()
  })

  it("_highlightElementAtPoint clears when there is no element under the point", () => {
    canvas.draggingConnection = { id: "c1", from: "e1", to: "e2" }
    canvas.draggingEndpointType = "from"
    vi.spyOn(canvas, "_findElementAtPoint").mockReturnValue(null)
    expect(() => canvas._highlightElementAtPoint(1, 1)).not.toThrow()
  })

  it("_clearElementHighlight removes the highlight class and clears state", () => {
    const group = svgNode({ "data-element-id": "e3" })
    group.classList.add("connection-target-highlight")
    canvas.elementLayer.appendChild(group)
    canvas.highlightedElement = { id: "e3" }
    canvas._clearElementHighlight()
    expect(group.classList.contains("connection-target-highlight")).toBe(false)
    expect(canvas.highlightedElement).toBeNull()
  })

  it("_clearElementHighlight is a no-op with no highlighted element", () => {
    canvas.highlightedElement = null
    expect(() => canvas._clearElementHighlight()).not.toThrow()
  })
})

describe("FlowchartCanvas P5-7 shortcuts and selection", () => {
  let canvas
  beforeEach(() => { document.body.innerHTML = ""; canvas = mountCanvas() })
  afterEach(() => {
    canvas.destroy()
    vi.useRealTimers()
  })

  function addEl(id, x = 0, y = 0) {
    const el = { id, x, y, width: 100, height: 45 }
    canvas.elements.push(el)
    const g = document.createElementNS("http://www.w3.org/2000/svg", "g")
    g.setAttribute("data-element-id", id)
    canvas.elementLayer.appendChild(g)
    return el
  }

  it("normalises Caps Lock so Ctrl+C / Ctrl+Z / Ctrl+Shift+Z still fire", () => {
    const el = addEl("a")
    canvas.selectedElements = [el]
    const copy = vi.spyOn(canvas.clipboardManager, "copy").mockReturnValue(true)
    canvas.onundo = vi.fn()
    canvas.onredo = vi.fn()
    keydown({ key: "C", ctrlKey: true })
    keydown({ key: "Z", ctrlKey: true })
    keydown({ key: "Z", ctrlKey: true, shiftKey: true })
    expect(copy).toHaveBeenCalledOnce()
    expect(canvas.onundo).toHaveBeenCalledOnce()
    expect(canvas.onredo).toHaveBeenCalledOnce()
  })

  it("Shift+click toggles selection the same way Ctrl/Cmd does", () => {
    const el = addEl("e1")
    const toggle = vi.spyOn(canvas, "_toggleElementSelection")
    const startDrag = vi.spyOn(canvas, "_startDrag")
    canvas._handleElementMouseDown({ dataset: { elementId: "e1" } }, eventOn(canvas.svg, { shiftKey: true }))
    expect(toggle).toHaveBeenCalledWith(el)
    expect(startDrag).not.toHaveBeenCalled()
  })

  it("Shift+marquee on empty canvas does not clear the existing selection", () => {
    const clear = vi.spyOn(canvas, "_clearSelection")
    vi.spyOn(canvas, "_startSelectionRect").mockImplementation(() => {})
    canvas._handleCanvasMouseDown(eventOn(canvas.svg, { shiftKey: true }))
    expect(clear).not.toHaveBeenCalled()
  })

  it("Ctrl+A / Cmd+A selects every element and prevents the browser select-all", () => {
    addEl("a")
    addEl("b")
    canvas.onSelectionChanged = vi.fn()
    expect(keydown({ key: "a", ctrlKey: true })).toBe(false)
    expect(canvas.selectedElements.map(e => e.id).sort()).toEqual(["a", "b"])
    expect(canvas.onSelectionChanged).toHaveBeenCalledOnce()
    canvas._clearSelection()
    expect(keydown({ key: "A", metaKey: true })).toBe(false)
    expect(canvas.selectedElements.map(e => e.id).sort()).toEqual(["a", "b"])
  })

  it("Ctrl+A is ignored while typing in a field", () => {
    addEl("a")
    const sel = vi.spyOn(canvas, "_selectAllElements")
    const input = document.createElement("input")
    document.body.appendChild(input)
    input.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "a", ctrlKey: true }))
    expect(sel).not.toHaveBeenCalled()
  })

  it("Ctrl+A on an empty canvas still prevents the browser select-all", () => {
    canvas.onSelectionChanged = vi.fn()
    expect(keydown({ key: "a", ctrlKey: true })).toBe(false)
    expect(canvas.onSelectionChanged).not.toHaveBeenCalled()
  })

  it("paste / duplicate / delete are suppressed in preview mode", () => {
    canvas.previewMode = true
    canvas.selectedElements = [{ id: "a" }]
    vi.spyOn(canvas.clipboardManager, "hasContent", "get").mockReturnValue(true)
    const paste = vi.spyOn(canvas, "_pasteElements")
    const del = vi.spyOn(canvas, "_deleteSelectedElements")
    keydown({ key: "v", ctrlKey: true })
    keydown({ key: "d", ctrlKey: true })
    keydown({ key: "Delete" })
    expect(paste).not.toHaveBeenCalled()
    expect(del).not.toHaveBeenCalled()
  })

  it("arrow keys nudge the selection by GRID_SIZE; Shift multiplies by 5", () => {
    vi.useFakeTimers()
    const a = addEl("b", 30, 45)
    const b = addEl("a", 90, 45)
    canvas.selectedElements = [a, b]
    vi.spyOn(canvas, "updateElementPosition").mockImplementation(() => {})
    vi.spyOn(canvas, "updateConnections").mockImplementation(() => {})
    vi.spyOn(canvas, "showResizeHandles").mockImplementation(() => {})
    vi.spyOn(canvas, "showConnectionHandles").mockImplementation(() => {})
    canvas.onBeforeChange = vi.fn()
    canvas.onchange = vi.fn()

    expect(keydown({ key: "ArrowRight" })).toBe(false)
    expect(a.x).toBe(30 + GRID_SIZE)
    expect(b.x).toBe(90 + GRID_SIZE)
    expect(canvas.undoCoalesceKey).toMatch(/^nudge:a,b#\d+$/)
    expect(canvas.onBeforeChange).toHaveBeenCalledOnce()
    expect(canvas.onchange).toHaveBeenCalledOnce()
    expect(canvas.showResizeHandles).not.toHaveBeenCalled()

    keydown({ key: "ArrowLeft" })
    keydown({ key: "ArrowUp" })
    keydown({ key: "ArrowDown", shiftKey: true })
    expect(a.x).toBe(30)
    expect(b.x).toBe(90)
    expect(a.y).toBe(45 - GRID_SIZE + 5 * GRID_SIZE)
    expect(b.y).toBe(45 - GRID_SIZE + 5 * GRID_SIZE)
  })

  it("a single-element nudge refreshes that element's resize handles", () => {
    vi.useFakeTimers()
    const a = addEl("only", 15, 15)
    canvas.selectedElements = [a]
    vi.spyOn(canvas, "updateElementPosition").mockImplementation(() => {})
    vi.spyOn(canvas, "updateConnections").mockImplementation(() => {})
    const resize = vi.spyOn(canvas, "showResizeHandles").mockImplementation(() => {})
    vi.spyOn(canvas, "showConnectionHandles").mockImplementation(() => {})
    keydown({ key: "ArrowRight" })
    expect(resize).toHaveBeenCalledWith(a)
  })

  it("does not nudge when canMutate is false, nothing is selected, or the user is typing", () => {
    const a = addEl("a", 0, 0)
    canvas.selectedElements = [a]
    vi.spyOn(canvas, "updateElementPosition")
    canvas.previewMode = true
    keydown({ key: "ArrowRight" })
    expect(a.x).toBe(0)

    canvas.previewMode = false
    canvas.selectedElements = []
    expect(keydown({ key: "ArrowRight" })).not.toBe(false)

    canvas.selectedElements = [a]
    const input = document.createElement("input")
    document.body.appendChild(input)
    input.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "ArrowRight" }))
    expect(a.x).toBe(0)
  })

  it("clears the nudge coalesce key after 500ms idle, on another key, and on destroy", () => {
    vi.useFakeTimers()
    const a = addEl("a", 0, 0)
    canvas.selectedElements = [a]
    vi.spyOn(canvas, "updateElementPosition").mockImplementation(() => {})
    vi.spyOn(canvas, "updateConnections").mockImplementation(() => {})
    vi.spyOn(canvas, "showResizeHandles").mockImplementation(() => {})
    vi.spyOn(canvas, "showConnectionHandles").mockImplementation(() => {})

    keydown({ key: "ArrowRight" })
    const firstBurst = canvas.undoCoalesceKey
    keydown({ key: "ArrowRight" })
    expect(firstBurst).toMatch(/^nudge:a#\d+$/)
    expect(canvas.undoCoalesceKey).toBe(firstBurst)
    vi.advanceTimersByTime(499)
    expect(canvas.undoCoalesceKey).toBe(firstBurst)
    vi.advanceTimersByTime(1)
    expect(canvas.undoCoalesceKey).toBeNull()

    keydown({ key: "ArrowUp" })
    const secondBurst = canvas.undoCoalesceKey
    expect(secondBurst).toMatch(/^nudge:a#\d+$/)
    expect(secondBurst).not.toBe(firstBurst)
    keydown({ key: " " })
    expect(canvas.undoCoalesceKey).toBeNull()

    keydown({ key: "ArrowDown" })
    expect(canvas._nudgeBurstTimer).toBeTruthy()
    canvas.destroy()
    expect(canvas._nudgeBurstTimer).toBeNull()
    expect(canvas.undoCoalesceKey).toBeNull()
  })

  it("_endNudgeBurst leaves a non-nudge coalesce key alone", () => {
    canvas.undoCoalesceKey = "e1:label"
    canvas._endNudgeBurst()
    expect(canvas.undoCoalesceKey).toBe("e1:label")
    canvas.undoCoalesceKey = null
    canvas._endNudgeBurst()
    expect(canvas.undoCoalesceKey).toBeNull()
  })

  it("Ctrl+S ends an in-flight nudge burst before requesting save", () => {
    vi.useFakeTimers()
    const a = addEl("a", 0, 0)
    canvas.selectedElements = [a]
    vi.spyOn(canvas, "updateElementPosition").mockImplementation(() => {})
    vi.spyOn(canvas, "updateConnections").mockImplementation(() => {})
    vi.spyOn(canvas, "showResizeHandles").mockImplementation(() => {})
    vi.spyOn(canvas, "showConnectionHandles").mockImplementation(() => {})
    canvas.onSaveRequested = vi.fn()
    keydown({ key: "ArrowRight" })
    expect(canvas.undoCoalesceKey).toMatch(/^nudge:a#\d+$/)
    keydown({ key: "s", ctrlKey: true })
    expect(canvas.undoCoalesceKey).toBeNull()
    expect(canvas.onSaveRequested).toHaveBeenCalledOnce()
  })

  it("Enter opens properties for a single selected element and no-ops otherwise", () => {
    const a = addEl("a", 0, 0)
    const b = addEl("b", 100, 0)
    canvas.onElementDoubleClick = vi.fn()

    canvas.selectedElements = []
    keydown({ key: "Enter" })
    expect(canvas.onElementDoubleClick).not.toHaveBeenCalled()

    canvas.selectedElements = [a, b]
    keydown({ key: "Enter" })
    expect(canvas.onElementDoubleClick).not.toHaveBeenCalled()

    canvas.selectedElements = [a]
    keydown({ key: "Enter", ctrlKey: true })
    expect(canvas.onElementDoubleClick).not.toHaveBeenCalled()

    keydown({ key: "Enter" })
    expect(canvas.onElementDoubleClick).toHaveBeenCalledWith(a)
  })

  it("touch gestures pan on empty canvas and open properties on double-tap of an element", () => {
    const a = addEl("a", 100, 100)
    canvas.renderElement(a)
    const group = canvas.elementLayer.querySelector('[data-element-id="a"]')
    canvas.onElementDoubleClick = vi.fn()
    canvas.onZoomChange = vi.fn()
    const startPan = vi.spyOn(canvas.zoomPanManager, "startPan")
    const updatePan = vi.spyOn(canvas.zoomPanManager, "updatePan")
    const endPan = vi.spyOn(canvas.zoomPanManager, "endPan")

    // Multi-touch is ignored
    canvas._handleTouchStart({ touches: [{ clientX: 0, clientY: 0 }, { clientX: 1, clientY: 1 }], target: canvas.svg })
    expect(startPan).not.toHaveBeenCalled()

    // Unknown element id is ignored
    const ghost = document.createElementNS("http://www.w3.org/2000/svg", "g")
    ghost.setAttribute("data-element-id", "ghost")
    canvas._handleTouchStart({ touches: [{ clientX: 0, clientY: 0 }], target: ghost })

    // Single tap selects element; rapid second tap fires onElementDoubleClick
    vi.spyOn(Date, "now").mockReturnValueOnce(1000).mockReturnValueOnce(1200).mockReturnValueOnce(5000)
    canvas.svg.dispatchEvent(Object.assign(new Event("touchstart", { bubbles: true }), {
      touches: [{ clientX: 100, clientY: 100 }],
    }))
    canvas._handleTouchStart({ touches: [{ clientX: 100, clientY: 100 }], target: group })
    expect(canvas.onElementDoubleClick).not.toHaveBeenCalled()
    canvas._handleTouchStart({ touches: [{ clientX: 100, clientY: 100 }], target: group })
    expect(canvas.onElementDoubleClick).toHaveBeenCalledWith(a)
    // Slow tap after >350ms only resets tap tracking
    canvas._handleTouchStart({ touches: [{ clientX: 100, clientY: 100 }], target: group })
    expect(canvas.onElementDoubleClick).toHaveBeenCalledTimes(1)

    // Ensure not panning first, then verify touchmove/touchend are no-ops when idle
    canvas._handleTouchEnd()
    updatePan.mockClear()
    startPan.mockClear()
    endPan.mockClear()
    canvas._handleTouchMove({ touches: [{ clientX: 20, clientY: 30 }], preventDefault: vi.fn() })
    canvas._handleTouchEnd()
    expect(updatePan).not.toHaveBeenCalled()

    canvas._handleTouchStart({ touches: [{ clientX: 10, clientY: 15 }], target: canvas.svg })
    expect(startPan).toHaveBeenCalledWith(10, 15)
    canvas.svg.dispatchEvent(Object.assign(new Event("touchmove", { bubbles: true, cancelable: true }), {
      touches: [{ clientX: 25, clientY: 35 }],
    }))
    expect(updatePan).toHaveBeenCalledWith(25, 35)
    expect(canvas.onZoomChange).toHaveBeenCalled()

    // Multi-touch during pan does not updatePan
    canvas._handleTouchMove({ touches: [{}, {}], preventDefault: vi.fn() })
    canvas.svg.dispatchEvent(new Event("touchend", { bubbles: true }))
    expect(endPan).toHaveBeenCalled()
  })
})
