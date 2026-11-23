import { describe, it, expect, beforeEach } from "vitest"
import Controller from "controllers/sidebar_scroll_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = (key = "settings") =>
  `<nav data-controller="sidebar-scroll" data-sidebar-scroll-key-value="${key}" style="height:40px;overflow:auto">` +
  `<div style="height:400px">menu</div></nav>`

describe("sidebar-scroll controller", () => {
  beforeEach(() => sessionStorage.clear())

  it("restores a saved scroll position when the menu reconnects", async () => {
    sessionStorage.setItem("sidebar-scroll:settings", "128")
    const { element } = await mountController("sidebar-scroll", Controller, html())
    expect(element.scrollTop).toBe(128)
  })

  it("remembers the position while the menu is scrolled", async () => {
    const { application, element } = await mountController("sidebar-scroll", Controller, html())
    element.scrollTop = 80
    element.dispatchEvent(new Event("scroll"))
    expect(sessionStorage.getItem("sidebar-scroll:settings")).toBe("80")

    const controller = controllerFor(application, element, "sidebar-scroll")
    controller.disconnect()
    element.scrollTop = 40
    element.dispatchEvent(new Event("scroll"))
    expect(sessionStorage.getItem("sidebar-scroll:settings")).toBe("80")
  })

  it("saves the current position when the menu is removed", async () => {
    const { application, element } = await mountController("sidebar-scroll", Controller, html())
    element.scrollTop = 55
    controllerFor(application, element, "sidebar-scroll").disconnect()
    expect(sessionStorage.getItem("sidebar-scroll:settings")).toBe("55")
  })

  it("ignores a missing, blank, or unreadable stored position", async () => {
    const missing = await mountController("sidebar-scroll", Controller, html())
    expect(missing.element.scrollTop).toBe(0)

    sessionStorage.setItem("sidebar-scroll:settings", "nope")
    const invalid = await mountController("sidebar-scroll", Controller, html())
    expect(invalid.element.scrollTop).toBe(0)

    const blank = await mountController("sidebar-scroll", Controller, html(""))
    blank.element.scrollTop = 30
    controllerFor(blank.application, blank.element, "sidebar-scroll").remember()
    expect(sessionStorage.getItem("sidebar-scroll:")).toBeNull()
  })

  it("does nothing when no storage key is declared", async () => {
    const { application, element } = await mountController(
      "sidebar-scroll",
      Controller,
      `<nav data-controller="sidebar-scroll"><div style="height:400px">menu</div></nav>`
    )
    element.scrollTop = 20
    const controller = controllerFor(application, element, "sidebar-scroll")
    controller.remember()
    controller.restore()
    expect(sessionStorage.length).toBe(0)
    expect(element.scrollTop).toBe(20)
  })
})
