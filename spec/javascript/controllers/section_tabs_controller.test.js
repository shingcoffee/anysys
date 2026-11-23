import { describe, it, expect, beforeEach } from "vitest"
import Controller from "controllers/section_tabs_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html =
  `<div data-controller="section-tabs">` +
  `<button data-action="click->section-tabs#toggle">Toggle</button>` +
  `<div data-section-tabs-target="panel" class="hidden">Panel</div>` +
  `</div>`

describe("section-tabs controller", () => {
  let application, element, ctrl
  beforeEach(async () => {
    ;({ application, element } = await mountController("section-tabs", Controller, html))
    ctrl = controllerFor(application, element, "section-tabs")
  })

  it("toggles the panel's hidden class each call", () => {
    const panel = element.querySelector("[data-section-tabs-target='panel']")
    expect(panel.classList.contains("hidden")).toBe(true)
    ctrl.toggle()
    expect(panel.classList.contains("hidden")).toBe(false)
    ctrl.toggle()
    expect(panel.classList.contains("hidden")).toBe(true)
  })
})
