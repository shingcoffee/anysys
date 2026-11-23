import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/wizard_controller"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

// Three-step wizard. Step panels + indicator targets. No geometry involved —
// everything is class/attribute toggling driven by the currentStep value.
const stepPanel = (i, required = false) =>
  `<div data-wizard-target="step">` +
  (required ? `<div><input required data-field="${i}"></div>` : `Step ${i}`) +
  `</div>`

const badge = (i) => `<div data-wizard-target="stepBadge" data-step-index="${i}"></div>`
const num = (i) => `<span data-wizard-target="stepNumber" data-step-index="${i}"></span>`
const check = (i) => `<span data-wizard-target="stepCheck" data-step-index="${i}"></span>`
const label = (i) => `<span data-wizard-target="stepLabel" data-step-index="${i}"></span>`
const connector = (i) => `<div data-wizard-target="stepConnector" data-step-index="${i}"></div>`
const indicator = (n) => `<button data-wizard-target="stepIndicator" data-step="${n}" data-action="click->wizard#goToStep"></button>`

const html = ({ total = 3, requiredStep = null } = {}) =>
  `<div data-controller="wizard" data-wizard-total-steps-value="${total}" data-wizard-current-step-value="1">` +
  Array.from({ length: total }, (_, i) => stepPanel(i + 1, requiredStep === i + 1)).join("") +
  Array.from({ length: total }, (_, i) => badge(i) + num(i) + check(i) + label(i) + connector(i) + indicator(i + 1)).join("") +
  `<button data-wizard-target="cancelButton">Cancel</button>` +
  `<button data-wizard-target="prevButton">Prev</button>` +
  `<button data-wizard-target="nextButton">Next</button>` +
  `<button data-wizard-target="submitButton">Submit</button>` +
  `<span data-wizard-target="stepCounter"></span>` +
  `</div>`

const visiblePanels = (el) =>
  [...el.querySelectorAll("[data-wizard-target='step']")].map((s) => !s.classList.contains("hidden"))
const isHidden = (el, name) => el.querySelector(`[data-wizard-target='${name}']`).classList.contains("hidden")

describe("wizard controller", () => {
  let application, element, ctrl
  beforeEach(async () => {
    ;({ application, element } = await mountController("wizard", Controller, html()))
    ctrl = controllerFor(application, element, "wizard")
  })

  it("renders step 1 as active on connect with Cancel + Next visible", () => {
    expect(visiblePanels(element)).toEqual([true, false, false])
    expect(isHidden(element, "cancelButton")).toBe(false)
    expect(isHidden(element, "prevButton")).toBe(true)
    expect(isHidden(element, "nextButton")).toBe(false)
    expect(isHidden(element, "submitButton")).toBe(true)
    expect(element.querySelector("[data-wizard-target='stepCounter']").textContent).toBe("Step 1 of 3")
  })

  it("next() advances the step and shows Previous", async () => {
    ctrl.next()
    await tick()
    expect(ctrl.currentStepValue).toBe(2)
    expect(visiblePanels(element)).toEqual([false, true, false])
    expect(isHidden(element, "prevButton")).toBe(false)
    expect(isHidden(element, "cancelButton")).toBe(true)
  })

  it("shows Submit (not Next) on the last step", async () => {
    ctrl.next(); ctrl.next()
    await tick()
    expect(ctrl.currentStepValue).toBe(3)
    expect(isHidden(element, "nextButton")).toBe(true)
    expect(isHidden(element, "submitButton")).toBe(false)
  })

  it("shows every submit button together on the last step only", async () => {
    element.insertAdjacentHTML("beforeend", `<span class="hidden" data-wizard-target="submitButton"><button>Again</button></span>`)
    await tick()
    const submits = () => [...element.querySelectorAll("[data-wizard-target='submitButton']")].map((el) => el.classList.contains("hidden"))
    ctrl.render()
    expect(submits()).toEqual([true, true])

    ctrl.next(); ctrl.next()
    await tick()
    expect(submits()).toEqual([false, false])
  })

  it("previous() does not go below step 1", () => {
    ctrl.previous()
    expect(ctrl.currentStepValue).toBe(1)
  })

  it("goToStep only navigates to already-completed (earlier) steps", () => {
    ctrl.next(); ctrl.next() // now on step 3
    ctrl.goToStep({ currentTarget: { dataset: { step: "1" } } })
    expect(ctrl.currentStepValue).toBe(1)
    // cannot jump forward past current
    ctrl.goToStep({ currentTarget: { dataset: { step: "3" } } })
    expect(ctrl.currentStepValue).toBe(1)
  })

  it("step indicators mark past/current badge states", async () => {
    ctrl.next() // step 2
    await tick()
    const badge0 = element.querySelector("[data-wizard-target='stepBadge'][data-step-index='0']")
    const badge1 = element.querySelector("[data-wizard-target='stepBadge'][data-step-index='1']")
    const badge2 = element.querySelector("[data-wizard-target='stepBadge'][data-step-index='2']")
    expect(badge0.classList.contains("bg-indigo-600")).toBe(true) // completed
    expect(badge1.classList.contains("ring-4")).toBe(true)        // current
    expect(badge2.classList.contains("bg-gray-100")).toBe(true)   // upcoming
    // indicator disabled state: only earlier steps clickable
    const ind1 = element.querySelector("[data-wizard-target='stepIndicator'][data-step='1']")
    const ind2 = element.querySelector("[data-wizard-target='stepIndicator'][data-step='2']")
    expect(ind1.disabled).toBe(false)
    expect(ind2.disabled).toBe(true)
  })

  it("validateCurrentStep blocks next() when a required field is empty and injects an error", async () => {
    const { application: app, element: el } = await mountController("wizard", Controller, html({ requiredStep: 1 }))
    const c = controllerFor(app, el, "wizard")
    c.next()
    expect(c.currentStepValue).toBe(1) // blocked
    const input = el.querySelector("input[required]")
    expect(input.classList.contains("border-red-500")).toBe(true)
    expect(el.querySelector(".error-message")).not.toBeNull()

    // Fill it and retry
    input.value = "ok"
    c.next()
    expect(c.currentStepValue).toBe(2)
    expect(el.querySelector(".error-message")).toBeNull()
  })

  it("reset() returns to step 1 and clears validation styling", async () => {
    const { application: app, element: el } = await mountController("wizard", Controller, html({ requiredStep: 1 }))
    const c = controllerFor(app, el, "wizard")
    c.next() // triggers error on step 1
    c.reset()
    expect(c.currentStepValue).toBe(1)
    expect(el.querySelector(".error-message")).toBeNull()
    expect(el.querySelector("input[required]").classList.contains("border-red-500")).toBe(false)
  })

  it("respects a custom accent color in indicator classes", async () => {
    const custom = html().replace('data-controller="wizard"', 'data-controller="wizard" data-wizard-accent-color-value="bg-emerald-600"')
    const { application: app, element: el } = await mountController("wizard", Controller, custom)
    const c = controllerFor(app, el, "wizard")
    c.next()
    const badge0 = el.querySelector("[data-wizard-target='stepBadge'][data-step-index='0']")
    expect(badge0.classList.contains("bg-emerald-600")).toBe(true)
  })

  it("previous() decrements when past step 1", async () => {
    ctrl.next() // step 2
    await tick()
    ctrl.previous()
    expect(ctrl.currentStepValue).toBe(1)
  })

  describe("cancel()", () => {
    let originalLocation
    beforeEach(() => {
      originalLocation = Object.getOwnPropertyDescriptor(window, "location")
    })
    afterEach(() => {
      if (originalLocation) Object.defineProperty(window, "location", originalLocation)
    })

    it("navigates to the configured cancelUrl", async () => {
      const hrefs = []
      Object.defineProperty(window, "location", {
        configurable: true,
        value: { set href(v) { hrefs.push(v) } }
      })
      const custom = html().replace('data-controller="wizard"', 'data-controller="wizard" data-wizard-cancel-url-value="/back-here"')
      const { application: app, element: el } = await mountController("wizard", Controller, custom)
      const c = controllerFor(app, el, "wizard")
      c.cancel()
      expect(hrefs).toEqual(["/back-here"])
    })
  })

  it("_accentBg falls back to the default when accent color is blank", async () => {
    const custom = html().replace('data-controller="wizard"', 'data-controller="wizard" data-wizard-accent-color-value=""')
    const { application: app, element: el } = await mountController("wizard", Controller, custom)
    const c = controllerFor(app, el, "wizard")
    expect(c._accentBg()).toBe("bg-indigo-600")
    expect(c._accentText()).toBe("text-indigo-600")
  })

  it("validateCurrentStep returns true when there is no panel for the current step", () => {
    ctrl.currentStepValue = 99 // out of range — no matching stepTarget
    expect(ctrl.validateCurrentStep()).toBe(true)
  })
})
