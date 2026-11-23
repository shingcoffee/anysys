import { describe, it, expect, beforeEach, vi } from "vitest"
import Controller from "controllers/condition_runtime_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const rulesJson = JSON.stringify([
  {
    enabled: true,
    conditions: { logic: "all", groups: [{ logic: "all", items: [{ field_id: "a", operator: "equals", value: "show" }] }] },
    actions: [{ type: "hide_field", target_id: "b" }],
  },
  {
    enabled: false, // disabled rule is skipped
    conditions: { logic: "all", groups: [] },
    actions: [{ type: "hide_field", target_id: "c" }],
  },
])

const html = (rules = rulesJson, calcs = "[]") => `
  <form data-controller="condition-runtime"
        data-condition-runtime-rules-value='${rules}'
        data-condition-runtime-calculations-value='${calcs}'>
    <div data-field-id="a"><input type="text" value="show"></div>
    <div data-field-id="b"><input type="text" value=""></div>
    <div data-field-id="c"><input type="checkbox" checked></div>
    <div data-field-id="tot"><input type="text" value=""></div>
  </form>`

const wrap = (el, id) => el.querySelector(`[data-field-id='${id}']`)
const input = (el, id) => wrap(el, id).querySelector("input")

describe("condition-runtime controller", () => {
  let application, element, ctrl
  beforeEach(async () => {
    ;({ application, element } = await mountController("condition-runtime", Controller, html()))
    ctrl = controllerFor(application, element, "condition-runtime")
  })

  it("applies matching rules on connect (hide_field when condition met)", () => {
    // field a == "show" matched the enabled rule -> b is hidden
    expect(wrap(element, "b").classList.contains("hidden")).toBe(true)
    expect(wrap(element, "b").getAttribute("aria-hidden")).toBe("true")
    // disabled rule was skipped -> c untouched
    expect(wrap(element, "c").classList.contains("hidden")).toBe(false)
  })

  it("collectFieldValues reads text and checkbox inputs", () => {
    const values = ctrl.collectFieldValues()
    expect(values.a).toBe("show")
    expect(values.c).toBe(true)
  })

  it("executeAction show_field toggles visibility with aria-hidden", () => {
    ctrl.executeAction({ type: "show_field", target_id: "b" }, false)
    expect(wrap(element, "b").classList.contains("hidden")).toBe(true)
    ctrl.executeAction({ type: "show_field", target_id: "b" }, true)
    expect(wrap(element, "b").classList.contains("hidden")).toBe(false)
  })

  it("executeAction enable/disable_field toggles the input disabled state", () => {
    ctrl.executeAction({ type: "disable_field", target_id: "b" }, true)
    expect(input(element, "b").disabled).toBe(true)
    ctrl.executeAction({ type: "enable_field", target_id: "b" }, true)
    expect(input(element, "b").disabled).toBe(false)
  })

  it("executeAction set_value writes into the input when applied", () => {
    ctrl.executeAction({ type: "set_value", target_id: "b", value: "hi" }, true)
    expect(input(element, "b").value).toBe("hi")
  })

  it("executeAction set_value does not re-dispatch change when the value is unchanged", () => {
    ctrl.executeAction({ type: "set_value", target_id: "b", value: "hi" }, true)
    let changes = 0
    input(element, "b").addEventListener("change", () => { changes += 1 })
    ctrl.executeAction({ type: "set_value", target_id: "b", value: "hi" }, true)
    expect(changes).toBe(0)
  })

  it("executeAction is a no-op for an unknown target", () => {
    expect(() => ctrl.executeAction({ type: "show_field", target_id: "nope" }, true)).not.toThrow()
  })

  it("applyCalculations formats a currency result with prefix", () => {
    ctrl.applyCalculations({ x: 2, y: 3 })
    // no calc targets tot yet; drive one explicitly
    ctrl.calculationsValue = [{ formula: "{x} * {y}", target_field_id: "tot", format: { type: "currency", decimals: 2, prefix: "$" } }]
    ctrl.applyCalculations({ x: 2, y: 3 })
    expect(input(element, "tot").value).toBe("$6.00")
  })

  it("applyCalculations formats a percent result with suffix rules", () => {
    ctrl.calculationsValue = [{ formula: "{x}", target_field_id: "tot", format: { type: "percent", decimals: 0 } }]
    ctrl.applyCalculations({ x: 0.25 })
    expect(input(element, "tot").value).toBe("25%")
  })

  it("executeAction set_required toggles required + aria-required when applied", () => {
    ctrl.executeAction({ type: "set_required", target_id: "b", value: true }, true)
    expect(input(element, "b").required).toBe(true)
    expect(input(element, "b").getAttribute("aria-required")).toBe("true")
  })

  it("executeAction set_required is a no-op when not applied", () => {
    ctrl.executeAction({ type: "set_required", target_id: "b", value: true }, false)
    expect(input(element, "b").required).toBe(false)
  })

  it("executeAction set_required restores a field that started required", () => {
    input(element, "b").required = true
    ctrl.executeAction({ type: "set_required", target_id: "b", value: false }, true)
    expect(input(element, "b").required).toBe(false)
    ctrl.executeAction({ type: "set_required", target_id: "b", value: false }, false)
    expect(input(element, "b").required).toBe(true)
    expect(input(element, "b").getAttribute("aria-required")).toBe("true")
  })

  it("executeAction set_required is a no-op when the target has no input", async () => {
    const extra = `
      <form data-controller="condition-runtime"
            data-condition-runtime-rules-value='[]'
            data-condition-runtime-calculations-value='[]'>
        <div data-field-id="empty"></div>
      </form>`
    const m = await mountController("condition-runtime", Controller, extra)
    const c = controllerFor(m.application, m.element, "condition-runtime")
    expect(() => c.executeAction({ type: "set_required", target_id: "empty", value: true }, true)).not.toThrow()
  })

  it("executeAction set_value treats a missing value as blank", () => {
    input(element, "b").value = "x"
    ctrl.executeAction({ type: "set_value", target_id: "b", value: null }, true)
    expect(input(element, "b").value).toBe("")
  })

  it("applyCalculations writes the raw result when there is no format", () => {
    ctrl.calculationsValue = [{ formula: "{x}", target_field_id: "tot" }]
    ctrl.applyCalculations({ x: 5 })
    expect(input(element, "tot").value).toBe("5")
  })

  it("applyCalculations defaults currency decimals to 2", () => {
    ctrl.calculationsValue = [{ formula: "{x}", target_field_id: "tot", format: { type: "currency" } }]
    ctrl.applyCalculations({ x: 3 })
    expect(input(element, "tot").value).toBe("3.00")
  })

  it("applyCalculations defaults percent decimals to 0", () => {
    ctrl.calculationsValue = [{ formula: "{x}", target_field_id: "tot", format: { type: "percent" } }]
    ctrl.applyCalculations({ x: 0.5 })
    expect(input(element, "tot").value).toBe("50%")
  })

  it("applyCalculations appends a suffix", () => {
    ctrl.calculationsValue = [{ formula: "{x}", target_field_id: "tot", format: { type: "number", decimals: 0, suffix: " kg" } }]
    ctrl.applyCalculations({ x: 7 })
    expect(input(element, "tot").value).toBe("7 kg")
  })

  it("re-evaluates after a debounced field change (input event)", () => {
    vi.useFakeTimers()
    try {
      const spy = vi.spyOn(ctrl, "evaluateAll")
      input(element, "a").dispatchEvent(new Event("input", { bubbles: true }))
      expect(spy).not.toHaveBeenCalled() // debounced, not yet fired
      vi.advanceTimersByTime(100)
      expect(spy).toHaveBeenCalled()
    } finally {
      vi.useRealTimers()
    }
  })

  it("disconnect unbinds the field listeners", () => {
    expect(ctrl.fieldChangeHandler).toBeDefined()
    expect(() => ctrl.disconnect()).not.toThrow()
  })

  describe("radio field collection", () => {
    const radioHtml = `
      <form data-controller="condition-runtime"
            data-condition-runtime-rules-value='[]'
            data-condition-runtime-calculations-value='[]'>
        <div data-field-id="r">
          <input type="radio" name="r" value="x">
          <input type="radio" name="r" value="y" checked>
        </div>
        <div data-field-id="empty">
          <input type="radio" name="empty" value="z">
        </div>
      </form>`

    it("reads the checked radio value, and null when none is checked", async () => {
      const m = await mountController("condition-runtime", Controller, radioHtml)
      const c = controllerFor(m.application, m.element, "condition-runtime")
      const values = c.collectFieldValues()
      expect(values.r).toBe("y")
      expect(values.empty).toBeNull()
    })
  })
})
