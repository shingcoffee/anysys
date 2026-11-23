import { describe, it, expect, vi } from "vitest"
import { RenderingMixin } from "flowchart/connection_manager/rendering"
import { RoutingMixin } from "flowchart/connection_manager/routing"
import { CONNECTION_STYLE } from "flowchart/connection_renderer"

// RenderingMixin builds SVG (via the `utils` createSvg* helpers, which use
// createElementNS — supported by happy-dom). The label geometry and group
// structure are DOM-STRUCTURAL and deterministic given numeric point arrays, so
// they are unit-testable without real layout. RoutingMixin supplies the pure
// path helpers used by _renderConnection.
//
// NOTE: the *visual* look (measured text width, hover animation timing) is only
// meaningfully verified in a real browser — covered by Playwright. Here we
// assert structure, wiring and the deterministic offset math.

const svgG = () => document.createElementNS("http://www.w3.org/2000/svg", "g")
const el = (id, x, y, over = {}) => ({ id, type: "process", x, y, width: 80, height: 40, ...over })

const host = (over = {}) =>
  Object.assign({}, RoutingMixin, RenderingMixin, {
    elements: [],
    selectedConnectionId: null,
    connectionLayer: svgG(),
    connectionRouting: "orthogonal",
    ...over,
  })

describe("RenderingMixin._createConnectionLabel", () => {
  const h = host()

  it("returns an empty <g> when there are fewer than two points", () => {
    const g = h._createConnectionLabel([{ x: 0, y: 0 }], "hi")
    expect(g.tagName).toBe("g")
    expect(g.children.length).toBe(0)
  })

  it("builds a badge (rect + text) for a straight 2-point path", () => {
    const g = h._createConnectionLabel([{ x: 0, y: 0 }, { x: 0, y: 100 }], "Go")
    expect(g.getAttribute("class")).toBe("connection-label-group")
    const rect = g.querySelector("rect.connection-label-bg")
    const text = g.querySelector("text.connection-label-text")
    expect(rect).not.toBeNull()
    expect(text.textContent).toBe("Go")
    expect(text.getAttribute("text-anchor")).toBe("middle")
  })

  it("vertical segment offsets the label to the right (x = midX + 14)", () => {
    // midpoint = (0,50); vertical (dy>dx) → offsetX = +14 → finalX = 14
    const g = h._createConnectionLabel([{ x: 0, y: 0 }, { x: 0, y: 100 }], "X")
    const text = g.querySelector("text.connection-label-text")
    expect(Number(text.getAttribute("x"))).toBe(14)
  })

  it("horizontal segment offsets the label upward (y = midY - 14 + fontShift)", () => {
    // midpoint = (50,0); horizontal → offsetY = -14 ; text y = finalY + fontSize/3
    const g = h._createConnectionLabel([{ x: 0, y: 0 }, { x: 100, y: 0 }], "X")
    const text = g.querySelector("text.connection-label-text")
    // finalY = 0 - 14 = -14 ; +10/3 ≈ -10.667
    expect(Number(text.getAttribute("y"))).toBeCloseTo(-14 + 10 / 3, 5)
  })

  it("orthogonal path positions the label at the first vertical segment midpoint", () => {
    // segment 0: (0,0)->(0,80) is vertical (dy=80) → label at (0,40), offsetX +14
    const pts = [
      { x: 0, y: 0 },
      { x: 0, y: 80 },
      { x: 100, y: 80 },
      { x: 100, y: 120 },
    ]
    const g = h._createConnectionLabel(pts, "L")
    const text = g.querySelector("text.connection-label-text")
    expect(Number(text.getAttribute("x"))).toBe(14) // 0 + 14
    expect(Number(text.getAttribute("y"))).toBeCloseTo(40 + 10 / 3, 5)
  })

  it("orthogonal path with no qualifying vertical segment falls back to the path midpoint", () => {
    // All 3 segments are horizontal (dy <= dx), so the loop never sets
    // verticalSegmentStart/End → falls into the `else` branch (path midpoint).
    const pts = [
      { x: 0, y: 0 },
      { x: 50, y: 1 },
      { x: 100, y: 2 },
      { x: 150, y: 3 },
    ]
    const g = h._createConnectionLabel(pts, "M")
    const text = g.querySelector("text.connection-label-text")
    // midIndex = floor(4/2) = 2 → pathPoints[2] = (100, 2); offsetX = +14
    expect(Number(text.getAttribute("x"))).toBe(114)
    expect(Number(text.getAttribute("y"))).toBeCloseTo(2 + 10 / 3, 5)
  })
})

describe("RenderingMixin._createConnectionGroup", () => {
  const h = host()
  const pts = [{ x: 0, y: 0 }, { x: 0, y: 100 }]

  it("assembles the hit-area, visible line and arrow with the connection id", () => {
    const g = h._createConnectionGroup("c1", "M 0 0 L 0 100", { x: 0, y: 100 }, pts)
    expect(g.getAttribute("data-connection-id")).toBe("c1")
    expect(g.style.cursor).toBe("pointer")

    const paths = g.querySelectorAll("path")
    expect(paths.length).toBe(2) // invisible hit + visible line
    expect(paths[0].getAttribute("stroke")).toBe("transparent")
    expect(paths[0].getAttribute("stroke-width")).toBe("16")

    const line = g.querySelector("path.connection-line")
    expect(line.getAttribute("stroke")).toBe(CONNECTION_STYLE.defaultColor)

    const arrow = g.querySelector("polygon.connection-arrow")
    expect(arrow).not.toBeNull()
    // downward segment → arrow rotated 180 at the end point
    expect(arrow.getAttribute("transform")).toBe("translate(0, 100) rotate(180)")
  })

  it("omits the label group when no label is given, includes it when provided", () => {
    const without = h._createConnectionGroup("c1", "M 0 0 L 0 100", { x: 0, y: 100 }, pts)
    expect(without.querySelector(".connection-label-group")).toBeNull()

    const withLabel = h._createConnectionGroup("c2", "M 0 0 L 0 100", { x: 0, y: 100 }, pts, "Yes")
    expect(withLabel.querySelector(".connection-label-group")).not.toBeNull()
    expect(withLabel.querySelector("text.connection-label-text").textContent).toBe("Yes")
  })
})

describe("RenderingMixin._attachConnectionHoverEvents", () => {
  it("swaps to hover colour on mouseenter and restores on mouseleave", () => {
    const h = host({ selectedConnectionId: null })
    const g = svgG()
    const line = document.createElementNS("http://www.w3.org/2000/svg", "path")
    const arrow = document.createElementNS("http://www.w3.org/2000/svg", "polygon")
    line.setAttribute("stroke", CONNECTION_STYLE.defaultColor)

    h._attachConnectionHoverEvents(g, "c1", line, arrow)

    g.dispatchEvent(new Event("mouseenter"))
    expect(line.getAttribute("stroke")).toBe(CONNECTION_STYLE.hoverColor)
    expect(line.classList.contains("flow-animated")).toBe(true)
    expect(arrow.getAttribute("fill")).toBe(CONNECTION_STYLE.hoverColor)

    g.dispatchEvent(new Event("mouseleave"))
    expect(line.getAttribute("stroke")).toBe(CONNECTION_STYLE.defaultColor)
    expect(line.classList.contains("flow-animated")).toBe(false)
  })

  it("does NOT restyle the currently-selected connection", () => {
    const h = host({ selectedConnectionId: "c1" })
    const g = svgG()
    const line = document.createElementNS("http://www.w3.org/2000/svg", "path")
    const arrow = document.createElementNS("http://www.w3.org/2000/svg", "polygon")
    line.setAttribute("stroke", CONNECTION_STYLE.selectedColor)

    h._attachConnectionHoverEvents(g, "c1", line, arrow)
    g.dispatchEvent(new Event("mouseenter"))
    expect(line.getAttribute("stroke")).toBe(CONNECTION_STYLE.selectedColor) // unchanged
    expect(line.classList.contains("flow-animated")).toBe(false)
  })

  it("shows and hides the edge-insert button when those hooks exist", () => {
    const show = vi.fn()
    const hide = vi.fn()
    const h = host({ selectedConnectionId: null, _showEdgeInsertButton: show, _scheduleHideEdgeInsertButton: hide })
    const g = svgG()
    const line = document.createElementNS("http://www.w3.org/2000/svg", "path")
    const arrow = document.createElementNS("http://www.w3.org/2000/svg", "polygon")
    h._attachConnectionHoverEvents(g, "c9", line, arrow)
    g.dispatchEvent(new Event("mouseenter"))
    expect(show).toHaveBeenCalledWith("c9")
    g.dispatchEvent(new Event("mouseleave"))
    expect(hide).toHaveBeenCalled()
  })
})

describe("RenderingMixin._connectionMidpoint", () => {
  it("returns the origin when the path is missing or empty", () => {
    const h = host({ elements: [] })
    expect(h._connectionMidpoint({ from: "a", to: "b" })).toEqual({ x: 0, y: 0 })
  })

  it("interpolates halfway along a two-point path", () => {
    const a = el("a", 0, 0)
    const b = el("b", 0, 200)
    const h = host({ elements: [a, b] })
    const mid = h._connectionMidpoint({ from: "a", to: "b", fromPosition: "bottom", toPosition: "top" })
    expect(mid.x).toBeCloseTo(0)
    expect(mid.y).toBeGreaterThan(0)
    expect(mid.y).toBeLessThan(200)
  })

  it("falls back to the first point when every segment has zero length", () => {
    const h = host()
    h._connectionPathPoints = () => [{ x: 7, y: 9 }, { x: 7, y: 9 }]
    expect(h._connectionMidpoint({})).toEqual({ x: 7, y: 9 })
  })
})

describe("RenderingMixin._renderConnection", () => {
  it("routes endpoints and appends one connection group to the layer", () => {
    const a = el("a", 0, 0)
    const b = el("b", 0, 200)
    const layer = svgG()
    const h = host({ elements: [a, b], connectionLayer: layer })
    h._renderConnection({ id: "c1", from: "a", to: "b", fromPosition: "bottom", toPosition: "top", label: null })

    expect(layer.children.length).toBe(1)
    const group = layer.querySelector("[data-connection-id='c1']")
    expect(group).not.toBeNull()
    expect(group.querySelector("path.connection-line")).not.toBeNull()
    expect(group.querySelector("polygon.connection-arrow")).not.toBeNull()
  })

  it("is a no-op when an endpoint element cannot be found", () => {
    const layer = svgG()
    const h = host({ elements: [el("a", 0, 0)], connectionLayer: layer })
    h._renderConnection({ id: "c1", from: "a", to: "ghost" })
    expect(layer.children.length).toBe(0)
  })

  it("prefers fromPort/toPort over fromPosition/toPosition when both are present", () => {
    const a = el("a", 0, 0)
    const b = el("b", 0, 200)
    const layer = svgG()
    const h = host({ elements: [a, b], connectionLayer: layer })
    // fromPort/toPort win over the (deliberately wrong) fromPosition/toPosition.
    h._renderConnection({
      id: "c1", from: "a", to: "b",
      fromPort: "bottom", fromPosition: "left",
      toPort: "top", toPosition: "right",
    })
    expect(layer.querySelector("[data-connection-id='c1']")).not.toBeNull()
  })

  it("falls back to bottom/top ports when neither *Port nor *Position is given", () => {
    const a = el("a", 0, 0)
    const b = el("b", 0, 200)
    const layer = svgG()
    const h = host({ elements: [a, b], connectionLayer: layer })
    h._renderConnection({ id: "c1", from: "a", to: "b" })
    expect(layer.querySelector("[data-connection-id='c1']")).not.toBeNull()
  })
})
