import { describe, it, expect } from "vitest"
import { validateOverrides } from "controllers/property_editor/element_io/override_validator"

function fakeCanvas(elements, connections) {
  return {
    elements,
    connections,
    iterateElements(cb) {
      elements.forEach((el) => cb(el))
    },
    getElementPins(id) {
      const el = elements.find((e) => e.id === id)
      return el?.pins || { inputs: [], outputs: [] }
    },
  }
}
const el = (id, { outputs = [], overrides = null } = {}) => ({
  id,
  type: "process",
  properties: overrides ? { io_overrides: overrides } : {},
  pins: { inputs: [], outputs: outputs.map((pin) => ({ pin })) },
})
const c = (from, to) => ({ from, to })

describe("validateOverrides", () => {
  it("leaves elements without io_overrides untouched", () => {
    const a = el("a", { outputs: ["x"] })
    const canvas = fakeCanvas([a], [])
    validateOverrides(canvas)
    expect(a.properties.io_overrides).toBeUndefined()
  })

  it("preserves input tombstones", () => {
    const b = el("b", {
      overrides: { inputs: [{ pin: "model", override_key: "" }], outputs: [] },
    })
    const canvas = fakeCanvas([el("a"), b], [c("a", "b")])
    validateOverrides(canvas)
    expect(b.properties.io_overrides.inputs).toEqual([{ pin: "model", override_key: "" }])
  })

  it("keeps an input override whose key is still emitted by a reachable producer", () => {
    const a = el("a", { outputs: ["model"] })
    const b = el("b", {
      overrides: { inputs: [{ pin: "model", override_key: "model" }], outputs: [] },
    })
    const canvas = fakeCanvas([a, b], [c("a", "b")])
    validateOverrides(canvas)
    expect(b.properties.io_overrides.inputs).toEqual([{ pin: "model", override_key: "model" }])
  })

  it("drops an input override whose key is no longer reachable", () => {
    const a = el("a", { outputs: ["other"] })
    const b = el("b", {
      overrides: { inputs: [{ pin: "model", override_key: "gone_key" }], outputs: [] },
    })
    const canvas = fakeCanvas([a, b], [c("a", "b")])
    validateOverrides(canvas)
    expect(b.properties.io_overrides.inputs).toEqual([])
  })

  it("keeps an output rename while a collision with another emitter persists", () => {
    const a = el("a", { outputs: ["token"] })
    const b = el("b", {
      outputs: ["token"],
      overrides: { inputs: [], outputs: [{ pin: "token", renamed_to: "token_ab12" }] },
    })
    const canvas = fakeCanvas([a, b], [c("a", "b")])
    validateOverrides(canvas)
    expect(b.properties.io_overrides.outputs).toEqual([{ pin: "token", renamed_to: "token_ab12" }])
  })

  it("drops an output rename once the collision is gone", () => {
    // b is the only emitter of token now — rename is stale.
    const a = el("a", { outputs: ["other"] })
    const b = el("b", {
      outputs: ["token"],
      overrides: { inputs: [], outputs: [{ pin: "token", renamed_to: "token_ab12" }] },
    })
    const canvas = fakeCanvas([a, b], [])
    validateOverrides(canvas)
    expect(b.properties.io_overrides.outputs).toEqual([])
  })

  it("drops an output rename whose pin the element no longer emits", () => {
    const b = el("b", {
      outputs: [], // no longer emits token
      overrides: { inputs: [], outputs: [{ pin: "token", renamed_to: "token_ab12" }] },
    })
    const canvas = fakeCanvas([el("a", { outputs: ["token"] }), b], [])
    validateOverrides(canvas)
    expect(b.properties.io_overrides.outputs).toEqual([])
  })

  it("treats a missing overrides.inputs list as empty (defaults via ||)", () => {
    const b = el("b", { overrides: { outputs: [] } }) // no inputs key at all
    const canvas = fakeCanvas([b], [])
    validateOverrides(canvas)
    expect(b.properties.io_overrides.inputs).toEqual([])
  })

  it("treats a missing overrides.outputs list as empty (defaults via ||)", () => {
    const b = el("b", { overrides: { inputs: [] } }) // no outputs key at all
    const canvas = fakeCanvas([b], [])
    validateOverrides(canvas)
    expect(b.properties.io_overrides.outputs).toEqual([])
  })

  it("drops an input override whose only reachable producer is a dangling connection endpoint", () => {
    // Connection references "ghost", which is not an actual canvas element —
    // emitted.get("ghost") is undefined, so that producer contributes nothing.
    const b = el("b", {
      overrides: { inputs: [{ pin: "model", override_key: "model" }], outputs: [] },
    })
    const canvas = fakeCanvas([b], [c("ghost", "b")])
    validateOverrides(canvas)
    expect(b.properties.io_overrides.inputs).toEqual([])
  })

  it("treats missing pins.outputs from getElementPins as empty", () => {
    const a = { id: "a", type: "process", properties: {}, pins: { inputs: [] } } // no outputs key
    const canvas = fakeCanvas([a], [])
    expect(() => validateOverrides(canvas)).not.toThrow()
  })
})
