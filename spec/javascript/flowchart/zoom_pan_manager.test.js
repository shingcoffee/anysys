import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { ZoomPanManager } from "flowchart/zoom_pan_manager"

const resizeObservers = []
class FakeResizeObserver {
  constructor(callback) {
    this.callback = callback
    this.observed = []
    this.disconnected = false
    resizeObservers.push(this)
  }
  observe(target) { this.observed.push(target) }
  disconnect() { this.disconnected = true }
}

// ZoomPanManager only touches these five surfaces of its SVG: clientWidth,
// clientHeight, getBoundingClientRect(), setAttribute(), and style. We inject a
// plain test-double SVG with *explicit, known* viewport dimensions so the
// coordinate-transform math is fully deterministic. This is NOT faking real DOM
// layout (happy-dom would zero those out) — every input is supplied by the test.
function makeSvg({ clientWidth = 800, clientHeight = 600, rect } = {}) {
  const r = rect || { left: 0, top: 0, width: clientWidth, height: clientHeight }
  return {
    clientWidth,
    clientHeight,
    style: {},
    attrs: {},
    setAttribute(name, value) { this.attrs[name] = value },
    getAttribute(name) { return this.attrs[name] },
    getBoundingClientRect: () => r,
  }
}

describe("ZoomPanManager", () => {
  let svg, zpm
  beforeEach(() => {
    resizeObservers.length = 0
    vi.stubGlobal("ResizeObserver", FakeResizeObserver)
    svg = makeSvg()
    zpm = new ZoomPanManager(svg)
  })
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("observes the SVG and refreshes the viewBox on resize", () => {
    expect(resizeObservers).toHaveLength(1)
    expect(resizeObservers[0].observed).toEqual([svg])
    svg.setAttribute("viewBox", "stale")
    resizeObservers[0].callback()
    expect(svg.getAttribute("viewBox")).toBe("0 0 800 600")
  })

  it("disconnects the ResizeObserver on destroy", () => {
    zpm.destroy()
    expect(resizeObservers[0].disconnected).toBe(true)
    expect(zpm._resizeObserver).toBeNull()
    zpm.destroy()
  })

  it("initializes at default zoom / origin pan and writes the viewBox", () => {
    expect(zpm.zoom).toBe(1)
    expect(zpm.panX).toBe(0)
    expect(zpm.panY).toBe(0)
    expect(svg.getAttribute("viewBox")).toBe("0 0 800 600")
  })

  it("derives viewWidth/viewHeight from clientSize / zoom", () => {
    expect(zpm.viewWidth).toBe(800)
    expect(zpm.viewHeight).toBe(600)
    zpm.zoom = 2
    expect(zpm.viewWidth).toBe(400)
    expect(zpm.viewHeight).toBe(300)
  })

  it("zoomPercent rounds zoom * 100", () => {
    expect(zpm.zoomPercent).toBe(100)
    zpm.zoom = 1.234
    expect(zpm.zoomPercent).toBe(123)
  })

  it("clientToSVG maps screen coords through pan/zoom", () => {
    expect(zpm.clientToSVG(400, 300)).toEqual({ x: 400, y: 300 })
    zpm.panX = 100
    zpm.panY = 50
    expect(zpm.clientToSVG(0, 0)).toEqual({ x: 100, y: 50 })
  })

  describe("zoomTo", () => {
    it("keeps the point under the cursor fixed", () => {
      zpm.zoomTo(2, 400, 300)
      expect(zpm.zoom).toBe(2)
      // Invariant: the SVG point under (400,300) is unchanged after the zoom.
      expect(zpm.clientToSVG(400, 300)).toEqual({ x: 400, y: 300 })
    })

    it("clamps above MAX_ZOOM (2.0) and below MIN_ZOOM (0.25)", () => {
      zpm.zoomTo(10, 400, 300)
      expect(zpm.zoom).toBe(2)
      zpm.zoomTo(0.01, 400, 300)
      expect(zpm.zoom).toBe(0.25)
    })

    it("is a no-op when the clamped zoom equals the current zoom", () => {
      const before = svg.getAttribute("viewBox")
      zpm.zoomTo(1, 400, 300) // already at 1
      expect(svg.getAttribute("viewBox")).toBe(before)
    })
  })

  it("zoomIn / zoomOut step by ZOOM_STEP (0.1)", () => {
    zpm.zoomIn()
    expect(zpm.zoom).toBeCloseTo(1.1)
    zpm.zoomOut()
    zpm.zoomOut()
    expect(zpm.zoom).toBeCloseTo(0.9)
  })

  it("resetZoom returns to 100% at origin", () => {
    zpm.zoom = 1.7
    zpm.panX = 123
    zpm.panY = 45
    zpm.resetZoom()
    expect(zpm.zoom).toBe(1)
    expect(zpm.panX).toBe(0)
    expect(zpm.panY).toBe(0)
  })

  it("panBy translates pan by screen delta / zoom", () => {
    zpm.panBy(100, 50)
    expect(zpm.panX).toBe(-100)
    expect(zpm.panY).toBe(-50)
    zpm.zoom = 2
    zpm.panBy(100, 50)
    expect(zpm.panX).toBe(-150)
    expect(zpm.panY).toBe(-75)
  })

  describe("pan drag lifecycle", () => {
    it("startPan / updatePan / endPan track drag and cursor", () => {
      zpm.startPan(10, 10)
      expect(zpm.isPanning).toBe(true)
      expect(svg.style.cursor).toBe("grabbing")

      zpm.updatePan(30, 10) // moved +20 right → pan left by 20
      expect(zpm.panX).toBe(-20)

      zpm.endPan()
      expect(zpm.isPanning).toBe(false)
      expect(zpm.panStart).toBeNull()
      expect(svg.style.cursor).toBe("default")
    })

    it("updatePan is a no-op when not panning", () => {
      zpm.updatePan(100, 100)
      expect(zpm.panX).toBe(0)
    })

    it("endPan restores grab cursor when space is held", () => {
      zpm.isSpaceHeld = true
      zpm.startPan(0, 0)
      zpm.endPan()
      expect(svg.style.cursor).toBe("grab")
    })
  })

  describe("fitToContent", () => {
    it("computes zoom + pan to frame all elements with padding", () => {
      zpm.fitToContent([{ x: 100, y: 100, width: 100, height: 45 }], 80)
      // content bounds 50..150 x, 77.5..122.5 y; +80 padding both sides
      // contentW=260, contentH=205; scaleX≈3.08, scaleY≈2.93 → min clamped to 2
      expect(zpm.zoom).toBe(2)
      expect(zpm.panX).toBe(-30)
      expect(zpm.panY).toBe(-2.5)
    })

    it("does nothing for an empty / missing element list", () => {
      zpm.fitToContent([])
      expect(zpm.zoom).toBe(1)
      zpm.fitToContent(undefined)
      expect(zpm.zoom).toBe(1)
    })
  })
})
