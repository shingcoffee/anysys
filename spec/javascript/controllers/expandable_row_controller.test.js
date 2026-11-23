import { describe, it, expect, beforeEach } from "vitest"
import Controller from "controllers/expandable_row_controller"
import { mountController } from "../support/stimulus.js"

const html = `
  <div data-controller="expandable-row">
    <button id="t1" data-action="click->expandable-row#toggle" data-expandable-row-panel="p1">Row 1</button>
    <button id="t2" data-action="click->expandable-row#toggle" data-expandable-row-panel="p2">Row 2</button>
    <div data-expandable-row-target="detailPanel" data-expandable-row-id="p1" class="hidden">Panel 1</div>
    <div data-expandable-row-target="detailPanel" data-expandable-row-id="p2" class="hidden">Panel 2</div>
  </div>`

const panel = (el, id) => el.querySelector(`[data-expandable-row-id='${id}']`)
const click = (el, id) => el.querySelector(`#${id}`).dispatchEvent(new Event("click", { bubbles: true }))

describe("expandable-row controller", () => {
  let element
  beforeEach(async () => {
    ;({ element } = await mountController("expandable-row", Controller, html))
  })

  it("opens the matching panel on toggle", () => {
    click(element, "t1")
    expect(panel(element, "p1").classList.contains("hidden")).toBe(false)
    expect(panel(element, "p2").classList.contains("hidden")).toBe(true)
  })

  it("toggling the open panel again closes it", () => {
    click(element, "t1")
    click(element, "t1")
    expect(panel(element, "p1").classList.contains("hidden")).toBe(true)
  })

  it("opening a second panel closes the first (accordion behaviour)", () => {
    click(element, "t1")
    click(element, "t2")
    expect(panel(element, "p1").classList.contains("hidden")).toBe(true)
    expect(panel(element, "p2").classList.contains("hidden")).toBe(false)
  })

  it("is a no-op when no panel matches the button's panel id", async () => {
    const noMatch = `
      <div data-controller="expandable-row">
        <button id="t1" data-action="click->expandable-row#toggle" data-expandable-row-panel="missing">Row</button>
        <div data-expandable-row-target="detailPanel" data-expandable-row-id="p1" class="hidden">Panel 1</div>
      </div>`
    const { element: el } = await mountController("expandable-row", Controller, noMatch)
    el.querySelector("#t1").dispatchEvent(new Event("click", { bubbles: true }))
    expect(el.querySelector("[data-expandable-row-id='p1']").classList.contains("hidden")).toBe(true)
  })
})
