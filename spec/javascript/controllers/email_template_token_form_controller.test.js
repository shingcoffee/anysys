import { describe, it, expect, beforeEach } from "vitest"
import Controller from "controllers/email_template_token_form_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html =
  `<div data-controller="email-template-token-form"
        data-email-template-token-form-attributes-value='{"1":[["Name","name"],["Status","status"]],"2":[["Amount","amount"]],"3":["solo"]}'
        data-email-template-token-form-blank-label-value="Select an attribute">` +
  `<select data-email-template-token-form-target="entity">` +
  `<option value="">Select</option>` +
  `<option value="1">Contact</option>` +
  `<option value="2">Order</option>` +
  `<option value="3">Solo</option>` +
  `</select>` +
  `<select data-email-template-token-form-target="attribute"><option value="name">Name</option></select>` +
  `<input type="text" data-email-template-token-form-target="label" value="Supporter name">` +
  `</div>`

describe("email-template-token-form controller", () => {
  let application, element, ctrl

  beforeEach(async () => {
    ;({ application, element } = await mountController("email-template-token-form", Controller, html))
    ctrl = controllerFor(application, element, "email-template-token-form")
  })

  it("populates attributes when an entity is selected", () => {
    element.querySelector('[data-email-template-token-form-target="entity"]').value = "1"
    ctrl.refreshAttributes()
    const options = [...element.querySelector('[data-email-template-token-form-target="attribute"]').options]
    expect(options.map((o) => o.value)).toEqual(["", "name", "status"])
    expect(options[1].textContent).toBe("Name")
  })

  it("switches attribute options when entity changes", () => {
    const entity = element.querySelector('[data-email-template-token-form-target="entity"]')
    entity.value = "1"
    ctrl.refreshAttributes()
    entity.value = "2"
    ctrl.refreshAttributes()
    const values = [...element.querySelector('[data-email-template-token-form-target="attribute"]').options].map((o) => o.value)
    expect(values).toEqual(["", "amount"])
  })

  it("preserves the previous attribute when still available", () => {
    const entity = element.querySelector('[data-email-template-token-form-target="entity"]')
    const attribute = element.querySelector('[data-email-template-token-form-target="attribute"]')
    entity.value = "1"
    ctrl.refreshAttributes()
    attribute.value = "status"
    ctrl.refreshAttributes()
    expect(attribute.value).toBe("status")
  })

  it("supports non-array attribute entries", () => {
    const entity = element.querySelector('[data-email-template-token-form-target="entity"]')
    entity.value = "3"
    ctrl.refreshAttributes()
    const values = [...element.querySelector('[data-email-template-token-form-target="attribute"]').options].map((o) => o.value)
    expect(values).toEqual(["", "solo"])
  })

  it("no-ops when targets are missing", async () => {
    const bare = `<div data-controller="email-template-token-form"></div>`
    const { application: app, element: el } = await mountController("email-template-token-form", Controller, bare)
    const c = controllerFor(app, el, "email-template-token-form")
    expect(() => c.refreshAttributes()).not.toThrow()
  })

  it("preserves a custom display name when opening an existing field", () => {
    expect(element.querySelector('[data-email-template-token-form-target="label"]').value).toBe("Supporter name")
  })

  it("chooses the first field and suggests its name when switching entities", () => {
    const entity = element.querySelector('[data-email-template-token-form-target="entity"]')
    entity.value = "1"
    ctrl.changeEntity()
    expect(element.querySelector('[data-email-template-token-form-target="attribute"]').value).toBe("name")
    expect(element.querySelector('[data-email-template-token-form-target="label"]').value).toBe("Name")
    entity.value = "2"
    ctrl.changeEntity()
    expect(element.querySelector('[data-email-template-token-form-target="attribute"]').value).toBe("amount")
    expect(element.querySelector('[data-email-template-token-form-target="label"]').value).toBe("Amount")
  })

  it("suggests the chosen field name and clears it when no field is selected", () => {
    const entity = element.querySelector('[data-email-template-token-form-target="entity"]')
    const attribute = element.querySelector('[data-email-template-token-form-target="attribute"]')
    const label = element.querySelector('[data-email-template-token-form-target="label"]')
    entity.value = "1"
    ctrl.refreshAttributes()
    attribute.value = "status"
    ctrl.changeAttribute()
    expect(label.value).toBe("Status")
    attribute.value = ""
    ctrl.changeAttribute()
    expect(label.value).toBe("")
    entity.value = ""
    ctrl.changeEntity()
    expect(attribute.value).toBe("")
    expect(label.value).toBe("")
  })
})
