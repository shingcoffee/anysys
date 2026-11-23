import { describe, it, expect, vi, afterEach } from "vitest"
import { computeElementOverrides } from "controllers/property_editor/element_io/override_computer"

// Fake canvas: pure data graph. Pins stored on each element under `pins`.
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
const el = (id, { inputs = [], outputs = [], overrides = null, type = "process" } = {}) => ({
  id,
  type,
  properties: overrides ? { io_overrides: overrides } : {},
  pins: {
    inputs: inputs.map((pin) => ({ pin })),
    outputs: outputs.map((pin) => ({ pin })),
  },
})
const c = (from, to) => ({ from, to })

describe("computeElementOverrides", () => {
  it("returns empty overrides for an unknown element", async () => {
    const canvas = fakeCanvas([el("a")], [])
    expect(await computeElementOverrides(canvas, "missing")).toEqual({ inputs: [], outputs: [] })
  })

  it("renames an output that collides with an earlier emitter", async () => {
    const canvas = fakeCanvas(
      [el("a", { outputs: ["token"] }), el("b", { outputs: ["token"] })],
      [c("a", "b")]
    )
    const result = await computeElementOverrides(canvas, "b")
    expect(result.outputs).toHaveLength(1)
    expect(result.outputs[0].pin).toBe("token")
    expect(result.outputs[0].renamed_to).toMatch(/^token_[0-9a-f]{4}$/)
  })

  it("keeps the first emitter's output name unchanged", async () => {
    const canvas = fakeCanvas(
      [el("a", { outputs: ["token"] }), el("b", { outputs: ["token"] })],
      [c("a", "b")]
    )
    const result = await computeElementOverrides(canvas, "a")
    expect(result.outputs).toEqual([])
  })

  it("keeps the original key for writers on exclusive branches", async () => {
    // start → left → merge, start → right → merge; left and right both emit reviewer
    const canvas = fakeCanvas(
      [
        el("start", { outputs: [] }),
        el("left", { outputs: ["reviewer"] }),
        el("right", { outputs: ["reviewer"] }),
        el("merge", { outputs: [] }),
      ],
      [c("start", "left"), c("start", "right"), c("left", "merge"), c("right", "merge")]
    )
    expect((await computeElementOverrides(canvas, "left")).outputs).toEqual([])
    expect((await computeElementOverrides(canvas, "right")).outputs).toEqual([])
  })

  it("renames a writer when another writer of the same pin is an ancestor", async () => {
    const canvas = fakeCanvas(
      [
        el("start"),
        el("seed", { outputs: ["status"] }),
        el("decision"),
        el("approved", { outputs: ["status"] }),
        el("merge"),
      ],
      [c("start", "seed"), c("seed", "decision"), c("decision", "approved"), c("approved", "merge")]
    )
    expect((await computeElementOverrides(canvas, "seed")).outputs).toEqual([])
    const approved = await computeElementOverrides(canvas, "approved")
    expect(approved.outputs).toHaveLength(1)
    expect(approved.outputs[0].renamed_to).toMatch(/^status_[0-9a-f]{4}$/)
  })

  it("renames every writer that has an upstream writer of the same pin", async () => {
    const canvas = fakeCanvas(
      [
        el("seed", { outputs: ["x"] }),
        el("left", { outputs: ["x"] }),
        el("right", { outputs: ["x"] }),
      ],
      [c("seed", "left"), c("seed", "right")]
    )
    expect((await computeElementOverrides(canvas, "seed")).outputs).toEqual([])
    expect((await computeElementOverrides(canvas, "left")).outputs[0].renamed_to).toMatch(/^x_[0-9a-f]{4}$/)
    expect((await computeElementOverrides(canvas, "right")).outputs[0].renamed_to).toMatch(/^x_[0-9a-f]{4}$/)
  })

  it("lets terminal Ends on exclusive branches share response", async () => {
    const canvas = fakeCanvas(
      [
        el("start"),
        el("end_a", { outputs: ["response"], type: "end" }),
        el("end_b", { outputs: ["response"], type: "end" }),
      ],
      [c("start", "end_a"), c("start", "end_b")]
    )
    expect((await computeElementOverrides(canvas, "end_a")).outputs).toEqual([])
    expect((await computeElementOverrides(canvas, "end_b")).outputs).toEqual([])
  })

  it("does not collide when the effective keys already differ", async () => {
    const canvas = fakeCanvas(
      [el("a", { outputs: ["model_a3f2"] }), el("b", { outputs: ["model"] })],
      [c("a", "b")]
    )
    expect((await computeElementOverrides(canvas, "a")).outputs).toEqual([])
    expect((await computeElementOverrides(canvas, "b")).outputs).toEqual([])
  })

  it("renames a loop-body writer when a seed before the loop writes the same pin", async () => {
    // seed → header → body → header (back-edge) and header → exit
    const canvas = fakeCanvas(
      [
        el("seed", { outputs: ["x"] }),
        el("header", { type: "loop", outputs: [] }),
        el("body", { outputs: ["x"] }),
        el("exit"),
      ],
      [c("seed", "header"), c("header", "body"), c("body", "header"), c("header", "exit")]
    )
    expect((await computeElementOverrides(canvas, "seed")).outputs).toEqual([])
    const body = await computeElementOverrides(canvas, "body")
    expect(body.outputs).toHaveLength(1)
    expect(body.outputs[0].pin).toBe("x")
    expect(body.outputs[0].renamed_to).toMatch(/^x_[0-9a-f]{4}$/)
  })

  it("lets exclusive branches inside a loop body keep the same pin", async () => {
    // header → decision → left|right → merge → header (back-edge) and header → exit
    const canvas = fakeCanvas(
      [
        el("header", { type: "loop", outputs: [] }),
        el("decision", { type: "decision" }),
        el("left", { outputs: ["x"] }),
        el("right", { outputs: ["x"] }),
        el("merge"),
        el("exit"),
      ],
      [
        c("header", "decision"),
        c("decision", "left"),
        c("decision", "right"),
        c("left", "merge"),
        c("right", "merge"),
        c("merge", "header"),
        c("header", "exit"),
      ]
    )
    expect((await computeElementOverrides(canvas, "left")).outputs).toEqual([])
    expect((await computeElementOverrides(canvas, "right")).outputs).toEqual([])
  })

  it("treats a loop-body writer as an ancestor of the exit, not of the header via the back-edge", async () => {
    // header → body → header (back-edge) and header → exit
    const canvas = fakeCanvas(
      [
        el("header", { type: "loop", outputs: [] }),
        el("body", { outputs: ["item"] }),
        el("exit", { outputs: ["item"] }),
      ],
      [c("header", "body"), c("body", "header"), c("header", "exit")]
    )
    expect((await computeElementOverrides(canvas, "body")).outputs).toEqual([])
    const exit = await computeElementOverrides(canvas, "exit")
    expect(exit.outputs).toHaveLength(1)
    expect(exit.outputs[0].renamed_to).toMatch(/^item_[0-9a-f]{4}$/)
  })

  it("is deterministic across calls when an ancestor forces a rename", async () => {
    const canvas = fakeCanvas(
      [el("a", { outputs: ["model"] }), el("b", { outputs: ["model"] })],
      [c("a", "b")]
    )
    const first = await computeElementOverrides(canvas, "b")
    const second = await computeElementOverrides(canvas, "b")
    expect(second).toEqual(first)
    expect(first.outputs[0].renamed_to).toMatch(/^model_[0-9a-f]{4}$/)
  })

  it("produces no input override when producer key already matches the pin", async () => {
    const canvas = fakeCanvas(
      [el("a", { outputs: ["model"] }), el("b", { inputs: ["model"] })],
      [c("a", "b")]
    )
    const result = await computeElementOverrides(canvas, "b")
    expect(result.inputs).toEqual([])
  })

  it("adds an input override pointing at a renamed upstream key", async () => {
    // a emits model but is itself renamed to model_ab12 via existing overrides;
    // b's input `model` should resolve to that renamed effective key.
    const a = el("a", {
      outputs: ["model"],
      overrides: { inputs: [], outputs: [{ pin: "model", renamed_to: "model_ab12" }] },
    })
    const b = el("b", { inputs: ["model"] })
    const canvas = fakeCanvas([a, b], [c("a", "b")])
    const result = await computeElementOverrides(canvas, "b")
    expect(result.inputs).toEqual([{ pin: "model", override_key: "model_ab12" }])
  })

  it("preserves an input tombstone (override_key === '')", async () => {
    const b = el("b", {
      inputs: ["model"],
      overrides: { inputs: [{ pin: "model", override_key: "" }], outputs: [] },
    })
    const canvas = fakeCanvas([el("a", { outputs: ["model"] }), b], [c("a", "b")])
    const result = await computeElementOverrides(canvas, "b")
    expect(result.inputs).toEqual([{ pin: "model", override_key: "" }])
  })

  it("routes a self-input to the element's own renamed output when it collides", async () => {
    // y emits data first; x also emits data (renamed) AND consumes data.
    const y = el("y", { outputs: ["data"] })
    const x = el("x", { inputs: ["data"], outputs: ["data"] })
    const canvas = fakeCanvas([y, x], [c("y", "x")])
    const result = await computeElementOverrides(canvas, "x")
    // x's own output renamed
    expect(result.outputs[0].renamed_to).toMatch(/^data_[0-9a-f]{4}$/)
    // x's input rewired to its own renamed key
    expect(result.inputs).toHaveLength(1)
    expect(result.inputs[0].pin).toBe("data")
    expect(result.inputs[0].override_key).toBe(result.outputs[0].renamed_to)
  })

  it("returns empty overrides when canvas.elements is undefined", async () => {
    const canvas = { connections: [], iterateElements() {}, getElementPins: () => ({ inputs: [], outputs: [] }) }
    const result = await computeElementOverrides(canvas, "a")
    expect(result).toEqual({ inputs: [], outputs: [] })
  })

  it("defaults missing pins.inputs/pins.outputs to empty arrays", async () => {
    const target = { id: "a", type: "process", properties: {}, pins: {} } // no inputs/outputs keys
    const canvas = {
      elements: [target],
      connections: [],
      iterateElements(cb) {
        cb(target)
      },
      getElementPins: () => target.pins,
    }
    const result = await computeElementOverrides(canvas, "a")
    expect(result).toEqual({ inputs: [], outputs: [] })
  })

  it("initializes a fresh self pin map when the target wasn't visited by collectEmittedKeys", () => {
    // Defensive fallback: guards a canvas whose iterateElements() and .elements
    // disagree about which elements exist.
    const target = el("a", { outputs: ["x"] })
    const canvas = {
      elements: [target],
      connections: [],
      iterateElements() {}, // never visits "a"
      getElementPins: (id) => (id === "a" ? target.pins : { inputs: [], outputs: [] }),
    }
    return computeElementOverrides(canvas, "a").then((result) => {
      expect(result).toEqual({ inputs: [], outputs: [] })
    })
  })

  it("defaults canvas.connections to [] and does not rename disconnected co-writers", async () => {
    const a = el("a", { outputs: ["x"] })
    const b = el("b", { outputs: ["x"] })
    const canvas = {
      elements: [a, b],
      iterateElements(cb) {
        ;[a, b].forEach(cb)
      },
      getElementPins: (id) => [a, b].find((e) => e.id === id)?.pins || { inputs: [], outputs: [] },
    }
    const result = await computeElementOverrides(canvas, "b")
    expect(result.outputs).toEqual([])
  })

  it("ignores connections whose endpoints are not known elements", async () => {
    const a = el("a", { outputs: ["x"] })
    const b = el("b", { outputs: ["x"] })
    const canvas = fakeCanvas([a, b], [
      c("ghost", "b"),
      c("a", "ghost2"),
    ])
    const result = await computeElementOverrides(canvas, "b")
    expect(result.outputs).toEqual([])
  })

  it("renames both writers when they are mutual ancestors through a cycle", async () => {
    const a = el("a", { outputs: ["x"] })
    const b = el("b", { outputs: ["x"] })
    const canvas = fakeCanvas([a, b], [c("a", "b"), c("b", "a")])
    const forB = await computeElementOverrides(canvas, "b")
    const forA = await computeElementOverrides(canvas, "a")
    expect(forB.outputs[0].renamed_to).toMatch(/^x_[0-9a-f]{4}$/)
    expect(forA.outputs[0].renamed_to).toMatch(/^x_[0-9a-f]{4}$/)
  })

  describe("input resolution via effectiveMatches (hash-suffix / exact-rename matches)", () => {
    it("self: matches on an exact (non-hash) rename of the element's own output", async () => {
      // x's own output "other" is manually renamed to "model" and has no
      // collision, so computeOutputOverrides leaves it untouched — the self
      // loop must match it via `effective === pin`, not `producerPin === pin`.
      const x = el("x", {
        inputs: ["model"],
        outputs: ["other"],
        overrides: { inputs: [], outputs: [{ pin: "other", renamed_to: "model" }] },
      })
      const canvas = fakeCanvas([x], [])
      const result = await computeElementOverrides(canvas, "x")
      // Already-correct effective key -> no override needed.
      expect(result.inputs).toEqual([])
    })

    it("self: matches via effectiveMatches when the rename carries a hash suffix", async () => {
      const x = el("x", {
        inputs: ["model"],
        outputs: ["other"],
        overrides: { inputs: [], outputs: [{ pin: "other", renamed_to: "model_ab12" }] },
      })
      const canvas = fakeCanvas([x], [])
      const result = await computeElementOverrides(canvas, "x")
      expect(result.inputs).toEqual([{ pin: "model", override_key: "model_ab12" }])
    })

    it("external: matches on an exact (non-hash) rename of an upstream producer", async () => {
      const a = el("a", {
        outputs: ["other"],
        overrides: { inputs: [], outputs: [{ pin: "other", renamed_to: "model" }] },
      })
      const b = el("b", { inputs: ["model"] })
      const canvas = fakeCanvas([a, b], [c("a", "b")])
      const result = await computeElementOverrides(canvas, "b")
      expect(result.inputs).toEqual([])
    })

    it("external: matches via effectiveMatches when the upstream rename carries a hash suffix", async () => {
      const a = el("a", {
        outputs: ["other"],
        overrides: { inputs: [], outputs: [{ pin: "other", renamed_to: "model_ab12" }] },
      })
      const b = el("b", { inputs: ["model"] })
      const canvas = fakeCanvas([a, b], [c("a", "b")])
      const result = await computeElementOverrides(canvas, "b")
      expect(result.inputs).toEqual([{ pin: "model", override_key: "model_ab12" }])
    })

    it("external: skips a predecessor id with no entry in the emitted map (dangling connection)", async () => {
      const b = el("b", { inputs: ["model"] })
      const canvas = fakeCanvas([b], [c("ghost", "b")]) // "ghost" is not a real element
      const result = await computeElementOverrides(canvas, "b")
      expect(result.inputs).toEqual([])
    })
  })

  it("tolerates canvas.elements becoming undefined between the target lookup and reachability's own read", async () => {
    const target = el("a", { outputs: ["x"] })
    let reads = 0
    const canvas = {
      get elements() {
        reads += 1
        return reads === 1 ? [target] : undefined
      },
      connections: [],
      iterateElements(cb) {
        cb(target)
      },
      getElementPins: (id) => (id === "a" ? target.pins : { inputs: [], outputs: [] }),
    }
    const result = await computeElementOverrides(canvas, "a")
    // No topo order at all (buildGlobalTopoOrder saw an empty elements array)
    // -> "a" is not its own first emitter by topo lookup, but it's still the
    // only emitter overall so no rename collision exists either way.
    expect(result.outputs).toEqual([])
  })

  describe("shortHash", () => {
    afterEach(() => {
      vi.unstubAllGlobals()
    })

    it("falls back to a deterministic djb2 hash when crypto.subtle is unavailable", async () => {
      vi.stubGlobal("crypto", {}) // no .subtle
      const canvas = fakeCanvas(
        [el("a", { outputs: ["token"] }), el("b", { outputs: ["token"] })],
        [c("a", "b")]
      )
      const result = await computeElementOverrides(canvas, "b")
      expect(result.outputs[0].renamed_to).toMatch(/^token_[0-9a-f]{4}$/)
    })
  })
})
