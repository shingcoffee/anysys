import { describe, it, expect, beforeEach, vi } from "vitest"
import { UndoRedoManager } from "controllers/flowchart_canvas/undo_redo_manager"
import { makeCanvas, makeController } from "../../support/flowchart.js"

const el = (id, extra = {}) => ({ id, type: "process", x: 1.4, y: 2.6, width: 100, height: 45, label: "L", properties: { a: 1 }, ...extra })

function newManager(canvasOverrides = {}, controllerOverrides = {}) {
  const canvas = makeCanvas(canvasOverrides)
  const controller = makeController(canvas, { idValue: "fc-9", ...controllerOverrides })
  const mgr = new UndoRedoManager(controller)
  return { mgr, canvas, controller }
}

describe("UndoRedoManager — construction & storage restore", () => {
  beforeEach(() => sessionStorage.clear())

  it("starts with empty stacks when storage is empty", () => {
    const { mgr } = newManager()
    expect(mgr.undoStack).toEqual([])
    expect(mgr.redoStack).toEqual([])
    expect(mgr.canUndo).toBe(false)
    expect(mgr.canRedo).toBe(false)
  })

  it("restores stacks from sessionStorage keyed by controller id", () => {
    sessionStorage.setItem("flowchart_undo_fc-9", JSON.stringify({ undoStack: ["a", "b"], redoStack: ["c"] }))
    const { mgr } = newManager()
    expect(mgr.undoStack).toEqual(["a", "b"])
    expect(mgr.redoStack).toEqual(["c"])
  })

  it("uses a version-scoped storage key on version-edit pages", () => {
    sessionStorage.setItem("flowchart_undo_fc-9_v12", JSON.stringify({ undoStack: ["ver"], redoStack: [] }))
    const { mgr } = newManager({}, { basedOnVersionIdValue: "12" })
    expect(mgr._storageKey).toBe("flowchart_undo_fc-9_v12")
    expect(mgr.undoStack).toEqual(["ver"])
  })

  it("discards stored stacks whose top does not match the loaded canvas", () => {
    const stored = JSON.stringify({ elements: [el("old")], connections: [] })
    sessionStorage.setItem("flowchart_undo_fc-9", JSON.stringify({ undoStack: [stored], redoStack: ["x"] }))
    const { mgr, canvas } = newManager()
    canvas.elements = [el("a")]
    canvas.connections = []
    mgr.saveInitialState()
    expect(mgr.undoStack).toHaveLength(1)
    expect(mgr.redoStack).toEqual([])
    expect(JSON.parse(mgr.undoStack[0]).elements.map(e => e.id)).toEqual(["a"])
  })

  it("survives corrupt storage without throwing", () => {
    sessionStorage.setItem("flowchart_undo_fc-9", "{not json")
    const { mgr } = newManager()
    expect(mgr.undoStack).toEqual([])
  })

  it("defaults undoStack/redoStack to [] when the stored payload omits them", () => {
    sessionStorage.setItem("flowchart_undo_fc-9", JSON.stringify({}))
    const { mgr } = newManager()
    expect(mgr.undoStack).toEqual([])
    expect(mgr.redoStack).toEqual([])
  })
})

describe("UndoRedoManager.captureCurrentState", () => {
  beforeEach(() => sessionStorage.clear())

  it("returns null when the canvas has no elements array", () => {
    const { mgr } = newManager({ elements: null })
    expect(mgr.captureCurrentState()).toBeNull()
  })

  it("rounds coordinates and keeps elements + connections in canvas order", () => {
    const { mgr, canvas } = newManager()
    canvas.elements = [el("b"), el("a")]
    canvas.connections = [
      { id: "c2", from: "a", to: "b" },
      { id: "c1", from: "b", to: "a", matchValue: 0 },
    ]
    const parsed = JSON.parse(mgr.captureCurrentState())
    expect(parsed.elements.map(e => e.id)).toEqual(["b", "a"])
    expect(parsed.elements[0].x).toBe(1)  // 1.4 rounded
    expect(parsed.elements[0].y).toBe(3)  // 2.6 rounded
    expect(parsed.connections.map(c => c.id)).toEqual(["c2", "c1"])
    expect(parsed.connections[1].matchValue).toBe(0) // ?? preserves 0
    expect(parsed.connections[0].matchValue).toBeNull()
  })

  it("defaults label/properties to blank/empty and connections to [] when absent", () => {
    const { mgr, canvas } = newManager()
    canvas.elements = [{ id: "a", type: "process", x: 1, y: 1, width: 10, height: 10 }] // no label, no properties
    canvas.connections = undefined // falls back to []
    const parsed = JSON.parse(mgr.captureCurrentState())
    expect(parsed.elements[0].label).toBe("")
    expect(parsed.elements[0].properties).toEqual({})
    expect(parsed.connections).toEqual([])
  })

  it("defaults a connection's properties to {} when absent, and deep-clones them when present", () => {
    const { mgr, canvas } = newManager()
    canvas.elements = [el("a")]
    canvas.connections = [
      { id: "c1", from: "a", to: "a" }, // no properties -> {}
      { id: "c2", from: "a", to: "a", properties: { weight: 3 } }, // present -> cloned
    ]
    const parsed = JSON.parse(mgr.captureCurrentState())
    expect(parsed.connections.find(c => c.id === "c1").properties).toEqual({})
    expect(parsed.connections.find(c => c.id === "c2").properties).toEqual({ weight: 3 })
  })
})

describe("UndoRedoManager — stack operations", () => {
  beforeEach(() => sessionStorage.clear())

  it("saveInitialState pushes exactly one baseline and dispatches", () => {
    const { mgr, canvas, controller } = newManager()
    canvas.elements = [el("a")]
    const spy = vi.spyOn(controller.element, "dispatchEvent")
    mgr.saveInitialState()
    expect(mgr.undoStack.length).toBe(1)
    mgr.saveInitialState() // no-op once non-empty
    expect(mgr.undoStack.length).toBe(1)
    expect(spy).toHaveBeenCalled()
  })

  it("commitPendingState dedupes identical consecutive states", () => {
    const { mgr, canvas } = newManager()
    canvas.elements = [el("a")]
    mgr.saveInitialState()
    mgr.commitPendingState() // identical -> ignored
    expect(mgr.undoStack.length).toBe(1)

    canvas.elements = [el("a"), el("b")]
    mgr.commitPendingState()
    expect(mgr.undoStack.length).toBe(2)
    expect(mgr.redoStack).toEqual([]) // commit clears redo
  })

  it("commitPendingState caps the undo stack at 50 entries", () => {
    const { mgr, canvas } = newManager()
    for (let i = 0; i < 60; i++) {
      canvas.elements = [el(`e${i}`)]
      mgr.commitPendingState()
    }
    expect(mgr.undoStack.length).toBe(50)
  })

  it("commitPendingState is a no-op during an undo/redo operation", () => {
    const { mgr, canvas } = newManager()
    canvas.elements = [el("a")]
    mgr.saveInitialState()
    mgr.isUndoRedoOperation = true
    canvas.elements = [el("a"), el("b")]
    mgr.commitPendingState()
    expect(mgr.undoStack.length).toBe(1)
  })

  it("commitPendingState no-ops when captureCurrentState returns null", () => {
    const { mgr, canvas } = newManager()
    canvas.elements = [el("a")]
    mgr.saveInitialState()
    canvas.elements = null // captureCurrentState -> null
    mgr.commitPendingState()
    expect(mgr.undoStack.length).toBe(1)
  })

  it("commitPendingState no-ops when the controller has no canvas", () => {
    const { mgr, canvas, controller } = newManager()
    canvas.elements = [el("a")]
    mgr.saveInitialState()
    controller.canvas = null
    mgr.commitPendingState()
    expect(mgr.undoStack.length).toBe(1)
  })
})

describe("UndoRedoManager — coalescing", () => {
  beforeEach(() => sessionStorage.clear())

  const labelled = (label) => [el("a", { label })]

  function typing(keys) {
    const { mgr, canvas, controller } = newManager()
    canvas.elements = labelled("")
    mgr.saveInitialState()
    keys.forEach(([label, key]) => {
      canvas.undoCoalesceKey = key
      canvas.elements = labelled(label)
      mgr.commitPendingState()
    })
    return { mgr, canvas, controller }
  }

  const labels = (stack) => stack.map(s => JSON.parse(s).elements[0].label)

  it("collapses consecutive commits with the same canvas key into one entry", () => {
    const { mgr } = typing([["H", "a:label"], ["He", "a:label"], ["Hello", "a:label"]])
    expect(labels(mgr.undoStack)).toEqual(["", "Hello"])
  })

  it("pushes a new entry when the key changes or is absent", () => {
    const { mgr } = typing([["A", "a:label"], ["AB", "a:notes"], ["ABC", null], ["ABCD", null]])
    expect(labels(mgr.undoStack)).toEqual(["", "A", "AB", "ABC", "ABCD"])
  })

  it("an explicit key argument overrides the canvas key", () => {
    const { mgr, canvas } = newManager()
    canvas.elements = labelled("")
    mgr.saveInitialState()
    canvas.undoCoalesceKey = "ignored"
    canvas.elements = labelled("x")
    mgr.commitPendingState("nudge:a")
    canvas.elements = labelled("y")
    mgr.commitPendingState("nudge:a")
    canvas.elements = labelled("z")
    mgr.commitPendingState("nudge:b")
    expect(labels(mgr.undoStack)).toEqual(["", "y", "z"])
  })

  it("a coalesced edit clears the redo stack", () => {
    const { mgr, canvas } = typing([["A", null], ["AB", "a:label"]])
    mgr.undo()
    expect(mgr.canRedo).toBe(true)
    canvas.undoCoalesceKey = "a:label"
    canvas.elements = labelled("AX")
    mgr.commitPendingState()
    expect(mgr.redoStack).toEqual([])
  })

  it("drops the entry when the coalesced edit returns to its before-state, then pushes again", () => {
    const { mgr, canvas } = typing([["A", null], ["AB", "a:label"], ["A", "a:label"]])
    expect(labels(mgr.undoStack)).toEqual(["", "A"])
    canvas.elements = labelled("AC")
    mgr.commitPendingState()
    canvas.elements = labelled("ACD")
    mgr.commitPendingState()
    expect(labels(mgr.undoStack)).toEqual(["", "A", "ACD"])
  })

  it("undo then redo of a coalesced entry restores its final after-state", () => {
    const { mgr, canvas } = typing([["H", "a:label"], ["Hi", "a:label"]])
    canvas.restoreGraph = vi.fn()
    mgr.undo()
    expect(canvas.restoreGraph).toHaveBeenLastCalledWith(JSON.parse(mgr.undoStack[0]))
    expect(JSON.parse(mgr.undoStack[0]).elements[0].label).toBe("")
    mgr.redo()
    expect(canvas.restoreGraph.mock.calls.at(-1)[0].elements[0].label).toBe("Hi")
    expect(mgr.canRedo).toBe(false)
  })

  it("does not merge into the restored state after undo, even with the same key", () => {
    const { mgr, canvas } = typing([["A", null], ["AB", "a:label"]])
    canvas.restoreGraph = vi.fn(() => { canvas.elements = labelled("A") })
    mgr.undo()
    canvas.elements = labelled("AZ")
    mgr.commitPendingState()
    expect(labels(mgr.undoStack)).toEqual(["", "A", "AZ"])
  })

  it("does not merge into the redone state after redo", () => {
    const { mgr, canvas } = typing([["A", "a:label"]])
    canvas.restoreGraph = vi.fn()
    mgr.undo()
    mgr.redo()
    canvas.elements = labelled("AB")
    mgr.commitPendingState()
    expect(labels(mgr.undoStack)).toEqual(["", "A", "AB"])
  })

  it("saveInitialState resets the coalesce run", () => {
    const { mgr, canvas } = typing([["A", "a:label"]])
    mgr.undoStack = []
    mgr.saveInitialState()
    canvas.elements = labelled("AB")
    mgr.commitPendingState()
    expect(labels(mgr.undoStack)).toEqual(["A", "AB"])
  })
})

describe("UndoRedoManager — undo / redo", () => {
  beforeEach(() => sessionStorage.clear())

  function seededTwoStates() {
    const { mgr, canvas, controller } = newManager({ restoreGraph: vi.fn() })
    canvas.elements = [el("a")]
    mgr.saveInitialState()
    canvas.elements = [el("a"), el("b")]
    mgr.commitPendingState()
    return { mgr, canvas, controller }
  }

  it("undo pops to the previous state through a silent restoreGraph swap and enables redo", () => {
    const { mgr, canvas, controller } = seededTwoStates()
    expect(mgr.canUndo).toBe(true)
    let flagDuringRestore
    canvas.restoreGraph.mockImplementation(() => { flagDuringRestore = mgr.isUndoRedoOperation })
    const result = mgr.undo()
    expect(result).toBe(true)
    expect(mgr.undoStack.length).toBe(1)
    expect(mgr.redoStack.length).toBe(1)
    expect(canvas.restoreGraph).toHaveBeenCalledWith(JSON.parse(mgr.undoStack[0]))
    expect(canvas.loadConfiguration).not.toHaveBeenCalled()
    expect(flagDuringRestore).toBe(true)
    expect(mgr.isUndoRedoOperation).toBe(false)
    expect(controller.hasUnsavedChanges).toBe(true)
    expect(controller._editsSinceSaveStart).toBe(true)
    expect(controller._updateUnsavedIndicator).toHaveBeenCalled()
    expect(controller._dispatchConfigurationChange).toHaveBeenCalled()
  })

  it("redo marks the flowchart unsaved and refreshes the indicator", () => {
    const { mgr, controller } = seededTwoStates()
    mgr.undo()
    controller.hasUnsavedChanges = false
    controller._updateUnsavedIndicator.mockClear()
    mgr.redo()
    expect(controller.hasUnsavedChanges).toBe(true)
    expect(controller._updateUnsavedIndicator).toHaveBeenCalledTimes(1)
  })

  it("undo refuses to go below the baseline (stack length 1)", () => {
    const { mgr } = seededTwoStates()
    mgr.undo()
    expect(mgr.undo()).toBe(false)
    expect(mgr.canUndo).toBe(false)
  })

  it("redo re-applies the undone state and empties when exhausted", () => {
    const { mgr } = seededTwoStates()
    mgr.undo()
    expect(mgr.canRedo).toBe(true)
    expect(mgr.redo()).toBe(true)
    expect(mgr.undoStack.length).toBe(2)
    expect(mgr.canRedo).toBe(false)
    expect(mgr.redo()).toBe(false)
  })

  it("leaves the canvas alone when a stored snapshot is corrupt", () => {
    const { mgr, canvas } = seededTwoStates()
    mgr.undoStack[0] = "{not json"
    expect(mgr.undo()).toBe(true)
    expect(canvas.restoreGraph).not.toHaveBeenCalled()
    expect(mgr.isUndoRedoOperation).toBe(false)
  })

  it("clears isUndoRedoOperation even if the post-restore bookkeeping throws", () => {
    const { mgr, controller } = seededTwoStates()
    controller._dispatchConfigurationChange.mockImplementationOnce(() => { throw new Error("boom") })
    expect(() => mgr.undo()).toThrow("boom")
    expect(mgr.isUndoRedoOperation).toBe(false)
  })

  it("_restoreState no-ops when the controller has no canvas", () => {
    const { mgr, controller } = seededTwoStates()
    controller.canvas = null
    expect(() => mgr.undo()).not.toThrow()
    expect(mgr.undoStack.length).toBe(1) // undo still popped the stack, just skipped the restore
  })
})

describe("UndoRedoManager — persistence", () => {
  beforeEach(() => sessionStorage.clear())

  it("persists only the last 10 states to sessionStorage", () => {
    const { mgr, canvas } = newManager()
    for (let i = 0; i < 15; i++) {
      canvas.elements = [el(`e${i}`)]
      mgr.commitPendingState()
    }
    const stored = JSON.parse(sessionStorage.getItem("flowchart_undo_fc-9"))
    expect(stored.undoStack.length).toBe(10)
  })

  it("swallows errors when persisting throws (storage full/unavailable)", () => {
    const { mgr } = newManager()
    mgr.undoStack = { slice() { throw new Error("quota") } }
    mgr.redoStack = []
    expect(() => mgr._persistToStorage()).not.toThrow()
  })
})

describe("P5-4 UndoRedoManager — preview snapshots and canMutate", () => {
  beforeEach(() => sessionStorage.clear())

  it("captures the stored collapsed configuration while previewing", () => {
    const stored = {
      elements: [{ id: "collapsed", type: "subflow", x: 1.6, y: 2.4, width: 10, height: 10 }],
      connections: [{ id: "c1", from: "a", to: "b" }],
    }
    const { mgr, canvas, controller } = newManager()
    canvas.previewMode = true
    canvas.elements = [el("expanded")]
    controller._collapsedPreviewConfiguration = stored
    const parsed = JSON.parse(mgr.captureCurrentState())
    expect(parsed.elements.map(e => e.id)).toEqual(["collapsed"])
    expect(parsed.elements[0].x).toBe(2)
    expect(parsed.connections[0].id).toBe("c1")
  })

  it("captures the live graph when previewing without a stored collapse", () => {
    const { mgr, canvas, controller } = newManager()
    canvas.previewMode = true
    canvas.elements = [el("live")]
    controller._collapsedPreviewConfiguration = null
    expect(JSON.parse(mgr.captureCurrentState()).elements.map(e => e.id)).toEqual(["live"])
  })

  it("_serializeConfiguration defaults missing arrays and blank fields", () => {
    const { mgr } = newManager()
    expect(JSON.parse(mgr._serializeConfiguration({}))).toEqual({ elements: [], connections: [] })
    const parsed = JSON.parse(mgr._serializeConfiguration({
      elements: [
        { id: "a", type: "process", x: 1, y: 1, width: 10, height: 10 },
        { id: "b", type: "process", x: 2, y: 2, width: 10, height: 10, label: "L", properties: { a: 1 } },
      ],
      connections: [
        { id: "c1", from: "a", to: "a" },
        { id: "c2", from: "a", to: "b", fromPort: "p", fromPosition: "bottom", toPort: "q", toPosition: "top", label: "Yes", matchValue: 0, properties: { w: 1 } },
      ],
    }))
    expect(parsed.elements[0].label).toBe("")
    expect(parsed.elements[0].properties).toEqual({})
    expect(parsed.elements[1].properties).toEqual({ a: 1 })
    expect(parsed.connections[0].properties).toEqual({})
    expect(parsed.connections[1]).toMatchObject({ fromPort: "p", label: "Yes", matchValue: 0, properties: { w: 1 } })
  })

  it("undo and redo leave preview then refuse when canMutate is still false", () => {
    const { mgr, canvas, controller } = newManager()
    canvas.elements = [el("a")]
    mgr.saveInitialState()
    canvas.elements = [el("b")]
    mgr.commitPendingState()
    canvas.previewMode = true
    canvas.isReadOnly = true
    const leave = vi.spyOn(controller, "_leavePreviewMode")
    expect(mgr.undo()).toBe(false)
    expect(leave).toHaveBeenCalledWith({ restore: true })
    expect(mgr.redo()).toBe(false)
  })
})
