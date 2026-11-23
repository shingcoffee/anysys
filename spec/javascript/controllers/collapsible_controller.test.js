import { describe, it, expect } from "vitest"
import Controller from "controllers/collapsible_controller"
import { mountController, controllerFor, click, tick } from "../support/stimulus.js"

const html = (open = "true") => `
  <div data-controller="collapsible" data-collapsible-open-value="${open}">
    <button data-action="click->collapsible#toggle">
      <span data-collapsible-target="icon">v</span>
    </button>
    <div data-collapsible-target="content">body</div>
  </div>`

const content = (el) => el.querySelector("[data-collapsible-target='content']")
const icon = (el) => el.querySelector("[data-collapsible-target='icon']")

describe("collapsible controller", () => {
  it("renders open by default: content visible, icon un-rotated", async () => {
    const { element } = await mountController("collapsible", Controller, html("true"))
    expect(content(element).classList.contains("hidden")).toBe(false)
    expect(icon(element).style.transform).toBe("rotate(0deg)")
  })

  it("renders closed when open=false: content hidden, icon rotated", async () => {
    const { element } = await mountController("collapsible", Controller, html("false"))
    expect(content(element).classList.contains("hidden")).toBe(true)
    expect(icon(element).style.transform).toBe("rotate(-90deg)")
  })

  it("toggle() flips visibility on each click", async () => {
    const { element } = await mountController("collapsible", Controller, html("true"))
    await click(element.querySelector("button"))
    expect(content(element).classList.contains("hidden")).toBe(true)
    await click(element.querySelector("button"))
    expect(content(element).classList.contains("hidden")).toBe(false)
  })

  it("open() and close() drive the state programmatically", async () => {
    const { application, element } = await mountController("collapsible", Controller, html("true"))
    const ctrl = controllerFor(application, element, "collapsible")
    ctrl.close()
    await tick()
    expect(content(element).classList.contains("hidden")).toBe(true)
    ctrl.open()
    await tick()
    expect(content(element).classList.contains("hidden")).toBe(false)
  })
})
