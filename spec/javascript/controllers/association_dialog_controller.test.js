import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { Controller } from "@hotwired/stimulus"
import AssociationDialog from "controllers/association_dialog_controller"
import { mountController, controllerFor, click } from "../support/stimulus.js"

const section = (outlet = true) => `
  <dialog id="entity-quick-add-dialog-0" data-controller="entity-quick-add-dialog"></dialog>
  <section id="entry-association-7" data-controller="association-dialog"
           ${outlet ? 'data-association-dialog-entity-quick-add-dialog-outlet="#entity-quick-add-dialog-0"' : ""}>
    <a class="add" href="/1/admin/entities/2/entries/3/associations/7/entries/new"
       data-action="association-dialog#open" data-association-dialog-title-param="Add Course">Add</a>
  </section>`

class FakeDialog extends Controller {
  open(options) { this.constructor.calls.push(options) }
}

async function mount(html) {
  FakeDialog.calls = []
  const { application, element } = await mountController("association-dialog", AssociationDialog, html)
  application.register("entity-quick-add-dialog", FakeDialog)
  await new Promise((resolve) => setTimeout(resolve, 0))
  return { application, element, controller: controllerFor(application, element, "association-dialog") }
}

describe("association-dialog controller", () => {
  let turbo

  beforeEach(() => {
    turbo = { visit: vi.fn() }
    window.Turbo = turbo
    window.history.replaceState({}, "", "/1/admin/entities/2/entries/3?tab=x#entry-association-7")
  })

  afterEach(() => {
    delete window.Turbo
  })

  it("opens the link's form in the dialog with the link's title", async () => {
    const { element } = await mount(section())
    const link = element.querySelector(".add")
    const event = new MouseEvent("click", { bubbles: true, cancelable: true })

    link.dispatchEvent(event)

    expect(event.defaultPrevented).toBe(true)
    expect(FakeDialog.calls).toHaveLength(1)
    expect(FakeDialog.calls[0].url).toBe("http://localhost:3000/1/admin/entities/2/entries/3/associations/7/entries/new")
    expect(FakeDialog.calls[0].title).toBe("Add Course")
  })

  it("lets the link navigate when there is no dialog", async () => {
    const { element } = await mount(section(false))
    const event = new MouseEvent("click", { bubbles: true, cancelable: true })

    element.querySelector(".add").dispatchEvent(event)

    expect(event.defaultPrevented).toBe(false)
    expect(FakeDialog.calls).toHaveLength(0)
  })

  it("reloads the entry page without the anchor once saved, then scrolls back to the card", async () => {
    const { element } = await mount(section())
    await click(element.querySelector(".add"))
    element.scrollIntoView = vi.fn()

    FakeDialog.calls[0].onCreated({ id: "3", label: "" })

    expect(turbo.visit).toHaveBeenCalledWith("/1/admin/entities/2/entries/3?tab=x", { action: "replace" })
    document.dispatchEvent(new Event("turbo:load"))
    expect(element.scrollIntoView).toHaveBeenCalledTimes(1)
    document.dispatchEvent(new Event("turbo:load"))
    expect(element.scrollIntoView).toHaveBeenCalledTimes(1)
  })

  it("tolerates the card being gone after the reload", async () => {
    const { controller, element } = await mount(section())

    controller.reload()
    element.remove()

    expect(() => document.dispatchEvent(new Event("turbo:load"))).not.toThrow()
  })

  it("falls back to a full reload without Turbo", async () => {
    delete window.Turbo
    const reload = vi.fn()
    const original = window.location.reload
    Object.defineProperty(window.location, "reload", { configurable: true, value: reload })
    const { controller } = await mount(section())

    controller.reload()

    expect(reload).toHaveBeenCalledTimes(1)
    Object.defineProperty(window.location, "reload", { configurable: true, value: original })
  })
})
