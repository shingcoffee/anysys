import { describe, it, expect } from "vitest"
import { ElementReachability } from "controllers/property_editor/element_io/reachability"

// Pure topology over canvas.connections — no DOM, no layout.
const canvasOf = (elements, connections) => ({ elements, connections })
const els = (...ids) => ids.map((id) => ({ id }))
const conn = (from, to) => ({ from, to })

describe("ElementReachability", () => {
  it("returns [] for an element with no predecessors", () => {
    const r = new ElementReachability(canvasOf(els("a", "b"), [conn("a", "b")]))
    expect(r.predecessors("a")).toEqual([])
  })

  it("orders predecessors farthest-first, nearest-last on a linear chain", () => {
    // a -> b -> c
    const r = new ElementReachability(canvasOf(els("a", "b", "c"), [conn("a", "b"), conn("b", "c")]))
    expect(r.predecessors("c")).toEqual(["a", "b"])
    expect(r.predecessors("b")).toEqual(["a"])
  })

  it("collects all upstream predecessors across a diamond", () => {
    // a -> b, a -> c, b -> d, c -> d
    const r = new ElementReachability(
      canvasOf(els("a", "b", "c", "d"), [conn("a", "b"), conn("a", "c"), conn("b", "d"), conn("c", "d")])
    )
    const preds = r.predecessors("d")
    expect(new Set(preds)).toEqual(new Set(["a", "b", "c"]))
    // nearest (direct parents) appear after farthest (a)
    expect(preds[0]).toBe("a")
  })

  it("tolerates cycles without infinite looping (visited guard)", () => {
    // In a 2-cycle a<->b, the BFS reaches every node in the cycle (including the
    // start itself) before the visited guard halts it — characterize that.
    const r = new ElementReachability(canvasOf(els("a", "b"), [conn("a", "b"), conn("b", "a")]))
    expect(new Set(r.predecessors("a"))).toEqual(new Set(["a", "b"]))
    expect(new Set(r.predecessors("b"))).toEqual(new Set(["a", "b"]))
  })

  it("ignores connections whose target is not a known element", () => {
    const r = new ElementReachability(canvasOf(els("a"), [conn("a", "ghost")]))
    expect(r.predecessors("a")).toEqual([])
  })

  it("handles a null/empty canvas gracefully", () => {
    const r = new ElementReachability(null)
    expect(r.predecessors("x")).toEqual([])
  })

  it("tolerates a predecessor id that isn't itself a known element (dangling source)", () => {
    // "ghost" is referenced as a connection source but never appears in
    // canvas.elements — reverse.get("ghost") is undefined mid-walk.
    const r = new ElementReachability(canvasOf(els("b"), [conn("ghost", "b")]))
    expect(r.predecessors("b")).toEqual(["ghost"])
  })

  describe("loop back-edges (dataflow graph)", () => {
    // header → body → header (back-edge) and header → exit
    const loopCanvas = () => canvasOf(
      [{ id: "header", type: "loop" }, { id: "body" }, { id: "exit" }],
      [conn("header", "body"), conn("body", "header"), conn("header", "exit")]
    )

    it("does not treat the body as a predecessor of the loop header", () => {
      const r = new ElementReachability(loopCanvas())
      expect(r.predecessors("header")).toEqual([])
    })

    it("redirects the back-edge so the body is a predecessor of the exit", () => {
      const r = new ElementReachability(loopCanvas())
      const preds = r.predecessors("exit")
      expect(new Set(preds)).toEqual(new Set(["header", "body"]))
    })

    it("does not treat an incoming edge from outside the loop as a back-edge", () => {
      const r = new ElementReachability(canvasOf(
        [{ id: "start" }, { id: "header", type: "loop" }, { id: "body" }, { id: "exit" }],
        [conn("start", "header"), conn("header", "body"), conn("body", "header"), conn("header", "exit")]
      ))
      expect(r.predecessors("header")).toEqual(["start"])
    })

    it("keeps a header→end empty-body loop without inventing a back-edge", () => {
      const r = new ElementReachability(canvasOf(
        [{ id: "header", type: "loop" }, { id: "end", type: "end" }],
        [conn("header", "end")]
      ))
      expect(r.predecessors("end")).toEqual(["header"])
      expect(r.predecessors("header")).toEqual([])
    })

    it("drops a back-edge when the loop has no valid exit", () => {
      const r = new ElementReachability(canvasOf(
        [{ id: "header", type: "loop" }, { id: "body" }],
        [conn("header", "body"), conn("body", "header")]
      ))
      expect(r.predecessors("header")).toEqual([])
      expect(r.predecessors("body")).toEqual(["header"])
    })

    it("drops a back-edge when the loop has more than two outgoing edges", () => {
      const r = new ElementReachability(canvasOf(
        [{ id: "header", type: "loop" }, { id: "body" }, { id: "exit" }, { id: "other" }],
        [conn("header", "body"), conn("header", "exit"), conn("header", "other"), conn("body", "header")]
      ))
      expect(r.predecessors("header")).toEqual([])
      expect(r.predecessors("exit")).toEqual(["header"])
      expect(r.predecessors("exit")).not.toContain("body")
    })

    it("drops back-edges when both outgoing edges return to the header", () => {
      const r = new ElementReachability(canvasOf(
        [{ id: "header", type: "loop" }, { id: "a" }, { id: "b" }],
        [conn("header", "a"), conn("header", "b"), conn("a", "header"), conn("b", "header")]
      ))
      expect(r.predecessors("header")).toEqual([])
      expect(r.predecessors("a")).toEqual(["header"])
      expect(r.predecessors("b")).toEqual(["header"])
    })
  })

  describe("nearestProducer", () => {
    it("returns the nearest predecessor that emits the pin", () => {
      // a(emits foo) -> b(emits foo) -> c
      const r = new ElementReachability(canvasOf(els("a", "b", "c"), [conn("a", "b"), conn("b", "c")]))
      const outputs = { a: ["foo"], b: ["foo"] }
      expect(r.nearestProducer("c", "foo", outputs)).toBe("b")
    })

    it("skips predecessors that don't emit the pin", () => {
      const r = new ElementReachability(canvasOf(els("a", "b", "c"), [conn("a", "b"), conn("b", "c")]))
      const outputs = { a: ["foo"], b: ["bar"] }
      expect(r.nearestProducer("c", "foo", outputs)).toBe("a")
    })

    it("returns null when no predecessor emits the pin", () => {
      const r = new ElementReachability(canvasOf(els("a", "b"), [conn("a", "b")]))
      expect(r.nearestProducer("b", "foo", { a: ["bar"] })).toBeNull()
    })

    it("returns null when producerOutputs is missing", () => {
      const r = new ElementReachability(canvasOf(els("a", "b"), [conn("a", "b")]))
      expect(r.nearestProducer("b", "foo", undefined)).toBeNull()
    })
  })
})
