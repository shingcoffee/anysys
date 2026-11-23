import { describe, it, expect, beforeAll } from "vitest"
import { RULE_NAV, navFor } from "flowchart/validation_navigation"

// navFor's missing_input anchorFn calls CSS.escape; happy-dom may not expose it.
beforeAll(() => {
  if (typeof globalThis.CSS === "undefined" || typeof globalThis.CSS.escape !== "function") {
    globalThis.CSS = { escape: (s) => String(s) }
  }
})

describe("RULE_NAV / navFor", () => {
  it("returns null for flowchart-level (canvas-only) rules mapped to null", () => {
    expect(navFor({ type: "orphan_start" })).toBeNull()
    expect(navFor({ type: "unreachable" })).toBeNull()
  })

  it("returns null for a rule not present in the table", () => {
    expect(navFor({ type: "totally_unknown_rule" })).toBeNull()
  })

  it("resolves a static tab + anchor + fixHint", () => {
    expect(navFor({ type: "empty_loop_condition" })).toEqual({
      tab: "general",
      anchor: '[data-element-field="condition"]',
      fixHint: "Define the loop condition",
    })
  })

  it.each(["too_few_branches", "duplicate_match_value", "multiple_otherwise", "invalid_condition_match", "missing_yes_branch"])(
    "opens the Branches tab at the branches section for %s",
    (type) => {
      expect(navFor({ type })).toEqual({ tab: "branches", anchor: '[data-element-field="branches"]', fixHint: null })
    }
  )

  it("returns a null anchor when the rule only switches tabs", () => {
    expect(navFor({ type: "empty_process" })).toEqual({
      tab: "steps",
      anchor: null,
      fixHint: "Add at least one step",
    })
  })

  it("builds a dynamic anchor from problem.meta for missing_input", () => {
    const nav = navFor({ type: "missing_input", meta: { pinKey: "user_id" } })
    expect(nav.tab).toBe("io")
    expect(nav.anchor).toBe('[data-element-io-input][data-pin="user_id"]')
  })

  it("missing_input anchorFn returns null when no pinKey is present", () => {
    const nav = navFor({ type: "missing_input", meta: {} })
    expect(nav.anchor).toBeNull()
    expect(navFor({ type: "missing_input" }).anchor).toBeNull()
  })

  it("lets a problem-level fixHint override the table default", () => {
    const nav = navFor({ type: "empty_process", fixHint: "custom hint" })
    expect(nav.fixHint).toBe("custom hint")
  })

  it("lets translated hints override the table default", () => {
    expect(navFor({ type: "empty_process" }, { empty_process: "translated hint" }).fixHint)
      .toBe("translated hint")
  })

  it("falls back to null tab/fixHint when a table entry has neither (defensive || null)", () => {
    // Every real table entry always declares tab + fixHint, so this branch is
    // otherwise dead in production; mutate a live entry to exercise navFor's
    // own fallback logic, then restore the table.
    const original = { ...RULE_NAV.empty_process }
    RULE_NAV.empty_process.tab = ""
    RULE_NAV.empty_process.fixHint = ""
    try {
      expect(navFor({ type: "empty_process" })).toEqual({ tab: null, anchor: null, fixHint: null })
    } finally {
      RULE_NAV.empty_process = original
    }
  })

  it("every non-null table entry declares a tab or a tab function", () => {
    for (const [, entry] of Object.entries(RULE_NAV)) {
      if (entry === null) continue
      expect(typeof entry.tab === "string" || typeof entry.tabFn === "function").toBe(true)
    }
  })

  it.each(["condition_invalid", "loop_invalid_collection", "loop_reserved_variable", "loop_colliding_variables"])(
    "opens %s at the reported field on its tab",
    (type) => {
      expect(navFor({ type, field: "condition" })).toEqual({ tab: "general", anchor: '[data-element-field="condition"]', fixHint: null })
      expect(navFor({ type, field: "stopWhen" })).toEqual({ tab: "advanced", anchor: '[data-element-field="stopWhen"]', fixHint: null })
      expect(navFor({ type })).toEqual({ tab: "general", anchor: null, fixHint: null })
    }
  )

  it("anchors element_config_invalid to the reported field on General", () => {
    expect(navFor({ type: "element_config_invalid", field: "returnValue" })).toEqual({
      tab: "general",
      anchor: '[data-element-field="returnValue"]',
      fixHint: "Fix this element's configuration",
    })
    expect(navFor({ type: "element_config_invalid" }).anchor).toBeNull()
  })

  it("does not keep an End HTTP-status navigation entry", () => {
    expect(navFor({ type: "end_http_no_status" })).toBeNull()
    expect(RULE_NAV.end_http_no_status).toBeUndefined()
  })

  it("opens Subflow and End fields on the general tab", () => {
    expect(navFor({ type: "subflow_no_target" }).tab).toBe("general")
    expect(navFor({ type: "end_no_return_value" }).tab).toBe("general")
  })
})
