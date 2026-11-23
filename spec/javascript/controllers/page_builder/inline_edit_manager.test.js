import { describe, it, expect, beforeEach, vi } from "vitest"
import { InlineEditManager } from "controllers/page_builder/inline_edit_manager"
import { makeCtrl, field } from "../../support/page_builder.js"

// Build a field card wrapping an editable label element and return both.
function cardWith(fieldId, { property = "label", text = "Original" } = {}) {
  const card = document.createElement("div")
  card.dataset.fieldId = fieldId
  const label = document.createElement("span")
  label.dataset.inlineEditProperty = property
  label.textContent = text
  card.appendChild(label)
  document.body.appendChild(card)
  return { card, label }
}

describe("InlineEditManager", () => {
  let ctrl, im
  beforeEach(() => {
    document.body.innerHTML = ""
    ctrl = makeCtrl({ selectedFieldId: null })
    ctrl.propertyManager.populatePropertyPanel = vi.fn()
    im = new InlineEditManager(ctrl)
  })

  describe("startEdit guards", () => {
    it("returns early when the event target has no field card", () => {
      const el = document.createElement("span")
      im.startEdit({ currentTarget: el, stopPropagation() {}, preventDefault() {} })
      expect(im.isEditing).toBe(false)
    })

    it("returns early when the field is not in the model", () => {
      const { label } = cardWith("missing")
      im.startEdit({ currentTarget: label, stopPropagation() {}, preventDefault() {} })
      expect(im.isEditing).toBe(false)
    })

    it("enters edit mode for a known field and makes the element editable", () => {
      const f = field({ id: "f1", label: "Original" })
      ctrl.currentPage.fields = [f]
      const { label } = cardWith("f1")
      im.startEdit({ currentTarget: label, stopPropagation() {}, preventDefault() {} })
      expect(im.isEditing).toBe(true)
      expect(im.editingFieldId).toBe("f1")
      expect(im.originalValue).toBe("Original")
      expect(label.getAttribute("contenteditable")).toBe("true")
    })

    it("defaults the edited property to 'label' when data-inline-edit-property is absent", () => {
      const f = field({ id: "f1", label: "Original" })
      ctrl.currentPage.fields = [f]
      const card = document.createElement("div")
      card.dataset.fieldId = "f1"
      const el = document.createElement("span") // no dataset.inlineEditProperty at all
      card.appendChild(el)
      document.body.appendChild(card)
      im.startEdit({ currentTarget: el, stopPropagation() {}, preventDefault() {} })
      expect(im.editingProperty).toBe("label")
    })

    it("defaults originalValue to '' when the target property is unset on the field", () => {
      const f = field({ id: "f1" })
      delete f.label
      ctrl.currentPage.fields = [f]
      const { label } = cardWith("f1")
      im.startEdit({ currentTarget: label, stopPropagation() {}, preventDefault() {} })
      expect(im.originalValue).toBe("")
    })

    it("cancels any in-progress edit before starting a new one", () => {
      const f1 = field({ id: "f1", label: "One" })
      const f2 = field({ id: "f2", label: "Two" })
      ctrl.currentPage.fields = [f1, f2]
      const { label: label1 } = cardWith("f1")
      const { label: label2 } = cardWith("f2")
      im.startEdit({ currentTarget: label1, stopPropagation() {}, preventDefault() {} })
      expect(im.isEditing).toBe(true)
      expect(im.editingFieldId).toBe("f1")
      im.startEdit({ currentTarget: label2, stopPropagation() {}, preventDefault() {} })
      expect(im.editingFieldId).toBe("f2")
      // the first field's editable state was torn down by the implicit cancelEdit()
      expect(label1.hasAttribute("contenteditable")).toBe(false)
    })

    it("shows the heading level toolbar when editing a heading field", () => {
      const f = field({ id: "f1", field_type: "heading", label: "Title", heading_level: "h3" })
      ctrl.currentPage.fields = [f]
      const { card, label } = cardWith("f1")
      im.startEdit({ currentTarget: label, stopPropagation() {}, preventDefault() {} })
      const toolbar = card.querySelector(".heading-level-toolbar")
      expect(toolbar).toBeTruthy()
      const buttons = [...toolbar.querySelectorAll("button")]
      expect(buttons.map((b) => b.textContent)).toEqual(["H2", "H3", "H4"])
      const active = buttons.find((b) => b.textContent === "H3")
      expect(active.className).toContain("bg-indigo-100")
      const inactive = buttons.find((b) => b.textContent === "H2")
      expect(inactive.className).toContain("text-gray-500")
    })

    it("clicking a heading toolbar button updates the field level and re-highlights", () => {
      const f = field({ id: "f1", field_type: "heading", label: "Title", heading_level: "h3" })
      ctrl.currentPage.fields = [f]
      const { card, label } = cardWith("f1")
      im.startEdit({ currentTarget: label, stopPropagation() {}, preventDefault() {} })
      const toolbar = card.querySelector(".heading-level-toolbar")
      const h2Btn = [...toolbar.querySelectorAll("button")].find((b) => b.textContent === "H2")
      h2Btn.dispatchEvent(new MouseEvent("mousedown", { bubbles: true, cancelable: true }))
      expect(f.heading_level).toBe("h2")
      expect(ctrl.saveState).toHaveBeenCalled()
      expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
      expect(h2Btn.className).toContain("bg-indigo-100")
      const h3Btn = [...toolbar.querySelectorAll("button")].find((b) => b.textContent === "H3")
      expect(h3Btn.className).toContain("text-gray-500")
    })

    it("wires real keydown/blur listeners that delegate through the stored handlers", () => {
      const f = field({ id: "f1", label: "Original" })
      ctrl.currentPage.fields = [f]
      const { label } = cardWith("f1")
      im.startEdit({ currentTarget: label, stopPropagation() {}, preventDefault() {} })

      const keydownSpy = vi.spyOn(im, "_handleKeydown")
      label.dispatchEvent(new KeyboardEvent("keydown", { key: "a" }))
      expect(keydownSpy).toHaveBeenCalled()

      const confirmSpy = vi.spyOn(im, "_confirmEdit")
      label.dispatchEvent(new Event("blur"))
      expect(confirmSpy).toHaveBeenCalledWith(label)
    })
  })

  describe("_confirmEdit", () => {
    it("saves the new value and marks dirty when it changed", () => {
      const f = field({ id: "f1", label: "Original" })
      ctrl.currentPage.fields = [f]
      const { label } = cardWith("f1")
      im.isEditing = true
      im.editingFieldId = "f1"
      im.editingProperty = "label"
      im.originalValue = "Original"
      label.textContent = "Updated"
      im._onKeydown = () => {}
      im._onBlur = () => {}
      im._confirmEdit(label)
      expect(f.label).toBe("Updated")
      expect(ctrl.saveState).toHaveBeenCalled()
      expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
      expect(im.isEditing).toBe(false)
    })

    it("does not save when the value is unchanged", () => {
      const f = field({ id: "f1", label: "Original" })
      ctrl.currentPage.fields = [f]
      const { label } = cardWith("f1")
      im.isEditing = true
      im.editingFieldId = "f1"
      im.editingProperty = "label"
      im.originalValue = "Original"
      label.textContent = "Original"
      im._onKeydown = () => {}
      im._onBlur = () => {}
      im._confirmEdit(label)
      expect(ctrl.saveState).not.toHaveBeenCalled()
    })

    it("is a no-op when not currently editing", () => {
      const label = document.createElement("span")
      expect(() => im._confirmEdit(label)).not.toThrow()
      expect(ctrl.saveState).not.toHaveBeenCalled()
    })

    it("refreshes the property panel when editing the selected field", () => {
      const f = field({ id: "f1", label: "Original" })
      ctrl.currentPage.fields = [f]
      ctrl.selectedFieldId = "f1"
      const { label } = cardWith("f1")
      im.isEditing = true
      im.editingFieldId = "f1"
      im.editingProperty = "label"
      im.originalValue = "Original"
      label.textContent = "New"
      im._onKeydown = () => {}
      im._onBlur = () => {}
      im._confirmEdit(label)
      expect(ctrl.propertyManager.populatePropertyPanel).toHaveBeenCalledWith(f)
    })
  })

  describe("_handleKeydown", () => {
    it("Enter (no shift) blurs the element to commit", () => {
      const el = document.createElement("span")
      el.blur = vi.fn()
      im._handleKeydown({ key: "Enter", shiftKey: false, preventDefault() {} }, el)
      expect(el.blur).toHaveBeenCalled()
    })

    it("Escape restores original text and cleans up", () => {
      const f = field({ id: "f1" })
      ctrl.currentPage.fields = [f]
      const { label } = cardWith("f1")
      im.isEditing = true
      im.editingFieldId = "f1"
      im.originalValue = "Original"
      im._onKeydown = () => {}
      im._onBlur = () => {}
      label.textContent = "typed junk"
      im._handleKeydown({ key: "Escape", preventDefault() {} }, label)
      expect(label.textContent).toBe("Original")
      expect(im.isEditing).toBe(false)
    })
  })

  describe("cancelEdit", () => {
    it("resets state when not editing", () => {
      im.cancelEdit()
      expect(im.isEditing).toBe(false)
    })

    it("restores the editable element's original text when it's still in the DOM", () => {
      const f = field({ id: "f1", label: "Original" })
      ctrl.currentPage.fields = [f]
      const { label } = cardWith("f1")
      im.startEdit({ currentTarget: label, stopPropagation() {}, preventDefault() {} })
      label.textContent = "typed junk"
      im.cancelEdit()
      expect(label.textContent).toBe("Original")
      expect(im.isEditing).toBe(false)
      expect(label.hasAttribute("contenteditable")).toBe(false)
    })

    it("just resets internal state when the editable element is no longer in the DOM", () => {
      const f = field({ id: "f1", label: "Original" })
      ctrl.currentPage.fields = [f]
      const { card, label } = cardWith("f1")
      im.startEdit({ currentTarget: label, stopPropagation() {}, preventDefault() {} })
      card.remove() // simulate a re-render that dropped the card out from under us
      expect(() => im.cancelEdit()).not.toThrow()
      expect(im.isEditing).toBe(false)
      expect(im.editingFieldId).toBeNull()
    })
  })
})
