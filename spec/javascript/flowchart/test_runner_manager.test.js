import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { TestRunnerManager } from "flowchart/test_runner_manager"
import { I18N_VALUE_DEFAULTS } from "../support/flowchart.js"

// TestRunnerManager is orchestration/logic over a Stimulus controller: JSON
// validation + Run gating, localStorage persistence, in-memory history, and
// HTML result rendering. All fully unit-testable in happy-dom with a fake
// controller whose targets are real DOM nodes and a stubbed fetch/save.

function makeController(over = {}) {
  const mk = (tag = "div") => document.createElement(tag)
  const testInput = mk("textarea")
  const testInputError = mk()
  const testRunButton = mk("button")
  const testStatus = mk("span")
  const testHistory = mk()
  const testOutput = mk()

  const canvas = {
    clearTraceOverlay: vi.fn(),
    showTraceOverlay: vi.fn(),
    elements: over.elements || [],
  }

  return {
    ...I18N_VALUE_DEFAULTS,
    idValue: "42",
    customerIdValue: "99",
    readOnlyValue: false,
    canvas,
    save: vi.fn().mockResolvedValue(true),
    _buildSaveConfiguration: vi.fn(() => ({ elements: [{ id: "folded" }], connections: [] })),
    urlsValue: { traces: "/tenant/flowcharts/42/traces" },

    hasTestInputTarget: true, testInputTarget: testInput,
    hasTestInputErrorTarget: true, testInputErrorTarget: testInputError,
    hasTestRunButtonTarget: true, testRunButtonTarget: testRunButton,
    hasTestStatusTarget: true, testStatusTarget: testStatus,
    hasTestHistoryTarget: true, testHistoryTarget: testHistory,
    hasTestOutputTarget: true, testOutputTarget: testOutput,
    ...over,
  }
}

beforeEach(() => {
  document.body.innerHTML = ""
  localStorage.clear()
})
afterEach(() => {
  vi.unstubAllGlobals()
})

describe("validateInput", () => {
  it("accepts empty input and enables the Run button", () => {
    const c = makeController()
    const m = new TestRunnerManager(c)
    expect(m.validateInput()).toBe(true)
    expect(c.testRunButtonTarget.disabled).toBe(false)
    expect(c.testInputErrorTarget.classList.contains("hidden")).toBe(true)
  })

  it("accepts well-formed JSON", () => {
    const c = makeController()
    c.testInputTarget.value = '{"a":1}'
    expect(new TestRunnerManager(c).validateInput()).toBe(true)
  })

  it("flags malformed JSON, shows an error and disables Run", () => {
    const c = makeController()
    c.testInputTarget.value = "{bad"
    const m = new TestRunnerManager(c)
    expect(m.validateInput()).toBe(false)
    expect(c.testInputTarget.classList.contains("border-red-400")).toBe(true)
    expect(c.testInputErrorTarget.textContent).toMatch(/Invalid JSON/)
    expect(c.testInputErrorTarget.classList.contains("hidden")).toBe(false)
    expect(c.testRunButtonTarget.disabled).toBe(true)
  })

  it("returns true when there is no input target", () => {
    const c = makeController({ hasTestInputTarget: false })
    expect(new TestRunnerManager(c).validateInput()).toBe(true)
  })

  it("keeps Run disabled while a run is in flight even for valid input", () => {
    const c = makeController()
    const m = new TestRunnerManager(c)
    m.runInFlight = true
    m.validateInput()
    expect(c.testRunButtonTarget.disabled).toBe(true)
  })
})

describe("localStorage persistence", () => {
  it("_storageKey is namespaced per flowchart id", () => {
    const m = new TestRunnerManager(makeController({ idValue: "7" }))
    expect(m._storageKey()).toBe("flowchartTestInput:7")
  })

  it("restoreSavedInput reloads the last saved input", () => {
    const c = makeController()
    localStorage.setItem("flowchartTestInput:42", '{"saved":true}')
    new TestRunnerManager(c).restoreSavedInput()
    expect(c.testInputTarget.value).toBe('{"saved":true}')
  })

  it("restoreSavedInput leaves the field empty when nothing was saved", () => {
    const c = makeController()
    new TestRunnerManager(c).restoreSavedInput()
    expect(c.testInputTarget.value).toBe("")
  })

  it("restoreSavedInput is a no-op when there is no input target", () => {
    const c = makeController({ hasTestInputTarget: false })
    expect(() => new TestRunnerManager(c).restoreSavedInput()).not.toThrow()
  })

  it("restoreSavedInput swallows a storage read failure", () => {
    const c = makeController()
    const spy = vi.spyOn(localStorage, "getItem").mockImplementation(() => { throw new Error("blocked") })
    expect(() => new TestRunnerManager(c).restoreSavedInput()).not.toThrow()
    expect(c.testInputTarget.value).toBe("")
    spy.mockRestore()
  })
})

describe("history", () => {
  it("_pushHistory prepends newest-first and classifies status", () => {
    const m = new TestRunnerManager(makeController())
    m._pushHistory("{}", { success: true })
    m._pushHistory("{}", { success: false })
    m._pushHistory("{}", { timeout: true })
    expect(m.history.map(h => h.status)).toEqual(["timeout", "failure", "success"])
    expect(m.activeHistoryIndex).toBe(0)
  })

  it("caps history at 10 entries", () => {
    const m = new TestRunnerManager(makeController())
    for (let i = 0; i < 15; i++) m._pushHistory(`${i}`, { success: true })
    expect(m.history.length).toBe(10)
  })

  it("_renderHistory paints one pill group per entry", () => {
    const c = makeController()
    const m = new TestRunnerManager(c)
    m._pushHistory("{}", { success: true })
    m._pushHistory("{}", { success: false })
    const buttons = c.testHistoryTarget.querySelectorAll("[data-history-index]")
    // two buttons per entry (view + use input) → 4 for 2 entries
    expect(buttons.length).toBe(4)
    expect(c.testHistoryTarget.innerHTML).toContain("use input")
  })

  it("useHistoryInput copies a run's input back into the editor", () => {
    const c = makeController()
    const m = new TestRunnerManager(c)
    m.history = [{ input: '{"x":9}', data: {}, status: "success", at: new Date() }]
    m.useHistoryInput(0)
    expect(c.testInputTarget.value).toBe('{"x":9}')
  })

  it("useHistoryInput ignores an out-of-range index", () => {
    const c = makeController()
    const m = new TestRunnerManager(c)
    m.useHistoryInput(5)
    expect(c.testInputTarget.value).toBe("")
  })

  it("selectHistory re-displays a past run", () => {
    const c = makeController()
    const m = new TestRunnerManager(c)
    m.history = [{ input: "{}", data: { success: true }, status: "success", at: new Date() }]
    m.selectHistory(0)
    expect(m.activeHistoryIndex).toBe(0)
    expect(c.testOutputTarget.innerHTML).toContain("Execution succeeded")
  })

  it("selectHistory ignores an out-of-range index", () => {
    const c = makeController()
    const m = new TestRunnerManager(c)
    m.selectHistory(5)
    expect(m.activeHistoryIndex).toBe(-1)
    expect(c.testOutputTarget.innerHTML).toBe("")
  })

  it("_renderHistory is a no-op when there is no history target", () => {
    const c = makeController({ hasTestHistoryTarget: false })
    const m = new TestRunnerManager(c)
    expect(() => m._pushHistory("{}", { success: true })).not.toThrow()
  })

  it("_renderHistory falls back to a generic icon/color for an unrecognized status", () => {
    const c = makeController()
    const m = new TestRunnerManager(c)
    m.history = [{ input: "{}", data: {}, status: "weird", at: new Date() }]
    m._renderHistory()
    expect(c.testHistoryTarget.innerHTML).toContain("text-slate-500")
    expect(c.testHistoryTarget.innerHTML).toContain(">•<")
  })
})

describe("P5-6 locale-aware run time and query durations", () => {
  const at = new Date(2026, 9, 20, 14, 5, 9)

  it("formats the history pill time with the app locale", () => {
    for (const locale of ["en", "zh-CN"]) {
      const c = makeController({ appLocaleValue: locale })
      const m = new TestRunnerManager(c)
      m.history = [{ input: "{}", data: {}, status: "success", at }]
      m._renderHistory()
      const expected = new Intl.DateTimeFormat(locale, { timeStyle: "medium" }).format(at)
      expect(c.testHistoryTarget.querySelector("button").textContent).toContain(expected)
    }
  })

  it("renders each query duration through the {duration} format value", () => {
    const c = makeController({ testQueryDurationFormatValue: "{duration} 毫秒" })
    const html = new TestRunnerManager(c)._renderQueries({ queries: [{ sql: "SELECT 1", duration_ms: 2.2 }] })
    expect(html).toContain('<span class="text-slate-500">2.2 毫秒</span>')
    expect(html).not.toContain(" ms<")
  })
})

describe("render helpers", () => {
  const m = () => new TestRunnerManager(makeController())

  it("_renderBanner reflects timeout / success / failure", () => {
    expect(m()._renderBanner({ timeout: true })).toContain("Timed out after")
    expect(m()._renderBanner({ success: true })).toContain("Execution succeeded")
    const fail = m()._renderBanner({ success: false, error: "boom" })
    expect(fail).toContain("Execution failed")
    expect(fail).toContain("boom")
  })

  it("_renderBanner escapes error text (XSS safe)", () => {
    const html = m()._renderBanner({ success: false, error: "<script>x</script>" })
    expect(html).toContain("&lt;script&gt;")
    expect(html).not.toContain("<script>")
  })

  it("_renderBanner omits the ': <error>' suffix when there is no error message", () => {
    const html = m()._renderBanner({ success: false })
    expect(html).toContain("Execution failed")
    expect(html).not.toContain(":")
  })

  it("_renderBanner lists data.errors under the failure text", () => {
    const html = m()._renderBanner({ success: false, errors: ["pin missing", "guard rejected"] })
    expect(html).toContain("Execution failed")
    expect(html).toContain("pin missing")
    expect(html).toContain("guard rejected")
    expect(html).toMatch(/<li[^>]*>pin missing<\/li>/)
  })

  it("_renderBanner escapes each collected error", () => {
    const html = m()._renderBanner({ success: false, errors: ["<img onerror=x>"] })
    expect(html).toContain("&lt;img")
    expect(html).not.toContain("<img")
  })

  it("_renderBanner skips an empty or missing errors list", () => {
    expect(m()._renderBanner({ success: false, errors: [] })).not.toContain("<li")
    expect(m()._renderBanner({ success: false })).not.toContain("<li")
  })

  it("_renderBanner does not list errors on success or timeout", () => {
    expect(m()._renderBanner({ success: true, errors: ["nope"] })).not.toContain("nope")
    expect(m()._renderBanner({ timeout: true, errors: ["nope"] })).not.toContain("nope")
  })

  it("_renderSteps handles the no-steps cases", () => {
    expect(m()._renderSteps({ success: true, trace_nodes: [] })).toContain("without traced steps")
    expect(m()._renderSteps({ success: false, trace_nodes: [] })).toBe("")
  })

  it("_renderSteps marks only the FIRST failing step with data-trace-failing", () => {
    const c = makeController({ elements: [{ id: "n2" }] })
    const mgr = new TestRunnerManager(c)
    const html = mgr._renderSteps({
      trace_nodes: [
        { id: "n1", status: "success", label: "ok" },
        { id: "n2", status: "failure", label: "bad", element_id: "n2" },
        { id: "n3", status: "error", label: "worse" },
      ],
    })
    expect((html.match(/data-trace-failing/g) || []).length).toBe(1)
    // n2 is resolvable (its element exists) → gets the focus action
    expect(html).toContain("focusTraceStep")
  })

  it("_renderSteps uses a neutral icon for a node that is neither success nor failing", () => {
    const html = m()._renderSteps({ trace_nodes: [{ id: "n1", status: "pending", label: "waiting" }] })
    expect(html).toContain("◦")
  })

  it("_renderSteps omits the inline error line when a failing node has no top-level error", () => {
    const html = m()._renderSteps({ trace_nodes: [{ id: "n1", status: "failure", label: "bad" }] })
    expect(html).not.toContain("mt-0.5 text-xs text-red-700")
  })

  it("_renderSteps renders the inline error line when a failing node has a top-level error", () => {
    const html = m()._renderSteps({ error: "boom", trace_nodes: [{ id: "n1", status: "error", label: "bad" }] })
    expect(html).toContain("mt-0.5 text-xs text-red-700")
    expect(html).toContain("boom")
  })

  it("_renderSteps renders the captured ctx_snapshot when present", () => {
    const html = m()._renderSteps({ trace_nodes: [{ id: "n1", status: "success", label: "ok", ctx_snapshot: { x: 1 } }] })
    expect(html).not.toContain("context not captured")
    expect(html).toContain("&quot;x&quot;: 1")
  })

  it("_renderSteps falls back from label -> id -> a generic placeholder", () => {
    const byId = m()._renderSteps({ trace_nodes: [{ id: "step-9", status: "success" }] })
    expect(byId).toContain("step-9")

    const placeholder = m()._renderSteps({ trace_nodes: [{ status: "success" }] })
    expect(placeholder).toContain("(unnamed step)")
  })

  it("_renderSteps shows the taken branch with {step} and {branch} tokens", () => {
    const c = makeController({ testDecisionBranchFormatValue: "{step} → {branch}" })
    const html = new TestRunnerManager(c)._renderSteps({
      trace_nodes: [{ id: "d1", status: "success", label: "Is large?", branch: "yes" }],
    })
    expect(html).toContain("Is large? → yes")
  })

  it("_renderSteps escapes step and branch before interpolating the format", () => {
    const c = makeController({ testDecisionBranchFormatValue: "{step} → {branch}" })
    const html = new TestRunnerManager(c)._renderSteps({
      trace_nodes: [{ id: "d1", status: "success", label: "<b>Dec</b>", branch: "<i>yes</i>" }],
    })
    expect(html).toContain("&lt;b&gt;Dec&lt;/b&gt; → &lt;i&gt;yes&lt;/i&gt;")
    expect(html).not.toContain("<b>Dec</b>")
  })

  it("_renderSteps treats $& in a branch as literal text, not a replace pattern", () => {
    const c = makeController({ testDecisionBranchFormatValue: "{step} → {branch}" })
    const html = new TestRunnerManager(c)._renderSteps({
      trace_nodes: [{ id: "d1", status: "success", label: "Save", branch: "$&" }],
    })
    expect(html).toContain("Save → $&amp;")
    expect(html).not.toContain("Save → {branch}")
  })

  it("_renderSteps treats $` in a branch as literal text, not a replace pattern", () => {
    const c = makeController({ testDecisionBranchFormatValue: "{step} → {branch}" })
    const html = new TestRunnerManager(c)._renderSteps({
      trace_nodes: [{ id: "d1", status: "success", label: "Save", branch: "$`" }],
    })
    expect(html).toContain("Save → $`")
    expect(html).not.toContain("Save → {step}")
  })

  it("_renderSteps treats $& in a step label as literal text, not a replace pattern", () => {
    const c = makeController({ testDecisionBranchFormatValue: "{step} → {branch}" })
    const html = new TestRunnerManager(c)._renderSteps({
      trace_nodes: [{ id: "d1", status: "success", label: "foo$&bar", branch: "yes" }],
    })
    expect(html).toContain("foo$&amp;bar → yes")
    expect(html).not.toContain("foo{step}bar")
  })

  it("_renderSteps leaves a row without a branch unchanged", () => {
    const html = m()._renderSteps({
      trace_nodes: [{ id: "n1", status: "success", label: "Save" }],
    })
    expect(html).toContain("Save")
    expect(html).not.toContain("→")
  })

  it("_renderSteps treats an empty branch as absent", () => {
    const c = makeController({ testDecisionBranchFormatValue: "{step} → {branch}" })
    const html = new TestRunnerManager(c)._renderSteps({
      trace_nodes: [{ id: "n1", status: "success", label: "Save", branch: "" }],
    })
    expect(html).toContain("Save")
    expect(html).not.toContain("→")
  })

  it("_renderSteps shows a truncation notice when trace_truncated is true", () => {
    const c = makeController({
      testTraceTruncatedFormatValue: "Showing the first {count} steps; the run had more.",
    })
    const html = new TestRunnerManager(c)._renderSteps({
      success: true,
      trace_truncated: true,
      trace_nodes: [
        { id: "n1", status: "success", label: "a" },
        { id: "n2", status: "success", label: "b" },
      ],
    })
    expect(html).toContain("Showing the first 2 steps; the run had more.")
  })

  it("_renderSteps omits the truncation notice when the run was not truncated", () => {
    const html = m()._renderSteps({
      success: true,
      trace_nodes: [{ id: "n1", status: "success", label: "a" }],
    })
    expect(html).not.toContain("Showing the first")
  })

  it("_renderSteps omits the truncation notice when trace_truncated is false", () => {
    const html = m()._renderSteps({
      success: true,
      trace_truncated: false,
      trace_nodes: [{ id: "n1", status: "success", label: "a" }],
    })
    expect(html).not.toContain("Showing the first")
  })

  it("_renderSteps interpolates {count} with a function replacer so $& stays literal", () => {
    const c = makeController({
      testTraceTruncatedFormatValue: "first {count} of $& more",
    })
    const html = new TestRunnerManager(c)._renderSteps({
      trace_truncated: true,
      trace_nodes: [{ id: "n1", status: "success", label: "a" }],
    })
    expect(html).toContain("first 1 of $&amp; more")
    expect(html).not.toContain("first 1 of first")
  })

  it("_renderSteps escapes the interpolated truncation notice", () => {
    const c = makeController({
      testTraceTruncatedFormatValue: "<b>{count}</b>",
    })
    const html = new TestRunnerManager(c)._renderSteps({
      trace_truncated: true,
      trace_nodes: [{ id: "n1", status: "success" }],
    })
    expect(html).toContain("&lt;b&gt;1&lt;/b&gt;")
    expect(html).not.toContain("<b>1</b>")
  })

  it("_renderSteps still shows the truncation notice when there are no rows", () => {
    const c = makeController({
      testTraceTruncatedFormatValue: "Showing the first {count} steps; the run had more.",
    })
    const html = new TestRunnerManager(c)._renderSteps({
      success: true,
      trace_truncated: true,
      trace_nodes: [],
    })
    expect(html).toContain("Showing the first 0 steps; the run had more.")
    expect(html).toContain("without traced steps")
  })

  it("_renderSteps counts zero when truncated and trace_nodes is missing", () => {
    const c = makeController({
      testTraceTruncatedFormatValue: "Showing the first {count} steps; the run had more.",
    })
    const html = new TestRunnerManager(c)._renderSteps({
      success: false,
      trace_truncated: true,
    })
    expect(html).toContain("Showing the first 0 steps; the run had more.")
  })

  it("_renderQueries summarises count and total duration", () => {
    const html = m()._renderQueries({ queries: [
      { sql: "SELECT 1", duration_ms: 1.2 },
      { sql: "SELECT 2", duration_ms: 2.3, name: "load" },
    ] })
    expect(html).toContain("2 queries")
    expect(html).toContain("3.5 ms total")
    expect(html).toContain("load")
  })

  it("_renderQueries uses the singular 'query' for exactly one result", () => {
    const html = m()._renderQueries({ queries: [{ sql: "SELECT 1", duration_ms: 1 }] })
    expect(html).toContain("1 query ")
  })

  it("_renderQueries defaults a missing/NaN duration_ms to 0", () => {
    const html = m()._renderQueries({ queries: [{ sql: "SELECT 1" }] })
    expect(html).toContain("0.0 ms")
  })

  it("_renderQueries defaults a missing sql to an empty string", () => {
    const html = m()._renderQueries({ queries: [{ duration_ms: 1 }] })
    expect(html).not.toContain("undefined")
  })

  it("_renderQueries reports when nothing ran", () => {
    expect(m()._renderQueries({ queries: [] })).toContain("No SQL queries executed")
    expect(m()._renderQueries({})).toContain("No SQL queries executed")
  })
})

describe("_displayTraceResults", () => {
  it("clears the overlay, sets the status banner and renders the overlay for trace_nodes", () => {
    const c = makeController()
    const m = new TestRunnerManager(c)
    m._displayTraceResults({ success: true, signal: "done", trace_nodes: [{ id: "n1", status: "success" }] })
    expect(c.canvas.clearTraceOverlay).toHaveBeenCalled()
    expect(c.testStatusTarget.textContent).toContain("Success")
    expect(c.canvas.showTraceOverlay).toHaveBeenCalledWith([{ id: "n1", status: "success" }])
  })

  it("shows a failure status when the run failed", () => {
    const c = makeController()
    const m = new TestRunnerManager(c)
    m._displayTraceResults({ success: false, error: "kaboom" })
    expect(c.testStatusTarget.textContent).toBe("kaboom")
    expect(c.testOutputTarget.innerHTML).toContain("Execution failed")
  })

  it("shows a timeout status", () => {
    const c = makeController()
    const m = new TestRunnerManager(c)
    m._displayTraceResults({ timeout: true })
    expect(c.testStatusTarget.textContent).toBe("Timed out")
    expect(c.testStatusTarget.classList.contains("bg-amber-100")).toBe(true)
  })

  it("renders a Context block when the trace returned a non-empty final context", () => {
    const c = makeController()
    const m = new TestRunnerManager(c)
    m._displayTraceResults({ success: true, context: { user_id: 5 } })
    expect(c.testOutputTarget.innerHTML).toContain("Context:")
    expect(c.testOutputTarget.innerHTML).toContain('"user_id": 5')
  })

  it("omits the Context block when context is an empty object", () => {
    const c = makeController()
    const m = new TestRunnerManager(c)
    m._displayTraceResults({ success: true, context: {} })
    expect(c.testOutputTarget.innerHTML).not.toContain("Context:")
  })

  it("renders a collapsible raw Trace Output block when present", () => {
    const c = makeController()
    const m = new TestRunnerManager(c)
    m._displayTraceResults({ success: true, trace: "step 1\nstep 2" })
    expect(c.testOutputTarget.innerHTML).toContain("Trace Output")
    expect(c.testOutputTarget.innerHTML).toContain("step 1")
  })

  it("includes the truncation notice in the rendered output", () => {
    const c = makeController({
      testTraceTruncatedFormatValue: "Showing the first {count} steps; the run had more.",
    })
    const m = new TestRunnerManager(c)
    m._displayTraceResults({
      success: true,
      trace_truncated: true,
      trace_nodes: [{ id: "n1", status: "success", label: "a" }],
    })
    expect(c.testOutputTarget.innerHTML).toContain("Showing the first 1 steps; the run had more.")
  })

  it("scrolls the first failing step into view when rendered", () => {
    const c = makeController({ elements: [{ id: "n1" }] })
    const m = new TestRunnerManager(c)
    const scrollSpy = vi.fn()
    // happy-dom doesn't implement scrollIntoView; stub it on the prototype so
    // the real DOM node produced by rendering picks it up.
    Element.prototype.scrollIntoView = scrollSpy
    m._displayTraceResults({
      success: false,
      trace_nodes: [{ id: "n1", status: "failure", label: "bad", element_id: "n1" }],
    })
    expect(scrollSpy).toHaveBeenCalledWith({ block: "nearest", behavior: "smooth" })
    delete Element.prototype.scrollIntoView
  })
})

describe("clear", () => {
  it("delegates to the canvas overlay clear", () => {
    const c = makeController()
    new TestRunnerManager(c).clear()
    expect(c.canvas.clearTraceOverlay).toHaveBeenCalled()
  })
})

describe("status/button target guards", () => {
  it("_setTestStatus is a no-op when there is no status target", () => {
    const c = makeController({ hasTestStatusTarget: false })
    expect(() => new TestRunnerManager(c)._setTestStatus("success", "ok")).not.toThrow()
  })

  it("_setRunButtonDisabled is a no-op when there is no run-button target", () => {
    const c = makeController({ hasTestRunButtonTarget: false })
    expect(() => new TestRunnerManager(c)._setRunButtonDisabled(true)).not.toThrow()
  })
})

describe("run()", () => {
  it("bails out immediately when a run is already in flight", async () => {
    const c = makeController()
    const m = new TestRunnerManager(c)
    m.runInFlight = true
    await m.run()
    expect(c.save).not.toHaveBeenCalled()
  })

  it("does nothing without id/customer", async () => {
    const c = makeController({ idValue: "" })
    const m = new TestRunnerManager(c)
    await m.run()
    expect(c.save).not.toHaveBeenCalled()
  })

  it("does nothing without a customer id", async () => {
    const c = makeController({ customerIdValue: "" })
    const m = new TestRunnerManager(c)
    await m.run()
    expect(c.save).not.toHaveBeenCalled()
  })

  it("does nothing without a traces URL", async () => {
    const fetchSpy = vi.fn()
    vi.stubGlobal("fetch", fetchSpy)
    const c = makeController({ urlsValue: {} })
    const m = new TestRunnerManager(c)
    await m.run()
    expect(fetchSpy).not.toHaveBeenCalled()
    expect(m.runInFlight).toBe(false)
    expect(c.testStatusTarget.textContent).not.toMatch(/Running/)
    expect(c.testStatusTarget.classList.contains("bg-yellow-100")).toBe(false)
  })

  it("tolerates a storage write failure while persisting the last input", async () => {
    const data = { success: true, trace_nodes: [] }
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => data }))
    const spy = vi.spyOn(localStorage, "setItem").mockImplementation(() => { throw new Error("full") })
    const c = makeController()
    c.testInputTarget.value = '{"n":1}'
    const m = new TestRunnerManager(c)
    await m.run()
    expect(spy).toHaveBeenCalled()
    expect(m.history.length).toBe(1)
    spy.mockRestore()
  })

  it("guards against malformed JSON before hitting the network", async () => {
    const fetchSpy = vi.fn()
    vi.stubGlobal("fetch", fetchSpy)
    const c = makeController()
    c.testInputTarget.value = "{oops"
    const m = new TestRunnerManager(c)
    await m.run()
    expect(fetchSpy).not.toHaveBeenCalled()
    expect(c.testOutputTarget.innerHTML).toMatch(/Invalid JSON input/)
  })

  it("defaults to empty input when there is no test-input target", async () => {
    const data = { success: true, trace_nodes: [] }
    const fetchSpy = vi.fn().mockResolvedValue({ ok: true, json: async () => data })
    vi.stubGlobal("fetch", fetchSpy)

    const c = makeController({ hasTestInputTarget: false })
    const m = new TestRunnerManager(c)
    await m.run()

    expect(c.save).not.toHaveBeenCalled()
    const [, opts] = fetchSpy.mock.calls[0]
    expect(JSON.parse(opts.body)).toEqual({
      input: {},
      configuration: { elements: [{ id: "folded" }], connections: [] }
    })
  })

  it("POSTs traces with input and folded configuration and never PATCHes", async () => {
    const data = { success: true, signal: "completed", trace_nodes: [] }
    const fetchSpy = vi.fn().mockResolvedValue({ ok: true, json: async () => data })
    vi.stubGlobal("fetch", fetchSpy)

    const c = makeController()
    c.testInputTarget.value = '{"n":1}'
    const m = new TestRunnerManager(c)
    await m.run()

    expect(c.save).not.toHaveBeenCalled()
    expect(c._buildSaveConfiguration).toHaveBeenCalled()
    const [url, opts] = fetchSpy.mock.calls[0]
    expect(url).toBe("/tenant/flowcharts/42/traces")
    expect(opts.method).toBe("POST")
    expect(JSON.parse(opts.body)).toEqual({
      input: { n: 1 },
      configuration: { elements: [{ id: "folded" }], connections: [] }
    })
    expect(fetchSpy.mock.calls.every(([, callOpts]) => callOpts.method !== "PATCH")).toBe(true)
    expect(m.history.length).toBe(1)
    expect(localStorage.getItem("flowchartTestInput:42")).toBe('{"n":1}')
    expect(m.runInFlight).toBe(false)
  })

  it("surfaces a server error status for a non-ok response", async () => {
    const fetchSpy = vi.fn().mockResolvedValue({
      ok: false, status: 500, json: async () => ({ error: "server exploded" }),
    })
    vi.stubGlobal("fetch", fetchSpy)
    const c = makeController()
    const m = new TestRunnerManager(c)
    await m.run()
    expect(c.testOutputTarget.innerHTML).toContain("server exploded")
    expect(m.history.length).toBe(0)
  })

  it("falls back to a generic status message when a non-ok response body isn't JSON", async () => {
    const fetchSpy = vi.fn().mockResolvedValue({
      ok: false, status: 502, json: async () => { throw new Error("not json") },
    })
    vi.stubGlobal("fetch", fetchSpy)
    const c = makeController()
    const m = new TestRunnerManager(c)
    await m.run()
    expect(c.testOutputTarget.innerHTML).toContain("Server error (502)")
  })

  it("reports a network error when fetch rejects", async () => {
    const fetchSpy = vi.fn().mockRejectedValue(new Error("offline"))
    vi.stubGlobal("fetch", fetchSpy)
    const c = makeController()
    const m = new TestRunnerManager(c)
    await m.run()
    expect(c.testOutputTarget.innerHTML).toContain("Network error")
    expect(c.testOutputTarget.innerHTML).toContain("offline")
    expect(m.runInFlight).toBe(false)
  })

  it("reports a timeout when the request is aborted", async () => {
    const abortErr = new Error("aborted")
    abortErr.name = "AbortError"
    const fetchSpy = vi.fn().mockRejectedValue(abortErr)
    vi.stubGlobal("fetch", fetchSpy)
    const c = makeController()
    const m = new TestRunnerManager(c)
    await m.run()
    expect(c.testOutputTarget.innerHTML).toContain("timed out")
  })
})
