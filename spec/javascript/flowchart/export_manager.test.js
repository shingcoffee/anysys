import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { ExportManager } from "flowchart/export_manager"

// NOTE: happy-dom has no real canvas backend or image decoder — `Image` never
// actually loads and `HTMLCanvasElement#getContext` returns null. To exercise
// exportPNG's rasterization (img.onload -> canvas 2d context -> toBlob) we
// stub `Image` (its `src` setter synchronously invokes `onload`, matching how
// the browser fires it once decode completes) and `HTMLCanvasElement#getContext`
// /`#toBlob`. The true pixel output under a real renderer is Playwright-covered.

function makeCanvasSvg() {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  for (const cls of ["handle-layer", "guide-layer", "selection-layer", "trace-overlay-layer", "element-layer"]) {
    const g = document.createElementNS("http://www.w3.org/2000/svg", "g")
    g.setAttribute("class", cls)
    svg.appendChild(g)
  }
  const fo = document.createElementNS("http://www.w3.org/2000/svg", "foreignObject")
  svg.appendChild(fo)
  svg.style.width = "500px"
  svg.style.height = "400px"
  return svg
}

const el = (x, y, width = 100, height = 45) => ({ x, y, width, height })

describe("ExportManager._getContentBounds", () => {
  it("returns a default box when there are no elements", () => {
    const em = new ExportManager({ elements: [] })
    expect(em._getContentBounds()).toEqual({ x: 0, y: 0, width: 400, height: 300 })
  })

  it("computes the bounding box across element half-extents", () => {
    const em = new ExportManager({ elements: [el(100, 100), el(300, 200)] })
    // minX = 100-50=50, minY=100-22.5=77.5, maxX=300+50=350, maxY=200+22.5=222.5
    expect(em._getContentBounds()).toEqual({ x: 50, y: 77.5, width: 300, height: 145 })
  })
})

describe("ExportManager._filename", () => {
  it("embeds the current date and the given extension", () => {
    const em = new ExportManager({ elements: [] })
    expect(em._filename("svg")).toMatch(/^flowchart_\d{4}-\d{2}-\d{2}\.svg$/)
    expect(em._filename("png")).toMatch(/\.png$/)
  })
})

describe("ExportManager._prepareSvgForExport", () => {
  it("clones the SVG, strips interactive layers + foreignObjects, and sets a fitted viewBox", () => {
    const svg = makeCanvasSvg()
    const em = new ExportManager({ svg, elements: [el(100, 100)] })
    const out = em._prepareSvgForExport()

    // Original is untouched (clone), and cruft is removed from the clone.
    expect(out).not.toBe(svg)
    expect(out.querySelector(".handle-layer")).toBeNull()
    expect(out.querySelector(".guide-layer")).toBeNull()
    expect(out.querySelector(".selection-layer")).toBeNull()
    expect(out.querySelector(".trace-overlay-layer")).toBeNull()
    expect(out.querySelector("foreignObject")).toBeNull()
    // The element-layer survives.
    expect(out.querySelector(".element-layer")).not.toBeNull()

    // viewBox = bounds padded by 40. bounds: x=50,y=77.5,w=100,h=45
    expect(out.getAttribute("viewBox")).toBe("10 37.5 180 125")
    expect(out.getAttribute("width")).toBe("180")
    expect(out.getAttribute("height")).toBe("125")
    expect(out.getAttribute("xmlns")).toBe("http://www.w3.org/2000/svg")
    expect(out.style.width).toBe("")
  })
})

describe("ExportManager.exportSVG", () => {
  let createObjSpy, revokeSpy, clickSpy
  beforeEach(() => {
    createObjSpy = vi.spyOn(URL, "createObjectURL").mockReturnValue("blob:fake")
    revokeSpy = vi.spyOn(URL, "revokeObjectURL").mockImplementation(() => {})
    clickSpy = vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(() => {})
  })
  afterEach(() => vi.restoreAllMocks())

  it("serializes and triggers an anchor download with an .svg filename", () => {
    const em = new ExportManager({ svg: makeCanvasSvg(), elements: [el(100, 100)] })
    em.exportSVG()
    expect(createObjSpy).toHaveBeenCalledOnce()
    // The blob passed to createObjectURL should be an SVG blob.
    expect(createObjSpy.mock.calls[0][0]).toBeInstanceOf(Blob)
    expect(createObjSpy.mock.calls[0][0].type).toBe("image/svg+xml")
    expect(clickSpy).toHaveBeenCalledOnce()
    expect(revokeSpy).toHaveBeenCalled()
  })
})

describe("ExportManager.exportPNG", () => {
  let createObjSpy, revokeSpy, clickSpy, fillRect, drawImage, toBlob

  beforeEach(() => {
    createObjSpy = vi.spyOn(URL, "createObjectURL").mockReturnValue("blob:fake")
    revokeSpy = vi.spyOn(URL, "revokeObjectURL").mockImplementation(() => {})
    clickSpy = vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(() => {})
  })
  afterEach(() => vi.restoreAllMocks())

  it("sets up an Image from a serialized SVG blob without throwing (decode itself is Playwright)", () => {
    const em = new ExportManager({ svg: makeCanvasSvg(), elements: [el(100, 100)] })
    expect(() => em.exportPNG()).not.toThrow()
    // A blob URL was created for the source SVG image.
    expect(createObjSpy).toHaveBeenCalledOnce()
    expect(createObjSpy.mock.calls[0][0].type).toBe("image/svg+xml;charset=utf-8")
  })

  describe("full raster path (Image + canvas 2d stubbed)", () => {
    beforeEach(() => {
      class FakeImage {
        // Mirrors the browser: assigning `src` after `onload` is wired fires
        // the load callback once decode "completes".
        set src(v) { this._src = v; this.onload && this.onload() }
      }
      vi.stubGlobal("Image", FakeImage)

      fillRect = vi.fn()
      drawImage = vi.fn()
      vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue({ fillStyle: null, fillRect, drawImage })
      toBlob = vi.spyOn(HTMLCanvasElement.prototype, "toBlob")
        .mockImplementation(function (cb) { cb(new Blob(["fake"], { type: "image/png" })) })
    })

    it("rasterizes onto a scaled canvas, fills white, draws the image, then downloads the PNG blob", () => {
      const em = new ExportManager({ svg: makeCanvasSvg(), elements: [el(100, 100)] })
      em.exportPNG(2)

      expect(fillRect).toHaveBeenCalled()
      expect(drawImage).toHaveBeenCalled()
      expect(toBlob).toHaveBeenCalledWith(expect.any(Function), "image/png")
      expect(clickSpy).toHaveBeenCalledOnce()
      const anchor = clickSpy.mock.instances[0]
      expect(anchor.download).toMatch(/^flowchart_\d{4}-\d{2}-\d{2}\.png$/)
      expect(revokeSpy).toHaveBeenCalled() // both the source-SVG URL and the anchor's blob URL
    })
  })
})
