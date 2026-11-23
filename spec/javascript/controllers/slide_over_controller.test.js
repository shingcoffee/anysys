import { describe, it, expect, beforeEach, afterEach } from "vitest"
import Controller from "controllers/slide_over_controller"
import { mountController, click, controllerFor, tick } from "../support/stimulus.js"

const html = (frameId = "page-publishing") =>
  `<turbo-frame id="${frameId}">` +
  `<div data-controller="slide-over" data-slide-over-frame-id-value="${frameId}">` +
  `<div data-slide-over-target="backdrop" data-action="click->slide-over#close"></div>` +
  `<aside data-slide-over-target="panel">` +
  `<a href="/close" data-action="slide-over#close">Close</a>` +
  `</aside>` +
  `</div>` +
  `</turbo-frame>`

describe("slide-over controller", () => {
  let element
  let frame
  let application

  beforeEach(async () => {
    ;({ element, application } = await mountController("slide-over", Controller, html()))
    frame = document.getElementById("page-publishing")
  })

  afterEach(() => {
    document.body.style.overflow = ""
  })

  it("locks body scroll on connect and unlocks on disconnect", async () => {
    expect(document.body.style.overflow).toBe("hidden")
    const controller = controllerFor(application, element, "slide-over")
    controller.disconnect()
    await tick()
    expect(document.body.style.overflow).toBe("")
  })

  it("clears the host turbo-frame when the backdrop is clicked", () => {
    expect(frame.innerHTML).not.toBe("")
    click(element.querySelector("[data-slide-over-target='backdrop']"))
    expect(frame.innerHTML).toBe("")
    expect(frame.hasAttribute("src")).toBe(false)
  })

  it("clears the host turbo-frame when Close is activated", () => {
    const close = element.querySelector("a")
    const event = new Event("click", { bubbles: true, cancelable: true })
    close.dispatchEvent(event)
    expect(event.defaultPrevented).toBe(true)
    expect(frame.innerHTML).toBe("")
  })

  it("closes on Escape", () => {
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }))
    expect(frame.innerHTML).toBe("")
  })

  it("ignores non-Escape keydowns", () => {
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }))
    expect(frame.innerHTML).not.toBe("")
  })

  it("removes the element when no turbo-frame host exists", async () => {
    document.body.innerHTML = ""
    const bare =
      `<div data-controller="slide-over" data-slide-over-frame-id-value="">` +
      `<div data-slide-over-target="backdrop" data-action="click->slide-over#close"></div>` +
      `<aside data-slide-over-target="panel"></aside>` +
      `</div>`
    ;({ element } = await mountController("slide-over", Controller, bare))
    click(element.querySelector("[data-slide-over-target='backdrop']"))
    expect(document.body.contains(element)).toBe(false)
  })
})
