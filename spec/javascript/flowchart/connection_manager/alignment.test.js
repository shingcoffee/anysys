import { describe, it, expect, vi } from "vitest"
import { AlignmentMixin } from "flowchart/connection_manager/alignment"
import { RoutingMixin } from "flowchart/connection_manager/routing"

// AlignmentMixin repositions elements so connectors run straight. Its logic is
// PURE DATA over `elements` / `connections` — the only DOM-facing collaborators
// (updateElementPosition, updateConnections) are stubbed. It leans on
// _portToCardinal, which RoutingMixin supplies, so we mix both into the host.

const el = (id, x, y, over = {}) => ({ id, type: "process", x, y, width: 80, height: 40, ...over })

const host = (over = {}) =>
  Object.assign({}, RoutingMixin, AlignmentMixin, {
    elements: [],
    connections: [],
    updateElementPosition: vi.fn(),
    updateConnections: vi.fn(),
    ...over,
  })

describe("AlignmentMixin._alignConnectionElements", () => {
  it("snaps the target's X onto the source for a vertical (bottom→top) connection", () => {
    const a = el("a", 0, 0)
    const b = el("b", 50, 100)
    const conn = { from: "a", to: "b", fromPosition: "bottom", toPosition: "top" }
    const h = host({ elements: [a, b], connections: [conn] })
    h._alignConnectionElements(conn)
    expect(b.x).toBe(0)
    expect(h.updateElementPosition).toHaveBeenCalledWith(b)
  })

  it("snaps the target's Y onto the source for a horizontal (right→left) connection", () => {
    const a = el("a", 0, 0)
    const b = el("b", 100, 40)
    const conn = { from: "a", to: "b", fromPosition: "right", toPosition: "left" }
    const h = host({ elements: [a, b], connections: [conn] })
    h._alignConnectionElements(conn)
    expect(b.y).toBe(0)
    expect(h.updateElementPosition).toHaveBeenCalledWith(b)
  })

  it("does nothing when already aligned (no reposition, no callback)", () => {
    const a = el("a", 10, 0)
    const b = el("b", 10, 100)
    const conn = { from: "a", to: "b", fromPosition: "bottom", toPosition: "top" }
    const h = host({ elements: [a, b], connections: [conn] })
    h._alignConnectionElements(conn)
    expect(h.updateElementPosition).not.toHaveBeenCalled()
  })

  it("is a no-op when an endpoint element is missing", () => {
    const a = el("a", 0, 0)
    const conn = { from: "a", to: "ghost", fromPosition: "bottom", toPosition: "top" }
    const h = host({ elements: [a], connections: [conn] })
    expect(() => h._alignConnectionElements(conn)).not.toThrow()
    expect(h.updateElementPosition).not.toHaveBeenCalled()
  })

  it("does not move anything for a diagonal (bottom→left) mismatch", () => {
    const a = el("a", 0, 0)
    const b = el("b", 50, 100)
    const conn = { from: "a", to: "b", fromPosition: "bottom", toPosition: "left" }
    const h = host({ elements: [a, b], connections: [conn] })
    h._alignConnectionElements(conn)
    expect(b.x).toBe(50)
    expect(b.y).toBe(100)
    expect(h.updateElementPosition).not.toHaveBeenCalled()
  })

  it("snaps X for the mirrored vertical case (top→bottom)", () => {
    const a = el("a", 0, 0)
    const b = el("b", 50, 100)
    const conn = { from: "a", to: "b", fromPosition: "top", toPosition: "bottom" }
    const h = host({ elements: [a, b], connections: [conn] })
    h._alignConnectionElements(conn)
    expect(b.x).toBe(0)
  })

  it("snaps Y for the mirrored horizontal case (left→right)", () => {
    const a = el("a", 0, 0)
    const b = el("b", 100, 40)
    const conn = { from: "a", to: "b", fromPosition: "left", toPosition: "right" }
    const h = host({ elements: [a, b], connections: [conn] })
    h._alignConnectionElements(conn)
    expect(b.y).toBe(0)
  })

  it("prefers fromPort/toPort over fromPosition/toPosition, and defaults to bottom/top when neither is given", () => {
    const a = el("a", 0, 0)
    const b = el("b", 50, 100)
    const withPort = { from: "a", to: "b", fromPort: "bottom", fromPosition: "left", toPort: "top", toPosition: "right" }
    const h1 = host({ elements: [a, b], connections: [withPort] })
    h1._alignConnectionElements(withPort)
    expect(b.x).toBe(0) // took the vertical (port) branch, not the mismatched *Position

    const c = el("c", 0, 0)
    const d = el("d", 50, 100)
    const bare = { from: "c", to: "d" }
    const h2 = host({ elements: [c, d], connections: [bare] })
    h2._alignConnectionElements(bare)
    expect(d.x).toBe(0) // defaulted to bottom→top, still vertical
  })
})

describe("AlignmentMixin.alignAllElements", () => {
  it("aligns every connection then refreshes connectors once", () => {
    const a = el("a", 0, 0)
    const b = el("b", 33, 100)
    const conn = { from: "a", to: "b", fromPosition: "bottom", toPosition: "top" }
    const h = host({ elements: [a, b], connections: [conn] })
    h.alignAllElements()
    expect(b.x).toBe(0)
    expect(h.updateConnections).toHaveBeenCalledOnce()
  })
})

describe("AlignmentMixin.alignElementWithParent", () => {
  it("aligns an element to its single incoming parent and returns true", () => {
    const parent = el("p", 0, 0)
    const child = el("c", 40, 100)
    const conn = { from: "p", to: "c", fromPosition: "bottom", toPosition: "top" }
    const h = host({ elements: [parent, child], connections: [conn] })
    expect(h.alignElementWithParent(child)).toBe(true)
    expect(child.x).toBe(0)
    expect(h.updateElementPosition).toHaveBeenCalledWith(child)
  })

  it("returns false when the element has no incoming connection", () => {
    const c = el("c", 0, 0)
    const h = host({ elements: [c], connections: [] })
    expect(h.alignElementWithParent(c)).toBe(false)
  })

  it("returns false when the connection's source element cannot be found", () => {
    const c = el("c", 0, 0)
    const h = host({ elements: [c], connections: [{ from: "ghost", to: "c" }] })
    expect(h.alignElementWithParent(c)).toBe(false)
  })

  it("aligns Y for the mirrored horizontal parent case (left→right)", () => {
    const parent = el("p", 100, 0)
    const child = el("c", 0, 40)
    const conn = { from: "p", to: "c", fromPosition: "left", toPosition: "right" }
    const h = host({ elements: [parent, child], connections: [conn] })
    expect(h.alignElementWithParent(child)).toBe(true)
    expect(child.y).toBe(0)
  })

  it("returns false (no move) when already aligned", () => {
    const parent = el("p", 7, 0)
    const child = el("c", 7, 100)
    const conn = { from: "p", to: "c", fromPosition: "bottom", toPosition: "top" }
    const h = host({ elements: [parent, child], connections: [conn] })
    expect(h.alignElementWithParent(child)).toBe(false)
    expect(h.updateElementPosition).not.toHaveBeenCalled()
  })

  it("aligns Y for a horizontal (right→left) parent connection", () => {
    const parent = el("p", 0, 0)
    const child = el("c", 100, 40)
    const conn = { from: "p", to: "c", fromPosition: "right", toPosition: "left" }
    const h = host({ elements: [parent, child], connections: [conn] })
    expect(h.alignElementWithParent(child)).toBe(true)
    expect(child.y).toBe(0)
    expect(h.updateElementPosition).toHaveBeenCalledWith(child)
  })

  it("aligns X for the mirrored vertical parent case (top→bottom)", () => {
    const parent = el("p", 0, 0)
    const child = el("c", 40, 100)
    const conn = { from: "p", to: "c", fromPosition: "top", toPosition: "bottom" }
    const h = host({ elements: [parent, child], connections: [conn] })
    expect(h.alignElementWithParent(child)).toBe(true)
    expect(child.x).toBe(0)
  })

  it("prefers fromPort/toPort over fromPosition/toPosition, and defaults to bottom/top when neither is given", () => {
    const parent = el("p", 0, 0)
    const child = el("c", 40, 100)
    const conn = { from: "p", to: "c", fromPort: "bottom", fromPosition: "left", toPort: "top", toPosition: "right" }
    const h = host({ elements: [parent, child], connections: [conn] })
    expect(h.alignElementWithParent(child)).toBe(true)
    expect(child.x).toBe(0)

    const parent2 = el("p2", 0, 0)
    const child2 = el("c2", 40, 100)
    const bare = { from: "p2", to: "c2" }
    const h2 = host({ elements: [parent2, child2], connections: [bare] })
    expect(h2.alignElementWithParent(child2)).toBe(true)
    expect(child2.x).toBe(0)
  })
})

describe("AlignmentMixin.alignChildElements", () => {
  it("recursively aligns a vertical chain onto the root's X", () => {
    const root = el("root", 0, 0)
    const mid = el("mid", 30, 100)
    const leaf = el("leaf", 60, 200)
    const conns = [
      { from: "root", to: "mid", fromPosition: "bottom", toPosition: "top" },
      { from: "mid", to: "leaf", fromPosition: "bottom", toPosition: "top" },
    ]
    const h = host({ elements: [root, mid, leaf], connections: conns })
    h.alignChildElements(root)
    expect(mid.x).toBe(0)
    expect(leaf.x).toBe(0) // recursion propagated the new mid.x down
  })

  it("stops recursing down a branch that was already aligned", () => {
    const root = el("root", 0, 0)
    const mid = el("mid", 0, 100) // already aligned → no move, no recursion
    const leaf = el("leaf", 55, 200)
    const conns = [
      { from: "root", to: "mid", fromPosition: "bottom", toPosition: "top" },
      { from: "mid", to: "leaf", fromPosition: "bottom", toPosition: "top" },
    ]
    const h = host({ elements: [root, mid, leaf], connections: conns })
    h.alignChildElements(root)
    expect(leaf.x).toBe(55) // untouched because mid didn't move
  })

  it("ignores a child connection whose target element cannot be found", () => {
    const root = el("root", 0, 0)
    const conns = [{ from: "root", to: "ghost", fromPosition: "bottom", toPosition: "top" }]
    const h = host({ elements: [root], connections: conns })
    expect(() => h.alignChildElements(root)).not.toThrow()
    expect(h.updateElementPosition).not.toHaveBeenCalled()
  })

  it("aligns Y for a horizontal (right→left) child connection", () => {
    const root = el("root", 0, 0)
    const child = el("child", 100, 40)
    const conns = [{ from: "root", to: "child", fromPosition: "right", toPosition: "left" }]
    const h = host({ elements: [root, child], connections: conns })
    h.alignChildElements(root)
    expect(child.y).toBe(0)
    expect(h.updateElementPosition).toHaveBeenCalledWith(child)
  })

  it("aligns Y for the mirrored horizontal child case (left→right)", () => {
    const root = el("root", 100, 0)
    const child = el("child", 0, 40)
    const conns = [{ from: "root", to: "child", fromPosition: "left", toPosition: "right" }]
    const h = host({ elements: [root, child], connections: conns })
    h.alignChildElements(root)
    expect(child.y).toBe(0)
  })

  it("aligns X for the mirrored vertical child case (top→bottom)", () => {
    const root = el("root", 0, 0)
    const child = el("child", 30, 100)
    const conns = [{ from: "root", to: "child", fromPosition: "top", toPosition: "bottom" }]
    const h = host({ elements: [root, child], connections: conns })
    h.alignChildElements(root)
    expect(child.x).toBe(0)
  })

  it("prefers fromPort/toPort over fromPosition/toPosition, and defaults to bottom/top when neither is given", () => {
    const root = el("root", 0, 0)
    const child = el("child", 30, 100)
    const conns = [{ from: "root", to: "child", fromPort: "bottom", fromPosition: "left", toPort: "top", toPosition: "right" }]
    const h = host({ elements: [root, child], connections: conns })
    h.alignChildElements(root)
    expect(child.x).toBe(0)

    const root2 = el("root2", 0, 0)
    const child2 = el("child2", 30, 100)
    const bare = [{ from: "root2", to: "child2" }]
    const h2 = host({ elements: [root2, child2], connections: bare })
    h2.alignChildElements(root2)
    expect(child2.x).toBe(0)
  })

  it("terminates on a cycle that keeps moving elements", () => {
    const a = el("a", 0, 0)
    const b = el("b", 30, 100)
    const conns = [
      { from: "a", to: "b", fromPosition: "bottom", toPosition: "top" },
      { from: "b", to: "a", fromPosition: "right", toPosition: "left" },
    ]
    const h = host({ elements: [a, b], connections: conns })
    h.alignChildElements(a)
    expect(b.x).toBe(0)
    expect(a.y).toBe(100)
  })
})

describe("AlignmentMixin._alignConnectionElements return value", () => {
  it("is true only when the target moved", () => {
    const a = el("a", 0, 0)
    const b = el("b", 50, 100)
    const conn = { from: "a", to: "b", fromPosition: "bottom", toPosition: "top" }
    const h = host({ elements: [a, b], connections: [conn] })
    expect(h._alignConnectionElements(conn)).toBe(true)
    expect(h._alignConnectionElements(conn)).toBe(false)
    expect(h._alignConnectionElements({ from: "a", to: "ghost" })).toBe(false)
  })
})

describe("AlignmentMixin._alignNewBranchToRow", () => {
  const decision = el("d", 0, 0, { type: "decision" })

  it("moves only the new branch box onto the most common row of its siblings", () => {
    const first = el("b1", -150, 120)
    const second = el("b2", 0, 120)
    const odd = el("b3", 150, 300)
    const fresh = el("new", 300, 45)
    const conns = ["b1", "b2", "b3", "new"].map((to) => ({ from: "d", to }))
    const h = host({ elements: [decision, first, second, odd, fresh], connections: conns })
    h._alignNewBranchToRow(decision, "new")
    expect(fresh.y).toBe(120)
    expect(odd.y).toBe(300)
    expect(h.updateElementPosition).toHaveBeenCalledOnce()
    expect(h.updateElementPosition).toHaveBeenCalledWith(fresh)
  })

  it("breaks a tie toward the topmost row", () => {
    const low = el("b1", -150, 300)
    const high = el("b2", 0, 120)
    const fresh = el("new", 300, 45)
    const conns = ["b1", "b2", "new"].map((to) => ({ from: "d", to }))
    const h = host({ elements: [decision, low, high, fresh], connections: conns })
    h._alignNewBranchToRow(decision, "new")
    expect(fresh.y).toBe(120)
  })

  it("is a no-op without a new id, for a missing box, for the first branch, or when already on the row", () => {
    const sibling = el("b1", 0, 120)
    const fresh = el("new", 150, 120)
    const h = host({
      elements: [decision, sibling, fresh],
      connections: [{ from: "d", to: "b1" }, { from: "d", to: "new" }, { from: "d", to: "ghost" }],
    })
    h._alignNewBranchToRow(decision, null)
    h._alignNewBranchToRow(decision, "missing")
    h._alignNewBranchToRow(decision, "new")
    const lone = host({ elements: [decision, fresh], connections: [{ from: "d", to: "new" }] })
    lone._alignNewBranchToRow(decision, "new")
    expect(h.updateElementPosition).not.toHaveBeenCalled()
    expect(lone.updateElementPosition).not.toHaveBeenCalled()
  })
})

