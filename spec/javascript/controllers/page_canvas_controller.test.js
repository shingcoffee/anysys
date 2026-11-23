import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/page_canvas_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

// NOTE: _handleFieldDragOver/_handleFieldDrop decide drop position via getBoundingClientRect
// midpoint math. happy-dom returns zeroed rects by default, but we stub getBoundingClientRect
// per element (see stubRect below) to deterministically drive both sides of the midpoint
// branch — enough to unit-test the decision logic without a real layout engine.

const config = (fields = []) => JSON.stringify({ fields, metadata: { entity_name: "Lead" } })

const html = (fields) => `
  <div data-controller="page-canvas"
       data-page-canvas-id-value="42"
       data-page-canvas-customer-id-value="7"
       data-page-canvas-configuration-value='${config(fields)}'>
    <div data-page-canvas-target="dropZone" data-role="dropzone">
      <div data-page-canvas-target="emptyPlaceholder" data-role="empty">Drop here</div>
      <div data-page-canvas-target="fieldsContainer" data-role="fields"></div>
    </div>
  </div>`

const seedFields = [
  { id: "field_1", label: "Name", property_type: "text", property_slug: "name", required: true, width: "full" },
  { id: "field_2", label: "<b>Email</b>", property_type: "email", property_slug: "email", placeholder: "you@x.com", width: "half" },
]

const q = (el, role) => el.querySelector(`[data-role='${role}']`)
const renderedIds = (el) => [...q(el, "fields").querySelectorAll("[data-field-id]")].map(n => n.dataset.fieldId)

describe("page-canvas controller", () => {
  let element, controller
  const mount = async (fields = seedFields) => {
    const m = await mountController("page-canvas", Controller, html(fields))
    element = m.element
    controller = controllerFor(m.application, element, "page-canvas")
  }
  afterEach(() => vi.restoreAllMocks())

  describe("rendering on connect", () => {
    it("renders each configured field and hides the empty placeholder", async () => {
      await mount()
      expect(renderedIds(element)).toEqual(["field_1", "field_2"])
      expect(q(element, "empty").style.display).toBe("none")
    })

    it("escapes field labels to prevent HTML injection", async () => {
      await mount()
      const emailCard = q(element, "fields").querySelector("[data-field-id='field_2']")
      expect(emailCard.innerHTML).toContain("&lt;b&gt;Email&lt;/b&gt;")
    })

    it("shows the empty placeholder when there are no fields", async () => {
      await mount([])
      expect(q(element, "empty").style.display).toBe("block")
      expect(renderedIds(element)).toEqual([])
    })

    it("recovers from malformed configuration to an empty field set", async () => {
      const m = await mountController("page-canvas", Controller,
        html([]).replace(config([]), "{bad json"))
      const c = controllerFor(m.application, m.element, "page-canvas")
      expect(c.fields).toEqual([])
    })
  })

  describe("field width classes", () => {
    it("maps width keywords to Tailwind column classes", async () => {
      await mount()
      expect(controller._getFieldWidthClass("half")).toContain("w-1/2")
      expect(controller._getFieldWidthClass("third")).toContain("w-1/3")
      expect(controller._getFieldWidthClass("full")).toContain("w-full")
      expect(controller._getFieldWidthClass(undefined)).toContain("w-full")
    })
  })

  describe("field mutations", () => {
    beforeEach(() => mount())

    it("addFieldFromPalette appends a new field and marks unsaved", async () => {
      const changed = vi.fn()
      element.addEventListener("pageChanged", changed)
      controller.addFieldFromPalette({ propertySlug: "phone", propertyType: "tel", propertyName: "Phone" })
      expect(controller.fields).toHaveLength(3)
      expect(controller.fields[2].property_slug).toBe("phone")
      expect(controller.fields[2].label).toBe("Phone")
      expect(controller.hasUnsavedChanges).toBe(true)
      expect(changed).toHaveBeenCalled()
    })

    it("updateField merges updates and re-renders", () => {
      controller.updateField("field_1", { label: "Full Name" })
      expect(controller.fields[0].label).toBe("Full Name")
      const card = q(element, "fields").querySelector("[data-field-id='field_1']")
      expect(card.textContent).toContain("Full Name")
    })

    it("removeField drops the field from state + DOM", () => {
      controller.removeField("field_1")
      expect(renderedIds(element)).toEqual(["field_2"])
    })
  })

  describe("undo / redo", () => {
    beforeEach(() => mount())

    it("undo restores the pre-mutation field set and emits undoRedoStateChanged", () => {
      const states = []
      element.addEventListener("undoRedoStateChanged", (e) => states.push(e.detail))
      controller.removeField("field_1")
      expect(renderedIds(element)).toEqual(["field_2"])
      controller.undo()
      expect(renderedIds(element)).toEqual(["field_1", "field_2"])
      expect(states.at(-1)).toEqual({ canUndo: false, canRedo: true })
    })

    it("redo re-applies an undone change", () => {
      controller.removeField("field_1")
      controller.undo()
      controller.redo()
      expect(renderedIds(element)).toEqual(["field_2"])
    })

    it("undo/redo are no-ops with empty stacks", () => {
      expect(() => { controller.undo(); controller.redo() }).not.toThrow()
      expect(renderedIds(element)).toEqual(["field_1", "field_2"])
    })
  })

  describe("drop", () => {
    beforeEach(() => mount())

    it("parses dragged JSON and adds a field", () => {
      const dt = { getData: () => JSON.stringify({ propertySlug: "city", propertyType: "text", propertyName: "City" }) }
      controller.drop({ preventDefault() {}, dataTransfer: dt })
      expect(controller.fields.at(-1).property_slug).toBe("city")
    })

    it("ignores invalid drop payloads", () => {
      const dt = { getData: () => "not json" }
      controller.drop({ preventDefault() {}, dataTransfer: dt })
      expect(controller.fields).toHaveLength(2)
    })

    it("dragEnter/dragLeave toggle drop-zone highlight classes", () => {
      controller.dragEnter({ preventDefault() {} })
      expect(q(element, "dropzone").classList.contains("bg-indigo-50")).toBe(true)
      controller.dragLeave({ currentTarget: q(element, "dropzone"), relatedTarget: document.body })
      expect(q(element, "dropzone").classList.contains("bg-indigo-50")).toBe(false)
    })
  })

  describe("save", () => {
    beforeEach(() => mount())

    it("PATCHes the autosave endpoint and clears the unsaved flag on success", async () => {
      global.fetch = vi.fn().mockResolvedValue({ ok: true, json: async () => ({}) })
      const saved = vi.fn()
      element.addEventListener("pageSaved", saved)
      const result = await controller.save()
      expect(result).toBe(true)
      expect(global.fetch).toHaveBeenCalledWith(
        "/7/admin/maintenance/pages/42/autosave",
        expect.objectContaining({ method: "PATCH" })
      )
      expect(controller.hasUnsavedChanges).toBe(false)
      expect(saved).toHaveBeenCalled()
    })

    it("emits pageSaveError with server errors on a non-ok response", async () => {
      global.fetch = vi.fn().mockResolvedValue({ ok: false, json: async () => ({ errors: ["boom"] }) })
      const err = vi.fn()
      element.addEventListener("pageSaveError", err)
      const result = await controller.save()
      expect(result).toBe(false)
      expect(err.mock.calls[0][0].detail.errors).toEqual(["boom"])
    })

    it("emits a network-error pageSaveError when fetch throws", async () => {
      global.fetch = vi.fn().mockRejectedValue(new Error("down"))
      const err = vi.fn()
      element.addEventListener("pageSaveError", err)
      await controller.save()
      expect(err.mock.calls[0][0].detail.errors).toEqual(["Network error"])
    })
  })

  describe("utilities", () => {
    beforeEach(() => mount())

    it("_generateId returns a short base36 id", () => {
      expect(controller._generateId()).toMatch(/^[a-z0-9]+$/)
    })

    it("getConfiguration returns the current fields + metadata", () => {
      const cfg = controller.getConfiguration()
      expect(cfg.fields).toHaveLength(2)
      expect(cfg.metadata.entity_name).toBe("Lead")
    })

    it("updateEntity merges entity metadata and marks changed", () => {
      controller.updateEntity(9, "Contact", [{ name: "x" }])
      expect(controller.metadata.entity_id).toBe(9)
      expect(controller.metadata.entity_name).toBe("Contact")
      expect(controller.hasUnsavedChanges).toBe(true)
    })
  })

  describe("disconnect", () => {
    it("is a no-op cleanup hook", async () => {
      await mount()
      expect(() => controller.disconnect()).not.toThrow()
    })
  })

  describe("_parseConfiguration edge cases", () => {
    it("falls back to an empty config when configurationValue is absent", async () => {
      const m = await mountController(
        "page-canvas", Controller,
        `<div data-controller="page-canvas" data-page-canvas-id-value="1" data-page-canvas-customer-id-value="1"></div>`
      )
      const c = controllerFor(m.application, m.element, "page-canvas")
      expect(c.fields).toEqual([])
      expect(c.metadata).toEqual({})
    })

    it("defaults fields to [] when the parsed config has no fields key", async () => {
      const m = await mountController(
        "page-canvas", Controller,
        `<div data-controller="page-canvas" data-page-canvas-id-value="1" data-page-canvas-customer-id-value="1" data-page-canvas-configuration-value='{"metadata":{"x":1}}'></div>`
      )
      const c = controllerFor(m.application, m.element, "page-canvas")
      expect(c.fields).toEqual([])
      expect(c.metadata).toEqual({ x: 1 })
    })

    it("defaults metadata to {} when the parsed config has no metadata key", async () => {
      const m = await mountController(
        "page-canvas", Controller,
        `<div data-controller="page-canvas" data-page-canvas-id-value="1" data-page-canvas-customer-id-value="1" data-page-canvas-configuration-value='{"fields":[]}'></div>`
      )
      const c = controllerFor(m.application, m.element, "page-canvas")
      expect(c.fields).toEqual([])
      expect(c.metadata).toEqual({})
    })
  })

  describe("_renderFields guard", () => {
    it("returns early without throwing when there is no fieldsContainer target", async () => {
      const m = await mountController(
        "page-canvas", Controller,
        `<div data-controller="page-canvas" data-page-canvas-id-value="1" data-page-canvas-customer-id-value="1" data-page-canvas-configuration-value='{"fields":[],"metadata":{}}'></div>`
      )
      const c = controllerFor(m.application, m.element, "page-canvas")
      expect(c.hasFieldsContainerTarget).toBe(false)
      expect(() => c._renderFields()).not.toThrow()
    })
  })

  describe("dragOver (canvas-level drop zone)", () => {
    beforeEach(() => mount())

    it("prevents default and sets a copy drop effect", () => {
      const event = { preventDefault: vi.fn(), dataTransfer: { dropEffect: "" } }
      controller.dragOver(event)
      expect(event.preventDefault).toHaveBeenCalled()
      expect(event.dataTransfer.dropEffect).toBe("copy")
    })
  })

  describe("_reorderFields", () => {
    beforeEach(() => mount())

    it("is a no-op when fromIndex equals toIndex", () => {
      const before = controller.fields.map(f => f.id)
      controller._reorderFields(1, 1)
      expect(controller.fields.map(f => f.id)).toEqual(before)
      expect(controller.undoStack).toHaveLength(0)
    })

    it("moves a field, renumbers order, re-renders and marks changed", () => {
      controller._reorderFields(0, 1)
      expect(controller.fields.map(f => f.id)).toEqual(["field_2", "field_1"])
      expect(controller.fields.map(f => f.order)).toEqual([0, 1])
      expect(renderedIds(element)).toEqual(["field_2", "field_1"])
      expect(controller.hasUnsavedChanges).toBe(true)
      expect(controller.undoStack).toHaveLength(1)
    })
  })

  describe("field drag & drop (reordering)", () => {
    beforeEach(() => mount())

    const card = (id) => q(element, "fields").querySelector(`[data-field-id='${id}']`)
    const stubRect = (el, top, height) => {
      Object.defineProperty(el, "getBoundingClientRect", {
        value: () => ({ top, height, bottom: top + height, left: 0, right: 0, x: 0, y: top, width: 0 }),
        configurable: true,
      })
    }

    it("_handleFieldDragStart stores the dragged field and dims the card", () => {
      const el = card("field_1")
      const dt = { setData: vi.fn(), effectAllowed: "" }
      const event = { target: el, dataTransfer: dt }
      controller._handleFieldDragStart(event, controller.fields[0])
      expect(controller.draggedField).toBe(controller.fields[0])
      expect(el.style.opacity).toBe("0.5")
      expect(dt.effectAllowed).toBe("move")
      expect(dt.setData).toHaveBeenCalledWith("text/plain", "field_1")
    })

    it("_handleFieldDragEnd clears the dragged field and restores every card's opacity", () => {
      const el = card("field_1")
      el.style.opacity = "0.5"
      controller.draggedField = controller.fields[0]
      controller._handleFieldDragEnd()
      expect(controller.draggedField).toBeNull()
      expect(el.style.opacity).toBe("")
    })

    it("_handleFieldDragOver marks a top border above the midpoint", () => {
      const el = card("field_2")
      stubRect(el, 100, 20) // midpoint = 110
      controller.draggedField = controller.fields[0]
      const event = { preventDefault: vi.fn(), currentTarget: el, clientY: 105 }
      controller._handleFieldDragOver(event, controller.fields[1])
      expect(event.preventDefault).toHaveBeenCalled()
      expect(el.style.borderTop).toBe("2px solid #6366f1")
      expect(el.style.borderBottom).toBe("")
    })

    it("_handleFieldDragOver marks a bottom border below the midpoint", () => {
      const el = card("field_2")
      stubRect(el, 100, 20)
      controller.draggedField = controller.fields[0]
      const event = { preventDefault: vi.fn(), currentTarget: el, clientY: 150 }
      controller._handleFieldDragOver(event, controller.fields[1])
      expect(el.style.borderBottom).toBe("2px solid #6366f1")
      expect(el.style.borderTop).toBe("")
    })

    it("_handleFieldDragOver is a no-op without a dragged field or hovering itself", () => {
      const el = card("field_1")
      controller.draggedField = null
      expect(() =>
        controller._handleFieldDragOver({ preventDefault: vi.fn(), currentTarget: el, clientY: 0 }, controller.fields[0])
      ).not.toThrow()

      controller.draggedField = controller.fields[0]
      controller._handleFieldDragOver({ preventDefault: vi.fn(), currentTarget: el, clientY: 0 }, controller.fields[0])
      expect(el.style.borderTop).toBe("")
      expect(el.style.borderBottom).toBe("")
    })

    it("_handleFieldDrop reorders the fields and clears border styling", () => {
      const el = card("field_1")
      el.style.borderTop = "2px solid #6366f1"
      controller.draggedField = controller.fields[1] // field_2
      const event = { preventDefault: vi.fn(), currentTarget: el }
      controller._handleFieldDrop(event, controller.fields[0]) // dropped onto field_1
      expect(event.preventDefault).toHaveBeenCalled()
      expect(el.style.borderTop).toBe("")
      expect(el.style.borderBottom).toBe("")
      expect(controller.fields.map(f => f.id)).toEqual(["field_2", "field_1"])
    })

    it("_handleFieldDrop is a no-op without a dragged field or when dropping onto itself", () => {
      const el = card("field_1")
      controller.draggedField = null
      const event1 = { preventDefault: vi.fn(), currentTarget: el }
      expect(() => controller._handleFieldDrop(event1, controller.fields[0])).not.toThrow()

      controller.draggedField = controller.fields[0]
      const event2 = { preventDefault: vi.fn(), currentTarget: el }
      expect(() => controller._handleFieldDrop(event2, controller.fields[0])).not.toThrow()
      expect(controller.fields.map(f => f.id)).toEqual(["field_1", "field_2"])
    })

    it("clearing border styling on dragleave only touches elements with a fieldId dataset", () => {
      const el = card("field_1")
      el.style.borderTop = "2px solid #6366f1"
      el.dispatchEvent(new Event("dragleave", { bubbles: true }))
      expect(el.style.borderTop).toBe("")
    })
  })

  describe("_openFieldEditor", () => {
    beforeEach(() => mount())

    it("dispatches openFieldEditor with the field in its detail when the edit button is clicked", () => {
      const handler = vi.fn()
      element.addEventListener("openFieldEditor", handler)
      const editBtn = q(element, "fields").querySelector("[data-field-id='field_1'] .edit-field-btn")
      editBtn.dispatchEvent(new Event("click", { bubbles: true }))
      expect(handler).toHaveBeenCalledOnce()
      expect(handler.mock.calls[0][0].detail.field.id).toBe("field_1")
    })
  })
})
