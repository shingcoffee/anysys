import { describe, it, expect, beforeEach, vi } from "vitest"
import Controller from "controllers/user_menu_controller"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

const html = (withTrigger = true) =>
  `<div data-controller="user-menu">` +
  (withTrigger ? `<button data-user-menu-target="trigger" aria-expanded="false" data-action="click->user-menu#toggle">Menu</button>` : "") +
  `<div data-user-menu-target="panel" class="hidden">Panel</div>` +
  `</div>`

const panelHidden = (el) => el.querySelector("[data-user-menu-target='panel']").classList.contains("hidden")

describe("user-menu controller", () => {
  let application, element, ctrl
  beforeEach(async () => {
    ;({ application, element } = await mountController("user-menu", Controller, html()))
    ctrl = controllerFor(application, element, "user-menu")
  })

  it("toggle() opens the panel and sets aria-expanded true", () => {
    ctrl.toggle({ stopPropagation() {} })
    expect(panelHidden(element)).toBe(false)
    expect(element.querySelector("[data-user-menu-target='trigger']").getAttribute("aria-expanded")).toBe("true")
  })

  it("toggle() again closes it and sets aria-expanded false", () => {
    ctrl.toggle({ stopPropagation() {} })
    ctrl.toggle({ stopPropagation() {} })
    expect(panelHidden(element)).toBe(true)
    expect(element.querySelector("[data-user-menu-target='trigger']").getAttribute("aria-expanded")).toBe("false")
  })

  it("outside click closes an open panel", () => {
    ctrl.toggle({ stopPropagation() {} })
    document.body.click()
    expect(panelHidden(element)).toBe(true)
  })

  it("clicking inside the element does not close the panel", () => {
    ctrl.toggle({ stopPropagation() {} })
    ctrl.handleOutsideClick({ target: element.querySelector("[data-user-menu-target='panel']") })
    expect(panelHidden(element)).toBe(false)
  })

  it("Escape key closes the panel", () => {
    ctrl.toggle({ stopPropagation() {} })
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }))
    expect(panelHidden(element)).toBe(true)
  })

  it("works without a trigger target (admin shell)", async () => {
    const { application: app, element: el } = await mountController("user-menu", Controller, html(false))
    const c = controllerFor(app, el, "user-menu")
    expect(() => c.toggle({ stopPropagation() {} })).not.toThrow()
    expect(el.querySelector("[data-user-menu-target='panel']").classList.contains("hidden")).toBe(false)
  })

  it("disconnect removes the document click/keydown listeners", async () => {
    const removeSpy = vi.spyOn(document, "removeEventListener")
    element.remove() // Stimulus disconnects controllers whose element leaves the DOM
    await tick()
    expect(removeSpy).toHaveBeenCalledWith("click", expect.any(Function))
    expect(removeSpy).toHaveBeenCalledWith("keydown", expect.any(Function))
    expect(removeSpy).toHaveBeenCalledWith("anysys:topbar-menu-open", expect.any(Function))
  })

  it("closes when a peer top-bar menu announces it opened", () => {
    ctrl.toggle({ stopPropagation() {} })
    expect(panelHidden(element)).toBe(false)
    document.dispatchEvent(new CustomEvent("anysys:topbar-menu-open", {
      detail: { source: document.createElement("div") }
    }))
    expect(panelHidden(element)).toBe(true)
  })

  it("does not close when it is the source of the open announcement", () => {
    ctrl.toggle({ stopPropagation() {} })
    document.dispatchEvent(new CustomEvent("anysys:topbar-menu-open", {
      detail: { source: element }
    }))
    expect(panelHidden(element)).toBe(false)
  })
})
