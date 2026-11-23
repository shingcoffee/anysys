import { describe, it, expect, beforeEach, vi } from "vitest"
import { Controller as StimulusController } from "@hotwired/stimulus"
import Controller from "controllers/field_editor_controller"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

const html = `
  <div data-controller="field-editor">
    <div data-field-editor-target="panel" class="translate-x-full"></div>
    <form data-field-editor-target="form">
      <span data-field-editor-target="title"></span>
      <input data-field-editor-target="fieldId">
      <input data-field-editor-target="labelInput">
      <input data-field-editor-target="placeholderInput">
      <select data-field-editor-target="widthSelect">
        <option value="full">full</option>
        <option value="half">half</option>
      </select>
      <input type="checkbox" data-field-editor-target="requiredCheckbox">
    </form>
  </div>`

const panel = (el) => el.querySelector("[data-field-editor-target='panel']")
const t = (el, name) => el.querySelector(`[data-field-editor-target='${name}']`)

const field = { id: "f1", label: "Email", placeholder: "you@x.com", width: "half", required: true }

describe("field-editor controller", () => {
  let application, element, ctrl
  beforeEach(async () => {
    ;({ application, element } = await mountController("field-editor", Controller, html))
    ctrl = controllerFor(application, element, "field-editor")
  })

  describe("open", () => {
    it("populates the form and slides the panel in", () => {
      ctrl.open(field)
      expect(t(element, "fieldId").value).toBe("f1")
      expect(t(element, "labelInput").value).toBe("Email")
      expect(t(element, "placeholderInput").value).toBe("you@x.com")
      expect(t(element, "widthSelect").value).toBe("half")
      expect(t(element, "requiredCheckbox").checked).toBe(true)
      expect(t(element, "title").textContent).toBe("Edit: Email")
      expect(panel(element).classList.contains("translate-x-0")).toBe(true)
      expect(panel(element).classList.contains("translate-x-full")).toBe(false)
    })

    it("applies defaults for missing optional field props", () => {
      ctrl.open({ id: "f2", label: "Name" })
      expect(t(element, "placeholderInput").value).toBe("")
      expect(t(element, "widthSelect").value).toBe("full")
      expect(t(element, "requiredCheckbox").checked).toBe(false)
    })
  })

  describe("openFieldEditor document event", () => {
    it("opens the editor for the field carried in event.detail", () => {
      document.dispatchEvent(new CustomEvent("openFieldEditor", { detail: { field } }))
      expect(ctrl.currentField).toEqual(field)
      expect(t(element, "labelInput").value).toBe("Email")
    })
  })

  describe("close", () => {
    it("clears currentField and slides the panel out", () => {
      ctrl.open(field)
      ctrl.close()
      expect(ctrl.currentField).toBeNull()
      expect(panel(element).classList.contains("translate-x-full")).toBe(true)
      expect(panel(element).classList.contains("translate-x-0")).toBe(false)
    })
  })

  describe("save", () => {
    it("is a no-op with no current field (does not throw)", () => {
      expect(() => ctrl.save({ preventDefault() {} })).not.toThrow()
    })

    it("closes the panel after saving when a field is open", () => {
      ctrl.open(field)
      t(element, "labelInput").value = "Changed"
      ctrl.save({ preventDefault() {} })
      // No page-canvas controller present, so it just closes.
      expect(ctrl.currentField).toBeNull()
      expect(panel(element).classList.contains("translate-x-full")).toBe(true)
    })
  })

  describe("removeField", () => {
    it("no-ops without a current field", () => {
      expect(() => ctrl.removeField()).not.toThrow()
    })

    it("closes the panel when a field is open", () => {
      ctrl.open(field)
      ctrl.removeField()
      expect(ctrl.currentField).toBeNull()
    })
  })

  describe("with a page-canvas controller present", () => {
    let updateField, removeField, canvasEl
    beforeEach(async () => {
      updateField = vi.fn()
      removeField = vi.fn()
      class Canvas extends StimulusController {
        updateField(...args) { updateField(...args) }
        removeField(...args) { removeField(...args) }
      }
      canvasEl = document.createElement("div")
      canvasEl.setAttribute("data-controller", "page-canvas")
      document.body.appendChild(canvasEl)
      application.register("page-canvas", Canvas)
      await tick()
    })

    it("save forwards the collected updates to the canvas and closes", () => {
      ctrl.open(field)
      t(element, "labelInput").value = "Changed"
      t(element, "requiredCheckbox").checked = false
      ctrl.save({ preventDefault() {} })
      expect(updateField).toHaveBeenCalledWith(
        "f1",
        expect.objectContaining({ label: "Changed", width: "half", required: false })
      )
      expect(ctrl.currentField).toBeNull()
    })

    it("removeField forwards the field id to the canvas and closes", () => {
      ctrl.open(field)
      ctrl.removeField()
      expect(removeField).toHaveBeenCalledWith("f1")
      expect(ctrl.currentField).toBeNull()
    })
  })

  describe("without the optional form targets", () => {
    it("save falls back to the current field values (target-absent branches)", async () => {
      const bare = `
        <div data-controller="field-editor">
          <div data-field-editor-target="panel" class="translate-x-full"></div>
        </div>`
      const m = await mountController("field-editor", Controller, bare)
      const c = controllerFor(m.application, m.element, "field-editor")
      c.open(field)
      expect(() => c.save({ preventDefault() {} })).not.toThrow()
      expect(c.currentField).toBeNull()
    })
  })

  it("removes the document listener on disconnect", async () => {
    ctrl.close()
    element.remove()
    await tick() // let Stimulus' MutationObserver fire disconnect()
    document.dispatchEvent(new CustomEvent("openFieldEditor", { detail: { field } }))
    expect(ctrl.currentField).toBeNull() // listener removed, open() never ran
  })
})
