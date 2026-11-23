import { describe, it, expect, beforeEach, vi } from "vitest"
import Controller from "controllers/dropdown_controller"
import { mountController, tick } from "../support/stimulus.js"

const html = `
  <div data-controller="dropdown">
    <button id="btn" data-action="click->dropdown#toggle">Toggle</button>
    <div data-dropdown-target="menu" class="hidden">Menu content</div>
  </div>`

const menu = (el) => el.querySelector("[data-dropdown-target='menu']")

describe("dropdown controller", () => {
  let element
  beforeEach(async () => {
    ;({ element } = await mountController("dropdown", Controller, html))
  })

  it("starts hidden with no open attribute", () => {
    expect(menu(element).classList.contains("hidden")).toBe(true)
    expect(element.hasAttribute("data-dropdown-open")).toBe(false)
  })

  it("toggle opens the menu and sets the open marker", () => {
    element.querySelector("#btn").dispatchEvent(new Event("click", { bubbles: true }))
    expect(menu(element).classList.contains("hidden")).toBe(false)
    expect(element.getAttribute("data-dropdown-open")).toBe("true")
  })

  it("toggle a second time closes the menu", () => {
    const btn = element.querySelector("#btn")
    btn.dispatchEvent(new Event("click", { bubbles: true }))
    btn.dispatchEvent(new Event("click", { bubbles: true }))
    expect(menu(element).classList.contains("hidden")).toBe(true)
    expect(element.hasAttribute("data-dropdown-open")).toBe(false)
  })

  it("closes when clicking outside the controller element", () => {
    element.querySelector("#btn").dispatchEvent(new Event("click", { bubbles: true }))
    expect(menu(element).classList.contains("hidden")).toBe(false)

    // A click somewhere on the document not contained by the element closes it.
    document.body.dispatchEvent(new Event("click", { bubbles: true }))
    expect(menu(element).classList.contains("hidden")).toBe(true)
  })

  it("does NOT close when clicking inside the controller element", () => {
    element.querySelector("#btn").dispatchEvent(new Event("click", { bubbles: true }))
    // Click the menu itself (inside element). toggle isn't wired to it, only clickOutside runs.
    menu(element).dispatchEvent(new Event("click", { bubbles: true }))
    expect(menu(element).classList.contains("hidden")).toBe(false)
  })

  it("closes on Escape keydown", () => {
    element.querySelector("#btn").dispatchEvent(new Event("click", { bubbles: true }))
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }))
    expect(menu(element).classList.contains("hidden")).toBe(true)
  })

  it("ignores non-Escape keydowns", () => {
    element.querySelector("#btn").dispatchEvent(new Event("click", { bubbles: true }))
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" }))
    expect(menu(element).classList.contains("hidden")).toBe(false)
  })

  it("disconnect removes the document click/keydown listeners", async () => {
    const removeSpy = vi.spyOn(document, "removeEventListener")
    element.remove() // Stimulus disconnects controllers whose element leaves the DOM
    await tick()
    expect(removeSpy).toHaveBeenCalledWith("click", expect.any(Function))
    expect(removeSpy).toHaveBeenCalledWith("keydown", expect.any(Function))
  })
})
