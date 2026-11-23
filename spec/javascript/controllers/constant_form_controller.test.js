// Option reordering is delegated to SortableJS; happy-dom cannot run its native
// drag engine, so we mock the module and assert the controller wires it up and
// renumbers on the onEnd callback (the drag gesture itself is Playwright's job).
import { describe, it, expect, vi, beforeEach } from "vitest"

vi.mock("sortablejs", () => ({
  default: { create: vi.fn(() => ({ destroy: vi.fn() })) },
}))

import Sortable from "sortablejs"
import Controller from "controllers/constant_form_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const item = (value) => `
  <div data-option-item>
    <svg class="drag-handle"></svg>
    <span>n.</span>
    <input type="text" data-option-input value="${value}">
    <button type="button" data-action="click->constant-form#removeOption">x</button>
  </div>`

const html = (values = ["a", "b"]) => `
  <form data-controller="constant-form">
    <input type="hidden" data-constant-form-target="optionsField">
    <div data-constant-form-target="optionsContainer">${values.map(item).join("")}</div>
    <div data-constant-form-target="emptyState" class="hidden">No options</div>
  </form>`

const items = (el) => el.querySelectorAll("[data-option-item]")
const inputs = (el) => [...el.querySelectorAll("[data-option-input]")]
const optionsField = (el) => el.querySelector("[data-constant-form-target='optionsField']")

const noopEvent = () => ({ preventDefault: vi.fn(), stopPropagation: vi.fn(), target: null })

describe("constant-form controller", () => {
  let application, element, ctrl
  beforeEach(async () => {
    Sortable.create.mockClear()
    ;({ application, element } = await mountController("constant-form", Controller, html()))
    ctrl = controllerFor(application, element, "constant-form")
  })

  it("seeds optionIndex from the existing option count", () => {
    expect(ctrl.optionIndex).toBe(2)
  })

  it("addOption appends a new option row and bumps the index", () => {
    ctrl.addOption(noopEvent())
    expect(items(element).length).toBe(3)
    expect(ctrl.optionIndex).toBe(3)
    // newest row uses the pre-increment number label "3."
    expect(items(element)[2].querySelector("span").textContent).toBe("3.")
  })

  it("removeOption removes the row and renumbers", () => {
    const ev = { preventDefault: vi.fn(), stopPropagation: vi.fn(), target: inputs(element)[0] }
    ctrl.removeOption(ev)
    expect(items(element).length).toBe(1)
    expect(items(element)[0].querySelector("span").textContent).toBe("1.")
  })

  it("collectOptions serializes trimmed, non-empty values into the hidden field", () => {
    inputs(element)[0].value = " apple "
    inputs(element)[1].value = "banana"
    ctrl.collectOptions(noopEvent())
    expect(JSON.parse(optionsField(element).value)).toEqual(["apple", "banana"])
  })

  it("collectOptions blocks submission and flags duplicates", () => {
    inputs(element)[0].value = "dup"
    inputs(element)[1].value = "dup"
    const ev = noopEvent()
    const result = ctrl.collectOptions(ev)
    expect(result).toBe(false)
    expect(ev.preventDefault).toHaveBeenCalled()
    expect(element.querySelector("[data-duplicate-error]")).not.toBeNull()
    expect(optionsField(element).value).toBe("")
    // duplicate inputs are highlighted
    expect(inputs(element)[0].classList.contains("border-red-500")).toBe(true)
  })

  it("findDuplicates returns each repeated value once", () => {
    expect(ctrl.findDuplicates(["a", "a", "b", "b", "c"])).toEqual(["a", "b"])
    expect(ctrl.findDuplicates(["a", "b", "c"])).toEqual([])
  })

  it("removeDuplicateError clears the error element and highlights", () => {
    ctrl.showDuplicateError(["a"])
    expect(element.querySelector("[data-duplicate-error]")).not.toBeNull()
    ctrl.removeDuplicateError()
    expect(element.querySelector("[data-duplicate-error]")).toBeNull()
    expect(inputs(element).some((i) => i.classList.contains("border-red-500"))).toBe(false)
  })

  it("shows the empty state after the last option is removed", () => {
    inputs(element).slice().forEach((input) => {
      ctrl.removeOption({ preventDefault: vi.fn(), stopPropagation: vi.fn(), target: input })
    })
    expect(items(element).length).toBe(0)
    expect(element.querySelector("[data-constant-form-target='emptyState']").classList.contains("hidden")).toBe(false)
  })

  describe("guard clauses when optional targets are absent", () => {
    it("every method degrades gracefully without an optionsContainer/optionsField/emptyState target", async () => {
      const { application, element: el } = await mountController(
        "constant-form", Controller, `<form data-controller="constant-form"></form>`
      )
      const c = controllerFor(application, el, "constant-form")

      expect(c.optionIndex).toBe(0) // getExistingOptionsCount guard

      // addOption degrades gracefully when optionsContainer is absent:
      // removeDuplicateError() now guards on hasOptionsContainerTarget before
      // touching the (throwing) target getter, and addOption's own guard returns.
      expect(() => c.addOption(noopEvent())).not.toThrow()

      expect(
        () => c.removeOption({ preventDefault: vi.fn(), stopPropagation: vi.fn(), target: el })
      ).not.toThrow() // event.target has no [data-option-item] ancestor -> early return before removeDuplicateError
      expect(c.collectOptions(noopEvent())).toBeUndefined()
      expect(() => c.highlightDuplicates(["x"])).not.toThrow()
      expect(() => c.renumberOptions()).not.toThrow()
      expect(() => c.showEmptyStateIfNeeded()).not.toThrow()
      expect(() => c.disconnect()).not.toThrow() // sortable?.destroy() no-ops when setupSortable early-returned
    })

    it("addOption's own missing-container guard returns early", async () => {
      // Exercises addOption's `if (!this.hasOptionsContainerTarget) return` in
      // isolation (removeDuplicateError stubbed) — it must no-op, not throw.
      const { application, element: el } = await mountController(
        "constant-form", Controller, `<form data-controller="constant-form"></form>`
      )
      const c = controllerFor(application, el, "constant-form")
      vi.spyOn(c, "removeDuplicateError").mockImplementation(() => {})
      expect(() => c.addOption(noopEvent())).not.toThrow()
    })
  })

  describe("SortableJS reordering", () => {
    it("initializes SortableJS on the options container with a drag handle on connect", () => {
      expect(Sortable.create).toHaveBeenCalledOnce()
      const [container, options] = Sortable.create.mock.calls[0]
      expect(container).toBe(element.querySelector("[data-constant-form-target='optionsContainer']"))
      expect(options.handle).toBe(".drag-handle")
      expect(options.draggable).toBe("[data-option-item]")
      expect(typeof options.onEnd).toBe("function")
    })

    it("renumbers the visible index labels after a drag finishes (onEnd)", () => {
      // Simulate SortableJS having physically moved row 0 below row 1 during the drag.
      const container = element.querySelector("[data-constant-form-target='optionsContainer']")
      container.appendChild(items(element)[0])

      Sortable.create.mock.calls[0][1].onEnd()

      expect([...items(element)].map((i) => i.querySelector("span").textContent))
        .toEqual(["1.", "2."])
    })

    it("does not initialize SortableJS when the options container is absent", async () => {
      Sortable.create.mockClear()
      await mountController("constant-form", Controller, `<form data-controller="constant-form"></form>`)
      expect(Sortable.create).not.toHaveBeenCalled()
    })

    it("destroys the Sortable instance on disconnect", async () => {
      const instance = Sortable.create.mock.results[0].value
      document.body.innerHTML = ""
      await new Promise((r) => setTimeout(r, 0))
      expect(instance.destroy).toHaveBeenCalled()
    })
  })
})
