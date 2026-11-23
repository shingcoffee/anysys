import { describe, it, expect } from "vitest"
import Controller from "controllers/tabs_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const tab = (id) => `<button data-tabs-target="tab" data-tabs-id="${id}" data-action="click->tabs#select">${id}</button>`
const panel = (id) => `<div data-tabs-target="panel" data-tabs-id="${id}">${id} content</div>`

const html = (active = "") =>
  `<div data-controller="tabs" ${active ? `data-tabs-active-value="${active}"` : ""}` +
  ` data-tabs-active-class="border-accent text-accent"` +
  ` data-tabs-inactive-class="border-transparent text-text-muted">` +
  tab("one") + tab("two") +
  panel("one") + panel("two") +
  `</div>`

const activePanels = (el) =>
  [...el.querySelectorAll("[data-tabs-target='panel']")].filter((p) => !p.classList.contains("hidden")).map((p) => p.dataset.tabsId)

describe("tabs controller", () => {
  it("activates the first tab by default when no active value is set", async () => {
    const { element } = await mountController("tabs", Controller, html())
    expect(activePanels(element)).toEqual(["one"])
    const firstTab = element.querySelector("[data-tabs-id='one']")
    expect(firstTab.classList.contains("border-accent")).toBe(true)
    expect(firstTab.classList.contains("text-accent")).toBe(true)
  })

  it("honors the active value on connect", async () => {
    const { element } = await mountController("tabs", Controller, html("two"))
    expect(activePanels(element)).toEqual(["two"])
  })

  it("select() switches the visible panel and updates active value", async () => {
    const { application, element } = await mountController("tabs", Controller, html())
    const ctrl = controllerFor(application, element, "tabs")
    ctrl.select({ preventDefault() {}, currentTarget: element.querySelector("[data-tabs-id='two']") })
    expect(activePanels(element)).toEqual(["two"])
    expect(ctrl.activeValue).toBe("two")
    const inactive = element.querySelector("[data-tabs-id='one']")
    expect(inactive.classList.contains("border-transparent")).toBe(true)
    expect(inactive.classList.contains("text-text-muted")).toBe(true)
  })

  it("sets aria-selected on the active tab", async () => {
    const { element } = await mountController("tabs", Controller, html())
    const first = element.querySelector("[data-tabs-id='one']")
    const second = element.querySelector("[data-tabs-id='two']")
    expect(first.getAttribute("aria-selected")).toBe("true")
    expect(second.getAttribute("aria-selected")).toBe("false")
  })

  it("select() no-ops when the tab has no id", async () => {
    const { application, element } = await mountController("tabs", Controller, html())
    const ctrl = controllerFor(application, element, "tabs")
    ctrl.select({ preventDefault() {}, currentTarget: document.createElement("button") })
    expect(activePanels(element)).toEqual(["one"])
  })
})
