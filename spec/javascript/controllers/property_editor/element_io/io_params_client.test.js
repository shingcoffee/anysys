import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import {
  fetchElementPins,
  primeAllElementPins,
  refreshElementPins,
  subscribeElementPins,
} from "controllers/property_editor/element_io/io_params_client"
import { applyFlowchartUrls, clearFlowchartUrls } from "../../../support/flowchart_urls.js"

describe("io_params_client", () => {
  beforeEach(() => {
    applyFlowchartUrls({
      elementIoParams: "/12345678/admin/maintenance/flowcharts/element_types/__TYPE__/io_params",
    })
    document.head.innerHTML = `<meta name="csrf-token" content="tok123">`
  })
  afterEach(() => {
    clearFlowchartUrls()
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
  })

  describe("fetchElementPins", () => {
    it("returns empty pins when no element type is given", async () => {
      expect(await fetchElementPins("")).toEqual({ inputs: [], outputs: [] })
    })

    it("returns empty pins when elementIoParams is not configured", async () => {
      applyFlowchartUrls({})
      expect(await fetchElementPins("process", {})).toEqual({ inputs: [], outputs: [] })
    })

    it("POSTs to the io_params endpoint with CSRF + properties and returns JSON", async () => {
      const json = { inputs: [{ pin: "model" }], outputs: [{ pin: "user" }] }
      const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => json })
      vi.stubGlobal("fetch", fetchMock)

      const result = await fetchElementPins("process", { foo: "bar" })
      expect(result).toEqual(json)

      const [url, opts] = fetchMock.mock.calls[0]
      expect(url).toBe("/12345678/admin/maintenance/flowcharts/element_types/process/io_params")
      expect(opts.method).toBe("POST")
      expect(opts.headers["X-CSRF-Token"]).toBe("tok123")
      expect(JSON.parse(opts.body)).toEqual({ properties: { foo: "bar" } })
    })

    it("returns empty pins on a non-ok response", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false }))
      expect(await fetchElementPins("process", {})).toEqual({ inputs: [], outputs: [] })
    })

    it("swallows network errors and warns", async () => {
      const warn = vi.spyOn(console, "warn").mockImplementation(() => {})
      vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("boom")))
      expect(await fetchElementPins("process", {})).toEqual({ inputs: [], outputs: [] })
      expect(warn).toHaveBeenCalled()
    })

    it("encodes the element type in the URL", async () => {
      const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => ({}) })
      vi.stubGlobal("fetch", fetchMock)
      await fetchElementPins("a/b", {})
      expect(fetchMock.mock.calls[0][0]).toContain("element_types/a%2Fb/")
    })

    it("sends an empty CSRF token when the meta tag is absent", async () => {
      document.head.innerHTML = ""
      const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => ({}) })
      vi.stubGlobal("fetch", fetchMock)
      await fetchElementPins("process", {})
      expect(fetchMock.mock.calls[0][1].headers["X-CSRF-Token"]).toBe("")
    })

    it("defaults properties to {} when omitted", async () => {
      const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => ({}) })
      vi.stubGlobal("fetch", fetchMock)
      await fetchElementPins("process")
      expect(JSON.parse(fetchMock.mock.calls[0][1].body)).toEqual({ properties: {} })
    })
  })

  describe("primeAllElementPins", () => {
    it("fetches pins for every canvas element and stores them", async () => {
      const json = { inputs: [], outputs: [{ pin: "x" }] }
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => json }))
      const stored = {}
      const canvas = {
        elements: [{ id: "1", type: "process", properties: {} }, { id: "2", type: "decision", properties: {} }],
        iterateElements(cb) {
          cb({ id: "1", type: "process", properties: {} })
          cb({ id: "2", type: "decision", properties: {} })
          cb(null) // skipped
          cb({ id: "3" }) // no type -> skipped
        },
        setElementPins(id, pins) {
          stored[id] = pins
        },
      }
      await primeAllElementPins(canvas)
      expect(Object.keys(stored).sort()).toEqual(["1", "2"])
      expect(stored["1"]).toEqual(json)
    })

    it("defaults properties to {} for an element with no properties field", async () => {
      const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => ({}) })
      vi.stubGlobal("fetch", fetchMock)
      const canvas = {
        elements: [{ id: "1", type: "process" }],
        iterateElements(cb) {
          cb({ id: "1", type: "process" })
        },
        setElementPins: vi.fn(),
      }
      await primeAllElementPins(canvas)
      expect(JSON.parse(fetchMock.mock.calls[0][1].body)).toEqual({ properties: {} })
    })
  })

  describe("refreshElementPins", () => {
    it("re-fetches pins for a single element by id", async () => {
      const json = { inputs: [{ pin: "in" }], outputs: [] }
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => json }))
      const setElementPins = vi.fn()
      const canvas = {
        elements: [{ id: "e1", type: "process", properties: {} }],
        setElementPins,
      }
      await refreshElementPins(canvas, "e1")
      expect(setElementPins).toHaveBeenCalledWith("e1", json)
    })

    it("no-ops when the element id is unknown", async () => {
      const setElementPins = vi.fn()
      await refreshElementPins({ elements: [], setElementPins }, "ghost")
      expect(setElementPins).not.toHaveBeenCalled()
    })

    it("defaults canvas.elements to [] when absent (no-op, no throw)", async () => {
      const setElementPins = vi.fn()
      await refreshElementPins({ setElementPins }, "e1")
      expect(setElementPins).not.toHaveBeenCalled()
    })

    it("defaults properties to {} for an element with no properties field", async () => {
      const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => ({}) })
      vi.stubGlobal("fetch", fetchMock)
      const canvas = { elements: [{ id: "e1", type: "process" }], setElementPins: vi.fn() }
      await refreshElementPins(canvas, "e1")
      expect(JSON.parse(fetchMock.mock.calls[0][1].body)).toEqual({ properties: {} })
    })
  })

  describe("subscribeElementPins", () => {
    it("subscribes the listener on the element pin channel", () => {
      const listener = vi.fn()
      const canvas = { _pinListeners: new Map() }
      const unsubscribe = subscribeElementPins(canvas, "e1", listener)
      expect(typeof unsubscribe).toBe("function")
    })
  })
})
