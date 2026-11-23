import { describe, it, expect, vi, beforeEach } from "vitest"
import Controller from "controllers/condition_builder_controller"
import { mountController, controllerFor, click } from "../support/stimulus.js"

const rule = (field = "name", op = "==", value = "x") => `
  <div data-condition-builder-target="rule">
    <select data-condition-builder-role="field"><option value="${field}" selected>${field}</option><option value=""></option></select>
    <select data-condition-builder-role="operator">
      <option value="==" ${op === "==" ? "selected" : ""}>==</option>
      <option value="blank?" ${op === "blank?" ? "selected" : ""}>blank?</option>
    </select>
    <input data-condition-builder-role="value" value="${value}">
  </div>`

const html = (outputValue = "") => `
  <div data-controller="condition-builder">
    <div role="group">
      <button data-action="click->condition-builder#setOperator"
              data-condition-builder-operator-param="AND"
              class="bg-white text-gray-700 border-gray-300 hover:bg-gray-50">AND</button>
      <button data-action="click->condition-builder#setOperator"
              data-condition-builder-operator-param="OR"
              class="bg-white text-gray-700 border-gray-300 hover:bg-gray-50">OR</button>
    </div>
    <div data-condition-builder-target="rulesList">${rule()}</div>
    <template data-condition-builder-target="ruleTemplate">${rule("email", "==", "")}</template>
    <input type="hidden" data-condition-builder-target="output" value='${outputValue}'>
  </div>`

const ruleCount = (el) => el.querySelectorAll("[data-condition-builder-target='rule']").length
const output = (el) => el.querySelector("[data-condition-builder-target='output']")

describe("condition-builder controller", () => {
  it("syncs the operator from the output value on connect", async () => {
    const { application, element } = await mountController(
      "condition-builder", Controller, html('{"operator":"OR","rules":[]}'))
    const ctrl = controllerFor(application, element, "condition-builder")
    expect(ctrl.currentOperator).toBe("OR")
  })

  it("defaults the operator to AND when output is empty/invalid", async () => {
    const { application, element } = await mountController("condition-builder", Controller, html("not-json"))
    const ctrl = controllerFor(application, element, "condition-builder")
    expect(ctrl.currentOperator).toBe("AND")
  })

  it("serialize() writes a JSON condition and dispatches 'changed'", async () => {
    const { application, element } = await mountController("condition-builder", Controller, html())
    const ctrl = controllerFor(application, element, "condition-builder")
    const changed = vi.fn()
    element.addEventListener("condition-builder:changed", changed)
    ctrl.serialize()
    const parsed = JSON.parse(output(element).value)
    expect(parsed.operator).toBe("AND")
    expect(parsed.rules).toEqual([{ field: "name", op: "==", value: "x" }])
    expect(changed).toHaveBeenCalledOnce()
    expect(changed.mock.calls[0][0].detail.condition.rules).toHaveLength(1)
  })

  it("serialize() drops rules with a blank field", async () => {
    const { application, element } = await mountController("condition-builder", Controller, html())
    const ctrl = controllerFor(application, element, "condition-builder")
    element.querySelector("[data-condition-builder-role='field']").value = ""
    ctrl.serialize()
    expect(JSON.parse(output(element).value).rules).toEqual([])
  })

  it("addRule() clones the template into the rules list", async () => {
    const { application, element } = await mountController("condition-builder", Controller, html())
    const ctrl = controllerFor(application, element, "condition-builder")
    expect(ruleCount(element)).toBe(1)
    ctrl.addRule()
    expect(ruleCount(element)).toBe(2)
  })

  it("removeRule() removes the enclosing rule", async () => {
    const { application, element } = await mountController("condition-builder", Controller, html())
    const ctrl = controllerFor(application, element, "condition-builder")
    const valueInput = element.querySelector("[data-condition-builder-role='value']")
    ctrl.removeRule({ target: valueInput })
    expect(ruleCount(element)).toBe(0)
  })

  it("setOperator() updates currentOperator and restyles the chosen button", async () => {
    const { application, element } = await mountController("condition-builder", Controller, html())
    const ctrl = controllerFor(application, element, "condition-builder")
    const orBtn = element.querySelectorAll("[role='group'] button")[1]
    click(orBtn)
    expect(ctrl.currentOperator).toBe("OR")
    expect(orBtn.className).toContain("bg-indigo-600 text-white border-indigo-600")
  })

  it("updateRule() hides the value input for no-value operators", async () => {
    const { application, element } = await mountController("condition-builder", Controller, html())
    const ctrl = controllerFor(application, element, "condition-builder")
    element.querySelector("[data-condition-builder-role='operator']").value = "blank?"
    ctrl.updateRule()
    expect(element.querySelector("[data-condition-builder-role='value']").style.display).toBe("none")
  })

  it("updateRule() shows the value input for operators that need a value", async () => {
    const { application, element } = await mountController("condition-builder", Controller, html())
    const ctrl = controllerFor(application, element, "condition-builder")
    // Default rule's operator select is "==" which isn't in noValueOps.
    ctrl.updateRule()
    expect(element.querySelector("[data-condition-builder-role='value']").style.display).toBe("")
  })

  it("addRule() is a no-op when there is no ruleTemplate target", async () => {
    const noTemplateHtml = `
      <div data-controller="condition-builder">
        <div data-condition-builder-target="rulesList">${rule()}</div>
        <input type="hidden" data-condition-builder-target="output" value="">
      </div>`
    const { application, element } = await mountController("condition-builder", Controller, noTemplateHtml)
    const ctrl = controllerFor(application, element, "condition-builder")
    expect(ruleCount(element)).toBe(1)
    ctrl.addRule()
    expect(ruleCount(element)).toBe(1)
  })

  it("serialize() falls back operator to '==' when a rule has no operator role element", async () => {
    const noOperatorRuleHtml = `
      <div data-controller="condition-builder">
        <div data-condition-builder-target="rulesList">
          <div data-condition-builder-target="rule">
            <select data-condition-builder-role="field"><option value="name" selected>name</option></select>
            <input data-condition-builder-role="value" value="x">
          </div>
        </div>
        <input type="hidden" data-condition-builder-target="output" value="">
      </div>`
    const { application, element } = await mountController("condition-builder", Controller, noOperatorRuleHtml)
    const ctrl = controllerFor(application, element, "condition-builder")
    ctrl.serialize()
    expect(JSON.parse(output(element).value).rules).toEqual([{ field: "name", op: "==", value: "x" }])
  })

  it("syncFromOutput() is a no-op when there is no output target", async () => {
    const noOutputHtml = `
      <div data-controller="condition-builder">
        <div role="group"></div>
        <div data-condition-builder-target="rulesList">${rule()}</div>
        <template data-condition-builder-target="ruleTemplate">${rule("email", "==", "")}</template>
      </div>`
    const { application, element } = await mountController("condition-builder", Controller, noOutputHtml)
    const ctrl = controllerFor(application, element, "condition-builder")
    // connect() called syncFromOutput(), which returned early leaving currentOperator unset.
    expect(ctrl.currentOperator).toBeUndefined()
    // serialize()'s `this.currentOperator || "AND"` fallback still produces "AND", and since
    // there's no output target, serialize() just skips writing/dispatching a change on it.
    expect(() => ctrl.serialize()).not.toThrow()
  })
})
