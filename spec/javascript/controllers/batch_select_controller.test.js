import { describe, it, expect, beforeEach } from "vitest"
import Controller from "controllers/batch_select_controller"
import { mountController } from "../support/stimulus.js"

// The controller's actions are bound to "change" (not "click"):
//   data-action="change->batch-select#toggleAll" / "change->batch-select#refresh"
// The shared `click()` helper dispatches a "click" event, which these
// checkboxes don't listen for, so it never invokes the handlers. Dispatch a
// real "change" event instead — toggleAll/refresh run synchronously, no tick
// needed.
const change = (el) => el.dispatchEvent(new Event("change", { bubbles: true }))

const html = (n = 3) =>
  `<div data-controller="batch-select">` +
  `<input type="checkbox" data-batch-select-target="all" data-action="change->batch-select#toggleAll">` +
  Array.from({ length: n }, () =>
    `<input type="checkbox" name="user_ids[]" data-batch-select-target="item" data-action="change->batch-select#refresh">`
  ).join("") +
  `<button data-batch-select-target="submit">Apply</button>` +
  `</div>`

describe("batch-select controller", () => {
  let element
  const all = () => element.querySelector("[data-batch-select-target='all']")
  const items = () => [...element.querySelectorAll("[data-batch-select-target='item']")]
  const submit = () => element.querySelector("[data-batch-select-target='submit']")

  beforeEach(async () => {
    ;({ element } = await mountController("batch-select", Controller, html()))
  })

  it("disables the submit button on connect (nothing selected)", () => {
    expect(submit().disabled).toBe(true)
    expect(all().checked).toBe(false)
  })

  it("toggleAll checks every item and enables submit", () => {
    all().checked = true
    change(all())
    expect(items().every((cb) => cb.checked)).toBe(true)
    expect(submit().disabled).toBe(false)
  })

  it("toggleAll unchecks every item and disables submit", () => {
    all().checked = true
    change(all())
    all().checked = false
    change(all())
    expect(items().every((cb) => !cb.checked)).toBe(true)
    expect(submit().disabled).toBe(true)
  })

  it("checking one item enables submit but leaves 'all' unchecked", () => {
    items()[0].checked = true
    change(items()[0])
    expect(submit().disabled).toBe(false)
    expect(all().checked).toBe(false)
  })

  it("checking every item individually syncs the 'all' checkbox on", () => {
    items().forEach((cb) => {
      cb.checked = true
      change(cb)
    })
    expect(all().checked).toBe(true)
    expect(submit().disabled).toBe(false)
  })

  it("sets indeterminate when selection is partial", () => {
    items()[0].checked = true
    change(items()[0])
    expect(all().indeterminate).toBe(true)
    expect(all().checked).toBe(false)
  })

  it("clears indeterminate when all selected", () => {
    items().forEach((cb) => {
      cb.checked = true
      change(cb)
    })
    expect(all().indeterminate).toBe(false)
    expect(all().checked).toBe(true)
  })

  it("updates selected-count from countTemplate default", async () => {
    const markup =
      `<div data-controller="batch-select">` +
      `<input type="checkbox" data-batch-select-target="all" data-action="change->batch-select#toggleAll">` +
      `<input type="checkbox" data-batch-select-target="item" data-action="change->batch-select#refresh">` +
      `<input type="checkbox" data-batch-select-target="item" data-action="change->batch-select#refresh">` +
      `<span data-batch-select-target="count"></span>` +
      `<div data-batch-select-target="toolbar"></div>` +
      `<div data-batch-select-target="bulkbar" class="hidden"></div>` +
      `<button data-batch-select-target="submit">Apply</button>` +
      `</div>`
    ;({ element } = await mountController("batch-select", Controller, markup))
    items()[0].checked = true
    change(items()[0])
    expect(element.querySelector("[data-batch-select-target='count']").textContent).toBe("1 selected")
    expect(element.querySelector("[data-batch-select-target='toolbar']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-batch-select-target='bulkbar']").classList.contains("hidden")).toBe(false)
  })

  it("clear unchecks every item and hides the bulk bar", async () => {
    const markup =
      `<div data-controller="batch-select">` +
      `<input type="checkbox" data-batch-select-target="all" data-action="change->batch-select#toggleAll">` +
      `<input type="checkbox" data-batch-select-target="item" data-action="change->batch-select#refresh">` +
      `<div data-batch-select-target="bulkbar" class="hidden"></div>` +
      `<button type="button" data-action="batch-select#clear">Clear</button>` +
      `<button data-batch-select-target="submit">Apply</button>` +
      `</div>`
    ;({ element } = await mountController("batch-select", Controller, markup))
    element.querySelector("[data-batch-select-target='item']").checked = true
    change(element.querySelector("[data-batch-select-target='item']"))
    element.querySelector("[data-action='batch-select#clear']").click()
    expect(element.querySelector("[data-batch-select-target='item']").checked).toBe(false)
    expect(element.querySelector("[data-batch-select-target='bulkbar']").classList.contains("hidden")).toBe(true)
    expect(submit().disabled).toBe(true)
  })
})
