import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { primeAllStepPins } from "controllers/property_editor/step_io/io_params_client"
import { applyFlowchartUrls, clearFlowchartUrls } from "../../../support/flowchart_urls.js"

// Minimal canvas whose iterateStepActions replays a fixed list of steps.
const makeCanvas = (steps) => {
  const stored = {}
  return {
    stored,
    findStepById(id) { const step = steps.find(step => step.id === id); return step && { step } },
    iterateStepActions(cb) { steps.forEach(cb) },
    setStepPins(id, pins) { stored[id] = pins },
  }
}

describe("step_io/io_params_client — primeAllStepPins", () => {
  beforeEach(() => {
    applyFlowchartUrls({
      stepIoParams: "/12345678/admin/maintenance/flowcharts/step_actions/__ACTION__/io_params",
    })
    document.head.innerHTML = `<meta name="csrf-token" content="tok123">`
  })
  afterEach(() => {
    clearFlowchartUrls()
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
  })

  it("POSTs to the tenant flowchart io_params endpoint per step and stores pins", async () => {
    const json = { inputs: [{ pin: "a" }], outputs: [{ pin: "b" }] }
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => json })
    vi.stubGlobal("fetch", fetchMock)

    const canvas = makeCanvas([
      { id: "s1", action: "create_model", config: { klass: "User" } },
      { id: "s2", action: "send_email", config: {} },
    ])
    await primeAllStepPins(canvas)

    expect(Object.keys(canvas.stored).sort()).toEqual(["s1", "s2"])
    expect(canvas.stored.s1).toEqual(json)

    const [url, opts] = fetchMock.mock.calls[0]
    expect(url).toBe("/12345678/admin/maintenance/flowcharts/step_actions/create_model/io_params")
    expect(opts.method).toBe("POST")
    expect(opts.headers["X-CSRF-Token"]).toBe("tok123")
    expect(JSON.parse(opts.body)).toEqual({ config: { klass: "User" } })
  })

  it("skips steps with no action (never fetches or stores them)", async () => {
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ inputs: [], outputs: [] }) })
    vi.stubGlobal("fetch", fetchMock)

    const canvas = makeCanvas([
      { id: "s1", action: "", config: {} },
      { id: "s2", action: null },
      { id: "s3", action: "do_thing", config: {} },
    ])
    await primeAllStepPins(canvas)

    expect(fetchMock).toHaveBeenCalledOnce()
    expect(Object.keys(canvas.stored)).toEqual(["s3"])
  })

  it("URL-encodes the action name", async () => {
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => ({}) })
    vi.stubGlobal("fetch", fetchMock)
    await primeAllStepPins(makeCanvas([{ id: "s1", action: "a/b" }]))
    expect(fetchMock.mock.calls[0][0]).toBe("/12345678/admin/maintenance/flowcharts/step_actions/a%2Fb/io_params")
  })

  it("stores empty pins on a non-ok response", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false }))
    const canvas = makeCanvas([{ id: "s1", action: "x" }])
    await primeAllStepPins(canvas)
    expect(canvas.stored.s1).toEqual({ inputs: [], outputs: [] })
  })

  it("swallows network errors, warns, and stores empty pins", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {})
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("boom")))
    const canvas = makeCanvas([{ id: "s1", action: "x" }])
    await primeAllStepPins(canvas)
    expect(canvas.stored.s1).toEqual({ inputs: [], outputs: [] })
    expect(warn).toHaveBeenCalled()
  })

  it("sends an empty CSRF token when the meta tag is absent", async () => {
    document.head.innerHTML = ""
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => ({}) })
    vi.stubGlobal("fetch", fetchMock)
    await primeAllStepPins(makeCanvas([{ id: "s1", action: "x", config: {} }]))
    expect(fetchMock.mock.calls[0][1].headers["X-CSRF-Token"]).toBe("")
  })

  it("stores empty pins (no fetch) when stepIoParams is not configured", async () => {
    applyFlowchartUrls({})
    const fetchMock = vi.fn()
    vi.stubGlobal("fetch", fetchMock)
    const canvas = makeCanvas([{ id: "s1", action: "x" }])
    await primeAllStepPins(canvas)
    expect(fetchMock).not.toHaveBeenCalled()
    expect(canvas.stored.s1).toEqual({ inputs: [], outputs: [] })
  })
})
