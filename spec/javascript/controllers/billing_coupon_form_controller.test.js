import { describe, it, expect } from "vitest"
import Controller from "controllers/billing_coupon_form_controller"
import { mountController } from "../support/stimulus.js"

// NOTE: mounted on a <div> rather than the real <form> markup because happy-dom
// v15.11.7's HTMLFormElement.contains() always returns false for descendants (the
// form wraps itself in a Proxy for named-control access, and Stimulus's action
// binder gates elementMatched on `formElement.contains(el)`) — so no action inside
// a <form data-controller="..."> root ever binds in this environment, regardless
// of timing. Verified directly: `form.contains(childButton)` -> false in happy-dom,
// `div.contains(childButton)` -> true. The controller itself is tag-agnostic.
const html = (discountType, duration) => `
  <div data-controller="billing-coupon-form"
        data-billing-coupon-form-discount-type-value="${discountType}"
        data-billing-coupon-form-duration-value="${duration}">
    <div data-billing-coupon-form-target="percentField">%</div>
    <div data-billing-coupon-form-target="fixedField">$</div>
    <div data-billing-coupon-form-target="cyclesField">cycles</div>
    <select data-action="change->billing-coupon-form#discountTypeChanged" data-role="discount">
      <option value="percent">percent</option>
      <option value="fixed">fixed</option>
    </select>
    <select data-action="change->billing-coupon-form#durationChanged" data-role="duration">
      <option value="once">once</option>
      <option value="repeating">repeating</option>
      <option value="forever">forever</option>
    </select>
  </div>`

const hidden = (el, sel) => el.querySelector(sel).classList.contains("hidden")

describe("billing-coupon-form controller", () => {
  it("on connect with percent+repeating: shows percent, hides fixed, shows cycles", async () => {
    const { element } = await mountController("billing-coupon-form", Controller, html("percent", "repeating"))
    expect(hidden(element, "[data-billing-coupon-form-target='percentField']")).toBe(false)
    expect(hidden(element, "[data-billing-coupon-form-target='fixedField']")).toBe(true)
    expect(hidden(element, "[data-billing-coupon-form-target='cyclesField']")).toBe(false)
  })

  it("on connect with fixed+once: hides percent, shows fixed, hides cycles", async () => {
    const { element } = await mountController("billing-coupon-form", Controller, html("fixed", "once"))
    expect(hidden(element, "[data-billing-coupon-form-target='percentField']")).toBe(true)
    expect(hidden(element, "[data-billing-coupon-form-target='fixedField']")).toBe(false)
    expect(hidden(element, "[data-billing-coupon-form-target='cyclesField']")).toBe(true)
  })

  it("discountTypeChanged toggles percent/fixed field visibility", async () => {
    const { element } = await mountController("billing-coupon-form", Controller, html("percent", "once"))
    const select = element.querySelector("[data-role='discount']")
    select.value = "fixed"
    select.dispatchEvent(new Event("change", { bubbles: true }))
    expect(hidden(element, "[data-billing-coupon-form-target='percentField']")).toBe(true)
    expect(hidden(element, "[data-billing-coupon-form-target='fixedField']")).toBe(false)
  })

  it("durationChanged shows cycles only for 'repeating'", async () => {
    const { element } = await mountController("billing-coupon-form", Controller, html("percent", "once"))
    const select = element.querySelector("[data-role='duration']")
    select.value = "repeating"
    select.dispatchEvent(new Event("change", { bubbles: true }))
    expect(hidden(element, "[data-billing-coupon-form-target='cyclesField']")).toBe(false)
    select.value = "forever"
    select.dispatchEvent(new Event("change", { bubbles: true }))
    expect(hidden(element, "[data-billing-coupon-form-target='cyclesField']")).toBe(true)
  })
})
