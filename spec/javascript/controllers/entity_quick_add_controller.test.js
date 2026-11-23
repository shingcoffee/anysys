import { describe, it, expect, vi, beforeEach } from "vitest"
import { Controller } from "@hotwired/stimulus"
import QuickAdd from "controllers/entity_quick_add_controller"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

const select = (outlet = "#entity-quick-add-dialog-0", options = `
      <option value="">Select…</option>
      <option value="14">S-014</option>
      <option value="" data-quick-add-option>+ Add New</option>`) => `
  <div class="contents" data-controller="entity-quick-add"
       data-entity-quick-add-url-value="/1/admin/entities/9/entries/new?label_field=code"
       data-entity-quick-add-title-value="Add Student"
       data-entity-quick-add-entity-quick-add-dialog-outlet="${outlet}">
    <select data-entity-quick-add-target="select" data-action="change->entity-quick-add#change">${options}
    </select>
  </div>
  <dialog id="entity-quick-add-dialog-0" data-controller="entity-quick-add-dialog"></dialog>`

const opened = []
class DialogStub extends Controller {
  open(request) { opened.push(request) }
}

async function mount(html) {
  const { application, element } = await mountController("entity-quick-add", QuickAdd, html)
  application.register("entity-quick-add-dialog", DialogStub)
  await tick()
  return { application, controller: controllerFor(application, element, "entity-quick-add"), field: element.querySelector("select") }
}

const choose = (field, index) => {
  field.selectedIndex = index
  field.dispatchEvent(new Event("change", { bubbles: true }))
}

describe("entity-quick-add controller", () => {
  beforeEach(() => { opened.length = 0 })

  it("restores the previous choice and opens the dialog when + Add New is chosen", async () => {
    const { field } = await mount(select())
    choose(field, 1)
    choose(field, 2)

    expect(field.selectedIndex).toBe(1)
    expect(opened).toHaveLength(1)
    expect(opened[0]).toMatchObject({ url: "/1/admin/entities/9/entries/new?label_field=code", title: "Add Student" })
  })

  it("inserts a newly created entry before + Add New and selects it, announcing the change", async () => {
    const { field } = await mount(select())
    const changes = vi.fn()
    field.addEventListener("change", changes)
    choose(field, 2)
    changes.mockClear()

    opened[0].onCreated({ id: "21", label: "S-021" })

    expect(field.value).toBe("21")
    expect(field.options[field.selectedIndex].text).toBe("S-021")
    expect(Array.from(field.options, (option) => option.text)).toEqual(["Select…", "S-014", "S-021", "+ Add New"])
    expect(changes).toHaveBeenCalledTimes(1)
  })

  it("selects an entry that is already listed instead of duplicating it", async () => {
    const { field } = await mount(select())
    choose(field, 2)

    opened[0].onCreated({ id: "14", label: "S-014" })

    expect(field.value).toBe("14")
    expect(field.options).toHaveLength(3)
  })

  it("only restores the choice when no dialog is on the page", async () => {
    const { field } = await mount(select("#missing-dialog"))
    choose(field, 1)
    choose(field, 2)

    expect(field.selectedIndex).toBe(1)
    expect(opened).toHaveLength(0)
  })

  it("tolerates a change with nothing selected", async () => {
    const { controller } = await mount(select(undefined, ""))

    controller.change()

    expect(controller.previousIndex).toBe(-1)
    expect(opened).toHaveLength(0)
  })
})
