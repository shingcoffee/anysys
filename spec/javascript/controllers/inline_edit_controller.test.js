import { describe, it, expect, beforeEach } from "vitest"
import Controller from "controllers/inline_edit_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = `
  <div data-controller="inline-edit">
    <div data-inline-edit-target="display" class="flex" data-role="display">shown</div>
    <div data-inline-edit-target="form" class="hidden" data-role="form">
      <input data-inline-edit-target="input" data-role="input" />
    </div>
  </div>`

const q = (el, role) => el.querySelector(`[data-role='${role}']`)

describe("inline-edit controller", () => {
  let element, controller
  beforeEach(async () => {
    const m = await mountController("inline-edit", Controller, html)
    element = m.element
    controller = controllerFor(m.application, element, "inline-edit")
  })

  it("edit() hides the display, shows the form, focuses the input", () => {
    controller.edit()
    expect(q(element, "display").classList.contains("hidden")).toBe(true)
    expect(q(element, "form").classList.contains("hidden")).toBe(false)
    expect(q(element, "form").classList.contains("flex")).toBe(true)
    expect(document.activeElement).toBe(q(element, "input"))
  })

  it("cancel() reverts to the display state", () => {
    controller.edit()
    controller.cancel()
    expect(q(element, "form").classList.contains("hidden")).toBe(true)
    expect(q(element, "display").classList.contains("hidden")).toBe(false)
    expect(q(element, "display").classList.contains("flex")).toBe(true)
  })
})
