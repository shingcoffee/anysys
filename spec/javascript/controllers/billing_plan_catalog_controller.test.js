import { describe, it, expect, vi } from "vitest"
import Controller from "controllers/billing_plan_catalog_controller"
import { mountController, click, controllerFor } from "../support/stimulus.js"

const button = (interval, extra = "") =>
  `<button type="button" role="radio" data-billing-plan-catalog-target="button"` +
  ` data-action="billing-plan-catalog#selectInterval keydown->billing-plan-catalog#keydown"` +
  ` data-billing-plan-catalog-interval-param="${interval}"${extra}>${interval}</button>`

const card = (code, interval, free = false) =>
  `<li data-billing-plan-catalog-target="card" data-plan-code="${code}"` +
  ` data-interval="${interval}" data-free="${free}">${code}</li>`

const html = (intervalAttr = "") =>
  `<div data-controller="billing-plan-catalog"${intervalAttr}>` +
  `<div role="radiogroup">` +
  button("monthly") +
  button("yearly") +
  `</div>` +
  `<ul>` +
  card("free", "monthly", true) +
  card("monthly-paid", "monthly") +
  card("yearly-paid", "yearly") +
  `</ul>` +
  `</div>`

const radio = (el, interval) =>
  el.querySelector(`[data-billing-plan-catalog-interval-param="${interval}"]`)

const checked = (el, interval) =>
  radio(el, interval).getAttribute("aria-checked")

const tabIndexOf = (el, interval) => radio(el, interval).tabIndex

const visible = (el, code) =>
  !el.querySelector(`[data-plan-code="${code}"]`).classList.contains("hidden")

const press = (el, key) => {
  const event = new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true })
  const prevent = vi.spyOn(event, "preventDefault")
  el.dispatchEvent(event)
  return { event, prevent }
}

const activeClasses = (el, interval) => {
  const btn = el.querySelector(`[data-billing-plan-catalog-interval-param="${interval}"]`)
  return {
    surface: btn.classList.contains("bg-surface"),
    primary: btn.classList.contains("text-text-primary"),
    shadow: btn.classList.contains("shadow-xs"),
    secondary: btn.classList.contains("text-text-secondary"),
    hover: btn.classList.contains("hover:text-text-primary")
  }
}

describe("billing-plan-catalog controller", () => {
  it("connects with monthly by default, highlighting monthly and keeping free cards visible", async () => {
    const { element } = await mountController("billing-plan-catalog", Controller, html())
    expect(checked(element, "monthly")).toBe("true")
    expect(checked(element, "yearly")).toBe("false")
    expect(activeClasses(element, "monthly")).toEqual({
      surface: true, primary: true, shadow: true, secondary: false, hover: false
    })
    expect(activeClasses(element, "yearly")).toEqual({
      surface: false, primary: false, shadow: false, secondary: true, hover: true
    })
    expect(visible(element, "monthly-paid")).toBe(true)
    expect(visible(element, "yearly-paid")).toBe(false)
    expect(visible(element, "free")).toBe(true)
    expect(tabIndexOf(element, "monthly")).toBe(0)
    expect(tabIndexOf(element, "yearly")).toBe(-1)
  })

  it("honors an initial yearly interval value", async () => {
    const { element } = await mountController(
      "billing-plan-catalog",
      Controller,
      html(` data-billing-plan-catalog-interval-value="yearly"`)
    )
    expect(checked(element, "yearly")).toBe("true")
    expect(checked(element, "monthly")).toBe("false")
    expect(visible(element, "yearly-paid")).toBe(true)
    expect(visible(element, "monthly-paid")).toBe(false)
    expect(visible(element, "free")).toBe(true)
    expect(tabIndexOf(element, "yearly")).toBe(0)
    expect(tabIndexOf(element, "monthly")).toBe(-1)
  })

  it("selectInterval switches the active button and paid-card visibility", async () => {
    const { element } = await mountController("billing-plan-catalog", Controller, html())
    await click(element.querySelector('[data-billing-plan-catalog-interval-param="yearly"]'))
    expect(checked(element, "yearly")).toBe("true")
    expect(checked(element, "monthly")).toBe("false")
    expect(visible(element, "yearly-paid")).toBe(true)
    expect(visible(element, "monthly-paid")).toBe(false)
    expect(visible(element, "free")).toBe(true)
    expect(tabIndexOf(element, "yearly")).toBe(0)
    expect(tabIndexOf(element, "monthly")).toBe(-1)

    await click(element.querySelector('[data-billing-plan-catalog-interval-param="monthly"]'))
    expect(checked(element, "monthly")).toBe("true")
    expect(checked(element, "yearly")).toBe("false")
    expect(visible(element, "monthly-paid")).toBe(true)
    expect(visible(element, "yearly-paid")).toBe(false)
    expect(visible(element, "free")).toBe(true)
    expect(tabIndexOf(element, "monthly")).toBe(0)
    expect(tabIndexOf(element, "yearly")).toBe(-1)
  })

  it.each([
    ["ArrowRight", "monthly", "yearly"],
    ["ArrowDown", "monthly", "yearly"],
    ["ArrowLeft", "yearly", "monthly"],
    ["ArrowUp", "yearly", "monthly"]
  ])("keydown %s from %s selects %s, focuses it, and prevents default", async (key, from, to) => {
    const { element } = await mountController(
      "billing-plan-catalog",
      Controller,
      html(from === "yearly" ? ` data-billing-plan-catalog-interval-value="yearly"` : "")
    )
    const { prevent } = press(radio(element, from), key)
    expect(prevent).toHaveBeenCalled()
    expect(checked(element, to)).toBe("true")
    expect(checked(element, from)).toBe("false")
    expect(tabIndexOf(element, to)).toBe(0)
    expect(tabIndexOf(element, from)).toBe(-1)
    expect(document.activeElement).toBe(radio(element, to))
    expect(visible(element, `${to}-paid`)).toBe(true)
    expect(visible(element, `${from}-paid`)).toBe(false)
    expect(visible(element, "free")).toBe(true)
  })

  it("wraps ArrowRight from the last radio to the first", async () => {
    const { element } = await mountController(
      "billing-plan-catalog",
      Controller,
      html(` data-billing-plan-catalog-interval-value="yearly"`)
    )
    const { prevent } = press(radio(element, "yearly"), "ArrowRight")
    expect(prevent).toHaveBeenCalled()
    expect(checked(element, "monthly")).toBe("true")
    expect(document.activeElement).toBe(radio(element, "monthly"))
  })

  it("wraps ArrowLeft from the first radio to the last", async () => {
    const { element } = await mountController("billing-plan-catalog", Controller, html())
    const { prevent } = press(radio(element, "monthly"), "ArrowLeft")
    expect(prevent).toHaveBeenCalled()
    expect(checked(element, "yearly")).toBe("true")
    expect(document.activeElement).toBe(radio(element, "yearly"))
  })

  it("ignores keys that are not arrow navigation", async () => {
    const { application, element } = await mountController("billing-plan-catalog", Controller, html())
    const ctrl = controllerFor(application, element, "billing-plan-catalog")
    const event = { key: "Enter", preventDefault: vi.fn(), currentTarget: radio(element, "monthly") }
    ctrl.keydown(event)
    expect(event.preventDefault).not.toHaveBeenCalled()
    expect(checked(element, "monthly")).toBe("true")
    expect(checked(element, "yearly")).toBe("false")
    expect(document.activeElement).not.toBe(radio(element, "yearly"))
  })
})
