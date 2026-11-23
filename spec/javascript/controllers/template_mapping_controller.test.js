import { describe, it, expect, beforeEach } from "vitest"
import Controller from "controllers/template_mapping_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

// happy-dom 15.x's `Element.prototype.textContent` setter only assigns when
// the value is truthy (`if (textContent) { ... }`), so `el.textContent = 0`
// silently no-ops instead of coercing to "0" like a real browser. The
// controller does `counterTarget.textContent = count`, which hits this
// exactly when the count drops to zero. Patch the setter for this file only
// so assertions reflect real DOM behavior instead of the happy-dom quirk.
const nativeTextContent = Object.getOwnPropertyDescriptor(Element.prototype, "textContent")
Object.defineProperty(Element.prototype, "textContent", {
  configurable: true,
  get: nativeTextContent.get,
  set(value) {
    nativeTextContent.set.call(this, value == null ? "" : String(value))
  },
})

const card = (cat, checked = false) =>
  `<div data-template-mapping-target="card" data-category="${cat}" class="border-gray-200 bg-white hover:border-gray-300">` +
  `<input type="checkbox" data-template-mapping-target="checkbox" data-action="change->template-mapping#toggleCard" ${checked ? "checked" : ""}>` +
  `</div>`

const html =
  `<div data-controller="template-mapping">` +
  `<button data-template-mapping-target="filterTab" data-category="all">All</button>` +
  `<button data-template-mapping-target="filterTab" data-category="a">A</button>` +
  `<div data-template-mapping-target="grid">` +
  card("a") + card("a", true) + card("b") +
  `</div>` +
  `<span data-template-mapping-target="counter"></span>` +
  `</div>`

const counter = (el) => el.querySelector("[data-template-mapping-target='counter']").textContent
const visibleCards = (el) =>
  [...el.querySelectorAll("[data-template-mapping-target='card']")].filter((c) => !c.classList.contains("hidden"))

describe("template-mapping controller", () => {
  let application, element, ctrl
  beforeEach(async () => {
    ;({ application, element } = await mountController("template-mapping", Controller, html))
    ctrl = controllerFor(application, element, "template-mapping")
  })

  it("counts checked checkboxes on connect", () => {
    expect(counter(element)).toBe("1")
  })

  it("filterCategory hides non-matching cards and styles the active tab", () => {
    ctrl.filterCategory({ currentTarget: element.querySelector("[data-category='a']") })
    expect(visibleCards(element).length).toBe(2)
    const tab = element.querySelector("[data-template-mapping-target='filterTab'][data-category='a']")
    expect(tab.className).toContain("bg-indigo-600")
    expect(tab.className).toContain("text-white")
  })

  it("filterCategory 'all' shows every card again", () => {
    ctrl.filterCategory({ currentTarget: element.querySelector("[data-category='a']") })
    ctrl.filterCategory({ currentTarget: element.querySelector("[data-category='all']") })
    expect(visibleCards(element).length).toBe(3)
  })

  it("selectAll checks only visible checkboxes and updates the counter/card styles", () => {
    ctrl.filterCategory({ currentTarget: element.querySelector("[data-category='a']") })
    ctrl.selectAll()
    expect(counter(element)).toBe("2")
    const firstCard = element.querySelector("[data-template-mapping-target='card']")
    expect(firstCard.classList.contains("border-indigo-300")).toBe(true)
    expect(firstCard.classList.contains("bg-indigo-50")).toBe(true)
  })

  it("deselectAll unchecks visible checkboxes", () => {
    ctrl.deselectAll()
    expect(counter(element)).toBe("0")
    const checked = [...element.querySelectorAll("[data-template-mapping-target='checkbox']")].filter((c) => c.checked)
    expect(checked.length).toBe(0)
  })

  it("updateCardStyle is a no-op when the checkbox isn't inside a card", () => {
    const orphan = document.createElement("input")
    orphan.type = "checkbox"
    expect(() => ctrl.updateCardStyle(orphan)).not.toThrow()
  })

  it("toggleCard restyles the card and recounts", () => {
    const cb = element.querySelector("[data-template-mapping-target='checkbox']")
    cb.checked = true
    ctrl.toggleCard({ target: cb })
    expect(counter(element)).toBe("2")
    expect(cb.closest("[data-template-mapping-target='card']").classList.contains("bg-indigo-50")).toBe(true)
  })
})
