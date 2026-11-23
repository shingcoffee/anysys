// NOTE: showDependencyLines() draws SVG bezier paths whose coordinates come from
// getBoundingClientRect (zeroed in happy-dom) — the path GEOMETRY is covered by
// Playwright (spec/e2e), not unit. We test the tractable parts here: badge HTML,
// connection derivation (whether an overlay is drawn at all), and teardown.
import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { FieldManager } from "controllers/page_builder/field_manager"
import { makeCtrl, field } from "../../../support/page_builder.js"

const ruleWith = ({ targetId, condFieldId }) => ({
  actions: targetId ? [{ target_id: targetId }] : [],
  conditions: condFieldId ? { groups: [{ items: [{ field_id: condFieldId }] }] } : { groups: [] },
})

describe("DependencyOverlayMixin._getDependencyBadgeHtml", () => {
  it("returns empty string when the field is neither a rule target nor referenced", () => {
    const fm = new FieldManager(makeCtrl())
    expect(fm._getDependencyBadgeHtml(field({ id: "x" }))).toBe("")
  })

  it("tolerates a configuration with no `rules` key (the `rules || []` fallback)", () => {
    const fm = new FieldManager(makeCtrl({ configuration: {} }))
    expect(fm._getDependencyBadgeHtml(field({ id: "x" }))).toBe("")
  })

  it("emits an orange badge when the field is a rule target (has conditions)", () => {
    const ctrl = makeCtrl({ configuration: { rules: [ruleWith({ targetId: "x", condFieldId: "y" })], calculations: [], pages: [], theme: {} } })
    const fm = new FieldManager(ctrl)
    const html = fm._getDependencyBadgeHtml(field({ id: "x" }))
    expect(html).toContain("text-orange-500")
    expect(html).toContain('data-field-id="x"')
  })

  it("emits a purple badge when the field is only referenced by another rule", () => {
    const ctrl = makeCtrl({ configuration: { rules: [ruleWith({ targetId: "z", condFieldId: "y" })], calculations: [], pages: [], theme: {} } })
    const fm = new FieldManager(ctrl)
    expect(fm._getDependencyBadgeHtml(field({ id: "y" }))).toContain("text-purple-500")
  })
})

describe("DependencyOverlayMixin overlay lifecycle", () => {
  let ctrl, fm
  beforeEach(() => {
    document.body.innerHTML = '<div id="canvas"></div>'
    const container = document.getElementById("canvas")
    ctrl = makeCtrl({
      configuration: { rules: [ruleWith({ targetId: "x", condFieldId: "y" })], calculations: [], pages: [], theme: {} },
    })
    ctrl.fieldsContainerTarget = container
    fm = new FieldManager(ctrl)
  })

  it("draws no overlay when the clicked field has no connections", () => {
    const event = { stopPropagation() {}, currentTarget: { dataset: { fieldId: "unrelated" } } }
    fm.showDependencyLines(event)
    expect(ctrl.fieldsContainerTarget.querySelector(".dependency-overlay")).toBeNull()
  })

  it("appends an SVG overlay when connections exist and both endpoints are in the DOM", () => {
    ctrl.fieldsContainerTarget.innerHTML =
      '<div data-field-id="y"></div><div data-field-id="x"></div>'
    const event = { stopPropagation() {}, currentTarget: { dataset: { fieldId: "x" } } }
    fm.showDependencyLines(event)
    const overlay = ctrl.fieldsContainerTarget.querySelector(".dependency-overlay")
    expect(overlay).not.toBeNull()
    expect(overlay.querySelectorAll("path").length).toBe(1)
    // orange path: fieldId "x" is the rule's action target.
    expect(overlay.querySelector("path").getAttribute("stroke")).toBe("#f97316")
  })

  it("draws a purple path when the clicked field is a condition (referenced, not target)", () => {
    ctrl.fieldsContainerTarget.innerHTML =
      '<div data-field-id="y"></div><div data-field-id="x"></div>'
    // fieldId "y" is the condition side of the rule → conditionFieldIds path (line 45-46).
    fm.showDependencyLines({ stopPropagation() {}, currentTarget: { dataset: { fieldId: "y" } } })
    const overlay = ctrl.fieldsContainerTarget.querySelector(".dependency-overlay")
    expect(overlay.querySelectorAll("path").length).toBe(1)
    expect(overlay.querySelector("path").getAttribute("stroke")).toBe("#a855f7")
  })

  it("skips a connection whose endpoint element is missing from the DOM", () => {
    // Only "x" is rendered — "y" (the connection's `from`) is missing, so the
    // overlay is created (connections.length > 0) but no path is appended.
    ctrl.fieldsContainerTarget.innerHTML = '<div data-field-id="x"></div>'
    fm.showDependencyLines({ stopPropagation() {}, currentTarget: { dataset: { fieldId: "x" } } })
    const overlay = ctrl.fieldsContainerTarget.querySelector(".dependency-overlay")
    expect(overlay).not.toBeNull()
    expect(overlay.querySelectorAll("path").length).toBe(0)
  })

  it("tolerates a configuration with no `rules` key when opening the overlay", () => {
    ctrl = makeCtrl({ configuration: {} })
    document.body.innerHTML = '<div id="canvas"></div>'
    ctrl.fieldsContainerTarget = document.getElementById("canvas")
    fm = new FieldManager(ctrl)
    expect(() => fm.showDependencyLines({ stopPropagation() {}, currentTarget: { dataset: { fieldId: "x" } } })).not.toThrow()
    expect(ctrl.fieldsContainerTarget.querySelector(".dependency-overlay")).toBeNull()
  })

  it("tolerates rules missing `actions`/`conditions` keys (optional-chaining fallbacks)", () => {
    ctrl = makeCtrl({
      configuration: {
        rules: [
          {}, // no actions, no conditions at all
          { actions: [{ target_id: "x" }] }, // has actions, no conditions
          { conditions: { groups: [{}] } }, // groups present, item has no `items`
        ],
        calculations: [], pages: [], theme: {},
      },
    })
    document.body.innerHTML = '<div id="canvas"><div data-field-id="x"></div></div>'
    ctrl.fieldsContainerTarget = document.getElementById("canvas")
    fm = new FieldManager(ctrl)
    // Doesn't throw despite the ragged rule shapes; no connections resolve for "x".
    expect(() => fm.showDependencyLines({ stopPropagation() {}, currentTarget: { dataset: { fieldId: "x" } } })).not.toThrow()
    expect(ctrl.fieldsContainerTarget.querySelector(".dependency-overlay")).toBeNull()
  })

  describe("document-level dismiss handlers", () => {
    beforeEach(() => {
      ctrl.fieldsContainerTarget.innerHTML =
        '<div data-field-id="y"></div><div data-field-id="x"></div>'
      fm.showDependencyLines({ stopPropagation() {}, currentTarget: { dataset: { fieldId: "x" } } })
    })

    afterEach(() => {
      // Prevent listeners from leaking into later tests when the overlay
      // wasn't dismissed by the test itself (e.g. the "other keys" case).
      fm.cleanup()
    })

    it("ignores clicks inside the overlay itself", () => {
      const path = ctrl.fieldsContainerTarget.querySelector(".dependency-overlay path")
      path.dispatchEvent(new Event("click", { bubbles: true }))
      expect(ctrl.fieldsContainerTarget.querySelector(".dependency-overlay")).not.toBeNull()
    })

    it("ignores clicks on the badge that opened it", () => {
      const badge = document.createElement("span")
      badge.setAttribute("data-action", "click->page-builder#showDependencyLines")
      document.body.appendChild(badge)
      badge.dispatchEvent(new Event("click", { bubbles: true }))
      expect(ctrl.fieldsContainerTarget.querySelector(".dependency-overlay")).not.toBeNull()
    })

    it("removes the overlay on an outside click", () => {
      document.body.dispatchEvent(new Event("click", { bubbles: true }))
      expect(ctrl.fieldsContainerTarget.querySelector(".dependency-overlay")).toBeNull()
    })

    it("removes the overlay on Escape", () => {
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }))
      expect(ctrl.fieldsContainerTarget.querySelector(".dependency-overlay")).toBeNull()
    })

    it("ignores other keys", () => {
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }))
      expect(ctrl.fieldsContainerTarget.querySelector(".dependency-overlay")).not.toBeNull()
    })
  })

  it("_removeDependencyOverlay and cleanup remove the overlay", () => {
    ctrl.fieldsContainerTarget.innerHTML =
      '<div data-field-id="y"></div><div data-field-id="x"></div>'
    fm.showDependencyLines({ stopPropagation() {}, currentTarget: { dataset: { fieldId: "x" } } })
    expect(ctrl.fieldsContainerTarget.querySelector(".dependency-overlay")).not.toBeNull()
    fm.cleanup()
    expect(ctrl.fieldsContainerTarget.querySelector(".dependency-overlay")).toBeNull()
  })
})
