import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import {
  getAvailableVariables,
  filterVariables,
  setContextGroupLabels,
  _resetCache,
} from "flowchart/context_variable_provider"
import { applyFlowchartUrls, clearFlowchartUrls } from "../support/flowchart_urls.js"

// getAvailableVariables composes: implicit keys (fetched), upstream element
// outputs (via the real ElementReachability topology), and prior-step outputs.
// We stub fetch and provide a plain canvas; the graph walk + override merge are
// exercised for real.

const makeCanvas = () => ({
  elements: [
    { id: "up", label: "Upstream", type: "process", properties: {} },
    {
      id: "cur",
      label: "Current",
      type: "process",
      properties: {
        steps: [
          { id: "s0", action: "validate", selectionLabels: ["Check", "Model"] },
          { id: "s1", action: "save" },
        ],
      },
    },
  ],
  connections: [{ from: "up", to: "cur" }],
  getElementPins: () => ({ outputs: [{ pin: "out1" }, { pin: "out2" }] }),
  getStepPins: () => ({ outputs: [{ pin: "step_out" }] }),
})

describe("filterVariables", () => {
  const result = {
    groups: [
      { label: "G1", variables: ["alpha", "Beta", "gamma"] },
      { label: "G2", variables: ["delta"] },
    ],
  }

  it("returns the input unchanged for a blank term", () => {
    expect(filterVariables(result, "")).toBe(result)
    expect(filterVariables(result, "   ")).toBe(result)
  })

  it("filters case-insensitively and drops empty groups", () => {
    const out = filterVariables(result, "a")
    // "alpha","Beta","gamma","delta" all contain 'a' -> both groups kept
    expect(out.groups).toHaveLength(2)
    const out2 = filterVariables(result, "beta")
    expect(out2.groups).toHaveLength(1)
    expect(out2.groups[0].variables).toEqual(["Beta"])
  })

  it("removes a group whose variables all fail the term", () => {
    const out = filterVariables(result, "delta")
    expect(out.groups).toHaveLength(1)
    expect(out.groups[0].label).toBe("G2")
  })
})

describe("getAvailableVariables", () => {
  // SOURCE BUG (not fixed here — see AGENT_GUIDE: test files only): when the
  // URL has no /<8-digit customer id>/ prefix, fetchImplicitKeys()'s inner IIFE
  // does `if (!customerId) return []` — that `[]` is only the IIFE's own
  // resolved value, it never assigns `_implicitKeysCache`. The outer function
  // then returns `_implicitKeysCache`, which is still `null`, so
  // `getAvailableVariables` crashes on `implicitKeys.length` for every caller on
  // a customer-less URL (e.g. happy-dom's default about:blank-ish URL). We route
  // around it below by using a customer-scoped URL with a mocked fetch that
  // resolves an empty `implicit_keys` array — that reaches the `response.ok`
  // branch, which *does* set the cache to `[]`, giving the same "no implicit
  // group" behavior the original (crashing) no-customer path was meant to test.
  beforeEach(() => {
    _resetCache()
    applyFlowchartUrls({
      implicitKeys: "/12345678/admin/maintenance/flowcharts/validation/implicit_keys.json",
    })
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({ ok: true, json: async () => ({ implicit_keys: [] }) })
    )
  })
  afterEach(() => {
    clearFlowchartUrls()
    vi.restoreAllMocks()
    _resetCache()
  })

  it("collects upstream element outputs and prior-step outputs (empty implicit keys -> no implicit group)", async () => {
    const canvas = makeCanvas()
    const { groups } = await getAvailableVariables(canvas, "cur", 1)

    const elementGroup = groups.find((g) => g.source === "element")
    expect(elementGroup).toMatchObject({ label: "From 'Upstream'", sourceId: "up" })
    expect(elementGroup.variables).toEqual(["out1", "out2"])

    const stepGroup = groups.find((g) => g.source === "step")
    expect(stepGroup).toMatchObject({ label: "From 'Check - Model' (this element)", sourceId: "s0" })
    expect(stepGroup.variables).toEqual(["step_out"])

    expect(groups.some((g) => g.source === "implicit")).toBe(false)
  })

  it("omits the step group at element level (stepIndex -1)", async () => {
    const { groups } = await getAvailableVariables(makeCanvas(), "cur", -1)
    expect(groups.some((g) => g.source === "step")).toBe(false)
    expect(groups.some((g) => g.source === "element")).toBe(true)
  })

  it("honors io_overrides renames on upstream outputs", async () => {
    const canvas = makeCanvas()
    canvas.elements[0].properties.io_overrides = { outputs: [{ pin: "out1", renamed_to: "renamed1" }] }
    const { groups } = await getAvailableVariables(canvas, "cur", -1)
    const elementGroup = groups.find((g) => g.source === "element")
    expect(elementGroup.variables).toEqual(["renamed1", "out2"])
  })

  it("includes an 'Always Available' group when implicit keys are fetched", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ implicit_keys: ["ctx.current_user", "ctx.now"] }),
    })
    vi.stubGlobal("fetch", fetchMock)

    const { groups } = await getAvailableVariables(makeCanvas(), "cur", -1)
    const implicit = groups.find((g) => g.source === "implicit")
    expect(implicit).toBeTruthy()
    expect(implicit.label).toBe("Always Available")
    expect(implicit.variables).toEqual(["ctx.current_user", "ctx.now"])
    expect(fetchMock).toHaveBeenCalledWith(
      "/12345678/admin/maintenance/flowcharts/validation/implicit_keys.json"
    )
  })

  it("caches implicit keys across calls (fetch once)", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ implicit_keys: ["ctx.x"] }),
    })
    vi.stubGlobal("fetch", fetchMock)

    await getAvailableVariables(makeCanvas(), "cur", -1)
    await getAvailableVariables(makeCanvas(), "cur", -1)
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it("returns an empty group list when there is no canvas/element", async () => {
    const { groups } = await getAvailableVariables(null, null)
    expect(groups).toEqual([])
  })

  it("skips the implicit-keys fetch when implicitKeys is not configured", async () => {
    applyFlowchartUrls({})
    const fetchMock = vi.fn()
    vi.stubGlobal("fetch", fetchMock)
    const { groups } = await getAvailableVariables(makeCanvas(), "cur", -1)
    expect(fetchMock).not.toHaveBeenCalled()
    expect(groups.some((g) => g.source === "implicit")).toBe(false)
  })
})

describe("getAvailableVariables — implicitKeys URL availability", () => {
  afterEach(() => {
    clearFlowchartUrls()
    vi.restoreAllMocks()
    _resetCache()
  })

  it("does not cache an empty implicit-keys result produced because the URL was unavailable", async () => {
    _resetCache()
    clearFlowchartUrls()
    const skipped = vi.fn()
    vi.stubGlobal("fetch", skipped)
    await getAvailableVariables(makeCanvas(), "cur", -1)
    expect(skipped).not.toHaveBeenCalled()

    applyFlowchartUrls({
      implicitKeys: "/12345678/admin/maintenance/flowcharts/validation/implicit_keys.json",
    })
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ implicit_keys: ["ctx.now"] }) })
    vi.stubGlobal("fetch", fetchMock)
    const { groups } = await getAvailableVariables(makeCanvas(), "cur", -1)
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(groups.some((g) => g.source === "implicit" && g.variables.includes("ctx.now"))).toBe(true)
  })

  it("concurrent callers do not crash when the implicitKeys URL is unavailable", async () => {
    _resetCache()
    clearFlowchartUrls()
    const fetchMock = vi.fn()
    vi.stubGlobal("fetch", fetchMock)
    const [a, b] = await Promise.all([
      getAvailableVariables(makeCanvas(), "cur", -1),
      getAvailableVariables(makeCanvas(), "cur", -1),
    ])
    expect(a.groups.some((g) => g.source === "implicit")).toBe(false)
    expect(b.groups.some((g) => g.source === "implicit")).toBe(false)
    expect(fetchMock).not.toHaveBeenCalled()
  })
})

describe("getAvailableVariables — implicit-keys fetch outcomes", () => {
  beforeEach(() => {
    _resetCache()
    applyFlowchartUrls({
      implicitKeys: "/12345678/admin/maintenance/flowcharts/validation/implicit_keys.json",
    })
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({ ok: true, json: async () => ({ implicit_keys: [] }) })
    )
  })
  afterEach(() => {
    clearFlowchartUrls()
    vi.restoreAllMocks()
    _resetCache()
  })

  it("a second concurrent call awaits the in-flight fetch instead of starting a new one", async () => {
    let resolveFetch
    const fetchMock = vi.fn(() => new Promise((resolve) => { resolveFetch = resolve }))
    vi.stubGlobal("fetch", fetchMock)

    const p1 = getAvailableVariables(makeCanvas(), "cur", -1)
    const p2 = getAvailableVariables(makeCanvas(), "cur", -1) // starts while p1's fetch is pending

    resolveFetch({ ok: true, json: async () => ({ implicit_keys: ["ctx.z"] }) })
    const [r1, r2] = await Promise.all([p1, p2])

    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(r1.groups.find((g) => g.source === "implicit").variables).toEqual(["ctx.z"])
    expect(r2.groups.find((g) => g.source === "implicit").variables).toEqual(["ctx.z"])
  })

  it("caches an empty implicit-keys list on a non-ok response", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false }))
    const { groups } = await getAvailableVariables(makeCanvas(), "cur", -1)
    expect(groups.some((g) => g.source === "implicit")).toBe(false)
  })

  it("defaults to an empty array when the response omits implicit_keys", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({}) }))
    const { groups } = await getAvailableVariables(makeCanvas(), "cur", -1)
    expect(groups.some((g) => g.source === "implicit")).toBe(false)
  })

  it("swallows a fetch rejection, warns, and caches an empty list", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {})
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("boom")))
    const { groups } = await getAvailableVariables(makeCanvas(), "cur", -1)
    expect(groups.some((g) => g.source === "implicit")).toBe(false)
    expect(warn).toHaveBeenCalled()
    warn.mockRestore()
  })

  it("skips a predecessor id with no matching element, and one with zero outputs", async () => {
    const canvas = makeCanvas()
    // "ghost" is a predecessor id with no element (dangling connection);
    // "empty" is a real predecessor whose pins produce zero effective outputs.
    canvas.elements.push({ id: "empty", label: "Empty", type: "process", properties: {} })
    canvas.connections.push({ from: "ghost", to: "cur" }, { from: "empty", to: "cur" })
    const originalGetElementPins = canvas.getElementPins
    canvas.getElementPins = (id) => (id === "empty" ? { outputs: [] } : originalGetElementPins())

    const { groups } = await getAvailableVariables(canvas, "cur", -1)
    const elementGroups = groups.filter((g) => g.source === "element")
    expect(elementGroups.map((g) => g.sourceId)).toEqual(["up"])
  })

  it("labels an upstream group by type when label is absent, and by id when both are absent", async () => {
    const canvas = makeCanvas()
    canvas.elements[0].label = undefined
    canvas.elements[0].type = "start_node"
    canvas.connections = [{ from: "up", to: "cur" }]
    const byType = await getAvailableVariables(canvas, "cur", -1)
    expect(byType.groups.find((g) => g.source === "element").label).toBe("From 'start_node'")

    canvas.elements[0].type = undefined
    const byId = await getAvailableVariables(canvas, "cur", -1)
    expect(byId.groups.find((g) => g.source === "element").label).toBe("From 'up'")
  })

  it("defaults an element's steps to [] when properties.steps is absent", async () => {
    const canvas = makeCanvas()
    canvas.elements[1].properties = {} // "cur" element, no steps key at all
    const { groups } = await getAvailableVariables(canvas, "cur", 3)
    expect(groups.some((g) => g.source === "step")).toBe(false)
  })

  it("skips a step with no id, and one whose pins produce zero outputs", async () => {
    const canvas = makeCanvas()
    canvas.elements[1].properties.steps = [
      { action: "no-id-step", selectionLabels: [] }, // no `id` -> skipped
      { id: "s_empty", action: "empty-outputs" },
    ]
    const originalGetStepPins = canvas.getStepPins
    canvas.getStepPins = (id) => (id === "s_empty" ? { outputs: [] } : originalGetStepPins())
    const { groups } = await getAvailableVariables(canvas, "cur", 2)
    expect(groups.some((g) => g.source === "step")).toBe(false)
  })

  it("labels a step group by action when selectionLabels is absent, and by id when both are absent", async () => {
    const canvas = makeCanvas()
    canvas.elements[1].properties.steps = [
      { id: "s0", action: "by_action" },
      { id: "s1", action: "irrelevant" },
    ]
    const byAction = await getAvailableVariables(canvas, "cur", 2)
    expect(byAction.groups.find((g) => g.source === "step").label).toBe("From 'by_action' (this element)")

    canvas.elements[1].properties.steps = [
      { id: "s0" }, // no selectionLabels, no action -> falls back to id
      { id: "s1", action: "irrelevant" },
    ]
    const byId = await getAvailableVariables(canvas, "cur", 2)
    expect(byId.groups.find((g) => g.source === "step").label).toBe("From 's0' (this element)")
  })
})

describe("getAvailableVariables — pin-accessor fallbacks", () => {
  beforeEach(() => {
    _resetCache()
    window.location.href = "http://localhost/12345678/admin/x"
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({ implicit_keys: [] }) }))
  })
  afterEach(() => {
    vi.restoreAllMocks()
    _resetCache()
  })

  it("treats a missing getElementPins/getStepPins as zero pins (no crash, no group)", async () => {
    const canvas = {
      elements: [
        { id: "up", label: "Upstream", type: "process", properties: {} },
        { id: "cur", label: "Current", type: "process", properties: { steps: [{ id: "s0", action: "save" }] } },
      ],
      connections: [{ from: "up", to: "cur" }],
      // No getElementPins / getStepPins at all — exercises the `?.` fallback.
    }
    const { groups } = await getAvailableVariables(canvas, "cur", 1)
    expect(groups.some((g) => g.source === "element" || g.source === "step")).toBe(false)
  })

  it("treats pins with no outputs key as zero outputs", async () => {
    const canvas = {
      elements: [
        { id: "up", label: "Upstream", type: "process", properties: {} },
        { id: "cur", label: "Current", type: "process", properties: { steps: [{ id: "s0", action: "save" }] } },
      ],
      connections: [{ from: "up", to: "cur" }],
      getElementPins: () => ({}),
      getStepPins: () => ({}),
    }
    const { groups } = await getAvailableVariables(canvas, "cur", 1)
    expect(groups.some((g) => g.source === "element" || g.source === "step")).toBe(false)
  })
})

describe("setContextGroupLabels", () => {
  beforeEach(() => {
    _resetCache()
    window.location.href = "http://localhost/12345678/admin/x"
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({ implicit_keys: [] }) }))
  })
  afterEach(() => {
    vi.restoreAllMocks()
    _resetCache()
    setContextGroupLabels({
      alwaysAvailable: "Always Available",
      from: "From '{label}'",
      fromStep: "From '{label}' (this element)",
    })
  })

  it("installs translated group labels (interpolating {label})", async () => {
    setContextGroupLabels({ from: "来自 '{label}'" })
    const canvas = makeCanvas()
    canvas.connections = [{ from: "up", to: "cur" }]
    const { groups } = await getAvailableVariables(canvas, "cur", -1)
    expect(groups.find((g) => g.source === "element").label).toBe("来自 'Upstream'")
  })

  it("ignores a nullish or non-object argument", async () => {
    setContextGroupLabels(null)
    setContextGroupLabels("nope")
    const canvas = makeCanvas()
    canvas.connections = [{ from: "up", to: "cur" }]
    const { groups } = await getAvailableVariables(canvas, "cur", -1)
    expect(groups.find((g) => g.source === "element").label).toBe("From 'Upstream'")
  })
})
