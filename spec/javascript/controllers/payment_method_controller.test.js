import { describe, it, expect } from "vitest"
import Controller from "controllers/payment_method_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

// payment_method is a lightweight namespace controller — it only declares a
// `removeButton` target and holds no behavior (confirm-before-remove is done by
// Turbo's data-turbo-confirm on the button_to forms). We verify it mounts and
// exposes the target collection.
describe("payment-method controller", () => {
  it("mounts and exposes removeButton targets", async () => {
    const html = `
      <div data-controller="payment-method">
        <form data-payment-method-target="removeButton"></form>
        <form data-payment-method-target="removeButton"></form>
      </div>`
    const { application, element } = await mountController("payment-method", Controller, html)
    const ctrl = controllerFor(application, element, "payment-method")
    expect(ctrl).toBeTruthy()
    expect(ctrl.removeButtonTargets.length).toBe(2)
  })

  it("mounts with no removeButton targets", async () => {
    const { application, element } = await mountController(
      "payment-method", Controller, `<div data-controller="payment-method"></div>`)
    const ctrl = controllerFor(application, element, "payment-method")
    expect(ctrl.hasRemoveButtonTarget).toBe(false)
  })
})
