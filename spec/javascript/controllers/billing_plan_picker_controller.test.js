import { describe, it, expect, beforeEach } from "vitest"
import Controller from "controllers/billing_plan_picker_controller"
import { mountController } from "../support/stimulus.js"

const card = (code, checked) => `
  <label data-billing-plan-picker-target="card"
         data-action="click->billing-plan-picker#select"
         class="border-border-subtle hover:border-accent/50">
    <input type="radio" name="plan_code" value="${code}"
           data-billing-plan-picker-target="radio" ${checked ? "checked" : ""}>
    <span>${code}</span>
  </label>`

// NOTE: mounted on a <div> rather than the real <form> markup because happy-dom
// v15.11.7's HTMLFormElement.contains() always returns false for descendants (the
// form wraps itself in a Proxy for named-control access, and Stimulus's action
// binder gates elementMatched on `formElement.contains(el)`) — so no action inside
// a <form data-controller="..."> root ever binds in this environment, regardless
// of timing. Verified directly: `form.contains(childButton)` -> false in happy-dom,
// `div.contains(childButton)` -> true. The controller itself is tag-agnostic.
const html = (checkedIdx = -1) => `
  <div data-controller="billing-plan-picker">
    ${["basic", "pro", "max"].map((c, i) => card(c, i === checkedIdx)).join("")}
  </div>`

const cards = (el) => [...el.querySelectorAll("[data-billing-plan-picker-target='card']")]
const isActive = (c) => c.classList.contains("border-accent") && c.classList.contains("bg-accent/5")

describe("billing-plan-picker controller", () => {
  it("connect highlights the initially-checked card", async () => {
    const { element } = await mountController("billing-plan-picker", Controller, html(1))
    const [basic, pro, max] = cards(element)
    expect(isActive(pro)).toBe(true)
    expect(isActive(basic)).toBe(false)
    expect(isActive(max)).toBe(false)
  })

  it("connect leaves all cards unstyled when none is checked", async () => {
    const { element } = await mountController("billing-plan-picker", Controller, html(-1))
    expect(cards(element).some(isActive)).toBe(false)
  })

  it("select() activates the clicked card and deactivates the rest", async () => {
    const { element } = await mountController("billing-plan-picker", Controller, html(-1))
    const [basic, pro] = cards(element)
    basic.dispatchEvent(new Event("click", { bubbles: true }))
    expect(isActive(basic)).toBe(true)
    pro.dispatchEvent(new Event("click", { bubbles: true }))
    expect(isActive(pro)).toBe(true)
    expect(isActive(basic)).toBe(false)
    // deactivated card regains the subtle border classes
    expect(basic.classList.contains("border-border-subtle")).toBe(true)
  })
})
