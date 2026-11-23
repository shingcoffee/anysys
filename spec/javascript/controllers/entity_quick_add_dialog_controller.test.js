import { describe, it, expect, vi, beforeEach } from "vitest"
import Dialog from "controllers/entity_quick_add_dialog_controller"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

const html = `
  <dialog id="entity-quick-add-dialog-0" data-controller="entity-quick-add-dialog"
          data-action="click->entity-quick-add-dialog#backdrop close->entity-quick-add-dialog#reset turbo:frame-missing->entity-quick-add-dialog#missing">
    <div class="body">
      <h2 data-entity-quick-add-dialog-target="title"></h2>
      <button type="button" class="close" data-action="entity-quick-add-dialog#close">x</button>
      <turbo-frame id="entity-quick-add-frame-0" data-entity-quick-add-dialog-target="frame"></turbo-frame>
    </div>
    <template data-entity-quick-add-dialog-target="loading"><p class="loading">Loading form…</p></template>
    <template data-entity-quick-add-dialog-target="failure"><p class="failure">Could not load</p></template>
  </dialog>`

describe("entity-quick-add-dialog controller", () => {
  let application, element, controller, frame

  beforeEach(async () => {
    ({ application, element } = await mountController("entity-quick-add-dialog", Dialog, html))
    controller = controllerFor(application, element, "entity-quick-add-dialog")
    frame = element.querySelector("turbo-frame")
    element.showModal = vi.fn()
    element.close = vi.fn(() => element.dispatchEvent(new Event("close")))
  })

  it("titles the dialog, shows the loading state and loads the form", () => {
    frame.setAttribute("src", "/stale")

    controller.open({ url: "/1/admin/entities/9/entries/new", title: "Add Student", onCreated: vi.fn() })

    expect(element.querySelector("h2").textContent).toBe("Add Student")
    expect(frame.querySelector(".loading")).not.toBeNull()
    expect(frame.getAttribute("src")).toBe("/1/admin/entities/9/entries/new")
    expect(element.showModal).toHaveBeenCalledTimes(1)
  })

  it("hands the saved entry to the opener and closes", async () => {
    const onCreated = vi.fn()
    controller.open({ url: "/new", title: "Add Student", onCreated })

    frame.innerHTML = `<p data-entity-quick-add-dialog-target="created" data-entry-id="21" data-entry-label="S-021">Saved</p>`
    await tick()

    expect(onCreated).toHaveBeenCalledWith({ id: "21", label: "S-021" })
    expect(element.close).toHaveBeenCalledTimes(1)
  })

  it("closes without a callback when nothing opened it", async () => {
    frame.innerHTML = `<p data-entity-quick-add-dialog-target="created" data-entry-id="21" data-entry-label="S-021"></p>`
    await tick()

    expect(element.close).toHaveBeenCalledTimes(1)
  })

  it("closes from the close button and clears the frame", async () => {
    controller.open({ url: "/new", title: "Add Student", onCreated: vi.fn() })

    element.querySelector(".close").click()

    expect(element.close).toHaveBeenCalledTimes(1)
    expect(frame.hasAttribute("src")).toBe(false)
    expect(frame.innerHTML).toBe("")
    expect(controller.onCreated).toBeNull()
  })

  it("ignores a late close event once the dialog has been reopened", () => {
    const onCreated = vi.fn()
    controller.open({ url: "/new", title: "Add Student", onCreated })
    element.setAttribute("open", "")

    element.dispatchEvent(new Event("close"))

    expect(controller.onCreated).toBe(onCreated)
    expect(frame.getAttribute("src")).toBe("/new")
    expect(frame.querySelector(".loading")).not.toBeNull()
  })

  it("closes on a backdrop click but not on clicks inside the panel", () => {
    element.querySelector(".body").dispatchEvent(new MouseEvent("click", { bubbles: true }))
    expect(element.close).not.toHaveBeenCalled()

    element.dispatchEvent(new MouseEvent("click", { bubbles: true }))
    expect(element.close).toHaveBeenCalledTimes(1)
  })

  it("shows the failure message when the response has no matching frame", () => {
    const event = new Event("turbo:frame-missing", { bubbles: true, cancelable: true })
    frame.dispatchEvent(event)

    expect(event.defaultPrevented).toBe(true)
    expect(frame.querySelector(".failure")).not.toBeNull()
  })

  it("leaves a nested level's saved entry to that level", async () => {
    const onCreated = vi.fn()
    controller.open({ url: "/new", title: "Add Student", onCreated })
    frame.innerHTML = `
      <form></form>
      <dialog id="entity-quick-add-dialog-1" data-controller="entity-quick-add-dialog">
        <turbo-frame id="entity-quick-add-frame-1" data-entity-quick-add-dialog-target="frame">
          <p data-entity-quick-add-dialog-target="created" data-entry-id="7" data-entry-label="Room 1"></p>
        </turbo-frame>
      </dialog>`
    await tick()

    expect(onCreated).not.toHaveBeenCalled()
    expect(element.close).not.toHaveBeenCalled()
    expect(controller.onCreated).toBe(onCreated)
  })

  it("leaves a nested level's missing frame to that level", () => {
    frame.innerHTML = `<form></form><turbo-frame id="entity-quick-add-frame-1"></turbo-frame>`
    const event = new Event("turbo:frame-missing", { bubbles: true, cancelable: true })
    frame.querySelector("turbo-frame").dispatchEvent(event)

    expect(event.defaultPrevented).toBe(false)
    expect(frame.querySelector("form")).not.toBeNull()
    expect(frame.querySelector(".failure")).toBeNull()
  })
})
