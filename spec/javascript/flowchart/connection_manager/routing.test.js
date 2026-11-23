import { describe, it, expect } from "vitest"
import { RoutingMixin } from "flowchart/connection_manager/routing"

// RoutingMixin is applied to FlowchartCanvas.prototype. Every method here is
// PURE MATH over numeric element coordinates passed as plain objects — nothing
// reads real layout (getBoundingClientRect) — so it is fully unit-testable.
// We build a bare host = the mixin itself (methods only call sibling mixin
// methods + numeric fields), and set `connectionRouting` per test.

const host = (over = {}) => Object.assign({}, RoutingMixin, over)

// process: width 80 / height 40 → hw 40, hh 20
const proc = (x, y, over = {}) => ({ id: "p", type: "process", x, y, width: 80, height: 40, ...over })

describe("RoutingMixin._getHandlePositions (standard 4-handle)", () => {
  it("places the four cardinal handles around the element center", () => {
    const h = host()._getHandlePositions(proc(100, 100))
    expect(h).toEqual({
      top: { x: 100, y: 80 },
      bottom: { x: 100, y: 120 },
      left: { x: 60, y: 100 },
      right: { x: 140, y: 100 },
    })
  })

  it("delegates to dynamic ports for a decision element (top + port_0)", () => {
    // decision with no branches → { top: input, port_0: bottom-center }
    const dec = { id: "d", type: "decision", x: 0, y: 0, width: 80, height: 60, properties: {} }
    const h = host()._getHandlePositions(dec)
    expect(h.top).toEqual({ position: "top", x: 0, y: -30 })
    expect(h.port_0).toEqual({ x: 0, y: 30 })
    expect(h.bottom).toBeUndefined()
    expect(h.left).toBeUndefined()
  })
})

describe("RoutingMixin._getHandlePosition (lookup + fallback)", () => {
  it("returns the requested cardinal handle when present", () => {
    expect(host()._getHandlePosition(proc(100, 100), "right")).toEqual({ x: 140, y: 100 })
  })

  it("falls back to top for a decision when a missing cardinal is requested", () => {
    // decision has no bottom/left/right keys → first fallback (bottom) absent,
    // then top is returned.
    const dec = { id: "d", type: "decision", x: 0, y: 0, width: 80, height: 60, properties: {} }
    expect(host()._getHandlePosition(dec, "left")).toEqual({ position: "top", x: 0, y: -30 })
  })

  it("falls back to bottom for a standard element when position is unknown", () => {
    expect(host()._getHandlePosition(proc(10, 10), "nope")).toEqual({ x: 10, y: 30 })
  })

  it("falls back to the first available handle when neither bottom nor top exist", () => {
    // Override _getHandlePositions to simulate a hypothetical port set with
    // neither "bottom" nor "top" keys — exercises the `keys[0]` last-resort path.
    const h = host({ _getHandlePositions: () => ({ port_0: { x: 1, y: 2 }, port_1: { x: 3, y: 4 } }) })
    expect(h._getHandlePosition(proc(0, 0), "nope")).toEqual({ x: 1, y: 2 })
  })

  it("falls back to the element center when there are no handles at all", () => {
    const h = host({ _getHandlePositions: () => ({}) })
    expect(h._getHandlePosition(proc(5, 9), "nope")).toEqual({ x: 5, y: 9 })
  })
})

describe("RoutingMixin._portToCardinal", () => {
  const h = host()
  it("passes cardinal positions straight through", () => {
    const el = proc(0, 0)
    expect(h._portToCardinal("top", el)).toBe("top")
    expect(h._portToCardinal("bottom", el)).toBe("bottom")
    expect(h._portToCardinal("left", el)).toBe("left")
    expect(h._portToCardinal("right", el)).toBe("right")
  })

  it("returns bottom for a nonexistent port", () => {
    expect(h._portToCardinal("port_9", proc(0, 0))).toBe("bottom")
  })

  it("maps a decision's port_0 (bottom-center) to 'bottom'", () => {
    const dec = { id: "d", type: "decision", x: 0, y: 0, width: 80, height: 60, properties: {} }
    expect(h._portToCardinal("port_0", dec)).toBe("bottom")
  })

  it("maps a dx-dominant port to right/left based on the sign of dx", () => {
    const dxHost = host({
      _getHandlePositions: () => ({ port_0: { x: 50, y: 0 }, port_1: { x: -50, y: 0 } }),
    })
    const center = proc(0, 0)
    expect(dxHost._portToCardinal("port_0", center)).toBe("right")
    expect(dxHost._portToCardinal("port_1", center)).toBe("left")
  })

  it("maps a dy-dominant port to bottom/top based on the sign of dy", () => {
    const dyHost = host({
      _getHandlePositions: () => ({ port_0: { x: 0, y: 50 }, port_1: { x: 0, y: -50 } }),
    })
    const center = proc(0, 0)
    expect(dyHost._portToCardinal("port_0", center)).toBe("bottom")
    expect(dyHost._portToCardinal("port_1", center)).toBe("top")
  })
})

describe("RoutingMixin._getClosestHandlePosition", () => {
  const h = host()
  it("finds the nearest cardinal handle to a point", () => {
    const el = proc(100, 100)
    expect(h._getClosestHandlePosition(el, 141, 100)).toBe("right")
    expect(h._getClosestHandlePosition(el, 100, 79)).toBe("top")
    expect(h._getClosestHandlePosition(el, 59, 100)).toBe("left")
    expect(h._getClosestHandlePosition(el, 100, 121)).toBe("bottom")
  })
})

describe("RoutingMixin._getOppositePosition", () => {
  const h = host()
  it.each([
    ["top", "bottom"],
    ["bottom", "top"],
    ["left", "right"],
    ["right", "left"],
    ["port_3", "top"], // unknown → top
  ])("%s => %s", (pos, expected) => {
    expect(h._getOppositePosition(pos)).toBe(expected)
  })
})

describe("RoutingMixin._calculatePath (routing mode dispatch)", () => {
  it("straight mode returns a 2-point line for vertically aligned endpoints", () => {
    const h = host({ connectionRouting: "straight" })
    const path = h._calculatePath({ x: 50, y: 0 }, { x: 50, y: 100 }, "bottom", "top")
    expect(path).toEqual([{ x: 50, y: 0 }, { x: 50, y: 100 }])
  })

  it("straight mode returns a 2-point line for horizontally aligned endpoints", () => {
    const h = host({ connectionRouting: "straight" })
    const path = h._calculatePath({ x: 0, y: 50 }, { x: 100, y: 50 }, "right", "left")
    expect(path).toEqual([{ x: 0, y: 50 }, { x: 100, y: 50 }])
  })

  it("straight mode: 'top'->'bottom' (second half of the isVertical OR) is also aligned", () => {
    const h = host({ connectionRouting: "straight" })
    const path = h._calculatePath({ x: 50, y: 100 }, { x: 50, y: 0 }, "top", "bottom")
    expect(path).toEqual([{ x: 50, y: 100 }, { x: 50, y: 0 }])
  })

  it("straight mode: 'left'->'right' (second half of the isHorizontal OR) is also aligned", () => {
    const h = host({ connectionRouting: "straight" })
    const path = h._calculatePath({ x: 100, y: 50 }, { x: 0, y: 50 }, "left", "right")
    expect(path).toEqual([{ x: 100, y: 50 }, { x: 0, y: 50 }])
  })

  it("straight mode falls through to orthogonal when endpoints are NOT aligned", () => {
    const h = host({ connectionRouting: "straight" })
    const path = h._calculatePath({ x: 0, y: 0 }, { x: 40, y: 100 }, "bottom", "top")
    expect(path).toHaveLength(4) // orthogonal
  })

  it("orthogonal mode (default) always routes right-angle segments", () => {
    const h = host({ connectionRouting: "orthogonal" })
    const path = h._calculatePath({ x: 50, y: 0 }, { x: 50, y: 100 }, "bottom", "top")
    expect(path).toHaveLength(4)
  })
})

describe("RoutingMixin._calculateOrthogonalPath", () => {
  const h = host()

  it("bottom→top: vertical-out uses a mid-Y elbow", () => {
    const path = h._calculateOrthogonalPath({ x: 0, y: 0 }, { x: 100, y: 200 }, "bottom", "top")
    expect(path).toEqual([
      { x: 0, y: 0 },
      { x: 0, y: 100 },
      { x: 100, y: 100 },
      { x: 100, y: 200 },
    ])
  })

  it("right→left: horizontal-out uses a mid-X elbow", () => {
    const path = h._calculateOrthogonalPath({ x: 0, y: 0 }, { x: 200, y: 100 }, "right", "left")
    expect(path).toEqual([
      { x: 0, y: 0 },
      { x: 100, y: 0 },
      { x: 100, y: 100 },
      { x: 200, y: 100 },
    ])
  })

  it("left→right: mirrors the mid-X elbow", () => {
    const path = h._calculateOrthogonalPath({ x: 200, y: 0 }, { x: 0, y: 100 }, "left", "right")
    expect(path).toEqual([
      { x: 200, y: 0 },
      { x: 100, y: 0 },
      { x: 100, y: 100 },
      { x: 0, y: 100 },
    ])
  })

  it("right→top: 5-point path ending in a straight-down arrow segment", () => {
    // turnX = max(from.x+20, to.x) = max(20, 300) = 300 ; turnY = to.y-25 = 175
    const path = h._calculateOrthogonalPath({ x: 0, y: 0 }, { x: 300, y: 200 }, "right", "top")
    expect(path).toEqual([
      { x: 0, y: 0 },
      { x: 300, y: 0 },
      { x: 300, y: 175 },
      { x: 300, y: 175 },
      { x: 300, y: 200 },
    ])
  })

  it("right→top: turnX honours the minHorizontalTravel floor when target is left/near", () => {
    // to.x (10) < from.x+20 (120) → turnX = 120
    const path = h._calculateOrthogonalPath({ x: 100, y: 0 }, { x: 10, y: 200 }, "right", "top")
    expect(path[1]).toEqual({ x: 120, y: 0 })
    expect(path[2]).toEqual({ x: 120, y: 175 })
    expect(path[4]).toEqual({ x: 10, y: 200 })
  })

  it("left→top: mirror — turnX = min(from.x-20, to.x)", () => {
    // min(from.x-20 = 80, to.x = -50) = -50 ; turnY = 175
    const path = h._calculateOrthogonalPath({ x: 100, y: 0 }, { x: -50, y: 200 }, "left", "top")
    expect(path).toEqual([
      { x: 100, y: 0 },
      { x: -50, y: 0 },
      { x: -50, y: 175 },
      { x: -50, y: 175 },
      { x: -50, y: 200 },
    ])
  })

  it("horizontal-out fallback (right→bottom) uses a mid-X elbow", () => {
    const path = h._calculateOrthogonalPath({ x: 0, y: 0 }, { x: 200, y: 100 }, "right", "bottom")
    expect(path).toEqual([
      { x: 0, y: 0 },
      { x: 100, y: 0 },
      { x: 100, y: 100 },
      { x: 200, y: 100 },
    ])
  })

  it("returns copies (not aliases) of the from/to endpoints", () => {
    const from = { x: 0, y: 0 }
    const to = { x: 100, y: 200 }
    const path = h._calculateOrthogonalPath(from, to, "bottom", "top")
    expect(path[0]).not.toBe(from)
    expect(path[3]).not.toBe(to)
  })
})

describe("RoutingMixin._getPortRotation", () => {
  const h = host()
  it.each([
    ["top", 0],
    ["right", 90],
    ["bottom", 180],
    ["left", 270],
  ])("standard handle %s => %s", (pos, deg) => {
    expect(h._getPortRotation(pos, proc(0, 0))).toBe(deg)
  })

  it("computes a dynamic port rotation from the element center (decision port_0 → 180)", () => {
    const dec = { id: "d", type: "decision", x: 0, y: 0, width: 80, height: 60, properties: {} }
    // port_0 is bottom-center → atan2(+hh, 0)=90° , +90 → 180
    expect(h._getPortRotation("port_0", dec)).toBe(180)
  })

  it("returns 180 for a missing dynamic port", () => {
    const dec = { id: "d", type: "decision", x: 0, y: 0, width: 80, height: 60, properties: {} }
    expect(h._getPortRotation("port_99", dec)).toBe(180)
  })
})
