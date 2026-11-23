import { describe, it, expect } from "vitest"
import Controller from "controllers/accordion_controller"
import { mountController } from "../support/stimulus.js"

const html = `
  <div data-controller="accordion">
    <details data-accordion-target="item" data-action="toggle->accordion#closeOthers">
      <summary>One</summary>
      <div>Content one</div>
    </details>
    <details data-accordion-target="item" data-action="toggle->accordion#closeOthers">
      <summary>Two</summary>
      <div>Content two</div>
    </details>
    <details data-accordion-target="item" data-action="toggle->accordion#closeOthers">
      <summary>Three</summary>
      <div>Content three</div>
    </details>
  </div>`

describe("accordion controller", () => {
  it("closes other details when one is opened", async () => {
    const { element } = await mountController("accordion", Controller, html)
    const details = Array.from(element.querySelectorAll("details"))

    details[0].open = true
    details[0].dispatchEvent(new Event("toggle", { bubbles: true }))

    expect(details[0].open).toBe(true)
    expect(details[1].open).toBe(false)
    expect(details[2].open).toBe(false)

    details[1].open = true
    details[1].dispatchEvent(new Event("toggle", { bubbles: true }))

    expect(details[0].open).toBe(false)
    expect(details[1].open).toBe(true)
    expect(details[2].open).toBe(false)
  })

  it("does not close others when a details is closed", async () => {
    const { element } = await mountController("accordion", Controller, html)
    const details = Array.from(element.querySelectorAll("details"))

    details[0].open = true
    details[0].dispatchEvent(new Event("toggle", { bubbles: true }))
    expect(details[1].open).toBe(false)
    expect(details[2].open).toBe(false)

    details[0].open = false
    details[0].dispatchEvent(new Event("toggle", { bubbles: true }))

    expect(details[0].open).toBe(false)
    expect(details[1].open).toBe(false)
    expect(details[2].open).toBe(false)
  })
})
