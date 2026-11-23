import { describe, it, expect } from "vitest"
import { ClipboardManager } from "flowchart/clipboard_manager"

// ClipboardManager is pure data: it reads canvas.selectedElements /
// canvas.connections and returns fresh element/connection objects. No DOM.

const makeCanvas = (selectedElements, connections = [], elements = selectedElements) => ({
  selectedElements,
  elements,
  connections,
})

describe("ClipboardManager", () => {
  describe("copy", () => {
    it("returns false and stays empty when nothing is selected", () => {
      const cm = new ClipboardManager(makeCanvas([]))
      expect(cm.copy()).toBe(false)
      expect(cm.hasContent).toBe(false)
    })

    it("returns true and snapshots the selection", () => {
      const cm = new ClipboardManager(makeCanvas([{ id: "a", x: 15, y: 15, label: "A" }]))
      expect(cm.copy()).toBe(true)
      expect(cm.hasContent).toBe(true)
    })

    it("only keeps connections whose BOTH endpoints are in the selection", () => {
      const canvas = makeCanvas(
        [{ id: "a", x: 0, y: 0 }, { id: "b", x: 0, y: 0 }],
        [
          { id: "c1", from: "a", to: "b" },       // both selected -> kept
          { id: "c2", from: "a", to: "outside" }, // dropped
        ]
      )
      const cm = new ClipboardManager(canvas)
      cm.copy()
      expect(cm.clipboard.connections).toHaveLength(1)
      expect(cm.clipboard.connections[0].id).toBe("c1")
    })

    it("deep-copies elements (mutating the snapshot doesn't touch the source)", () => {
      const src = { id: "a", x: 15, y: 15, properties: { steps: [] } }
      const cm = new ClipboardManager(makeCanvas([src]))
      cm.copy()
      cm.clipboard.elements[0].x = 999
      expect(src.x).toBe(15)
    })
  })

  describe("paste", () => {
    it("returns null when the clipboard is empty", () => {
      const cm = new ClipboardManager(makeCanvas([]))
      expect(cm.paste()).toBeNull()
    })

    it("offsets positions by 30 (snapped) and assigns fresh ids", () => {
      const cm = new ClipboardManager(makeCanvas([{ id: "a", x: 15, y: 15, label: "A" }]))
      cm.copy()
      const { elements } = cm.paste()
      expect(elements[0].id).not.toBe("a")
      expect(elements[0].id).toMatch(/^el_/)
      expect(elements[0].x).toBe(45) // snapToGrid(15+30, 15)
      expect(elements[0].y).toBe(45)
      expect(elements[0].label).toBe("A 2")
    })

    it("cascades the offset by 30 * n and resets n on the next copy", () => {
      const src = { id: "a", x: 15, y: 15, label: "A" }
      const cm = new ClipboardManager(makeCanvas([src]))
      cm.copy()
      expect(cm.paste().elements[0].x).toBe(45)
      expect(cm.paste().elements[0].x).toBe(75) // snapToGrid(15+60, 15)
      cm.copy()
      expect(cm.paste().elements[0].x).toBe(45)
    })

    it("leaves an element without properties untouched besides id and offset", () => {
      const cm = new ClipboardManager(makeCanvas([{ id: "a", x: 15, y: 15 }]))
      cm.copy()
      const pasted = cm.paste().elements[0]
      expect(pasted.properties).toBeUndefined()
      expect(pasted.x).toBe(45)
    })

    it("regenerates step ids so duplicates don't share identity", () => {
      const cm = new ClipboardManager(makeCanvas([
        { id: "a", x: 15, y: 15, properties: { steps: [{ id: "s1", action: "validate" }] } },
      ]))
      cm.copy()
      const step = cm.paste().elements[0].properties.steps[0]
      expect(step.id).not.toBe("s1")
      expect(step.id).toMatch(/^step_/)
      expect(step.action).toBe("validate") // other fields preserved
    })

    it("gives each paste its own properties object so a second paste cannot mutate the first", () => {
      const cm = new ClipboardManager(makeCanvas([
        { id: "proc", x: 15, y: 15, properties: { steps: [{ id: "s1", action: "validate" }] } },
      ]))
      cm.copy()
      const first = cm.paste().elements[0]
      const second = cm.paste().elements[0]

      expect(first.properties).not.toBe(second.properties)
      expect(first.properties).not.toBe(cm.clipboard.elements[0].properties)
      expect(first.properties.steps).not.toBe(second.properties.steps)

      const firstStepIds = first.properties.steps.map((s) => s.id)
      second.properties.steps.push({ id: "injected", action: "extra" })
      expect(first.properties.steps.map((s) => s.id)).toEqual(firstStepIds)
      expect(first.properties.steps).toHaveLength(1)
    })

    it("passes through falsy/non-object steps unchanged", () => {
      const cm = new ClipboardManager(makeCanvas([
        { id: "a", x: 15, y: 15, properties: { steps: [null, "not-an-object"] } },
      ]))
      cm.copy()
      const steps = cm.paste().elements[0].properties.steps
      expect(steps).toEqual([null, "not-an-object"])
    })

    it("remaps connection endpoints and assigns fresh connection ids", () => {
      const canvas = makeCanvas(
        [{ id: "a", x: 15, y: 15 }, { id: "b", x: 30, y: 30 }],
        [{ id: "c1", from: "a", to: "b" }]
      )
      const cm = new ClipboardManager(canvas)
      cm.copy()
      const { elements, connections } = cm.paste()
      const [na, nb] = elements
      expect(connections[0].id).toMatch(/^conn_/)
      expect(connections[0].from).toBe(na.id)
      expect(connections[0].to).toBe(nb.id)
    })
  })

  describe("duplicate", () => {
    it("copies then pastes in one call", () => {
      const cm = new ClipboardManager(makeCanvas([{ id: "a", x: 15, y: 15 }]))
      const result = cm.duplicate()
      expect(result.elements).toHaveLength(1)
      expect(result.elements[0].id).not.toBe("a")
    })

    it("returns null when there is nothing to copy", () => {
      const cm = new ClipboardManager(makeCanvas([]))
      expect(cm.duplicate()).toBeNull()
    })
  })
})

describe("P5-4 clipboard — strip expanded-subflow markers on paste", () => {
  it("drops _expandedFromSubflow so pasted inner elements stay collapsed", () => {
    const cm = new ClipboardManager(makeCanvas([
      { id: "inner", x: 15, y: 15, properties: { _expandedFromSubflow: "SF", varMappings: [{ v: 1 }] } },
    ]))
    cm.copy()
    const pasted = cm.paste().elements[0]
    expect(pasted.properties._expandedFromSubflow).toBeUndefined()
    expect(pasted.properties.varMappings).toEqual([{ v: 1 }])
    expect(cm.clipboard.elements[0].properties._expandedFromSubflow).toBe("SF")
  })
})

describe("P5-5 clipboard — unique labels on paste/duplicate", () => {
  it("numbers each pasted label past every label already on the canvas and in the paste", () => {
    const selection = [{ id: "a", x: 15, y: 15, label: "Check" }, { id: "b", x: 15, y: 60, label: "Check 2" }]
    const cm = new ClipboardManager(makeCanvas(selection, [], [...selection, { id: "c", label: "end" }]))
    cm.copy()
    expect(cm.paste().elements.map(el => el.label)).toEqual(["Check 3", "Check 4"])
  })

  it("keeps a label nothing else uses and uses the canvas's translated format", () => {
    const canvas = makeCanvas([{ id: "a", x: 15, y: 15, label: "结束" }], [], [{ id: "z", label: "结束" }])
    canvas.labels = { uniqueLabelFormat: "{label}（{n}）" }
    const cm = new ClipboardManager(canvas)
    cm.copy()
    expect(cm.paste().elements[0].label).toBe("结束（2）")

    canvas.elements = []
    expect(cm.paste().elements[0].label).toBe("结束")
  })
})
