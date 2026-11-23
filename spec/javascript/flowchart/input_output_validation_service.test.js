import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { InputOutputValidationService } from "flowchart/input_output_validation_service"
import { applyFlowchartUrls, clearFlowchartUrls } from "../support/flowchart_urls.js"

// The service walks the element graph (real ElementReachability) and flags any
// input pin with no matching upstream/self/implicit output. Pin data comes from
// canvas.getElementPins; io_overrides live on element.properties. No real layout.

// A minimal canvas fake. `pins` maps elementId -> { inputs:[{pin}], outputs:[{pin}] }.
function makeCanvas(elements, connections, pins) {
  return {
    elements,
    connections,
    iterateElements(cb) { for (const el of elements) cb(el) },
    getElementPins(id) { return pins[id] || { inputs: [], outputs: [] } },
  }
}

const resetCache = () => {
  InputOutputValidationService._implicitKeysCache = null
  InputOutputValidationService._implicitKeysPromise = null
}

describe("InputOutputValidationService.validate", () => {
  beforeEach(resetCache)
  afterEach(() => { vi.restoreAllMocks(); resetCache() })

  it("flags an input with no upstream producer as missing_input", () => {
    const canvas = makeCanvas(
      [{ id: "a", properties: {} }, { id: "b", properties: {} }],
      [{ from: "a", to: "b" }],
      { a: { outputs: [{ pin: "x" }] }, b: { inputs: [{ pin: "y" }] } }
    )
    const errors = new InputOutputValidationService(canvas).validate()
    expect(errors).toHaveLength(1)
    expect(errors[0]).toMatchObject({ elementId: "b", type: "missing_input" })
    expect(errors[0].message).toContain('"y"')
    expect(errors[0].meta).toEqual({ pinKey: "y" })
  })

  it("passes when an upstream element outputs the required input", () => {
    const canvas = makeCanvas(
      [{ id: "a", properties: {} }, { id: "b", properties: {} }],
      [{ from: "a", to: "b" }],
      { a: { outputs: [{ pin: "x" }] }, b: { inputs: [{ pin: "x" }] } }
    )
    expect(new InputOutputValidationService(canvas).validate()).toEqual([])
  })

  it("does not treat a downstream element as an upstream producer", () => {
    // a -> b: b outputs x, but a needs x. b is a successor, not a predecessor.
    const canvas = makeCanvas(
      [{ id: "a", properties: {} }, { id: "b", properties: {} }],
      [{ from: "a", to: "b" }],
      { a: { inputs: [{ pin: "x" }] }, b: { outputs: [{ pin: "x" }] } }
    )
    const errors = new InputOutputValidationService(canvas).validate()
    expect(errors.map(e => e.elementId)).toEqual(["a"])
  })

  it("honors an output rename (io_overrides.outputs.renamed_to) upstream", () => {
    const canvas = makeCanvas(
      [
        { id: "a", properties: { io_overrides: { outputs: [{ pin: "x", renamed_to: "z" }] } } },
        { id: "b", properties: {} },
      ],
      [{ from: "a", to: "b" }],
      { a: { outputs: [{ pin: "x" }] }, b: { inputs: [{ pin: "z" }] } }
    )
    expect(new InputOutputValidationService(canvas).validate()).toEqual([])
  })

  it("skips a tombstoned input (override_key === '')", () => {
    const canvas = makeCanvas(
      [{ id: "b", properties: { io_overrides: { inputs: [{ pin: "y", override_key: "" }] } } }],
      [],
      { b: { inputs: [{ pin: "y" }] } }
    )
    expect(new InputOutputValidationService(canvas).validate()).toEqual([])
  })

  it("lets an element's own raw output satisfy its own input (no input override)", () => {
    const canvas = makeCanvas(
      [{ id: "b", properties: {} }],
      [],
      { b: { inputs: [{ pin: "y" }], outputs: [{ pin: "y" }] } }
    )
    expect(new InputOutputValidationService(canvas).validate()).toEqual([])
  })

  it("skips inputs whose effective key is an implicit key", () => {
    const canvas = makeCanvas(
      [{ id: "b", properties: {} }],
      [],
      { b: { inputs: [{ pin: "ctx.now" }] } }
    )
    const svc = new InputOutputValidationService(canvas)
    svc.implicitKeys = new Set(["ctx.now"])
    expect(svc.validate()).toEqual([])
  })

  it("lets an element's own renamed output satisfy its own overridden input", () => {
    const canvas = makeCanvas(
      [{ id: "b", properties: {
        io_overrides: { outputs: [{ pin: "y", renamed_to: "z" }], inputs: [{ pin: "in1", override_key: "z" }] }
      } }],
      [],
      { b: { inputs: [{ pin: "in1" }], outputs: [{ pin: "y" }] } }
    )
    expect(new InputOutputValidationService(canvas).validate()).toEqual([])
  })

  it("_validateElementInputs falls back to an empty own-output set when the element is absent from the map", () => {
    // Direct call with an elementOutputs map that was never primed for "b" —
    // exercises the `elementOutputs.get(element.id) || new Set()` fallback,
    // which validate()'s own _collectElementOutputs never leaves unprimed.
    const canvas = makeCanvas([{ id: "b", properties: {} }], [], { b: { inputs: [{ pin: "y" }] } })
    const svc = new InputOutputValidationService(canvas)
    const reachability = { predecessors: () => [] }
    const errors = svc._validateElementInputs(canvas.elements[0], reachability, new Map())
    expect(errors).toHaveLength(1)
    expect(errors[0].meta).toEqual({ pinKey: "y" })
  })
})

describe("InputOutputValidationService — implicit keys loading", () => {
  beforeEach(() => {
    resetCache()
    applyFlowchartUrls({
      implicitKeys: "/12345678/admin/maintenance/flowcharts/validation/implicit_keys.json",
    })
  })
  afterEach(() => { clearFlowchartUrls(); vi.restoreAllMocks(); resetCache() })

  it("fetches implicit keys from urls.implicitKeys and caches them", async () => {
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ implicit_keys: ["ctx.a", "ctx.b"] }) })
    vi.stubGlobal("fetch", fetchMock)

    const svc = new InputOutputValidationService(makeCanvas([], [], {}))
    await svc.loadImplicitKeys()
    expect([...svc.implicitKeys]).toEqual(["ctx.a", "ctx.b"])
    expect(fetchMock).toHaveBeenCalledWith("/12345678/admin/maintenance/flowcharts/validation/implicit_keys.json")

    // Second instance reuses the static cache (no second fetch).
    const svc2 = new InputOutputValidationService(makeCanvas([], [], {}))
    await svc2.loadImplicitKeys()
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect([...svc2.implicitKeys]).toEqual(["ctx.a", "ctx.b"])
  })

  it("a second concurrent call awaits the in-flight fetch instead of starting a new one", async () => {
    let resolveFetch
    const fetchMock = vi.fn(() => new Promise((resolve) => { resolveFetch = resolve }))
    vi.stubGlobal("fetch", fetchMock)

    const svc1 = new InputOutputValidationService(makeCanvas([], [], {}))
    const svc2 = new InputOutputValidationService(makeCanvas([], [], {}))
    const p1 = svc1.loadImplicitKeys()
    const p2 = svc2.loadImplicitKeys() // starts while svc1's fetch is still pending

    resolveFetch({ ok: true, json: async () => ({ implicit_keys: ["ctx.a"] }) })
    await Promise.all([p1, p2])

    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect([...svc1.implicitKeys]).toEqual(["ctx.a"])
    expect([...svc2.implicitKeys]).toEqual(["ctx.a"])
  })

  it("caches an empty array when the server response omits implicit_keys", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({}) }))
    const svc = new InputOutputValidationService(makeCanvas([], [], {}))
    await svc.loadImplicitKeys()
    expect(svc.implicitKeys.size).toBe(0)
  })

  it("does not cache when implicitKeys is not configured so a later URL can fetch", async () => {
    applyFlowchartUrls({})
    const skipped = vi.fn()
    vi.stubGlobal("fetch", skipped)
    const svc = new InputOutputValidationService(makeCanvas([], [], {}))
    await svc.loadImplicitKeys()
    expect(svc.implicitKeys.size).toBe(0)
    expect(skipped).not.toHaveBeenCalled()
    expect(InputOutputValidationService._implicitKeysCache).toBeNull()

    applyFlowchartUrls({
      implicitKeys: "/12345678/admin/maintenance/flowcharts/validation/implicit_keys.json",
    })
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ implicit_keys: ["ctx.now"] }) })
    vi.stubGlobal("fetch", fetchMock)
    const svc2 = new InputOutputValidationService(makeCanvas([], [], {}))
    await svc2.loadImplicitKeys()
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect([...svc2.implicitKeys]).toEqual(["ctx.now"])
  })

  it("concurrent callers do not cache when the implicitKeys URL is unavailable", async () => {
    applyFlowchartUrls({})
    const fetchMock = vi.fn()
    vi.stubGlobal("fetch", fetchMock)
    const svc1 = new InputOutputValidationService(makeCanvas([], [], {}))
    const svc2 = new InputOutputValidationService(makeCanvas([], [], {}))
    await Promise.all([svc1.loadImplicitKeys(), svc2.loadImplicitKeys()])
    expect(svc1.implicitKeys.size).toBe(0)
    expect(svc2.implicitKeys.size).toBe(0)
    expect(fetchMock).not.toHaveBeenCalled()
    expect(InputOutputValidationService._implicitKeysCache).toBeNull()
  })

  it("falls back to an empty set on a non-ok response", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false }))
    const svc = new InputOutputValidationService(makeCanvas([], [], {}))
    await svc.loadImplicitKeys()
    expect(svc.implicitKeys.size).toBe(0)
  })

  it("swallows a fetch rejection and warns", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {})
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("boom")))
    const svc = new InputOutputValidationService(makeCanvas([], [], {}))
    await svc.loadImplicitKeys()
    expect(svc.implicitKeys.size).toBe(0)
    expect(warn).toHaveBeenCalled()
  })
})

describe("P5-6 InputOutputValidationService — raw keys in messages", () => {
  beforeEach(resetCache)
  afterEach(resetCache)

  it("puts the raw key into the message (the Problems panel escapes once at insertion)", () => {
    const key = 'a&b<c>"$&'
    const canvas = makeCanvas([{ id: "b", properties: {} }], [], { b: { inputs: [{ pin: key }] } })
    const [error] = new InputOutputValidationService(canvas).validate()
    expect(error.message).toBe(`Input "${key}" has no upstream output`)
    expect(InputOutputValidationService.prototype._safe).toBeUndefined()
  })
})
