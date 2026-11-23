import { describe, it, expect, vi, beforeAll, beforeEach, afterEach } from "vitest"

// validate() news up the two validation services; mock them so the orchestration
// (merge structural + IO + server problems, badge, rings, panel) is unit-testable
// without a live canvas engine.
vi.mock("flowchart/validation_service", () => ({
  ValidationService: class {
    constructor(elements, connections) { this.elements = elements; this.connections = connections }
    validate() { return { errors: [{ type: "duplicate_start", elementId: "a", message: "dup" }], warnings: [{ type: "orphan_end", elementId: null, message: "warn" }] } }
  },
}))
vi.mock("flowchart/input_output_validation_service", () => ({
  InputOutputValidationService: class {
    constructor(canvas) { this.canvas = canvas }
    async loadImplicitKeys() {}
    validate() { return [{ type: "missing_input", elementId: "b", message: "io", meta: { pinKey: "in1" } }] }
  },
}))

import { ValidationMixin } from "controllers/flowchart_canvas/validation_mixin"
import { ValidationService } from "flowchart/validation_service"
import { makeCanvas, mixinHost } from "../../support/flowchart.js"

beforeAll(() => {
  if (typeof globalThis.CSS === "undefined" || typeof globalThis.CSS.escape !== "function") {
    globalThis.CSS = { escape: (s) => String(s) }
  }
})

function host(canvasOverrides = {}, extra = {}) {
  document.body.innerHTML = `
    <span data-badge class="bg-red-500 text-white hidden"></span>
    <div data-list></div>
    <span data-notice class="hidden"></span>`
  const canvas = makeCanvas({
    selectConnection: vi.fn(),
    clearConnectionSelection: vi.fn(),
    _selectElement: vi.fn(),
    ...canvasOverrides,
  })
  return mixinHost(ValidationMixin, {
    idValue: 7,
    customerIdValue: 42,
    urlsValue: { validation: "/tenant/flowcharts/7/validation" },
    canvas,
    hasValidationBadgeTarget: true,
    validationBadgeTarget: document.querySelector("[data-badge]"),
    hasValidationListTarget: true,
    validationListTarget: document.querySelector("[data-list]"),
    hasValidationNoticeTarget: true,
    validationNoticeTarget: document.querySelector("[data-notice]"),
    openBottomPanel: vi.fn(),
    closeBottomPanel: vi.fn(),
    _showPropertySidebar: vi.fn(),
    _handleConnectionSelected: vi.fn(),
    _updateZoomDisplay: vi.fn(),
    _updateAlignmentToolbar: vi.fn(),
    ...extra,
  })
}

beforeEach(() => { try { sessionStorage.clear() } catch (_e) { /* noop */ } })
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals() })

describe("ValidationMixin.validate — orchestration", () => {
  it("threads the localized element-rule messages into ValidationService", () => {
    const h = host({}, {
      validationTooFewBranchesValue: "localized branches",
      validationElementProblemFormatValue: "{label}（{type}）：{message}"
    })

    expect(h._validationMessages()).toMatchObject({
      tooFewBranches: "localized branches",
      elementProblemFormat: "{label}（{type}）：{message}"
    })
  })

  it("merges structural + IO + server problems and paints the canvas rings", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => ({
      ok: true,
      json: async () => ({ problems: [{ type: "codegen_failed", severity: "error", elementId: "c", message: "srv" }] }),
    })))
    const h = host()
    const ok = await h.validate()
    expect(ok).toBe(false) // errors present
    // 2 errors (dup + io + server error = 3) -> badge shows total incl warning
    expect(h.validationBadgeTarget.classList.contains("hidden")).toBe(false)
    expect(h.validationBadgeTarget.classList.contains("bg-red-100")).toBe(true)
    expect(h.canvas.clearValidationStates).toHaveBeenCalled()
    // element "a","b","c" get rings; null-element warning is skipped
    expect(h.canvas.setValidationState).toHaveBeenCalledWith("a", "error")
    expect(h.canvas.setValidationState).toHaveBeenCalledWith("b", "error")
    expect(h.openBottomPanel).toHaveBeenCalledWith("problems")
  })

  it("degrades to a warning when the server validation fetch fails", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 500 })))
    const h = host()
    const problems = await h._runServerValidation()
    expect(problems).toEqual([expect.objectContaining({ type: "server_check_unavailable", severity: "warning" })])
  })

  it("_runServerValidation returns [] without id/customer", async () => {
    const h = host({}, { idValue: null })
    expect(await h._runServerValidation()).toEqual([])
  })

  it("_runServerValidation returns [] without a validation URL", async () => {
    const h = host({}, { urlsValue: {} })
    expect(await h._runServerValidation()).toEqual([])
  })
})

describe("ValidationMixin._applyValidationRings — severity precedence", () => {
  it("error beats warning for the same element", () => {
    const h = host()
    h._validationProblems = [
      { elementId: "x", severity: "warning" },
      { elementId: "x", severity: "error" },
      { elementId: null, severity: "error" },
    ]
    h._applyValidationRings()
    expect(h.canvas.setValidationState).toHaveBeenCalledTimes(1)
    expect(h.canvas.setValidationState).toHaveBeenCalledWith("x", "error")
  })
})

describe("ValidationMixin._renderValidationList", () => {
  it("renders 'No problems found' for an empty list", () => {
    const h = host()
    h._validationProblems = []
    h._renderValidationList()
    expect(h.validationListTarget.innerHTML).toContain("No problems found")
  })

  it("renders filter pills and grouped items with escaped messages + fix hints", () => {
    const h = host()
    h._validationProblems = [
      { type: "duplicate_label", severity: "error", elementId: "a", message: "<b>bad</b>" },
      { type: "orphan_end", severity: "warning", elementId: null, message: "warny" },
    ]
    h._renderValidationList()
    const html = h.validationListTarget.innerHTML
    expect(html).toContain("All (2)")
    expect(html).toContain("Errors (1)")
    expect(html).toContain("Warnings (1)")
    expect(html).toContain("&lt;b&gt;bad&lt;/b&gt;") // escaped
    expect(html).toContain("Rename this element to a unique label") // navFor fixHint
  })

  it("filters the rendered groups to the active filter (errors only)", () => {
    const h = host()
    // _validationFilter() reads the per-flowchart choice from sessionStorage
    // (idValue = 7). Seed it so the group-filtering render logic sees "error".
    sessionStorage.setItem("flowchartValidationFilter:7", "error")
    h._validationProblems = [
      { type: "duplicate_label", severity: "error", elementId: "a", message: "e" },
      { type: "orphan_end", severity: "warning", elementId: null, message: "w" },
    ]
    h._renderValidationList()
    // warning group is filtered out
    expect(h.validationListTarget.querySelector('[data-validation-group="warning"]')).toBeNull()
    expect(h.validationListTarget.querySelector('[data-validation-group="error"]')).toBeTruthy()
  })

  it("_validationFilter is a per-instance method (survives Object.assign flattening)", () => {
    // Regression guard for a fixed bug: _validationFilter was a getter, which
    // Object.assign (used to merge the mixin onto the controller prototype, and by
    // mixinHost here) INVOKES once at copy time — flattening it to a static "all"
    // and defeating the sessionStorage-backed per-flowchart filter. It is now a
    // plain method, so it must be copied by reference and evaluated per instance.
    const h = host()
    const desc = Object.getOwnPropertyDescriptor(h, "_validationFilter")
    expect(desc.get).toBeUndefined()
    expect(typeof h._validationFilter).toBe("function")

    // Defaults to "all" with nothing stored, and reflects the stored per-flowchart
    // value at call time (idValue = 7).
    expect(h._validationFilter()).toBe("all")
    sessionStorage.setItem("flowchartValidationFilter:7", "warning")
    expect(h._validationFilter()).toBe("warning")
  })

  it("setValidationFilter round-trips into _renderValidationList (filter is actually applied)", () => {
    const h = host()
    h._validationProblems = [
      { type: "duplicate_label", severity: "error", elementId: "a", message: "e" },
      { type: "orphan_end", severity: "warning", elementId: null, message: "w" },
    ]
    h.setValidationFilter({ currentTarget: { dataset: { filter: "warning" } } })
    // The persisted filter is now read back on render: only the warning group shows.
    expect(h.validationListTarget.querySelector('[data-validation-group="error"]')).toBeNull()
    expect(h.validationListTarget.querySelector('[data-validation-group="warning"]')).toBeTruthy()
  })
})

describe("ValidationMixin — filter + group toggle actions", () => {
  it("setValidationFilter persists the choice and re-renders", () => {
    const h = host()
    h._validationProblems = []
    h.setValidationFilter({ currentTarget: { dataset: { filter: "warning" } } })
    expect(sessionStorage.getItem("flowchartValidationFilter:7")).toBe("warning")
  })

  it("toggleValidationGroup flips the collapsed flag and hides the group body", () => {
    const h = host()
    h._validationProblems = [{ type: "duplicate_label", severity: "error", elementId: "a", message: "e" }]
    h._renderValidationList()
    const groupBtn = h.validationListTarget.querySelector('[data-group="error"]')
    h.toggleValidationGroup({ currentTarget: groupBtn })
    expect(h._validationCollapsed.error).toBe(true)
    expect(h.validationListTarget.querySelector('[data-validation-group="error"]').classList.contains("hidden")).toBe(true)
  })
})

describe("ValidationMixin.focusValidationIssue", () => {
  it("routes a connection issue through the connection-selection path", () => {
    const conn = { id: "c1", from: "a", to: "b" }
    const h = host({ connections: [conn], elements: [{ id: "a" }, { id: "b" }], selectedElements: [{ id: "old" }] })
    h.focusValidationIssue({ currentTarget: { dataset: { rule: "decision_branch_no_label", severity: "error", connectionId: "c1" } } })
    expect(h.canvas.selectConnection).toHaveBeenCalledWith("c1")
    expect(h.canvas.zoomPanManager.fitToContent).toHaveBeenCalled()
  })

  it("selects a connection even when its endpoints are not on the canvas", () => {
    const conn = { id: "c1", from: "gone", to: "gone2" }
    const h = host({ connections: [conn], elements: [], selectedElements: [] })
    h.focusValidationIssue({ currentTarget: { dataset: { rule: "dangling", severity: "error", connectionId: "c1" } } })
    expect(h.canvas.selectConnection).toHaveBeenCalledWith("c1")
    expect(h.canvas.zoomPanManager.fitToContent).not.toHaveBeenCalled()
  })

  it("opens the property sidebar for an element issue", () => {
    const el = { id: "a" }
    const h = host({ elements: [el], selectedElements: [] })
    h.focusValidationIssue({ currentTarget: { dataset: { rule: "duplicate_label", severity: "error", elementId: "a" } } })
    expect(h._showPropertySidebar).toHaveBeenCalledWith(el, expect.objectContaining({ tab: "general" }))
  })

  it("navigates element_config_invalid to the reported field", () => {
    const el = { id: "e", type: "end" }
    const h = host({ elements: [el], selectedElements: [] })
    h.focusValidationIssue({
      currentTarget: {
        dataset: { rule: "element_config_invalid", severity: "error", elementId: "e", field: "returnValue" },
      },
    })
    expect(h._showPropertySidebar).toHaveBeenCalledWith(el, expect.objectContaining({
      tab: "general",
      anchor: '[data-element-field="returnValue"]',
    }))
  })

  it("opens an advanced catalog field on the advanced tab", () => {
    const el = { id: "l", type: "loop" }
    const h = host({ elements: [el], selectedElements: [] })
    h.focusValidationIssue({
      currentTarget: {
        dataset: { rule: "element_config_invalid", severity: "error", elementId: "l", field: "stopWhen" },
      },
    })
    expect(h._showPropertySidebar).toHaveBeenCalledWith(el, expect.objectContaining({ tab: "advanced" }))
  })

  it("shows a notice when the problem has no resolvable element", () => {
    const h = host({ elements: [] })
    h.focusValidationIssue({ currentTarget: { dataset: { rule: "cycle", severity: "error" } } })
    expect(h.validationNoticeTarget.classList.contains("hidden")).toBe(false)
    expect(h.validationNoticeTarget.textContent).toContain("isn't tied to a specific element")
  })
})

describe("ValidationMixin._focusElementById", () => {
  it("selects, shows handles and zooms to the element", () => {
    const el = { id: "a" }
    const h = host({ elements: [el], selectedElements: [{ id: "old" }] })
    const result = h._focusElementById("a")
    expect(result).toBe(el)
    expect(h.canvas.clearConnectionSelection).toHaveBeenCalled()
    expect(h.canvas._selectElement).toHaveBeenCalledWith(el)
    expect(h.canvas.zoomPanManager.fitToContent).toHaveBeenCalledWith([el], 300)
    expect(h._updateAlignmentToolbar).toHaveBeenCalled()
  })

  it("returns null for an unknown id", () => {
    const h = host({ elements: [] })
    expect(h._focusElementById("ghost")).toBeNull()
  })
})

describe("ValidationMixin — branch coverage completion", () => {
  it("_runServerValidation returns [] when the server payload's problems isn't an array", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => ({ problems: "nope" }) })))
    const h = host()
    expect(await h._runServerValidation()).toEqual([])
  })

  it("_showValidationResults paints the badge yellow for a warnings-only result", () => {
    const h = host()
    h._showValidationResults([], [{ elementId: null, severity: "warning", message: "w" }])
    expect(h.validationBadgeTarget.classList.contains("hidden")).toBe(false)
    expect(h.validationBadgeTarget.classList.contains("bg-yellow-100")).toBe(true)
    expect(h.validationBadgeTarget.classList.contains("bg-red-100")).toBe(false)
    expect(h.validationBadgeTarget.textContent).toBe("1")
  })

  it("_showValidationResults hides the badge when there are no problems at all", () => {
    const h = host()
    h._showValidationResults([], [])
    expect(h.validationBadgeTarget.classList.contains("hidden")).toBe(true)
    expect(h.validationBadgeTarget.title).toBe("0 errors, 0 warnings")
  })

  it("_applyValidationRings no-ops when the canvas can't clear validation states", () => {
    const h = host()
    h.canvas = {}
    expect(() => h._applyValidationRings()).not.toThrow()
  })

  it("_applyValidationRings keeps an element's error severity when a later problem repeats it", () => {
    const h = host()
    h._validationProblems = [
      { elementId: "x", severity: "error" },
      { elementId: "x", severity: "warning" }, // hits the `=== "error" continue` guard
    ]
    h._applyValidationRings()
    expect(h.canvas.setValidationState).toHaveBeenCalledTimes(1)
    expect(h.canvas.setValidationState).toHaveBeenCalledWith("x", "error")
  })

  it("_validationFilter falls back to 'all' when sessionStorage.getItem throws", () => {
    const h = host()
    vi.spyOn(sessionStorage, "getItem").mockImplementation(() => { throw new Error("blocked") })
    expect(h._validationFilter()).toBe("all")
  })

  it("_renderValidationList no-ops without a list target", () => {
    const h = host({}, { hasValidationListTarget: false })
    expect(() => h._renderValidationList()).not.toThrow()
  })

  it("_renderValidationList treats an unset problems list as empty", () => {
    const h = host()
    delete h._validationProblems
    h._renderValidationList()
    expect(h.validationListTarget.innerHTML).toContain("No problems found")
  })

  it("_renderValidationList shows the 'no match' fallback when the filter excludes every group", () => {
    const h = host()
    sessionStorage.setItem("flowchartValidationFilter:7", "error")
    h._validationProblems = [{ type: "orphan_end", severity: "warning", elementId: null, message: "w" }]
    h._renderValidationList()
    expect(h.validationListTarget.innerHTML).toContain("No problems match this filter")
  })

  it("_renderValidationList renders a collapsed group with the rotated chevron and hidden body", () => {
    const h = host()
    h._validationCollapsed = { error: true }
    h._validationProblems = [{ type: "duplicate_label", severity: "error", elementId: "a", message: "e" }]
    h._renderValidationList()
    const body = h.validationListTarget.querySelector('[data-validation-group="error"]')
    expect(body.classList.contains("hidden")).toBe(true)
    expect(h.validationListTarget.querySelector("svg").getAttribute("class")).toContain("-rotate-90")
  })

  it("_renderValidationItem tolerates a problem with no rule type", () => {
    const h = host()
    h._validationProblems = [{ severity: "error", elementId: "a", message: "no type" }]
    h._renderValidationList()
    expect(h.validationListTarget.innerHTML).toContain('data-rule=""')
  })

  it("_renderValidationItem omits the fix button for a rule with no auto-correction", () => {
    const h = host()
    h._validationProblems = [{ type: "unreachable", severity: "error", elementId: "a", message: "e" }]
    h._renderValidationList()
    expect(h.validationListTarget.querySelector("[data-problem-index]")).toBeNull()
    expect(h.validationListTarget.innerHTML).not.toContain("Fix all")
  })

  it("setValidationFilter defaults to 'all' when the clicked pill has no data-filter", () => {
    const h = host()
    h._validationProblems = []
    h.setValidationFilter({ currentTarget: { dataset: {} } })
    expect(sessionStorage.getItem("flowchartValidationFilter:7")).toBe("all")
  })

  it("setValidationFilter swallows a sessionStorage.setItem failure", () => {
    const h = host()
    h._validationProblems = []
    vi.spyOn(sessionStorage, "setItem").mockImplementation(() => { throw new Error("full") })
    expect(() => h.setValidationFilter({ currentTarget: { dataset: { filter: "error" } } })).not.toThrow()
  })

  it("toggleValidationGroup no-ops when the button carries no group key", () => {
    const h = host()
    expect(() => h.toggleValidationGroup({ currentTarget: { dataset: {} } })).not.toThrow()
  })

  it("toggleValidationGroup initialises the collapsed map on first use (no prior render)", () => {
    const h = host()
    const btn = document.createElement("button")
    btn.dataset.group = "error"
    h.toggleValidationGroup({ currentTarget: btn })
    expect(h._validationCollapsed.error).toBe(true)
  })

  it("_showValidationNotice no-ops without a notice target", () => {
    const h = host({}, { hasValidationNoticeTarget: false })
    expect(() => h._showValidationNotice("x")).not.toThrow()
  })

  it("_showValidationNotice re-hides the notice after the timeout elapses", () => {
    vi.useFakeTimers()
    try {
      const h = host()
      h._showValidationNotice("heads up")
      expect(h.validationNoticeTarget.classList.contains("hidden")).toBe(false)
      vi.advanceTimersByTime(4000)
      expect(h.validationNoticeTarget.classList.contains("hidden")).toBe(true)
    } finally {
      vi.useRealTimers()
    }
  })

  it("closeValidationPanel delegates to closeBottomPanel", () => {
    const h = host()
    h.closeValidationPanel()
    expect(h.closeBottomPanel).toHaveBeenCalled()
  })

  it("focusValidationIssue passes pin-key meta through to navigation", () => {
    const el = { id: "a" }
    const h = host({ elements: [el], selectedElements: [] })
    h.focusValidationIssue({ currentTarget: { dataset: { rule: "missing_input", severity: "error", elementId: "a", pinKey: "in1" } } })
    expect(h._showPropertySidebar).toHaveBeenCalledWith(el, expect.objectContaining({ tab: "io" }))
  })

  it("focusValidationIssue opens the sidebar with no nav hint for an element-level rule that has no navigation entry", () => {
    const el = { id: "a" }
    const h = host({ elements: [el], selectedElements: [] })
    h.focusValidationIssue({ currentTarget: { dataset: { rule: "orphan_start", severity: "warning", elementId: "a" } } })
    expect(h._showPropertySidebar).toHaveBeenCalledWith(el, undefined)
  })

  it("renders the field name so a server element_config_invalid can open that field", () => {
    const h = host()
    h._validationProblems = [{
      type: "element_config_invalid",
      severity: "error",
      elementId: "e",
      field: "returnValue",
      message: "needed",
    }]
    h._renderValidationList()
    expect(h.validationListTarget.innerHTML).toContain('data-field="returnValue"')
  })

  it("normalizes snake_case server problems so rings and field paint share one shape", () => {
    const h = host()
    h._showValidationResults(
      [{ type: "element_config_invalid", element_id: "e1", field: "returnValue", message: "m" }],
      []
    )
    expect(h._validationProblems[0]).toMatchObject({
      elementId: "e1",
      field: "returnValue",
      severity: "error",
    })
    expect(h.canvas.setValidationState).toHaveBeenCalledWith("e1", "error")
  })

  it("leaves a non-object problem unchanged when normalizing", () => {
    const h = host()
    expect(h._normalizeValidationProblem(null)).toBeNull()
    expect(h._normalizeValidationProblem("x")).toBe("x")
  })

  it("_navForProblem returns null when the rule has no navigation entry", () => {
    const h = host()
    expect(h._navForProblem({ type: "orphan_start", field: "label" })).toBeNull()
  })

  it("_navForProblem defaults to general when the canvas has no matching element", () => {
    const h = host({ elements: [] })
    expect(h._navForProblem({
      type: "element_config_invalid",
      field: "returnValue",
      elementId: "gone",
    }).tab).toBe("general")
  })

  it("_tabForElementField defaults to general without a typed element or field", () => {
    const h = host()
    expect(h._tabForElementField({}, "returnValue")).toBe("general")
    expect(h._tabForElementField({ type: "end" }, "")).toBe("general")
    expect(h._tabForElementField({ type: "end" }, "notACatalogField")).toBe("general")
  })
})

describe("ValidationMixin — auto-correct", () => {
  // One safe deterministic fix plus a suggestion that "Fix all" leaves alone.
  function fixableHost(extra = {}) {
    const process = { id: "p", type: "process", label: "Duplicate", properties: {} }
    const end = { id: "e", type: "end", label: "End", properties: {} }
    const twin = { id: "twin", type: "process", label: "Duplicate", properties: {} }
    const h = host({
      elements: [process, end, twin],
      connections: [],
      updateElementProperties: vi.fn((id, label, props) => {
        const element = h.canvas.elements.find((x) => x.id === id)
        if (label !== undefined) element.label = label
        element.properties = { ...element.properties, ...props }
        return element
      }),
    }, { validate: vi.fn(async () => true), ...extra })
    h._validationProblems = [
      { type: "duplicate_label", severity: "error", elementId: "p", message: "duplicate" },
      { type: "end_no_return_value", severity: "error", elementId: "e", message: "no value" },
    ]
    return h
  }

  it("renders a Fix button per fixable problem and a Fix all count of the safe ones", () => {
    const h = fixableHost()
    h._renderValidationList()
    const html = h.validationListTarget.innerHTML
    expect(html).toContain("Fix all (1)") // the suggestion is not counted
    expect(h.validationListTarget.querySelectorAll("[data-problem-index]")).toHaveLength(2)
    expect(html).toContain("Rename uniquely")
    expect(html).toContain("Use ctx[:result]")
  })

  it("applyValidationFix applies that one problem's fix and re-validates", async () => {
    const h = fixableHost()
    await h.applyValidationFix({ preventDefault: vi.fn(), currentTarget: { dataset: { problemIndex: "0" } } })
    expect(h.canvas.elements[0].label).toBe("Duplicate 2")
    expect(h.validate).toHaveBeenCalled()
  })

  it("applyValidationFix applies a suggestion when its own button is clicked", async () => {
    const h = fixableHost()
    await h.applyValidationFix({ preventDefault: vi.fn(), currentTarget: { dataset: { problemIndex: "1" } } })
    expect(h.canvas.elements[1].properties.returnValue).toBe("ctx[:result]")
  })

  it("applyValidationFix ignores an index that no longer resolves to a problem", async () => {
    const h = fixableHost()
    await h.applyValidationFix({ preventDefault: vi.fn(), currentTarget: { dataset: { problemIndex: "9" } } })
    expect(h.validate).not.toHaveBeenCalled()
  })

  it("applyValidationFix tolerates an unset problem list", async () => {
    const h = fixableHost()
    delete h._validationProblems
    await h.applyValidationFix({ preventDefault: vi.fn(), currentTarget: { dataset: { problemIndex: "0" } } })
    expect(h.validate).not.toHaveBeenCalled()
  })

  it("applyValidationFix shows a notice when the fix finds nothing left to change", async () => {
    const h = fixableHost()
    h._validationProblems = [{ type: "duplicate_label", severity: "error", elementId: "ghost", message: "e" }]
    await h.applyValidationFix({ preventDefault: vi.fn(), currentTarget: { dataset: { problemIndex: "0" } } })
    expect(h.validationNoticeTarget.textContent).toBe("Nothing left to fix automatically")
    expect(h.validate).not.toHaveBeenCalled()
  })

  it("applyValidationFix shows the same notice for a problem with no registered fix", async () => {
    const h = fixableHost()
    h._validationProblems = [{ type: "unreachable", severity: "error", elementId: "j", message: "e" }]
    await h.applyValidationFix({ preventDefault: vi.fn(), currentTarget: { dataset: { problemIndex: "0" } } })
    expect(h.validationNoticeTarget.textContent).toBe("Nothing left to fix automatically")
  })

  it("applyAllValidationFixes applies only the safe fixes and reports how many", async () => {
    const h = fixableHost()
    await h.applyAllValidationFixes({ preventDefault: vi.fn() })
    expect(h.canvas.elements[0].label).toBe("Duplicate 2")
    expect(h.canvas.elements[1].properties).toEqual({}) // suggestion untouched
    expect(h.validate).toHaveBeenCalled()
    expect(h.validationNoticeTarget.textContent).toBe("Applied 1 fixes")
  })

  it("applyAllValidationFixes falls back to the nothing-to-do notice", async () => {
    const h = fixableHost()
    h._validationProblems = [{ type: "unreachable", severity: "error", elementId: "j", message: "e" }]
    await h.applyAllValidationFixes({ preventDefault: vi.fn() })
    expect(h.validationNoticeTarget.textContent).toBe("Nothing left to fix automatically")
  })

  it("applyAllValidationFixes tolerates an unset problem list", async () => {
    const h = fixableHost()
    delete h._validationProblems
    await expect(h.applyAllValidationFixes({ preventDefault: vi.fn() })).resolves.toBeUndefined()
  })

  it("hides autofix buttons and refuses apply when canMutate is false", async () => {
    const h = fixableHost()
    h.canvas.canMutate = () => false
    h._renderValidationList()
    expect(h.validationListTarget.innerHTML).not.toContain("Fix all")
    expect(h.validationListTarget.querySelector("[data-problem-index]")).toBeNull()
    await h.applyValidationFix({ preventDefault: vi.fn(), currentTarget: { dataset: { problemIndex: "0" } } })
    await h.applyAllValidationFixes({ preventDefault: vi.fn() })
    expect(h.validate).not.toHaveBeenCalled()
    expect(h.canvas.elements[0].label).toBe("Duplicate")
  })
})

describe("P5-5 ValidationMixin.validate — client/server merge", () => {
  async function validateWith(serverProblems, structural = null) {
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => ({ problems: serverProblems }) })))
    if (structural) vi.spyOn(ValidationService.prototype, "validate").mockReturnValue(structural)
    const h = host()
    vi.spyOn(h, "_showValidationResults")
    await h.validate()
    const [errors, warnings] = h._showValidationResults.mock.calls[0]
    return { errors, warnings }
  }
  const keys = (problems) => problems.map((p) => [p.type, p.elementId ?? null, p.field ?? null])

  it("drops a server problem on the same element and field as a client problem", async () => {
    const { errors } = await validateWith([
      { type: "element_config_invalid", severity: "error", element_id: "l", field: "collection", message: "srv" },
      { type: "element_config_invalid", severity: "error", element_id: "l", field: "itemVariable", message: "srv" },
      { type: "element_config_invalid", severity: "error", element_id: "other", field: "collection", message: "srv" },
    ], { errors: [{ type: "loop_no_collection", elementId: "l", field: "collection", message: "client" }], warnings: [] })
    expect(keys(errors)).toEqual([
      ["loop_no_collection", "l", "collection"],
      ["missing_input", "b", null],
      ["element_config_invalid", "l", "itemVariable"],
      ["element_config_invalid", "other", "collection"],
    ])
  })

  it("drops a field-less server problem only when the client reports the same type on that element", async () => {
    const { errors, warnings } = await validateWith([
      { type: "duplicate_start", severity: "error", element_id: "a", message: "srv dup" },
      { type: "codegen_failed", severity: "error", element_id: "a", message: "srv codegen" },
      { type: "codegen_failed", severity: "error", element_id: null, message: "srv flow-level" },
    ])
    expect(errors.filter((p) => p.type === "duplicate_start").map((p) => p.message)).toEqual(["dup"])
    expect(keys(errors)).toEqual([
      ["duplicate_start", "a", null],
      ["missing_input", "b", null],
      ["codegen_failed", "a", null],
      ["codegen_failed", null, null],
    ])
    expect(keys(warnings)).toEqual([["orphan_end", null, null]])
  })

  it("de-duplicates by element, connection, type and field across errors and warnings", async () => {
    const { errors, warnings } = await validateWith([
      { type: "codegen_failed", severity: "error", message: "structure 1" },
      { type: "codegen_failed", severity: "error", message: "structure 2" },
      { type: "dangling_connection", severity: "error", connection_id: "c1", message: "c1" },
      { type: "dangling_connection", severity: "error", connection_id: "c2", message: "c2" },
      { type: "orphan_end", severity: "warning", message: "srv warn" },
      { type: "codegen_failed", severity: "warning", message: "same key as an error" },
    ])
    expect(errors.filter((p) => p.type === "codegen_failed").map((p) => p.message)).toEqual(["structure 1"])
    expect(errors.filter((p) => p.type === "dangling_connection").map((p) => p.connectionId)).toEqual(["c1", "c2"])
    expect(warnings.map((p) => p.message)).toEqual(["warn"])
  })
})

describe("P5-4 ValidationMixin — preview configuration", () => {
  it("posts the stored collapsed configuration while previewing", async () => {
    const stored = { elements: [{ id: "collapsed" }], connections: [] }
    const fetchMock = vi.fn(async () => ({ ok: true, json: async () => ({ problems: [] }) }))
    vi.stubGlobal("fetch", fetchMock)
    const h = host({}, { _previewAwareConfiguration: () => stored })
    await h._runServerValidation()
    expect(JSON.parse(fetchMock.mock.calls[0][1].body).configuration).toEqual(stored)
  })

  it("validate() uses the preview-aware canvas and configuration when those helpers exist", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => ({ problems: [] }) })))
    const stored = { elements: [{ id: "collapsed" }], connections: [] }
    const previewCanvas = { elements: stored.elements, connections: stored.connections }
    const h = host({}, {
      _previewAwareConfiguration: () => stored,
      _canvasForValidation: () => previewCanvas,
    })
    await h.validate()
    expect(h.canvas.clearValidationStates).toHaveBeenCalled()
  })
})
