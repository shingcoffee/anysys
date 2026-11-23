import { describe, it, expect, vi } from "vitest"
import {
  AUTO_FIXES,
  DEFAULT_AUTO_FIX_LABELS,
  buildAutoFix,
  applySafeAutoFixes,
  countSafeAutoFixes,
} from "flowchart/validation_autofix"
import { DEFAULT_ELEMENT_HEIGHT, DEFAULT_ELEMENT_SPACING } from "flowchart/constants"

// A canvas stand-in with the same mutation surface the real engine exposes.
// Each fix is asserted through that surface (updateElementProperties,
// deleteConnection, …) so a change to the engine API breaks these tests
// rather than silently no-opping in production.
function makeCanvas(over = {}) {
  const canvas = {
    elements: [],
    connections: [],
    onBeforeChange: vi.fn(),
    onchange: vi.fn(),
    updateConnections: vi.fn(),
    updateElementProperties: vi.fn((id, label, props) => {
      const element = canvas.elements.find((e) => e.id === id)
      if (!element) return undefined
      if (label !== undefined) element.label = label
      if (props !== undefined) element.properties = { ...(element.properties || {}), ...props }
      return element
    }),
    updateConnectionProperties: vi.fn((id, label) => {
      const connection = canvas.connections.find((c) => c.id === id)
      if (connection && label !== undefined) connection.label = label
    }),
    deleteConnection: vi.fn((id) => {
      canvas.connections = canvas.connections.filter((c) => c.id !== id)
    }),
    createConnection: vi.fn((from, to) => {
      const connection = { id: `${from.id}-${to.id}`, from: from.id, to: to.id }
      canvas.connections.push(connection)
      return connection
    }),
    _deleteElement: vi.fn((element) => {
      canvas.elements = canvas.elements.filter((e) => e.id !== element.id)
    }),
    addElement: vi.fn((data) => {
      const element = { id: "new-end", type: data.type, label: "End", properties: {} }
      canvas.elements.push(element)
      return element
    }),
    ...over,
  }
  return canvas
}

const el = (id, type, properties = {}, label = id) => ({ id, type, label, properties })
const box = (id, type, x, y) => ({ id, type, label: id, x, y, width: 120, height: 60, properties: {} })
const conn = (id, from, to, extra = {}) => ({ id, from, to, ...extra })

describe("buildAutoFix", () => {
  it("returns null for a rule with no registered fix, and without a canvas", () => {
    expect(buildAutoFix({ type: "unreachable" }, makeCanvas())).toBeNull()
    expect(buildAutoFix({ type: "duplicate_label" }, null)).toBeNull()
    expect(buildAutoFix(undefined, makeCanvas())).toBeNull()
  })

  it("falls back to the English captions when no translations are threaded in", () => {
    const canvas = makeCanvas({ elements: [el("a", "process")] })
    const fix = buildAutoFix({ type: "duplicate_label", elementId: "a" }, canvas)
    expect(fix.label).toBe(DEFAULT_AUTO_FIX_LABELS.renameUnique)
    expect(fix.safe).toBe(true)
  })

  it("uses a threaded translation when one is supplied", () => {
    const canvas = makeCanvas({ elements: [el("a", "process")] })
    const fix = buildAutoFix({ type: "duplicate_label", elementId: "a" }, canvas, { renameUnique: "重命名" })
    expect(fix.label).toBe("重命名")
  })

  it("withholds a fix whose `available` guard fails", () => {
    const canvas = makeCanvas()
    expect(buildAutoFix({ type: "join_required_count", elementId: "j", meta: { incomingCount: 0 } }, canvas)).toBeNull()
    expect(buildAutoFix({ type: "join_required_count", elementId: "j" }, canvas)).toBeNull()
    expect(buildAutoFix({ type: "missing_end", elementId: null }, canvas)).toBeNull()
  })

  it("reports false when the fix finds nothing to change", () => {
    const canvas = makeCanvas()
    const fix = buildAutoFix({ type: "duplicate_label", elementId: "ghost" }, canvas)
    expect(fix.apply()).toBe(false)
  })
})

describe("duplicate_start fix", () => {
  it("deletes the extra Start through the canvas API", () => {
    const canvas = makeCanvas({ elements: [el("s1", "start"), el("s2", "start")] })
    expect(buildAutoFix({ type: "duplicate_start", elementId: "s2" }, canvas).apply()).toBe(true)
    expect(canvas.elements.map((e) => e.id)).toEqual(["s1"])
    expect(canvas.onBeforeChange).toHaveBeenCalled()
    expect(canvas.onchange).toHaveBeenCalled()
  })

  it("is offered as a suggestion, not a safe fix", () => {
    expect(AUTO_FIXES.duplicate_start.safe).toBe(false)
  })

  it("does nothing when the canvas cannot delete elements", () => {
    const canvas = makeCanvas({ elements: [el("s2", "start")], _deleteElement: undefined })
    expect(buildAutoFix({ type: "duplicate_start", elementId: "s2" }, canvas).apply()).toBe(false)
  })
})

describe("duplicate_label fix", () => {
  it("appends the first free numeric suffix", () => {
    const canvas = makeCanvas({
      elements: [el("a", "process", {}, "Check"), el("b", "process", {}, "Check"), el("c", "process", {}, "Check 2")],
    })
    expect(buildAutoFix({ type: "duplicate_label", elementId: "b" }, canvas).apply()).toBe(true)
    expect(canvas.elements.find((e) => e.id === "b").label).toBe("Check 3")
  })

  it("strips an existing numeric suffix before renumbering", () => {
    const canvas = makeCanvas({ elements: [el("a", "process", {}, "Check 4"), el("b", "process", {}, "Check 4")] })
    buildAutoFix({ type: "duplicate_label", elementId: "b" }, canvas).apply()
    expect(canvas.elements.find((e) => e.id === "b").label).toBe("Check 2")
  })

  it("leaves a blank or no-longer-duplicated label alone and reports nothing to do", () => {
    const canvas = makeCanvas({
      elements: [el("a", "process", {}, "  "), { id: "b", type: "process", properties: {} }, el("c", "process", {}, "Solo")],
    })
    for (const id of ["a", "b", "c"]) {
      expect(buildAutoFix({ type: "duplicate_label", elementId: id }, canvas).apply(), id).toBe(false)
    }
    expect(canvas.updateElementProperties).not.toHaveBeenCalled()
  })

  it("ignores unlabelled siblings when looking for a free suffix", () => {
    const canvas = makeCanvas({
      elements: [el("a", "process", {}, ""), { id: "b", type: "process", properties: {} }, el("c", "process", {}, "Check"), el("d", "process", {}, "Check")],
    })
    expect(buildAutoFix({ type: "duplicate_label", elementId: "d" }, canvas).apply()).toBe(true)
    expect(canvas.elements[3].label).toBe("Check 2")
  })

  it("numbers with the canvas's translated format", () => {
    const canvas = makeCanvas({ elements: [el("a", "process", {}, "检查"), el("b", "process", {}, "检查")] })
    canvas.labels = { uniqueLabelFormat: "{label}（{n}）" }
    buildAutoFix({ type: "duplicate_label", elementId: "b" }, canvas).apply()
    expect(canvas.elements[1].label).toBe("检查（2）")
  })

  it("writes directly when the canvas exposes no updateElementProperties", () => {
    const canvas = makeCanvas({
      elements: [el("a", "process", {}, "Check"), el("b", "process", {}, "Check")],
      updateElementProperties: undefined,
    })
    expect(buildAutoFix({ type: "duplicate_label", elementId: "a" }, canvas).apply()).toBe(true)
    expect(canvas.elements[0].label).toBe("Check 2")
  })

  it("reports false on a direct write when the element is gone", () => {
    const canvas = makeCanvas({ updateElementProperties: undefined })
    expect(buildAutoFix({ type: "duplicate_label", elementId: "ghost" }, canvas).apply()).toBe(false)
  })
})

describe("connection fixes", () => {
  it("removes the offending edge for self, duplicate, and dangling connections", () => {
    for (const type of ["self_connection", "duplicate_connection", "dangling_connection"]) {
      const canvas = makeCanvas({ connections: [conn("c1", "a", "a"), conn("c2", "a", "b")] })
      expect(buildAutoFix({ type, connectionId: "c1" }, canvas).apply(), type).toBe(true)
      expect(canvas.connections.map((c) => c.id), type).toEqual(["c2"])
    }
  })

  it("reports false for an edge that is already gone", () => {
    const canvas = makeCanvas()
    expect(buildAutoFix({ type: "self_connection", connectionId: "gone" }, canvas).apply()).toBe(false)
  })
})

describe("unsupported structural fixes", () => {
  it("never offers autofix behavior for the explicit unsupported-structure error", () => {
    const canvas = makeCanvas()
    expect(buildAutoFix({
      type: "unsupported_structural_element",
      elementId: "legacy"
    }, canvas)).toBeNull()
  })
})

describe("schema-defaulted value fixes", () => {
  it("has no Timer duration auto-fix after Timer removal", () => {
    const canvas = makeCanvas({ elements: [el("t", "timer")] })
    expect(buildAutoFix({ type: "timer_no_duration", elementId: "t" }, canvas)).toBeNull()
  })

  it("does not offer an HTTP-status auto-fix after that field left the catalog", () => {
    const canvas = makeCanvas({ elements: [el("e", "end", { responseType: "http_response" })] })
    expect(buildAutoFix({ type: "end_http_no_status", elementId: "e" }, canvas)).toBeNull()
  })

})

describe("suggested value fixes", () => {
  it("seeds a Return Value", () => {
    const canvas = makeCanvas({ elements: [el("e", "end")] })
    const fix = buildAutoFix({ type: "end_no_return_value", elementId: "e" }, canvas)
    expect(fix.safe).toBe(false)
    expect(fix.label).toBe("Use ctx[:result]")
    expect(fix.apply()).toBe(true)
    expect(canvas.elements[0].properties.returnValue).toBe("ctx[:result]")
  })

  it("patches properties directly when the canvas exposes no updateElementProperties", () => {
    const canvas = makeCanvas({ elements: [{ id: "e", type: "end" }], updateElementProperties: undefined })
    expect(buildAutoFix({ type: "end_no_return_value", elementId: "e" }, canvas).apply()).toBe(true)
    expect(canvas.elements[0].properties).toEqual({ returnValue: "ctx[:result]" })
    expect(buildAutoFix({ type: "end_no_return_value", elementId: "ghost" }, canvas).apply()).toBe(false)
  })

  it("does not offer a Start cron auto-fix after triggers left the catalog", () => {
    const canvas = makeCanvas({ elements: [el("s", "start")] })
    expect(buildAutoFix({ type: "start_schedule_no_cron", elementId: "s" }, canvas)).toBeNull()
  })

  it("clears the canonical target key on a self-referencing Subflow", () => {
    const canvas = makeCanvas({ elements: [el("sf", "subflow", { flowchartId: "7", subflowId: "7" })] })
    expect(buildAutoFix({ type: "subflow_self_reference", elementId: "sf" }, canvas).apply()).toBe(true)
    expect(canvas.elements[0].properties).toMatchObject({ flowchartId: "", subflowId: "7" })
  })
})

// Start → a, Start → b: the reachable dead ends are [a, b] in traversal order.
const forkCanvas = (over = {}) =>
  makeCanvas({
    elements: [box("s", "start", 400, 80), box("a", "process", 300, 200), box("b", "process", 500, 200)],
    connections: [conn("c1", "s", "a"), conn("c2", "s", "b")],
    ...over,
  })

describe("P5-5 missing_end fix", () => {
  it("adds the End below the last reachable dead end and connects only that one, as one undo entry", () => {
    const canvas = forkCanvas({ undoCoalesceKey: "prior" })
    const keysDuringAdd = []
    const addElement = canvas.addElement
    canvas.addElement = vi.fn((data) => {
      keysDuringAdd.push(canvas.undoCoalesceKey)
      return addElement(data)
    })

    expect(buildAutoFix({ type: "missing_end", elementId: null }, canvas).apply()).toBe(true)

    expect(canvas.addElement).toHaveBeenCalledWith({
      type: "end",
      x: 500,
      y: 200 + 30 + DEFAULT_ELEMENT_SPACING + DEFAULT_ELEMENT_HEIGHT / 2,
    })
    expect(canvas.connections.filter((c) => c.to === "new-end").map((c) => c.from)).toEqual(["b"])
    expect(canvas.createConnection).toHaveBeenCalledWith(expect.objectContaining({ id: "b" }), expect.objectContaining({ id: "new-end" }), "bottom", "top")
    expect(keysDuringAdd).toEqual(["autofix:missing_end:b"])
    expect(canvas.undoCoalesceKey).toBe("prior")
    expect(canvas.updateConnections).toHaveBeenCalled()
    expect(canvas.onchange).toHaveBeenCalled()
  })

  it("is not offered without a Start, or when the only dead ends are unreachable, Decisions or Ends", () => {
    const noStart = makeCanvas({ elements: [box("a", "process", 0, 0)] })
    expect(buildAutoFix({ type: "missing_end", elementId: null }, noStart)).toBeNull()

    const noDeadEnd = makeCanvas({
      elements: [box("s", "start", 0, 0), box("d", "decision", 0, 100), box("e", "end", 0, 200), box("island", "process", 300, 0)],
      connections: [conn("c1", "s", "d"), conn("c2", "d", "e")],
    })
    expect(buildAutoFix({ type: "missing_end", elementId: null }, noDeadEnd)).toBeNull()
    expect(buildAutoFix({ type: "missing_end", elementId: null }, makeCanvas({ elements: [box("s", "start", 0, 0)] }))).toBeNull()
  })

  it("follows branches breadth-first, skips loop back-edges and dangling targets", () => {
    const canvas = makeCanvas({
      elements: [
        box("s", "start", 0, 0), box("p", "process", 0, 100), box("d", "decision", 0, 200),
        box("a", "process", -100, 300), box("b", "process", 100, 300), box("c", "process", 100, 400),
        box("x", "process", 200, 300),
      ],
      connections: [
        conn("c1", "s", "p"), conn("c2", "p", "d"), conn("c3", "d", "a"), conn("c4", "d", "b"),
        conn("c5", "b", "c"), conn("c6", "d", "x"), conn("c7", "x", "p"), conn("c8", "a", "ghost"),
      ],
    })
    buildAutoFix({ type: "missing_end", elementId: null }, canvas).apply()
    expect(canvas.connections.filter((c) => c.to === "new-end").map((c) => c.from)).toEqual(["c"])
  })

  it("reports false when the canvas cannot add elements or connections, or addElement refuses", () => {
    const noAdd = forkCanvas({ addElement: undefined })
    expect(buildAutoFix({ type: "missing_end", elementId: null }, noAdd).apply()).toBe(false)

    const noConnect = forkCanvas({ createConnection: undefined })
    expect(buildAutoFix({ type: "missing_end", elementId: null }, noConnect).apply()).toBe(false)

    const refuses = forkCanvas({ addElement: vi.fn(() => null) })
    expect(buildAutoFix({ type: "missing_end", elementId: null }, refuses).apply()).toBe(false)
    expect(refuses.undoCoalesceKey).toBeUndefined()
  })
})

describe("P5-5 orphan_end fix", () => {
  it("connects the last reachable dead end into the orphaned End", () => {
    const canvas = forkCanvas()
    canvas.elements.push(box("e", "end", 400, 400))
    expect(buildAutoFix({ type: "orphan_end", elementId: "e" }, canvas).apply()).toBe(true)
    expect(canvas.connections.filter((c) => c.to === "e").map((c) => c.from)).toEqual(["b"])
    expect(canvas.onBeforeChange).toHaveBeenCalled()
    expect(canvas.onchange).toHaveBeenCalled()
  })

  it("is not offered when no dead end is reachable from Start", () => {
    const canvas = makeCanvas({ elements: [box("s", "start", 0, 0), box("island", "process", 0, 100), box("e", "end", 0, 200)] })
    expect(buildAutoFix({ type: "orphan_end", elementId: "e" }, canvas)).toBeNull()
  })

  it("reports false for an End that is no longer on the canvas", () => {
    expect(buildAutoFix({ type: "orphan_end", elementId: "ghost" }, forkCanvas()).apply()).toBe(false)
  })

  it("reports false when the canvas cannot create connections", () => {
    const canvas = forkCanvas({ createConnection: undefined })
    canvas.elements.push(box("e", "end", 400, 400))
    expect(buildAutoFix({ type: "orphan_end", elementId: "e" }, canvas).apply()).toBe(false)
  })
})

describe("applySafeAutoFixes / countSafeAutoFixes", () => {
  const problems = () => [
    { type: "duplicate_label", elementId: "u" },
    { type: "self_connection", connectionId: "c1" },
    { type: "end_no_return_value", elementId: "e" }, // suggested — skipped
    { type: "unreachable", elementId: "u" }, // no fix at all
  ]

  const canvasWithAll = () =>
    makeCanvas({
      elements: [el("e", "end"), el("u", "process"), el("u-twin", "process", {}, "u")],
      connections: [conn("c1", "x", "x")],
    })

  it("counts only the safe fixes", () => {
    expect(countSafeAutoFixes(problems(), canvasWithAll())).toBe(2)
    expect(countSafeAutoFixes(undefined, canvasWithAll())).toBe(0)
  })

  it("applies only the safe fixes and leaves the suggestions alone", () => {
    const canvas = canvasWithAll()
    expect(applySafeAutoFixes(problems(), canvas)).toEqual({ applied: 2, skipped: 2 })
    expect(canvas.elements.find((e) => e.id === "u").label).toBe("u 2")
    expect(canvas.connections).toHaveLength(0)
    expect(canvas.elements.find((e) => e.id === "e").properties).toEqual({})
  })

  it("counts a fix that finds nothing to change as skipped rather than throwing", () => {
    const canvas = makeCanvas()
    expect(applySafeAutoFixes([{ type: "self_connection", connectionId: "gone" }], canvas))
      .toEqual({ applied: 0, skipped: 1 })
  })

  it("tolerates an empty problem list", () => {
    expect(applySafeAutoFixes(undefined, makeCanvas())).toEqual({ applied: 0, skipped: 0 })
  })
})

describe("P5-4 validation_autofix — canMutate guard", () => {
  it("buildAutoFix and applySafeAutoFixes no-op when canMutate is false", () => {
    const canvas = makeCanvas({
      canMutate: () => false,
      elements: [el("u", "process")],
      connections: [conn("c1", "x", "x")],
    })
    expect(buildAutoFix({ type: "duplicate_label", elementId: "u" }, canvas)).toBeNull()
    expect(applySafeAutoFixes([{ type: "duplicate_label", elementId: "u" }], canvas))
      .toEqual({ applied: 0, skipped: 1 })
    expect(applySafeAutoFixes(undefined, canvas)).toEqual({ applied: 0, skipped: 0 })
    expect(canvas.elements[0].label).toBe("u")
  })
})
