import { describe, it, expect, vi, afterEach } from "vitest"
import Controller from "controllers/billing_plan_compare_controller"
import { mountController } from "../support/stimulus.js"

const html = `
  <div data-controller="billing-plan-compare">
    <form data-action="submit->billing-plan-compare#confirmSwitch"
          data-billing-plan-compare-plan-name-param="Pro Monthly">
      <button type="submit">Switch</button>
    </form>
  </div>`

const submit = (form) => {
  const evt = new Event("submit", { bubbles: true, cancelable: true })
  form.dispatchEvent(evt)
  return evt
}

describe("billing-plan-compare controller", () => {
  afterEach(() => vi.restoreAllMocks())

  it("confirming lets the submit proceed (not prevented)", async () => {
    vi.spyOn(window, "confirm").mockReturnValue(true)
    const { element } = await mountController("billing-plan-compare", Controller, html)
    const evt = submit(element.querySelector("form"))
    expect(window.confirm).toHaveBeenCalledWith(expect.stringContaining("Pro Monthly"))
    expect(evt.defaultPrevented).toBe(false)
  })

  it("cancelling prevents the submit", async () => {
    vi.spyOn(window, "confirm").mockReturnValue(false)
    const { element } = await mountController("billing-plan-compare", Controller, html)
    const evt = submit(element.querySelector("form"))
    expect(evt.defaultPrevented).toBe(true)
  })

  it("falls back to a generic label when no plan-name param is present", async () => {
    vi.spyOn(window, "confirm").mockReturnValue(true)
    const noParam = `
      <div data-controller="billing-plan-compare">
        <form data-action="submit->billing-plan-compare#confirmSwitch"><button>Go</button></form>
      </div>`
    const { element } = await mountController("billing-plan-compare", Controller, noParam)
    submit(element.querySelector("form"))
    expect(window.confirm).toHaveBeenCalledWith(expect.stringContaining("this plan"))
  })
})
