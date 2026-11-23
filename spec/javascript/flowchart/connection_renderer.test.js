import { describe, it, expect } from "vitest"
import ConnectionRenderer, { CONNECTION_STYLE } from "flowchart/connection_renderer"

describe("CONNECTION_STYLE", () => {
  it("exposes the color/width configuration", () => {
    expect(CONNECTION_STYLE).toMatchObject({
      defaultColor: "#94a3b8",
      selectedColor: "#4f46e5",
      strokeWidth: 2,
      selectedStrokeWidth: 3,
      arrowSize: 5,
      cornerRadius: 8,
    })
  })
})

describe("ConnectionRenderer.pointsToPath", () => {
  it("returns empty string for fewer than two points", () => {
    expect(ConnectionRenderer.pointsToPath([])).toBe("")
    expect(ConnectionRenderer.pointsToPath([{ x: 1, y: 1 }])).toBe("")
    expect(ConnectionRenderer.pointsToPath(null)).toBe("")
  })

  it("draws a straight line for exactly two points", () => {
    expect(ConnectionRenderer.pointsToPath([{ x: 0, y: 0 }, { x: 100, y: 100 }])).toBe(
      "M 0 0 L 100 100"
    )
  })

  it("inserts a rounded corner (Q) at an interior vertex", () => {
    const d = ConnectionRenderer.pointsToPath([
      { x: 0, y: 0 },
      { x: 0, y: 100 },
      { x: 100, y: 100 },
    ])
    expect(d.startsWith("M 0 0")).toBe(true)
    expect(d).toContain("Q 0 100")
    expect(d.endsWith("L 100 100")).toBe(true)
  })

  it("degenerates to a straight L when a segment has zero length", () => {
    const d = ConnectionRenderer.pointsToPath([
      { x: 0, y: 0 },
      { x: 0, y: 0 }, // duplicate -> len1 === 0
      { x: 100, y: 0 },
    ])
    expect(d).toContain("L 0 0")
    expect(d).not.toContain("Q")
  })
})

describe("ConnectionRenderer.calculateArrowAngle", () => {
  it("returns 0 for fewer than two points", () => {
    expect(ConnectionRenderer.calculateArrowAngle([{ x: 0, y: 0 }])).toBe(0)
  })

  it("returns 180 for a downward segment (points down)", () => {
    expect(ConnectionRenderer.calculateArrowAngle([{ x: 0, y: 0 }, { x: 0, y: 100 }])).toBe(180)
  })

  it("returns 0 for an upward segment", () => {
    expect(ConnectionRenderer.calculateArrowAngle([{ x: 0, y: 100 }, { x: 0, y: 0 }])).toBe(0)
  })

  it("returns 90 for a rightward segment", () => {
    expect(ConnectionRenderer.calculateArrowAngle([{ x: 0, y: 0 }, { x: 100, y: 0 }])).toBe(90)
  })
})

describe("ConnectionRenderer.getArrowPoints", () => {
  it("uses the default arrow size", () => {
    expect(ConnectionRenderer.getArrowPoints()).toBe("0,-5 5,5 -5,5")
  })

  it("scales with an explicit size", () => {
    expect(ConnectionRenderer.getArrowPoints(3)).toBe("0,-3 3,3 -3,3")
  })
})
