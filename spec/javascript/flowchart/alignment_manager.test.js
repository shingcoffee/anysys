import { describe, it, expect, vi } from "vitest"
import { AlignmentManager } from "flowchart/alignment_manager"

// AlignmentManager mutates element {x,y} data and delegates DOM sync to the
// canvas. We feed it a fake canvas (plain data + spies) so the alignment MATH
// is exercised without real layout. GRID_SIZE is 15.

const el = (id, x, y, width = 30, height = 30) => ({ id, x, y, width, height })

const makeCanvas = (selectedElements) => ({
  selectedElements,
  onBeforeChange: vi.fn(),
  onchange: vi.fn(),
  updateElementPosition: vi.fn(),
  updateConnections: vi.fn(),
})

describe("AlignmentManager", () => {
  describe("guards", () => {
    it("alignLeft is a no-op with fewer than 2 elements", () => {
      const canvas = makeCanvas([el("a", 90, 90)])
      new AlignmentManager(canvas).alignLeft()
      expect(canvas.onBeforeChange).not.toHaveBeenCalled()
      expect(canvas.updateConnections).not.toHaveBeenCalled()
    })

    it("distributeH requires at least 3 elements", () => {
      const canvas = makeCanvas([el("a", 0, 0), el("b", 45, 0)])
      new AlignmentManager(canvas).distributeH()
      expect(canvas.onBeforeChange).not.toHaveBeenCalled()
    })

    it.each([
      ["alignCenterH"], ["alignRight"], ["alignTop"], ["alignCenterV"], ["alignBottom"],
    ])("%s is a no-op with fewer than 2 elements", (method) => {
      const canvas = makeCanvas([el("a", 90, 90)])
      new AlignmentManager(canvas)[method]()
      expect(canvas.onBeforeChange).not.toHaveBeenCalled()
      expect(canvas.updateConnections).not.toHaveBeenCalled()
    })

    it("distributeV requires at least 3 elements", () => {
      const canvas = makeCanvas([el("a", 0, 0), el("b", 0, 45)])
      new AlignmentManager(canvas).distributeV()
      expect(canvas.onBeforeChange).not.toHaveBeenCalled()
    })
  })

  describe("horizontal alignment", () => {
    it("alignLeft snaps all left edges to the leftmost element", () => {
      const a = el("a", 90, 0)  // left edge 75
      const b = el("b", 150, 0) // left edge 135
      const canvas = makeCanvas([a, b])
      new AlignmentManager(canvas).alignLeft()
      expect([a.x, b.x]).toEqual([90, 90])
    })

    it("alignRight snaps all right edges to the rightmost element", () => {
      const a = el("a", 90, 0)  // right edge 105
      const b = el("b", 150, 0) // right edge 165
      const canvas = makeCanvas([a, b])
      new AlignmentManager(canvas).alignRight()
      expect([a.x, b.x]).toEqual([150, 150])
    })

    it("alignCenterH snaps every x to the (grid-snapped) average", () => {
      const a = el("a", 90, 0)
      const b = el("b", 150, 0)
      const canvas = makeCanvas([a, b])
      new AlignmentManager(canvas).alignCenterH()
      expect([a.x, b.x]).toEqual([120, 120]) // avg 120, already on grid
    })
  })

  describe("vertical alignment", () => {
    it("alignTop snaps all top edges to the topmost element", () => {
      const a = el("a", 0, 90)
      const b = el("b", 0, 150)
      const canvas = makeCanvas([a, b])
      new AlignmentManager(canvas).alignTop()
      expect([a.y, b.y]).toEqual([90, 90])
    })

    it("alignBottom snaps all bottom edges to the lowest element", () => {
      const a = el("a", 0, 90)
      const b = el("b", 0, 150)
      const canvas = makeCanvas([a, b])
      new AlignmentManager(canvas).alignBottom()
      expect([a.y, b.y]).toEqual([150, 150])
    })

    it("alignCenterV snaps every y to the (grid-snapped) average", () => {
      const a = el("a", 0, 90)
      const b = el("b", 0, 150)
      const canvas = makeCanvas([a, b])
      new AlignmentManager(canvas).alignCenterV()
      expect([a.y, b.y]).toEqual([120, 120])
    })
  })

  describe("distribution", () => {
    it("distributeH spreads middle elements evenly between the outermost", () => {
      const a = el("a", 0, 0)
      const mid = el("mid", 30, 0)
      const c = el("c", 150, 0)
      const canvas = makeCanvas([a, mid, c])
      new AlignmentManager(canvas).distributeH()
      // step = 150/2 = 75; positions 0, 75, 150
      expect([a.x, mid.x, c.x]).toEqual([0, 75, 150])
    })

    it("distributeV spreads middle elements evenly on the Y axis", () => {
      const a = el("a", 0, 0)
      const mid = el("mid", 0, 20)
      const c = el("c", 0, 150)
      const canvas = makeCanvas([a, mid, c])
      new AlignmentManager(canvas).distributeV()
      expect([a.y, mid.y, c.y]).toEqual([0, 75, 150])
    })
  })

  describe("_applyAlignment lifecycle", () => {
    it("fires onBeforeChange, repositions each element, updates connections, then onchange", () => {
      const a = el("a", 90, 0)
      const b = el("b", 150, 0)
      const canvas = makeCanvas([a, b])
      new AlignmentManager(canvas).alignLeft()
      expect(canvas.onBeforeChange).toHaveBeenCalledOnce()
      expect(canvas.updateElementPosition).toHaveBeenCalledTimes(2)
      expect(canvas.updateConnections).toHaveBeenCalledOnce()
      expect(canvas.onchange).toHaveBeenCalledOnce()
    })

    it("tolerates absent optional callbacks (onBeforeChange/onchange undefined)", () => {
      const a = el("a", 90, 0)
      const b = el("b", 150, 0)
      const canvas = {
        selectedElements: [a, b],
        updateElementPosition: vi.fn(),
        updateConnections: vi.fn(),
      }
      expect(() => new AlignmentManager(canvas).alignLeft()).not.toThrow()
    })
  })
})

describe("P5-4 AlignmentManager — canMutate guard", () => {
  it("align and distribute are no-ops when the canvas cannot mutate", () => {
    const canvas = makeCanvas([el("a", 0, 0), el("b", 45, 0), el("c", 90, 0)])
    canvas.canMutate = () => false
    const mgr = new AlignmentManager(canvas)
    mgr.alignLeft()
    mgr.distributeH()
    expect(canvas.onBeforeChange).not.toHaveBeenCalled()
    expect(canvas.updateConnections).not.toHaveBeenCalled()
  })
})
