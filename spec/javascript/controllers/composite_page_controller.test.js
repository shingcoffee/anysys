import { describe, it, expect, vi, beforeEach } from "vitest"
import Controller from "controllers/composite_page_controller"
import { mountController, tick } from "../support/stimulus.js"

const html = `
  <div data-controller="composite-page">
    <div data-module-id="m1" data-listen-events="row:selected" class="hidden">A</div>
    <div data-module-id="m2" data-listen-events="other:event" class="hidden">B</div>
    <div data-module-id="m3" data-listen-events="row:selected,foo" class="hidden">C</div>
    <div data-module-id="m4" class="hidden">D (no data-listen-events attribute)</div>
  </div>`

describe("composite-page controller", () => {
  let element
  beforeEach(async () => {
    ;({ element } = await mountController("composite-page", Controller, html))
  })

  const fire = (name, detail) =>
    element.dispatchEvent(new CustomEvent(name, { detail, bubbles: true }))

  it("row-selected reveals only modules listening for 'row:selected' and re-dispatches", () => {
    const relay = vi.fn()
    element.addEventListener("composite-page:row-selected", relay)

    fire("list-module:row-selected", { recordId: 7, moduleId: "src" })

    expect(element.querySelector("[data-module-id='m1']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-module-id='m3']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-module-id='m2']").classList.contains("hidden")).toBe(true)

    expect(relay).toHaveBeenCalledOnce()
    expect(relay.mock.calls[0][0].detail).toMatchObject({ recordId: 7, moduleId: "src" })

    // m4 has no data-listen-events attribute at all; the `|| ""` fallback
    // keeps it out of the "row:selected" module set, so it stays hidden.
    expect(element.querySelector("[data-module-id='m4']").classList.contains("hidden")).toBe(true)
  })

  it("row-action re-dispatches action details without changing module visibility", () => {
    const relay = vi.fn()
    element.addEventListener("composite-page:row-action", relay)

    fire("list-module:row-action", { action: "delete", recordId: 3, moduleId: "src" })

    expect(relay).toHaveBeenCalledOnce()
    expect(relay.mock.calls[0][0].detail).toMatchObject({ action: "delete", recordId: 3, moduleId: "src" })
    // no module toggled visible by a row-action
    expect(element.querySelector("[data-module-id='m1']").classList.contains("hidden")).toBe(true)
  })

  it("disconnect removes the row-selected/row-action listeners", async () => {
    const removeSpy = vi.spyOn(element, "removeEventListener")
    element.remove() // Stimulus disconnects controllers whose element leaves the DOM
    await tick()
    expect(removeSpy).toHaveBeenCalledWith("list-module:row-selected", expect.any(Function))
    expect(removeSpy).toHaveBeenCalledWith("list-module:row-action", expect.any(Function))
  })
})
