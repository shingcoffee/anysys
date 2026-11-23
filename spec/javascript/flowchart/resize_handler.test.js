import { describe, it, expect, vi } from "vitest"
import { ResizeHandlerMixin } from "flowchart/resize_handler"

// ResizeHandlerMixin draws corner handles (SVG via createElementNS — happy-dom
// OK) and computes new dimensions during a drag. The ONLY geometry-dependent
// input is `_getSVGPoint(e)` (screen→SVG coord); we stub it with concrete
// coordinates, which makes the resize math (delta → snap → clamp → recentre)
// PURE and exactly assertable.
//
// NOTE: `_getSVGPoint` itself (getScreenCTM / getBoundingClientRect) is real-
// layout and out of scope — covered by Playwright. We never call it unstubbed.

const svgG = () => document.createElementNS("http://www.w3.org/2000/svg", "g")

const host = (over = {}) =>
  Object.assign({}, ResizeHandlerMixin, {
    handleLayer: svgG(),
    svg: { style: {} },
    isResizing: false,
    selectedElements: [{}],
    updateElementPosition: vi.fn(),
    updateConnections: vi.fn(),
    showConnectionHandles: vi.fn(),
    onBeforeChange: vi.fn(),
    onchange: vi.fn(),
    _getSVGPoint: vi.fn(),
    ...over,
  })

const el = (over = {}) => ({ id: "e1", x: 200, y: 200, width: 100, height: 60, ...over })

describe("ResizeHandlerMixin.showResizeHandles / hideResizeHandles", () => {
  it("renders one handle group per corner with cursor + data attributes", () => {
    const h = host()
    h.showResizeHandles(el())
    const handles = h.handleLayer.querySelectorAll("[data-resize-handle]")
    expect(handles.length).toBe(4)
    const corners = [...handles].map(g => g.getAttribute("data-resize-handle")).sort()
    expect(corners).toEqual(["bottom-left", "bottom-right", "top-left", "top-right"])
    handles.forEach(g => expect(g.getAttribute("data-resize-element-id")).toBe("e1"))
    expect(h.handleLayer.querySelector("[data-resize-handle='top-left']").style.cursor).toBe("nw-resize")
  })

  it("re-showing clears the previous handles (no duplicates)", () => {
    const h = host()
    h.showResizeHandles(el())
    h.showResizeHandles(el())
    expect(h.handleLayer.querySelectorAll("[data-resize-handle]").length).toBe(4)
  })

  it("mouseenter darkens the handle stroke; mouseleave restores it when not resizing", () => {
    const h = host()
    h.showResizeHandles(el())
    const group = h.handleLayer.querySelector("[data-resize-handle='top-left']")
    const handle = group.querySelector(".resize-handle")

    group.dispatchEvent(new Event("mouseenter"))
    expect(handle.getAttribute("stroke-width")).toBe("2")
    expect(handle.getAttribute("stroke")).toBe("#2563eb")

    group.dispatchEvent(new Event("mouseleave"))
    expect(handle.getAttribute("stroke-width")).toBe("1.5")
    expect(handle.getAttribute("stroke")).toBe("#3b82f6")
  })

  it("mouseleave does not restore the stroke while an active resize is in progress", () => {
    const h = host()
    h.showResizeHandles(el())
    const group = h.handleLayer.querySelector("[data-resize-handle='top-left']")
    const handle = group.querySelector(".resize-handle")

    group.dispatchEvent(new Event("mouseenter"))
    h.isResizing = true
    group.dispatchEvent(new Event("mouseleave"))
    // Still the hover colour — the leave-handler bails out while isResizing.
    expect(handle.getAttribute("stroke-width")).toBe("2")
    expect(handle.getAttribute("stroke")).toBe("#2563eb")
  })

  it("hideResizeHandles removes every handle group", () => {
    const h = host()
    h.showResizeHandles(el())
    h.hideResizeHandles()
    expect(h.handleLayer.querySelectorAll("[data-resize-handle]").length).toBe(0)
  })
})

describe("ResizeHandlerMixin._handleResizeStart", () => {
  it("captures the start state and marks the canvas as resizing", () => {
    const stopPropagation = vi.fn(), preventDefault = vi.fn()
    const h = host({ _getSVGPoint: vi.fn(() => ({ x: 250, y: 230 })) })
    const element = el()
    h._handleResizeStart(element, "bottom-right", { stopPropagation, preventDefault })

    expect(stopPropagation).toHaveBeenCalled()
    expect(preventDefault).toHaveBeenCalled()
    expect(h.onBeforeChange).toHaveBeenCalled()
    expect(h.isResizing).toBe(true)
    expect(h._resizeState).toMatchObject({
      corner: "bottom-right",
      startX: 250, startY: 230,
      startWidth: 100, startHeight: 60,
      startCenterX: 200, startCenterY: 200,
    })
    expect(h.svg.style.cursor).toBe("se-resize")
  })

  it("does not start a resize when canMutate is false", () => {
    const stopPropagation = vi.fn(), preventDefault = vi.fn()
    const h = host({ canMutate: () => false })
    h._handleResizeStart(el(), "bottom-right", { stopPropagation, preventDefault })
    expect(h.isResizing).toBe(false)
    expect(h.onBeforeChange).not.toHaveBeenCalled()
  })
})

describe("ResizeHandlerMixin._handleResizeMove (delta → snap → clamp → recentre)", () => {
  const setupState = (h, element, corner, start) => {
    h.isResizing = true
    h._resizeState = {
      element, corner,
      startX: start.x, startY: start.y,
      startWidth: element.width, startHeight: element.height,
      startCenterX: element.x, startCenterY: element.y,
    }
  }

  it("bottom-right growth snaps to grid and shifts centre toward the corner", () => {
    const element = el() // 100x60 @ (200,200)
    const h = host({ _getSVGPoint: vi.fn(() => ({ x: 280, y: 260 })) })
    setupState(h, element, "bottom-right", { x: 250, y: 230 })
    h._handleResizeMove({})
    // dx=30,dy=30 → 130x90 → snap → 135x90 ; widthDelta 35 heightDelta 30
    expect(element.width).toBe(135)
    expect(element.height).toBe(90)
    expect(element.x).toBe(200 + 35 / 2) // 217.5
    expect(element.y).toBe(200 + 30 / 2) // 215
    expect(h.updateElementPosition).toHaveBeenCalledWith(element)
    expect(h.updateConnections).toHaveBeenCalled()
    expect(h.showConnectionHandles).toHaveBeenCalledWith(element)
  })

  it("top-left drag grows toward the top-left (negative multipliers)", () => {
    const element = el() // 100x60 @ (200,200)
    const h = host({ _getSVGPoint: vi.fn(() => ({ x: 130, y: 155 })) })
    // start at the top-left corner (150,170)
    setupState(h, element, "top-left", { x: 150, y: 170 })
    h._handleResizeMove({})
    // deltaX=-20 → width 100+(-20*-1)=120 snap 120 ; deltaY=-15 → height 60+15=75 snap 75
    expect(element.width).toBe(120)
    expect(element.height).toBe(75)
    // widthDelta 20, dx=-1 → x = 200 + (20/2)*-1 = 190
    expect(element.x).toBe(190)
    // heightDelta 15, dy=-1 → y = 200 + (15/2)*-1 = 192.5
    expect(element.y).toBe(192.5)
  })

  it("clamps below the minimum element size", () => {
    const element = el()
    const h = host({ _getSVGPoint: vi.fn(() => ({ x: 0, y: 0 })) })
    setupState(h, element, "bottom-right", { x: 250, y: 230 })
    h._handleResizeMove({})
    expect(element.width).toBe(60) // MIN_ELEMENT_WIDTH
    expect(element.height).toBe(30) // MIN_ELEMENT_HEIGHT
  })

  it("clamps above the maximum element size", () => {
    const element = el()
    const h = host({ _getSVGPoint: vi.fn(() => ({ x: 5000, y: 5000 })) })
    setupState(h, element, "bottom-right", { x: 250, y: 230 })
    h._handleResizeMove({})
    expect(element.width).toBe(400) // MAX_ELEMENT_WIDTH
    expect(element.height).toBe(200) // MAX_ELEMENT_HEIGHT
  })

  it("is a no-op when not resizing", () => {
    const h = host()
    h.isResizing = false
    h._resizeState = null
    h._handleResizeMove({})
    expect(h.updateElementPosition).not.toHaveBeenCalled()
  })

  it("does not draw connection handles when multiple elements are selected", () => {
    const element = el()
    const h = host({ selectedElements: [{}, {}], _getSVGPoint: vi.fn(() => ({ x: 280, y: 260 })) })
    setupState(h, element, "bottom-right", { x: 250, y: 230 })
    h._handleResizeMove({})
    expect(h.showConnectionHandles).not.toHaveBeenCalled()
  })
})

describe("ResizeHandlerMixin._handleResizeEnd", () => {
  it("snaps the final centre to grid, fires onchange and clears state", () => {
    const element = el({ x: 217.5, y: 215, width: 135, height: 90 })
    const h = host()
    h.isResizing = true
    h._resizeState = { element }
    h._handleResizeEnd()
    // snapToGrid(217.5,15)=Math.round(14.5)*15=15*15=225 ; snapToGrid(215,15)=Math.round(14.33)*15=210
    expect(element.x).toBe(225)
    expect(element.y).toBe(210)
    expect(h.updateElementPosition).toHaveBeenCalledWith(element)
    expect(h.updateConnections).toHaveBeenCalled()
    expect(h.onchange).toHaveBeenCalled()
    expect(h.isResizing).toBe(false)
    expect(h._resizeState).toBeNull()
    expect(h.svg.style.cursor).toBe("default")
  })

  it("is a no-op when there is no active resize", () => {
    const h = host()
    h.isResizing = false
    h._resizeState = null
    h._handleResizeEnd()
    expect(h.onchange).not.toHaveBeenCalled()
  })
})
