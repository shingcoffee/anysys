import { describe, it, expect, beforeEach } from "vitest"
import Controller from "controllers/rating_controller"
import { mountController, controllerFor, click } from "../support/stimulus.js"

const star = (i) =>
  `<button data-rating-star data-value="${i}" data-action="click->rating#select">` +
  `<svg class="text-gray-300"></svg></button>`

const html = (value = "") =>
  `<div data-controller="rating">` +
  `<input type="hidden" data-rating-target="input" value="${value}">` +
  `<div data-rating-target="stars">${[1, 2, 3, 4, 5].map(star).join("")}</div>` +
  `<span data-rating-target="label"></span>` +
  `</div>`

const svgs = (el) => [...el.querySelectorAll("[data-rating-star] svg")]
const selectedFlags = (el) => [...el.querySelectorAll("[data-rating-star]")].map((s) => s.dataset.selected)
const labelText = (el) => el.querySelector("[data-rating-target='label']").textContent
const inputVal = (el) => el.querySelector("[data-rating-target='input']").value

describe("rating controller", () => {
  let application, element, ctrl
  beforeEach(async () => {
    ;({ application, element } = await mountController("rating", Controller, html("2")))
    ctrl = controllerFor(application, element, "rating")
  })

  it("highlights up to the current value on connect and sets the label", () => {
    expect(selectedFlags(element)).toEqual(["true", "true", "false", "false", "false"])
    const filled = svgs(element)
    expect(filled[0].classList.contains("text-amber-400")).toBe(true)
    expect(filled[0].classList.contains("fill-current")).toBe(true)
    expect(filled[2].classList.contains("text-gray-300")).toBe(true)
    expect(labelText(element)).toBe("2 of 5")
  })

  it("select() sets the hidden input, re-highlights and dispatches change", () => {
    let changed = false
    element.querySelector("[data-rating-target='input']").addEventListener("change", () => (changed = true))
    click(element.querySelector("[data-rating-star][data-value='4']"))
    expect(inputVal(element)).toBe("4")
    expect(selectedFlags(element)).toEqual(["true", "true", "true", "true", "false"])
    expect(labelText(element)).toBe("4 of 5")
    expect(changed).toBe(true)
  })

  it("hover() previews a value without mutating the input", () => {
    const starEl = element.querySelector("[data-rating-star][data-value='5']")
    ctrl.hover({ currentTarget: starEl })
    expect(selectedFlags(element)).toEqual(["true", "true", "true", "true", "true"])
    expect(inputVal(element)).toBe("2") // input unchanged
  })

  it("unhover() restores highlight to the stored input value", () => {
    const starEl = element.querySelector("[data-rating-star][data-value='5']")
    ctrl.hover({ currentTarget: starEl })
    ctrl.unhover()
    expect(selectedFlags(element)).toEqual(["true", "true", "false", "false", "false"])
  })

  it("shows 'Not rated' and no filled stars when value is 0/blank", async () => {
    const { element: el } = await mountController("rating", Controller, html("0"))
    expect(labelText(el)).toBe("Not rated")
    expect(selectedFlags(el)).toEqual(["false", "false", "false", "false", "false"])
  })

  it("unhover() falls back to 0 when the stored input value is blank", async () => {
    const { application: app, element: el } = await mountController("rating", Controller, html(""))
    const c = controllerFor(app, el, "rating")
    c.unhover()
    expect(selectedFlags(el)).toEqual(["false", "false", "false", "false", "false"])
  })

  it("updateLabel is a no-op when there is no label target", async () => {
    const noLabelHtml =
      `<div data-controller="rating">` +
      `<input type="hidden" data-rating-target="input" value="2">` +
      `<div data-rating-target="stars">${[1, 2, 3, 4, 5].map(star).join("")}</div>` +
      `</div>`
    const { element: el } = await mountController("rating", Controller, noLabelHtml)
    expect(selectedFlags(el)).toEqual(["true", "true", "false", "false", "false"])
  })
})
