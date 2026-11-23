import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import {
  fetchReferenceOptions,
  filterReferenceOptions,
  referenceOptionsUrl,
  resetReferenceCache,
} from "controllers/property_editor/controls/reference_options"

describe("filterReferenceOptions", () => {
  const options = [
    { value: "t1", label: "Welcome" },
    { value: "t2", label: "Receipt" },
  ]

  it("returns all options when the query is blank", () => {
    expect(filterReferenceOptions(options, "")).toEqual(options)
    expect(filterReferenceOptions(options, "  ")).toEqual(options)
  })

  it("matches label or value case-insensitively", () => {
    expect(filterReferenceOptions(options, "come")).toEqual([options[0]])
    expect(filterReferenceOptions(options, "T2")).toEqual([options[1]])
    expect(filterReferenceOptions([{ value: 9 }], "9")).toEqual([{ value: 9 }])
    expect(filterReferenceOptions([{ label: "Hello" }], "hel")).toEqual([{ label: "Hello" }])
    expect(filterReferenceOptions([{ label: "Hello" }], "zzz")).toEqual([])
  })
})

describe("referenceOptionsUrl / fetchReferenceOptions", () => {
  beforeEach(() => {
    resetReferenceCache()
    document.body.innerHTML = ""
    vi.unstubAllGlobals()
  })
  afterEach(() => {
    resetReferenceCache()
    vi.unstubAllGlobals()
    document.body.innerHTML = ""
  })

  it("returns null without a source or canvas urls", () => {
    expect(referenceOptionsUrl("")).toBeNull()
    expect(referenceOptionsUrl("entities")).toBeNull()
  })

  it("builds the A6 url from the canvas urls value", () => {
    document.body.innerHTML = `<div data-controller="flowchart-canvas"
      data-flowchart-canvas-urls-value='{"referenceOptions":"/c/admin/maintenance/flowcharts/reference_options/__SOURCE__.json"}'></div>`
    expect(referenceOptionsUrl("email_templates"))
      .toBe("/c/admin/maintenance/flowcharts/reference_options/email_templates.json")
  })

  it("returns a cached miss when no url can be resolved", async () => {
    const first = await fetchReferenceOptions("entities")
    const second = await fetchReferenceOptions("entities")
    expect(first).toEqual({ ok: false, options: [] })
    expect(second).toBe(first)
  })

  it("fetches once per source with CSRF/JSON headers and caches the hit", async () => {
    document.body.innerHTML = `
      <meta name="csrf-token" content="tok">
      <div data-controller="flowchart-canvas"
           data-flowchart-canvas-urls-value='{"referenceOptions":"/ref/__SOURCE__.json"}'></div>`
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ options: [{ value: "1", label: "One" }] }),
    })
    vi.stubGlobal("fetch", fetchMock)

    const first = await fetchReferenceOptions("entities")
    const second = await fetchReferenceOptions("entities")
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(fetchMock).toHaveBeenCalledWith("/ref/entities.json", {
      headers: { Accept: "application/json", "X-CSRF-Token": "tok" },
    })
    expect(first).toEqual({ ok: true, options: [{ value: "1", label: "One" }] })
    expect(second).toBe(first)
  })

  it("caches an empty list when the payload has no options array", async () => {
    document.body.innerHTML = `<div data-controller="flowchart-canvas"
      data-flowchart-canvas-urls-value='{"referenceOptions":"/ref/__SOURCE__.json"}'></div>`
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({}) }))
    expect(await fetchReferenceOptions("pages")).toEqual({ ok: true, options: [] })
  })

  it("caches a failure on a non-ok response or a thrown fetch", async () => {
    document.body.innerHTML = `<div data-controller="flowchart-canvas"
      data-flowchart-canvas-urls-value='{"referenceOptions":"/ref/__SOURCE__.json"}'></div>`
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false }))
    expect(await fetchReferenceOptions("a")).toEqual({ ok: false, options: [] })

    resetReferenceCache()
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("net")))
    expect(await fetchReferenceOptions("b")).toEqual({ ok: false, options: [] })
  })
})
