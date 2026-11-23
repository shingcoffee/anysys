import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import {
  getCSRFToken,
  escapeHtml,
  fuzzyMatch,
  generateId,
  generateStepId,
  snapToGrid,
  distance,
  clamp,
  createSvgElement,
  setAttributes,
  createGroup,
  createRect,
  createCircle,
  createEllipse,
  createLine,
  createPath,
  createPolygon,
  createText,
} from "utils"

const SVG_NS = "http://www.w3.org/2000/svg"

describe("DOM utilities", () => {
  afterEach(() => {
    document.head.innerHTML = ""
  })

  describe("getCSRFToken", () => {
    it("returns the meta tag content when present", () => {
      document.head.innerHTML = `<meta name="csrf-token" content="tok123">`
      expect(getCSRFToken()).toBe("tok123")
    })

    it("returns empty string when the meta tag is absent", () => {
      expect(getCSRFToken()).toBe("")
    })
  })

  describe("escapeHtml", () => {
    it("escapes all five special characters", () => {
      expect(escapeHtml(`<a href="x" title='y'>&</a>`)).toBe(
        "&lt;a href=&quot;x&quot; title=&#39;y&#39;&gt;&amp;&lt;/a&gt;"
      )
    })

    it("escapes ampersand before other entities (no double-escaping)", () => {
      expect(escapeHtml("&lt;")).toBe("&amp;lt;")
    })

    it("returns empty string for null/undefined", () => {
      expect(escapeHtml(null)).toBe("")
      expect(escapeHtml(undefined)).toBe("")
    })

    it("coerces non-strings to string", () => {
      expect(escapeHtml(42)).toBe("42")
    })
  })
})

describe("String utilities", () => {
  describe("fuzzyMatch", () => {
    it("returns true for a direct substring", () => {
      expect(fuzzyMatch("hello world", "world")).toBe(true)
    })

    it("matches non-contiguous characters in order", () => {
      expect(fuzzyMatch("hello world", "hlwd")).toBe(true)
    })

    it("returns false when order is wrong", () => {
      expect(fuzzyMatch("hello", "leh")).toBe(false)
    })

    it("returns false for empty inputs", () => {
      expect(fuzzyMatch("", "x")).toBe(false)
      expect(fuzzyMatch("x", "")).toBe(false)
    })
  })

  describe("generateId", () => {
    it("uses the default 'el' prefix", () => {
      expect(generateId()).toMatch(/^el_[a-z0-9]+$/)
    })

    it("honors a custom prefix", () => {
      expect(generateId("conn")).toMatch(/^conn_[a-z0-9]+$/)
    })

    it("produces distinct values across calls", () => {
      expect(generateId()).not.toBe(generateId())
    })
  })

  describe("generateStepId", () => {
    it("prefixes with 'step_' and uses crypto.randomUUID when available", () => {
      const spy = vi.spyOn(crypto, "randomUUID").mockReturnValue("uuid-1234")
      expect(generateStepId()).toBe("step_uuid-1234")
      spy.mockRestore()
    })

    it("falls back to a random suffix when randomUUID is unavailable", () => {
      const original = crypto.randomUUID
      // eslint-disable-next-line no-import-assign
      crypto.randomUUID = undefined
      expect(generateStepId()).toMatch(/^step_[a-z0-9]+$/)
      crypto.randomUUID = original
    })
  })
})

describe("Math utilities", () => {
  describe("snapToGrid", () => {
    it("rounds to the nearest multiple of the grid size", () => {
      expect(snapToGrid(23, 15)).toBe(30)
      expect(snapToGrid(22, 15)).toBe(15)
      expect(snapToGrid(0, 15)).toBe(0)
    })

    it("handles negatives", () => {
      expect(snapToGrid(-8, 15)).toBe(-15)
      expect(snapToGrid(-7, 15)).toBe(-0)
    })
  })

  describe("distance", () => {
    it("computes a 3-4-5 triangle", () => {
      expect(distance(0, 0, 3, 4)).toBe(5)
    })

    it("is zero for coincident points", () => {
      expect(distance(2, 2, 2, 2)).toBe(0)
    })
  })

  describe("clamp", () => {
    it("passes through values inside the range", () => {
      expect(clamp(5, 0, 10)).toBe(5)
    })

    it("clamps below min and above max", () => {
      expect(clamp(-3, 0, 10)).toBe(0)
      expect(clamp(99, 0, 10)).toBe(10)
    })
  })
})

describe("SVG utilities", () => {
  it("createSvgElement builds an element in the SVG namespace and sets attrs", () => {
    const el = createSvgElement("rect", { x: 1, width: 5 })
    expect(el.namespaceURI).toBe(SVG_NS)
    expect(el.tagName.toLowerCase()).toBe("rect")
    expect(el.getAttribute("x")).toBe("1")
    expect(el.getAttribute("width")).toBe("5")
  })

  it("setAttributes skips null and undefined values", () => {
    const el = createSvgElement("g")
    setAttributes(el, { a: "1", b: null, c: undefined, d: 0 })
    expect(el.getAttribute("a")).toBe("1")
    expect(el.hasAttribute("b")).toBe(false)
    expect(el.hasAttribute("c")).toBe(false)
    expect(el.getAttribute("d")).toBe("0") // 0 is not null
  })

  it("createGroup makes a <g>", () => {
    expect(createGroup().tagName.toLowerCase()).toBe("g")
  })

  it("createRect positions and sizes a rect", () => {
    const r = createRect(1, 2, 3, 4, { fill: "red" })
    expect(r.tagName.toLowerCase()).toBe("rect")
    expect([r.getAttribute("x"), r.getAttribute("y"), r.getAttribute("width"), r.getAttribute("height")]).toEqual(["1", "2", "3", "4"])
    expect(r.getAttribute("fill")).toBe("red")
  })

  it("createCircle sets cx/cy/r", () => {
    const c = createCircle(5, 6, 7)
    expect([c.getAttribute("cx"), c.getAttribute("cy"), c.getAttribute("r")]).toEqual(["5", "6", "7"])
  })

  it("createEllipse sets cx/cy/rx/ry", () => {
    const e = createEllipse(1, 2, 3, 4)
    expect([e.getAttribute("cx"), e.getAttribute("cy"), e.getAttribute("rx"), e.getAttribute("ry")]).toEqual(["1", "2", "3", "4"])
  })

  it("createLine sets both endpoints", () => {
    const l = createLine(0, 0, 10, 20)
    expect([l.getAttribute("x1"), l.getAttribute("y1"), l.getAttribute("x2"), l.getAttribute("y2")]).toEqual(["0", "0", "10", "20"])
  })

  it("createPath sets the d attribute", () => {
    expect(createPath("M 0 0 L 1 1").getAttribute("d")).toBe("M 0 0 L 1 1")
  })

  describe("createPolygon", () => {
    it("joins an array of points into a string", () => {
      expect(createPolygon(["0,0", "1,1", "2,0"]).getAttribute("points")).toBe("0,0 1,1 2,0")
    })

    it("passes through a string of points unchanged", () => {
      expect(createPolygon("0,0 5,5").getAttribute("points")).toBe("0,0 5,5")
    })
  })

  it("createText sets position and textContent", () => {
    const t = createText("hi", 3, 4, { fill: "blue" })
    expect(t.tagName.toLowerCase()).toBe("text")
    expect(t.textContent).toBe("hi")
    expect([t.getAttribute("x"), t.getAttribute("y")]).toEqual(["3", "4"])
    expect(t.getAttribute("fill")).toBe("blue")
  })
})
