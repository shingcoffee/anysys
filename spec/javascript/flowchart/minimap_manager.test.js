import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { MinimapManager, fitTransform, minimapToCanvas } from "flowchart/minimap_manager"

// MinimapManager builds SVG via createElementNS (happy-dom supports it) and does
// pure coordinate math (content bounds, fit-scale, viewport rect). All of that
// is unit-testable with concrete numbers. `_navigateTo` reads
// svg.getBoundingClientRect(); in happy-dom that rect origins at (0,0), so the
// minimap→canvas transform is still deterministic (mx = clientX). We exercise it
// on that basis.
//
// happy-dom has no layout, so the container's clientWidth/clientHeight are
// stubbed (200×140 by default, the sm+ container size) and ResizeObserver is
// replaced by a fake whose callback the tests fire by hand.
//
// NOTE: the true pixel placement under real CSS layout (non-zero rect origin,
// the 160×120 container below `sm`) is only verified in a browser — covered by
// Playwright, not here.

const el = (over = {}) => ({ x: 0, y: 0, width: 80, height: 40, type: "process", properties: {}, ...over })

const makeCanvas = (elements = [], zpm = null) => ({ elements, zoomPanManager: zpm, onZoomChange: vi.fn() })

class FakeResizeObserver {
  static instances = []
  constructor(callback) {
    this.callback = callback
    this.observed = []
    this.disconnect = vi.fn()
    FakeResizeObserver.instances.push(this)
  }
  observe(target) { this.observed.push(target) }
  fire() { this.callback([]) }
}

let container
let size
function sizeContainer(width, height) { size = { width, height } }

beforeEach(() => {
  document.body.innerHTML = ""
  FakeResizeObserver.instances = []
  vi.stubGlobal("ResizeObserver", FakeResizeObserver)
  container = document.createElement("div")
  sizeContainer(200, 140)
  Object.defineProperty(container, "clientWidth", { configurable: true, get: () => size.width })
  Object.defineProperty(container, "clientHeight", { configurable: true, get: () => size.height })
  document.body.appendChild(container)
})

afterEach(() => { vi.unstubAllGlobals() })

describe("MinimapManager constructor", () => {
  it("builds the SVG scaffold inside the container, sized from the container", () => {
    const mm = new MinimapManager(makeCanvas(), container)
    expect(mm.width).toBe(200)
    expect(mm.height).toBe(140)
    const svg = container.querySelector("svg")
    expect(svg).not.toBeNull()
    expect(svg.getAttribute("width")).toBe("200")
    expect(svg.getAttribute("height")).toBe("140")
    expect(mm.viewportRect).not.toBeNull()
    expect(mm.isDragging).toBe(false)
  })

  it("observes the container for size changes", () => {
    const mm = new MinimapManager(makeCanvas(), container)
    expect(mm._resizeObserver.observed).toEqual([container])
  })
})

describe("MinimapManager._getContentBounds", () => {
  it("computes the union bounding box of all element rects (center-based)", () => {
    const mm = new MinimapManager(makeCanvas(), container)
    const bounds = mm._getContentBounds([
      el({ x: 100, y: 100, width: 80, height: 40 }), // 60..140 , 80..120
      el({ x: 300, y: 200, width: 100, height: 60 }), // 250..350 , 170..230
    ])
    expect(bounds).toEqual({ x: 60, y: 80, width: 290, height: 150 })
  })
})

describe("MinimapManager.update", () => {
  it("hides the panel when there are no elements", () => {
    const mm = new MinimapManager(makeCanvas([]), container)
    mm.update()
    expect(container.classList.contains("hidden")).toBe(true)
  })

  it("shows the panel and draws one rect per element", () => {
    const els = [el({ x: 100, y: 100 }), el({ x: 300, y: 100 })]
    const mm = new MinimapManager(makeCanvas(els), container)
    mm.update()
    expect(container.classList.contains("hidden")).toBe(false)
    expect(mm.elementLayer.children.length).toBe(2)
    expect(mm._scale).toBeGreaterThan(0)
    expect(Number.isFinite(mm._offsetX)).toBe(true)
    expect(Number.isFinite(mm._offsetY)).toBe(true)
  })

  it("colours element rects by their type's stroke colour", () => {
    const mm = new MinimapManager(makeCanvas([el({ type: "process" })]), container)
    mm.update()
    const rect = mm.elementLayer.querySelector("rect")
    expect(rect.getAttribute("fill")).toBe("#3b82f6") // ELEMENT_COLORS.process.stroke
  })

  it("falls back to the process colour for an unrecognized element type", () => {
    const mm = new MinimapManager(makeCanvas([el({ type: "bogus_type" })]), container)
    mm.update()
    const rect = mm.elementLayer.querySelector("rect")
    expect(rect.getAttribute("fill")).toBe("#3b82f6") // ELEMENT_COLORS.process.stroke
  })

  it("prefers a per-element style override for the rect colour", () => {
    const styled = el({ properties: { style: { fill: "#111111", stroke: "#abcdef" } } })
    const mm = new MinimapManager(makeCanvas([styled]), container)
    mm.update()
    expect(mm.elementLayer.querySelector("rect").getAttribute("fill")).toBe("#abcdef")
  })

  it("enforces minimum rendered rect size (>=3 wide, >=2 tall)", () => {
    // A tiny element scaled down must never collapse below the floor.
    const tiny = el({ x: 0, y: 0, width: 1, height: 1 })
    const mm = new MinimapManager(makeCanvas([tiny]), container)
    mm.update()
    const rect = mm.elementLayer.querySelector("rect")
    expect(Number(rect.getAttribute("width"))).toBeGreaterThanOrEqual(3)
    expect(Number(rect.getAttribute("height"))).toBeGreaterThanOrEqual(2)
  })

  it("fits content to the minimap: scale = min(W/totalW, H/totalH)", () => {
    // single element 80x40 → bounds 80x40, padding 40 → totalW 160, totalH 120
    // scale = min(200/160=1.25, 140/120≈1.1667) = 1.1667
    const mm = new MinimapManager(makeCanvas([el({ x: 100, y: 100, width: 80, height: 40 })]), container)
    mm.update()
    expect(mm._scale).toBeCloseTo(140 / 120, 6)
  })
})

describe("MinimapManager._updateViewport", () => {
  it("sizes the viewport rect from the zoom/pan state and current scale", () => {
    const zpm = { panX: 10, panY: 20, viewWidth: 100, viewHeight: 60, zoomPercent: 100 }
    const mm = new MinimapManager(makeCanvas([el({ x: 100, y: 100 })], zpm), container)
    mm.update() // sets _scale/_offset* and calls _updateViewport
    const s = mm._scale
    expect(Number(mm.viewportRect.getAttribute("width"))).toBeCloseTo(100 * s, 5)
    expect(Number(mm.viewportRect.getAttribute("height"))).toBeCloseTo(60 * s, 5)
    expect(Number(mm.viewportRect.getAttribute("x"))).toBeCloseTo(10 * s + mm._offsetX, 5)
    expect(Number(mm.viewportRect.getAttribute("y"))).toBeCloseTo(20 * s + mm._offsetY, 5)
  })

  it("does nothing without a zoomPanManager or a computed scale", () => {
    const mm = new MinimapManager(makeCanvas([el()]), container)
    // no zpm, so _updateViewport (called inside update) must not throw
    expect(() => mm.update()).not.toThrow()
  })
})

describe("MinimapManager drag state", () => {
  it("mousedown starts dragging and navigates; mouseup stops", () => {
    const zpm = { panX: 0, panY: 0, viewWidth: 100, viewHeight: 60, zoomPercent: 100, _updateViewBox: vi.fn() }
    const canvas = makeCanvas([el({ x: 100, y: 100 })], zpm)
    const mm = new MinimapManager(canvas, container)
    mm.update()

    mm._handleMouseDown({ clientX: 50, clientY: 40 })
    expect(mm.isDragging).toBe(true)
    expect(zpm._updateViewBox).toHaveBeenCalled()
    expect(canvas.onZoomChange).toHaveBeenCalledWith(100)

    mm._handleMouseUp()
    expect(mm.isDragging).toBe(false)
  })

  it("mousemove only navigates while dragging", () => {
    const zpm = { panX: 0, panY: 0, viewWidth: 100, viewHeight: 60, zoomPercent: 100, _updateViewBox: vi.fn() }
    const mm = new MinimapManager(makeCanvas([el({ x: 100, y: 100 })], zpm), container)
    mm.update()

    mm.isDragging = false
    mm._handleMouseMove({ clientX: 10, clientY: 10 })
    expect(zpm._updateViewBox).not.toHaveBeenCalled()

    mm.isDragging = true
    mm._handleMouseMove({ clientX: 10, clientY: 10 })
    expect(zpm._updateViewBox).toHaveBeenCalled()
  })
})

describe("MinimapManager._navigateTo (minimap→canvas transform, origin at 0,0)", () => {
  it("centers the viewport on the clicked canvas point", () => {
    const zpm = { panX: 0, panY: 0, viewWidth: 100, viewHeight: 60, zoomPercent: 100, _updateViewBox: vi.fn() }
    const mm = new MinimapManager(makeCanvas([el({ x: 100, y: 100 })], zpm), container)
    mm.update()

    const mx = 50, my = 40 // rect origin is (0,0) in happy-dom → mx = clientX
    const canvasX = (mx - mm._offsetX) / mm._scale
    const canvasY = (my - mm._offsetY) / mm._scale

    mm._navigateTo({ clientX: mx, clientY: my })
    expect(zpm.panX).toBeCloseTo(canvasX - zpm.viewWidth / 2, 5)
    expect(zpm.panY).toBeCloseTo(canvasY - zpm.viewHeight / 2, 5)
  })

  it("is a no-op before a scale has been computed", () => {
    const zpm = { panX: 7, panY: 9, viewWidth: 100, viewHeight: 60, _updateViewBox: vi.fn() }
    const mm = new MinimapManager(makeCanvas([el()], zpm), container)
    // never called update → _scale undefined
    mm._navigateTo({ clientX: 10, clientY: 10 })
    expect(zpm.panX).toBe(7)
    expect(zpm._updateViewBox).not.toHaveBeenCalled()
  })
})

describe("P5-6 minimap math (pure)", () => {
  it("fitTransform centres the padded bounds and scales by the tighter axis", () => {
    // bounds 80×40 + 2×40 padding → 160×120; box 160×120 → scale 1, offset = padding − bounds origin
    expect(fitTransform({ x: 60, y: 80, width: 80, height: 40 }, 160, 120)).toEqual({ scale: 1, offsetX: -20, offsetY: -40 })
    // a wide box is limited by its height: 400×120 → scale 1, extra width split evenly
    const wide = fitTransform({ x: 0, y: 0, width: 80, height: 40 }, 400, 120)
    expect(wide.scale).toBe(1)
    expect(wide.offsetX).toBe((400 - 160) / 2 + 40)
    expect(wide.offsetY).toBe(40)
    expect(fitTransform({ x: 0, y: 0, width: 80, height: 40 }, 80, 60, 0)).toEqual({ scale: 1, offsetX: 0, offsetY: 10 })
  })

  it("minimapToCanvas inverts the transform", () => {
    const transform = { scale: 0.5, offsetX: 10, offsetY: 20 }
    expect(minimapToCanvas({ x: 60, y: 70 }, transform)).toEqual({ x: 100, y: 100 })
  })
})

describe("P5-6 minimap sizing from its container", () => {
  it("re-sizes and redraws when the observed container changes size (e.g. below sm)", () => {
    const zpm = { panX: 0, panY: 0, viewWidth: 100, viewHeight: 60, zoomPercent: 100, _updateViewBox: vi.fn() }
    const mm = new MinimapManager(makeCanvas([el({ x: 100, y: 100 })], zpm), container)
    mm.update()
    expect(mm._scale).toBeCloseTo(140 / 120, 6)

    sizeContainer(158, 118)
    mm._resizeObserver.fire()
    expect(mm.width).toBe(158)
    expect(mm.height).toBe(118)
    expect(mm.svg.getAttribute("width")).toBe("158")
    expect(mm._scale).toBeCloseTo(118 / 120, 6)

    // A click at the centre of the smaller minimap lands on the content centre.
    mm._navigateTo({ clientX: 79, clientY: 59 })
    expect(zpm.panX + zpm.viewWidth / 2).toBeCloseTo(100, 5)
    expect(zpm.panY + zpm.viewHeight / 2).toBeCloseTo(100, 5)
  })

  it("ignores resize callbacks that report the same size", () => {
    const mm = new MinimapManager(makeCanvas([el()]), container)
    const update = vi.spyOn(mm, "update")
    mm._resizeObserver.fire()
    expect(update).not.toHaveBeenCalled()
  })

  it("keeps the last size while the container is hidden (0 × 0)", () => {
    const mm = new MinimapManager(makeCanvas([el()]), container)
    sizeContainer(0, 0)
    const update = vi.spyOn(mm, "update")
    mm._resizeObserver.fire()
    expect(update).not.toHaveBeenCalled()
    expect(mm.width).toBe(200)
    expect(mm.height).toBe(140)
  })

  it("measures again when shown, and skips drawing until the container has a size", () => {
    sizeContainer(0, 0)
    const mm = new MinimapManager(makeCanvas([el()]), container)
    expect(mm.width).toBe(0)
    expect(container.querySelector("svg").hasAttribute("width")).toBe(false)

    mm.update()
    expect(mm.elementLayer.children.length).toBe(0)
    expect(mm._scale).toBeUndefined()

    sizeContainer(160, 120)
    mm.update()
    expect(mm.width).toBe(160)
    expect(mm.elementLayer.children.length).toBe(1)
  })

  it("treats a container with only one measurable axis as unsized", () => {
    sizeContainer(160, 0)
    const mm = new MinimapManager(makeCanvas([el()]), container)
    mm.update()
    expect(mm.width).toBe(0)
    expect(mm.elementLayer.children.length).toBe(0)
  })

  it("destroy disconnects the observer and removes the SVG", () => {
    const mm = new MinimapManager(makeCanvas(), container)
    const observer = mm._resizeObserver
    mm.destroy()
    expect(observer.disconnect).toHaveBeenCalled()
    expect(mm._resizeObserver).toBeNull()
    expect(container.querySelector("svg")).toBeNull()
    expect(() => mm.destroy()).not.toThrow()
  })
})
