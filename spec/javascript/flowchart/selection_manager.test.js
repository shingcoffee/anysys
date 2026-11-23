import { describe, it, expect, vi, beforeEach } from "vitest"
import { SelectionManagerMixin, SelectionManager } from "flowchart/selection_manager"

// The mixin manipulates canvas.selectedElements (data) and toggles a "selected"
// class on the matching [data-element-id] SVG group (light DOM). Connection /
// resize handle plumbing is stubbed. AABB intersection + rect math are pure.

function makeHost(elements = []) {
  const elementLayer = document.createElementNS("http://www.w3.org/2000/svg", "g")
  const selectionLayer = document.createElementNS("http://www.w3.org/2000/svg", "g")
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  svg.appendChild(elementLayer)
  svg.appendChild(selectionLayer)
  document.body.appendChild(svg)
  for (const e of elements) {
    const g = document.createElementNS("http://www.w3.org/2000/svg", "g")
    g.setAttribute("data-element-id", e.id)
    elementLayer.appendChild(g)
  }
  const host = Object.assign(Object.create(SelectionManagerMixin), {
    elements,
    selectedElements: [],
    svg,
    elementLayer,
    selectionLayer,
    clearConnectionSelection: vi.fn(),
    showConnectionHandles: vi.fn(),
    _hideConnectionHandles: vi.fn(),
    _hideConnectionEndpointHandles: vi.fn(),
    showResizeHandles: vi.fn(),
    hideResizeHandles: vi.fn(),
    onElementSelected: vi.fn(),
    onSelectionChanged: vi.fn(),
    _deleteElement: vi.fn(),
    _getSVGPoint: vi.fn(() => ({ x: 0, y: 0 })),
  })
  return host
}

const el = (id, x, y, w = 100, h = 45) => ({ id, x, y, width: w, height: h })
const groupClass = (host, id) => host.elementLayer.querySelector(`[data-element-id="${id}"]`).classList

describe("SelectionManagerMixin — add / remove / toggle", () => {
  let host, a, b
  beforeEach(() => {
    document.body.innerHTML = ""
    a = el("a", 0, 0); b = el("b", 200, 0)
    host = makeHost([a, b])
  })

  it("_addToSelection adds once, marks the group, fires single-selection callback", () => {
    host._addToSelection(a)
    expect(host.selectedElements).toEqual([a])
    expect(groupClass(host, "a").contains("selected")).toBe(true)
    expect(host.onElementSelected).toHaveBeenCalledWith(a)
    expect(host.showResizeHandles).toHaveBeenCalledWith(a)
    // Idempotent
    host._addToSelection(a)
    expect(host.selectedElements).toHaveLength(1)
  })

  it("multi-select hides resize handles and stops firing onElementSelected", () => {
    host.onElementSelected.mockClear()
    host._addToSelection(a)
    host._addToSelection(b)
    expect(host.selectedElements).toHaveLength(2)
    expect(host.hideResizeHandles).toHaveBeenCalled()
    expect(host.onElementSelected).toHaveBeenCalledTimes(1) // only for the first
  })

  it("_removeFromSelection unmarks and, back to single, re-selects the remaining one", () => {
    host._addToSelection(a)
    host._addToSelection(b)
    host._removeFromSelection(a)
    expect(host.selectedElements).toEqual([b])
    expect(groupClass(host, "a").contains("selected")).toBe(false)
    expect(host.showResizeHandles).toHaveBeenCalledWith(b)
  })

  it("_removeFromSelection on the last element hides handles", () => {
    host._addToSelection(a)
    host._removeFromSelection(a)
    expect(host.selectedElements).toEqual([])
    expect(host._hideConnectionHandles).toHaveBeenCalled()
  })

  it("_removeFromSelection is a no-op for an element that isn't selected", () => {
    host._addToSelection(a)
    host._removeFromSelection(b) // b was never selected
    expect(host.selectedElements).toEqual([a])
  })

  it("_removeFromSelection keeps hiding resize handles when more than one element remains", () => {
    const c = el("c", 400, 0)
    host.elements.push(c)
    const g = document.createElementNS("http://www.w3.org/2000/svg", "g")
    g.setAttribute("data-element-id", "c")
    host.elementLayer.appendChild(g)
    host._addToSelection(a); host._addToSelection(b); host._addToSelection(c)
    host.hideResizeHandles.mockClear()
    host._removeFromSelection(a)
    expect(host.selectedElements.map(e => e.id)).toEqual(["b", "c"])
    expect(host.hideResizeHandles).toHaveBeenCalled()
  })

  it("_toggleElementSelection flips membership and always notifies onSelectionChanged", () => {
    host._toggleElementSelection(a)
    expect(host._isElementSelected(a)).toBe(true)
    host._toggleElementSelection(a)
    expect(host._isElementSelected(a)).toBe(false)
    expect(host.onSelectionChanged).toHaveBeenCalledTimes(2)
  })

  it("_selectElement clears then selects a single element", () => {
    host._addToSelection(a)
    host._selectElement(b)
    expect(host.selectedElements).toEqual([b])
  })

  it("_clearSelection unmarks all and empties the list", () => {
    host._addToSelection(a)
    host._addToSelection(b)
    host._clearSelection()
    expect(host.selectedElements).toEqual([])
    expect(groupClass(host, "a").contains("selected")).toBe(false)
    expect(groupClass(host, "b").contains("selected")).toBe(false)
  })

  it("_deleteSelectedElements delegates to _deleteElement per selection and clears", () => {
    host._addToSelection(a)
    host._addToSelection(b)
    host._deleteSelectedElements()
    expect(host._deleteElement).toHaveBeenCalledTimes(2)
    expect(host.selectedElements).toEqual([])
    expect(host.hideResizeHandles).toHaveBeenCalled()
  })

  it("_isAdditiveSelect is true for Ctrl, Cmd, or Shift", () => {
    expect(host._isAdditiveSelect({ ctrlKey: true })).toBe(true)
    expect(host._isAdditiveSelect({ metaKey: true })).toBe(true)
    expect(host._isAdditiveSelect({ shiftKey: true })).toBe(true)
    expect(host._isAdditiveSelect({ ctrlKey: true, shiftKey: true })).toBe(true)
    expect(host._isAdditiveSelect({})).toBe(false)
  })

  it("_selectAllElements adds every element and notifies once", () => {
    host._selectAllElements()
    expect(host.selectedElements.map(e => e.id)).toEqual(["a", "b"])
    expect(host.onSelectionChanged).toHaveBeenCalledOnce()
  })

  it("_selectAllElements is a no-op notification when the canvas is empty", () => {
    const empty = makeHost([])
    empty._selectAllElements()
    expect(empty.selectedElements).toEqual([])
    expect(empty.onSelectionChanged).not.toHaveBeenCalled()
  })
})

describe("SelectionManagerMixin — rectangle math (pure)", () => {
  const host = Object.create(SelectionManagerMixin)

  it("_calculateSelectionRect normalizes two points", () => {
    expect(host._calculateSelectionRect({ x: 30, y: 40 }, { x: 10, y: 90 }))
      .toEqual({ x: 10, y: 40, width: 20, height: 50 })
  })

  it("_elementIntersectsRect uses AABB (half-extents around center)", () => {
    const e = el("z", 100, 100) // spans x[50,150], y[77.5,122.5]
    expect(host._elementIntersectsRect(e, 0, 0, 200, 200)).toBe(true)   // rect covers it
    expect(host._elementIntersectsRect(e, 0, 0, 40, 40)).toBe(false)    // rect misses
    expect(host._elementIntersectsRect(e, 140, 0, 20, 200)).toBe(true)  // overlaps right edge
  })
})

describe("SelectionManagerMixin — selection rectangle DOM", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = makeHost([el("a", 100, 100)]) })

  it("_startSelectionRect appends a rect to the selection layer and sets crosshair", () => {
    host._startSelectionRect({ clientX: 0, clientY: 0 })
    expect(host.isSelecting).toBe(true)
    expect(host.selectionLayer.querySelector("rect")).not.toBeNull()
    expect(host.svg.style.cursor).toBe("crosshair")
  })

  it("_selectElementsInRect selects the intersecting elements", () => {
    host._selectElementsInRect({ x: 0, y: 0, width: 300, height: 300 }, false)
    expect(host.selectedElements.map(e => e.id)).toEqual(["a"])
  })

  it("_highlightElementsInRect toggles selection-preview class", () => {
    host._highlightElementsInRect({ x: 0, y: 0, width: 300, height: 300 })
    expect(groupClass(host, "a").contains("selection-preview")).toBe(true)
    host._clearSelectionHighlights()
    expect(groupClass(host, "a").contains("selection-preview")).toBe(false)
  })

  it("_highlightElementsInRect skips an element with no rendered group", () => {
    host.elements.push(el("ghost", 100, 100)) // no matching [data-element-id] node
    expect(() => host._highlightElementsInRect({ x: 0, y: 0, width: 300, height: 300 })).not.toThrow()
  })

  it("_updateSelectionRect is a no-op before a drag has started", () => {
    expect(() => host._updateSelectionRect({ x: 10, y: 10 })).not.toThrow()
    expect(host.selectionRect).toBeUndefined()
  })

  it("_updateSelectionRect resizes the rect and previews intersecting elements as the drag proceeds", () => {
    host._startSelectionRect({ clientX: 0, clientY: 0 }) // selectionStart = (0,0) via stubbed _getSVGPoint
    host._updateSelectionRect({ x: 300, y: 300 })
    expect(host.selectionRect.getAttribute("width")).toBe("300")
    expect(host.selectionRect.getAttribute("height")).toBe("300")
    expect(groupClass(host, "a").contains("selection-preview")).toBe(true)
  })

  it("_endSelectionRect just stops selecting when no drag rect exists", () => {
    host._endSelectionRect({ clientX: 0, clientY: 0 })
    expect(host.isSelecting).toBe(false)
  })

  it("_endSelectionRect selects contained elements and cleans up the drag state", () => {
    host._getSVGPoint = vi.fn()
      .mockReturnValueOnce({ x: 0, y: 0 })     // _startSelectionRect
      .mockReturnValueOnce({ x: 300, y: 300 }) // _endSelectionRect
    host._startSelectionRect({ clientX: 0, clientY: 0 })
    host._endSelectionRect({ clientX: 300, clientY: 300, ctrlKey: false })

    expect(host.selectedElements.map(e => e.id)).toEqual(["a"])
    expect(host.selectionRect).toBeNull()
    expect(host.isSelecting).toBe(false)
    expect(host.selectionStart).toBeNull()
    expect(host.selectionLayer.querySelector("rect")).toBeNull()
    expect(host.svg.style.cursor).toBe("default")
  })

  it("_endSelectionRect adds to the existing selection when ctrlKey/metaKey is held", () => {
    const b = el("b", 400, 400)
    host.elements.push(b)
    const g = document.createElementNS("http://www.w3.org/2000/svg", "g")
    g.setAttribute("data-element-id", "b")
    host.elementLayer.appendChild(g)
    host._addToSelection(b)

    host._getSVGPoint = vi.fn()
      .mockReturnValueOnce({ x: 0, y: 0 })
      .mockReturnValueOnce({ x: 300, y: 300 })
    host._startSelectionRect({ clientX: 0, clientY: 0 })
    host._endSelectionRect({ clientX: 300, clientY: 300, metaKey: true })

    expect(host.selectedElements.map(e => e.id).sort()).toEqual(["a", "b"])
  })

  it("_endSelectionRect adds to the existing selection when Shift is held", () => {
    const b = el("b", 400, 400)
    host.elements.push(b)
    const g = document.createElementNS("http://www.w3.org/2000/svg", "g")
    g.setAttribute("data-element-id", "b")
    host.elementLayer.appendChild(g)
    host._addToSelection(b)

    host._getSVGPoint = vi.fn()
      .mockReturnValueOnce({ x: 0, y: 0 })
      .mockReturnValueOnce({ x: 300, y: 300 })
    host._startSelectionRect({ clientX: 0, clientY: 0 })
    host._endSelectionRect({ clientX: 300, clientY: 300, shiftKey: true })

    expect(host.selectedElements.map(e => e.id).sort()).toEqual(["a", "b"])
  })
})

describe("SelectionManager class (delegates to mixin, bound to canvas)", () => {
  it("select/clear/toggle proxy onto the wrapped canvas", () => {
    const canvas = makeHost([el("a", 0, 0), el("b", 1, 1)])
    const sm = new SelectionManager(canvas)
    sm.addToSelection(canvas.elements[0])
    expect(sm.isElementSelected(canvas.elements[0])).toBe(true)
    sm.selectElement(canvas.elements[1])
    expect(canvas.selectedElements.map(e => e.id)).toEqual(["b"])
    sm.clearSelection()
    expect(canvas.selectedElements).toEqual([])
  })

  it("removeFromSelection and toggleElementSelection proxy onto the wrapped canvas", () => {
    const canvas = makeHost([el("a", 0, 0)])
    const sm = new SelectionManager(canvas)

    sm.addToSelection(canvas.elements[0])
    sm.removeFromSelection(canvas.elements[0])
    expect(canvas.selectedElements).toEqual([])

    sm.toggleElementSelection(canvas.elements[0])
    expect(sm.isElementSelected(canvas.elements[0])).toBe(true)
    sm.toggleElementSelection(canvas.elements[0])
    expect(sm.isElementSelected(canvas.elements[0])).toBe(false)
  })

  it("suppresses connection and resize handles in _addToSelection and _removeFromSelection when canMutate is false", () => {
    const a = el("a", 0, 0)
    const b = el("b", 10, 10)
    const host = Object.assign(makeHost([a, b]), {
      canMutate: () => false,
      onElementSelected: vi.fn(),
    })
    host._addToSelection(a)
    host._addToSelection(b)
    expect(host.showConnectionHandles).not.toHaveBeenCalled()
    expect(host.showResizeHandles).not.toHaveBeenCalled()
    expect(host.hideResizeHandles).toHaveBeenCalled()

    host._removeFromSelection(b)
    expect(host.showConnectionHandles).not.toHaveBeenCalled()
    expect(host.showResizeHandles).not.toHaveBeenCalled()
    expect(host.onElementSelected).toHaveBeenCalledWith(a)
  })
})
