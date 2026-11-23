import { describe, it, expect, beforeEach, vi } from "vitest"
import { makeBranchManager, makeCanvas } from "../_support.js"

// CanvasOperationsMixin via a real BranchManager. Positions are pure arithmetic
// over element coordinates (branchSlotPosition), not real layout, so they unit-
// test cleanly. Canvas mutation methods use the fake canvas from _support.

function withBranchContainer(controller, ids = []) {
  const items = ids.map((id) => `<div data-branch-item data-branch-element-id="${id}"></div>`).join("")
  controller.formFieldsTarget.innerHTML = `<div data-branches-container>${items}</div>`
}

describe("CanvasOperationsMixin", () => {
  let mgr, controller
  const decisionEl = () => ({ id: "d", type: "decision", x: 300, y: 100, height: 45, properties: { branches: [] } })

  describe("_calculateBranchCanvasPosition", () => {
    beforeEach(() => {
      ;({ mgr, controller } = makeBranchManager({ currentElement: decisionEl() }))
    })
    it("centers branch_0 (slot 0.5) on the decision x", () => {
      const d = { ...decisionEl(), properties: { branches: [{}] } }
      expect(mgr._calculateBranchCanvasPosition(d, 0).x).toBe(300)
    })
    it("places a second branch to the right (slot 1.0)", () => {
      const d = { ...decisionEl(), properties: { branches: [{}, {}] } }
      const x0 = mgr._calculateBranchCanvasPosition(d, 0).x
      const x1 = mgr._calculateBranchCanvasPosition(d, 1).x
      expect(x1).toBeGreaterThan(x0)
    })
    it("computes y one row below the decision", () => {
      const d = { ...decisionEl(), properties: { branches: [{}] } }
      expect(mgr._calculateBranchCanvasPosition(d, 0).y).toBe(Math.round(100 + 45 / 2 + 120))
    })

    it("defaults decision height to 45 when absent", () => {
      const d = { id: "d", x: 300, y: 100, properties: { branches: [{}] } } // no height
      expect(mgr._calculateBranchCanvasPosition(d, 0).y).toBe(Math.round(100 + 45 / 2 + 120))
    })

    it("treats a missing/empty branches list as a single branch (totalBranches = 1)", () => {
      const dNoProps = { ...decisionEl(), properties: undefined }
      const dEmpty = { ...decisionEl(), properties: { branches: [] } }
      expect(mgr._calculateBranchCanvasPosition(dNoProps, 0).x).toBe(300)
      expect(mgr._calculateBranchCanvasPosition(dEmpty, 0).x).toBe(300)
    })

    it("counts outgoing canvas connections when they exist", () => {
      const d = { ...decisionEl(), id: "d" }
      controller.canvas = makeCanvas({
        connections: [
          { from: "d", to: "a", fromPort: "port_0" },
          { from: "d", to: "b", fromPort: "port_1" }
        ]
      })
      const x0 = mgr._calculateBranchCanvasPosition(d, 0).x
      const x1 = mgr._calculateBranchCanvasPosition(d, 1).x
      expect(x1).toBeGreaterThan(x0)
    })
  })

  describe("_createBranchElement / _addBranchElementToCanvas", () => {
    beforeEach(() => {
      const canvas = makeCanvas({ elements: [] })
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: decisionEl() }))
      controller.canvas.elements.push(controller.currentElement)
      withBranchContainer(controller, [])
    })

    it("returns null for a non-decision current element", () => {
      controller.currentElement = { id: "p", type: "process" }
      expect(mgr._createBranchElement("Yes", { label: "Yes" }, 0)).toBeNull()
    })

    it("creates a process element, pushes it, renders it, and connects from the decision", () => {
      const el = mgr._createBranchElement("Yes", { label: "Yes" }, 0)
      expect(el.type).toBe("process")
      expect(el.label).toBe("Yes")
      expect(controller.canvas.elements).toContain(el)
      expect(controller.canvas.renderElement).toHaveBeenCalledWith(el)
      expect(controller.canvas.createConnection).toHaveBeenCalledWith(
        controller.currentElement,
        el,
        "port_0",
        "top",
        { label: "Yes", skipBranchSync: true }
      )
    })

    it("returns null when there is no canvas", () => {
      controller.canvas = null
      expect(mgr._createBranchElement("Yes", { label: "Yes" }, 0)).toBeNull()
    })

    it("falls back to conditionOption.label when branchLabel is blank", () => {
      const el = mgr._createBranchElement(null, { label: "Maybe" }, 0)
      expect(el.label).toBe("Maybe")
      expect(el.properties.description).toBe("")
    })

    it("falls back to the translated Branch {index} label when neither name is given", () => {
      const el = mgr._createBranchElement(null, null, 0)
      expect(el.label).toBe("Branch 1")
      expect(el.properties.description).toBe("")
    })

    it("treats an undefined index as the DOM count and a missing container as zero items", () => {
      controller.formFieldsTarget.innerHTML = ""
      const el = mgr._createBranchElement("Yes", { label: "Yes" }, undefined)
      expect(controller.canvas.createConnection).toHaveBeenCalledWith(
        controller.currentElement,
        el,
        "port_0",
        "top",
        expect.any(Object)
      )
    })

    it("counts existing DOM branch items when no explicit index is given", () => {
      withBranchContainer(controller, ["existing1", "existing2"])
      const el = mgr._createBranchElement("Yes", { label: "Yes" }, null)
      expect(controller.canvas.createConnection).toHaveBeenCalledWith(
        controller.currentElement,
        el,
        "port_2",
        "top",
        expect.any(Object)
      )
    })

    it("falls back to an empty branch list when there is no branches container", () => {
      controller.formFieldsTarget.innerHTML = ""
      const el = mgr._createBranchElement("Yes", { label: "Yes" }, null)
      expect(controller.canvas.createConnection).toHaveBeenCalledWith(
        controller.currentElement,
        el,
        "port_0",
        "top",
        expect.any(Object)
      )
    })

    it("treats a missing form fields target as zero existing branches", () => {
      controller.formFieldsTarget = null
      const el = mgr._createBranchElement("Yes", { label: "Yes" }, null)
      expect(el).not.toBeNull()
      expect(controller.canvas.createConnection).toHaveBeenCalledWith(
        controller.currentElement,
        el,
        "port_0",
        "top",
        expect.any(Object)
      )
    })
  })

  describe("_addBranchElementToCanvas", () => {
    it("returns null when there is no canvas", () => {
      ;({ mgr, controller } = makeBranchManager({ canvas: null, currentElement: decisionEl() }))
      expect(mgr._addBranchElementToCanvas({ type: "process", label: "X" }, decisionEl(), 0, "X")).toBeNull()
    })

    it("defaults description/properties when elementData.properties is absent", () => {
      const canvas = makeCanvas({ elements: [] })
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: decisionEl() }))
      const el = mgr._addBranchElementToCanvas({ type: "process", label: "X" }, decisionEl(), 0, "X")
      expect(el.properties.description).toBe("")
      expect(el.properties.inputs).toEqual([])
      expect(el.properties.outputs).toEqual([])
    })
  })

  describe("_removeBranchConnectionFromCanvas", () => {
    it("no-ops when there is no canvas", () => {
      ;({ mgr, controller } = makeBranchManager({ canvas: null, currentElement: decisionEl() }))
      expect(() => mgr._removeBranchConnectionFromCanvas("c1", "b1")).not.toThrow()
    })

    it("no-ops when the connection is not found", () => {
      const canvas = makeCanvas({ elements: [], connections: [] })
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: decisionEl() }))
      mgr._removeBranchConnectionFromCanvas("missing", "missing")
      expect(canvas.deleteConnection).not.toHaveBeenCalled()
    })

    it("deletes only the decision→box connection and keeps the box", () => {
      const branch = { id: "b1", type: "process" }
      const canvas = makeCanvas({
        elements: [branch],
        connections: [{ id: "c1", from: "d", to: "b1" }, { id: "c2", from: "b1", to: "e" }],
      })
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: decisionEl() }))
      mgr._removeBranchConnectionFromCanvas("c1", "b1")
      expect(canvas.elements).toContain(branch)
      expect(canvas.deleteConnection).toHaveBeenCalledWith("c1")
    })

    it("treats a missing connections array as empty", () => {
      const canvas = makeCanvas({ elements: [] })
      canvas.connections = null
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: decisionEl() }))
      expect(() => mgr._removeBranchConnectionFromCanvas("c1", "b1")).not.toThrow()
    })

    it("matches by decision→box when connectionId is blank", () => {
      const canvas = makeCanvas({
        connections: [{ id: "c1", from: "d", to: "b1" }],
      })
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: decisionEl() }))
      mgr._removeBranchConnectionFromCanvas("", "b1")
      expect(canvas.deleteConnection).toHaveBeenCalledWith("c1")
    })

    it("filters the connection list when deleteConnection is absent", () => {
      const canvas = makeCanvas({
        connections: [{ id: "c1", from: "d", to: "b1" }],
      })
      canvas.deleteConnection = undefined
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: decisionEl() }))
      mgr._removeBranchConnectionFromCanvas("c1", "b1")
      expect(canvas.connections).toEqual([])
      expect(canvas.updateConnections).toHaveBeenCalled()
    })
  })

  describe("_remapBranchConnections", () => {
    it("no-ops when there is no canvas", () => {
      ;({ mgr, controller } = makeBranchManager({ canvas: null, currentElement: decisionEl() }))
      expect(() => mgr._remapBranchConnections({ id: "d" })).not.toThrow()
    })

    it("no-ops when there is no branches container", () => {
      const canvas = makeCanvas({ connections: [] })
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: decisionEl() }))
      controller.formFieldsTarget.innerHTML = ""
      expect(() => mgr._remapBranchConnections({ id: "d" })).not.toThrow()
    })

    it("no-ops when the form fields target is missing", () => {
      const canvas = makeCanvas({ connections: [] })
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: decisionEl() }))
      controller.formFieldsTarget = null
      expect(() => mgr._remapBranchConnections({ id: "d" })).not.toThrow()
    })

    it("treats a missing connections array as empty", () => {
      const canvas = makeCanvas({ connections: [] })
      canvas.connections = null
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: decisionEl() }))
      withBranchContainer(controller, ["b1"])
      expect(() => mgr._remapBranchConnections({ id: "d" })).not.toThrow()
    })

    it("skips branch items with no elementId dataset", () => {
      const conns = [{ from: "d", to: "b1", fromPort: "port_7" }]
      const canvas = makeCanvas({ connections: conns })
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: decisionEl() }))
      controller.formFieldsTarget.innerHTML =
        '<div data-branches-container><div data-branch-item></div></div>'
      mgr._remapBranchConnections({ id: "d" })
      expect(conns[0].fromPort).toBe("port_7")
    })

    it("rewrites fromPort to DOM branch order", () => {
      const conns = [
        { from: "d", to: "b1", fromPort: "port_7" },
        { from: "d", to: "b2", fromPort: "port_3" },
      ]
      const canvas = makeCanvas({ connections: conns })
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: decisionEl() }))
      withBranchContainer(controller, ["b1", "b2"])
      mgr._remapBranchConnections({ id: "d" })
      expect(conns[0].fromPort).toBe("port_0")
      expect(conns[1].fromPort).toBe("port_1")
      expect(conns[0].fromPosition).toBeNull()
    })
  })

  describe("_refreshDecisionElement", () => {
    it("removes and re-renders the element's group", () => {
      const canvas = makeCanvas()
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: decisionEl() }))
      const group = document.createElement("div")
      group.setAttribute("data-element-id", "d")
      canvas.elementLayer.appendChild(group)
      const el = { id: "d" }
      mgr._refreshDecisionElement(el)
      expect(canvas.renderElement).toHaveBeenCalledWith(el)
    })

    it("no-ops when there is no canvas", () => {
      ;({ mgr, controller } = makeBranchManager({ canvas: null, currentElement: decisionEl() }))
      expect(() => mgr._refreshDecisionElement({ id: "d" })).not.toThrow()
    })

    it("no-ops when the element has no rendered group yet", () => {
      const canvas = makeCanvas()
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: decisionEl() }))
      mgr._refreshDecisionElement({ id: "unrendered" })
      expect(canvas.renderElement).not.toHaveBeenCalled()
    })
  })

  describe("_layoutDecisionBranches", () => {
    it("no-ops when there is no canvas", () => {
      ;({ mgr, controller } = makeBranchManager({ canvas: null, currentElement: decisionEl() }))
      expect(() => mgr._layoutDecisionBranches(decisionEl())).not.toThrow()
    })

    it("no-ops when there is no branches container", () => {
      const canvas = makeCanvas()
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: decisionEl() }))
      controller.formFieldsTarget.innerHTML = ""
      expect(() => mgr._layoutDecisionBranches(decisionEl())).not.toThrow()
    })

    it("no-ops when the container's branch items don't resolve to canvas elements", () => {
      const canvas = makeCanvas({ elements: [] })
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: decisionEl() }))
      withBranchContainer(controller, ["ghost"])
      expect(() => mgr._layoutDecisionBranches(decisionEl())).not.toThrow()
      expect(canvas.updateElementPosition).not.toHaveBeenCalled()
    })

    it("breaks Y ties by preferring the smaller y as the preserved row", () => {
      const d = { id: "d", type: "decision", x: 300, y: 100, height: 45, properties: { branches: [{}, {}] } }
      const b1 = { id: "b1", x: 999, y: 500 }
      const b2 = { id: "b2", x: 111, y: 50 }
      const canvas = makeCanvas({ elements: [d, b1, b2] })
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: d }))
      withBranchContainer(controller, ["b1", "b2"])
      mgr._layoutDecisionBranches(d)
      // Both ys occur once each (tie) -> the smaller y (50) wins.
      expect(b1.y).toBe(50)
      expect(b2.y).toBe(50)
    })

    it("skips a box that is already at its target x/y", () => {
      const d = { id: "d", type: "decision", x: 300, y: 100, height: 45, properties: { branches: [{}] } }
      const b1 = { id: "b1", x: 300, y: Math.round(100 + 45 / 2 + 120) }
      const canvas = makeCanvas({ elements: [d, b1] })
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: d }))
      withBranchContainer(controller, ["b1"])
      mgr._layoutDecisionBranches(d)
      expect(canvas.updateElementPosition).not.toHaveBeenCalled()
    })

    it("carries a moved box's downstream subtree along by the same delta", () => {
      const d = { id: "d", type: "decision", x: 300, y: 100, height: 45, properties: { branches: [{}, {}] } }
      const b1 = { id: "b1", x: 999, y: 242 }
      const b2 = { id: "b2", x: 111, y: 242 }
      const child = { id: "child", x: 999, y: 400 }
      const canvas = makeCanvas({ elements: [d, b1, b2, child] })
      canvas._getSubTreeElements = vi.fn((id) => (id === "b1" ? [{ id: "child" }, { id: "ghost-not-in-elements" }] : []))
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: d }))
      withBranchContainer(controller, ["b1", "b2"])
      const dxExpected = 300 - 999
      mgr._layoutDecisionBranches(d)
      expect(child.x).toBe(999 + dxExpected)
      expect(canvas.updateElementPosition).toHaveBeenCalledWith(child)
    })

    it("moves branch boxes to slot X on the preserved row Y", () => {
      const d = { id: "d", type: "decision", x: 300, y: 100, height: 45, properties: { branches: [{}, {}] } }
      const b1 = { id: "b1", x: 999, y: 242 }
      const b2 = { id: "b2", x: 111, y: 242 }
      const canvas = makeCanvas({ elements: [d, b1, b2] })
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: d }))
      withBranchContainer(controller, ["b1", "b2"])
      mgr._layoutDecisionBranches(d)
      // b1 -> slot 0 (center = 300); b2 -> slot 1 (right of center)
      expect(b1.x).toBe(300)
      expect(b2.x).toBeGreaterThan(300)
      // Y preserved on the existing row (242)
      expect(b1.y).toBe(242)
      expect(canvas.updateElementPosition).toHaveBeenCalled()
    })
  })

  describe("_ensureBranchRowClearance", () => {
    it("no-ops when there is no canvas", () => {
      ;({ mgr, controller } = makeBranchManager({ canvas: null, currentElement: decisionEl() }))
      expect(() => mgr._ensureBranchRowClearance(decisionEl())).not.toThrow()
    })

    it("treats a missing connections list as empty when collecting branch ids", () => {
      const d = { id: "d", type: "decision", x: 300, y: 100, height: 45, properties: {} }
      const canvas = makeCanvas({ elements: [d], connections: [] })
      canvas.connections = null
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: d }))
      expect(() => mgr._ensureBranchRowClearance(d)).not.toThrow()
    })

    it("defaults decision height to 45 and treats a missing properties/branches list as empty", () => {
      const d = { id: "d", type: "decision", x: 300, y: 100 } // no height, no properties
      const child = { id: "c", x: 300, y: 240, height: 45 }
      const canvas = makeCanvas({ elements: [d, child], connections: [{ from: "d", to: "c" }] })
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: d }))
      expect(() => mgr._ensureBranchRowClearance(d)).not.toThrow()
      expect(canvas.shiftElementAndSubTree).toHaveBeenCalled()
    })

    it("treats a DOM-listed target as a branch even without fromPort", () => {
      const d = { id: "d", type: "decision", x: 300, y: 100, height: 45, properties: {} }
      const child = { id: "c", x: 300, y: 240, height: 45 }
      const canvas = makeCanvas({ elements: [d, child], connections: [{ from: "d", to: "c" }] })
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: d }))
      withBranchContainer(controller, ["c"])
      mgr._ensureBranchRowClearance(d)
      expect(canvas.shiftElementAndSubTree).not.toHaveBeenCalled()
    })

    it("excludes children that already leave the decision on a port handle", () => {
      const d = { id: "d", type: "decision", x: 300, y: 100, height: 45, properties: {} }
      const child = { id: "c", x: 300, y: 240, height: 45 }
      const canvas = makeCanvas({ elements: [d, child], connections: [{ from: "d", to: "c", fromPort: "port_0" }] })
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: d }))
      mgr._ensureBranchRowClearance(d)
      expect(canvas.shiftElementAndSubTree).not.toHaveBeenCalled()
    })

    it("shifts a cardinal downstream subtree out of the branch row band", () => {
      const d = { id: "d", type: "decision", x: 300, y: 100, height: 45, properties: { branches: [] } }
      // A cardinal child sitting right where the branch row lands (~y 242).
      const child = { id: "c", x: 300, y: 240, height: 45 }
      const canvas = makeCanvas({
        elements: [d, child],
        connections: [{ from: "d", to: "c" }], // no fromPort => cardinal
      })
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: d }))
      mgr._ensureBranchRowClearance(d)
      expect(canvas.shiftElementAndSubTree).toHaveBeenCalled()
      const [shiftedEl, dx, dy] = canvas.shiftElementAndSubTree.mock.calls[0]
      expect(shiftedEl).toBe(child)
      expect(dx).toBe(0)
      expect(dy).toBeGreaterThan(0) // pushed downward
    })

    it("defaults a subtree member's height to 45 when computing the intrusion band", () => {
      const d = { id: "d", type: "decision", x: 300, y: 100, height: 45, properties: { branches: [] } }
      const child = { id: "c", x: 300, y: 240 } // no height
      const canvas = makeCanvas({
        elements: [d, child],
        connections: [{ from: "d", to: "c" }],
      })
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: d }))
      mgr._ensureBranchRowClearance(d)
      expect(canvas.shiftElementAndSubTree).toHaveBeenCalled()
    })

    it("skips a cardinal child whose own element has been removed from canvas.elements mid-loop (defensive subtree.length===0 guard)", () => {
      // Two cardinal children under the same decision. The stubbed
      // shiftElementAndSubTree for the FIRST child removes the SECOND child
      // from canvas.elements as a side effect — simulating a canvas mutation
      // between the cardinalChildren filter and the per-child subtree lookup.
      // On the second loop iteration, `canvas.elements.find` for that child's
      // own id then comes back empty, so `subtree` is [] and the `continue`
      // guard fires — a real (not faked) reachable path for this defensive check.
      const d = { id: "d", type: "decision", x: 300, y: 100, height: 45, properties: { branches: [] } }
      const child1 = { id: "c1", x: 300, y: 240, height: 45 }
      const child2 = { id: "c2", x: 500, y: 240, height: 45 }
      const canvas = makeCanvas({
        elements: [d, child1, child2],
        connections: [{ from: "d", to: "c1" }, { from: "d", to: "c2" }],
      })
      canvas.shiftElementAndSubTree = vi.fn((el) => {
        if (el.id === "c1") {
          const idx = canvas.elements.indexOf(child2)
          if (idx !== -1) canvas.elements.splice(idx, 1)
        }
      })
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: d }))
      expect(() => mgr._ensureBranchRowClearance(d)).not.toThrow()
      // c1 was shifted normally...
      expect(canvas.shiftElementAndSubTree).toHaveBeenCalledWith(child1, 0, expect.any(Number))
      // ...but c2's own lookup came back empty (subtree.length === 0), so it
      // was skipped via `continue` rather than shifted a second time.
      expect(canvas.shiftElementAndSubTree).toHaveBeenCalledTimes(1)
    })

    it("leaves a subtree already clear of the band alone", () => {
      const d = { id: "d", type: "decision", x: 300, y: 100, height: 45, properties: { branches: [] } }
      const child = { id: "c", x: 300, y: 800, height: 45 } // far below
      const canvas = makeCanvas({ elements: [d, child], connections: [{ from: "d", to: "c" }] })
      ;({ mgr, controller } = makeBranchManager({ canvas, currentElement: d }))
      mgr._ensureBranchRowClearance(d)
      expect(canvas.shiftElementAndSubTree).not.toHaveBeenCalled()
    })
  })

})
