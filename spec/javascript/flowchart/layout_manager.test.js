import { describe, it, expect, vi } from "vitest"
import { LayoutManager } from "flowchart/layout_manager"

const el = (id, type = "process", extra = {}) => ({
  id, type, x: 0, y: 0, width: 100, height: 45, ...extra,
})
const conn = (from, to, extra = {}) => ({ id: `${from}-${to}`, from, to, ...extra })

function makeCanvas(elements, connections) {
  return {
    elements,
    connections,
    onBeforeChange: vi.fn(),
    onchange: vi.fn(),
    onZoomChange: vi.fn(),
    updateElementPosition: vi.fn(),
    updateConnections: vi.fn(),
    zoomPanManager: { fitToContent: vi.fn(), zoomPercent: 100 },
  }
}

describe("LayoutManager.autoLayout", () => {
  it("no-ops on an empty canvas", () => {
    const canvas = makeCanvas([], [])
    new LayoutManager(canvas).autoLayout()
    expect(canvas.onBeforeChange).not.toHaveBeenCalled()
    expect(canvas.updateConnections).not.toHaveBeenCalled()
  })

  it("keeps Start as the origin, layers children, and fires one undo pair", () => {
    const start = el("s", "start", { x: 405, y: 75 })
    const a = el("a")
    const b = el("b")
    const canvas = makeCanvas([start, a, b], [conn("s", "a"), conn("a", "b")])
    new LayoutManager(canvas).autoLayout()

    expect(start.x).toBe(405)
    expect(start.y).toBe(75)
    expect(a.y).toBeGreaterThan(start.y)
    expect(b.y).toBeGreaterThan(a.y)
    expect(a.x % 15).toBe(0)
    expect(canvas.onBeforeChange).toHaveBeenCalledOnce()
    expect(canvas.onchange).toHaveBeenCalledOnce()
    expect(canvas.updateElementPosition).toHaveBeenCalledTimes(3)
    expect(canvas.updateConnections).toHaveBeenCalledOnce()
    expect(canvas.zoomPanManager.fitToContent).toHaveBeenCalledWith(canvas.elements)
    expect(canvas.onZoomChange).toHaveBeenCalledWith(100)
  })

  it("orders decision children by source port and centres the parent over them", () => {
    const start = el("s", "start", { x: 405, y: 75 })
    const dec = el("d", "decision")
    const yes = el("yes")
    const no = el("no")
    const canvas = makeCanvas(
      [start, dec, yes, no],
      [
        conn("s", "d"),
        conn("d", "no", { fromPort: "port_1" }),
        conn("d", "yes", { fromPort: "port_0" }),
      ]
    )
    new LayoutManager(canvas).autoLayout()

    expect(yes.y).toBe(no.y)
    expect(yes.y).toBeGreaterThan(dec.y)
    expect(yes.x).toBeLessThan(no.x)
    expect(Math.abs(dec.x - (yes.x + no.x) / 2)).toBeLessThan(15)
  })

  it("ignores loop back-edges for layering and places a merge below both branches", () => {
    const start = el("s", "start", { x: 405, y: 75 })
    const a = el("a")
    const b = el("b")
    const merge = el("m")
    const canvas = makeCanvas(
      [start, a, b, merge],
      [
        conn("s", "a"),
        conn("a", "m"),
        conn("a", "b"),
        conn("b", "m"),
        conn("m", "a"),
      ]
    )
    new LayoutManager(canvas).autoLayout()

    expect(a.y).toBeGreaterThan(start.y)
    expect(b.y).toBeGreaterThan(a.y)
    expect(merge.y).toBeGreaterThan(b.y)
  })

  it("walks the deeper parent up when a merge joins branches of different depth", () => {
    const start = el("s", "start", { x: 405, y: 75 })
    const a = el("a")
    const b = el("b")
    const c = el("c")
    const merge = el("m")
    const canvas = makeCanvas(
      [start, a, b, c, merge],
      [conn("s", "a"), conn("a", "b"), conn("s", "c"), conn("b", "m"), conn("c", "m")]
    )
    new LayoutManager(canvas).autoLayout()
    expect(merge.y).toBeGreaterThan(b.y)
    expect(merge.y).toBeGreaterThan(c.y)
  })

  it("pushes apart two merge points that land on the same slot", () => {
    const start = el("s", "start", { x: 405, y: 75 })
    const a = el("a")
    const b = el("b")
    const m1 = el("m1")
    const m2 = el("m2")
    const canvas = makeCanvas(
      [start, a, b, m1, m2],
      [conn("s", "a"), conn("s", "b"), conn("a", "m1"), conn("b", "m1"), conn("a", "m2"), conn("b", "m2")]
    )
    new LayoutManager(canvas).autoLayout()
    expect(m1.y).toBe(m2.y)
    expect(Math.abs(m1.x - m2.x)).toBeGreaterThanOrEqual(15)
  })

  it("centres a merge under the split of two same-depth branches", () => {
    const start = el("s", "start", { x: 405, y: 75 })
    const left = el("left")
    const right = el("right")
    const merge = el("m")
    const canvas = makeCanvas(
      [start, left, right, merge],
      [conn("s", "left"), conn("s", "right"), conn("left", "m"), conn("right", "m")]
    )
    new LayoutManager(canvas).autoLayout()

    expect(left.y).toBe(right.y)
    expect(merge.y).toBeGreaterThan(left.y)
    expect(Math.abs(merge.x - (left.x + right.x) / 2)).toBeLessThan(15)
  })

  it("places unreachable elements in a row below the reachable layout", () => {
    const start = el("s", "start", { x: 405, y: 75 })
    const a = el("a")
    const island = el("island")
    const other = el("other")
    const canvas = makeCanvas([start, a, island, other], [conn("s", "a")])
    new LayoutManager(canvas).autoLayout()

    expect(island.y).toBe(other.y)
    expect(island.y).toBeGreaterThan(a.y)
    expect(island.x).not.toBe(other.x)
  })

  it("lays out a graph with no Start as a single unreachable row from the first element", () => {
    const a = el("a", "process", { x: 30, y: 45 })
    const b = el("b")
    const canvas = makeCanvas([a, b], [conn("a", "b")])
    new LayoutManager(canvas).autoLayout()

    expect(a.y).toBe(b.y)
    expect(a.y).toBe(45)
    expect(canvas.onBeforeChange).toHaveBeenCalledOnce()
  })

  it("separates two same-layer siblings that would otherwise share a slot", () => {
    const start = el("s", "start", { x: 405, y: 75 })
    const left = el("left")
    const right = el("right")
    const canvas = makeCanvas(
      [start, left, right],
      [conn("s", "left"), conn("s", "right")]
    )
    new LayoutManager(canvas).autoLayout()

    expect(left.y).toBe(right.y)
    expect(Math.abs(left.x - right.x)).toBeGreaterThanOrEqual(15)
  })
})

describe("P5-4 LayoutManager — canMutate guard", () => {
  it("autoLayout is a no-op when the canvas cannot mutate", () => {
    const start = el("s", "start")
    const canvas = makeCanvas([start, el("a")], [conn("s", "a")])
    canvas.canMutate = () => false
    new LayoutManager(canvas).autoLayout()
    expect(canvas.onBeforeChange).not.toHaveBeenCalled()
    expect(canvas.updateConnections).not.toHaveBeenCalled()
  })
})
