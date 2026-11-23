import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/entity_form_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

// Minimal DOM: enough targets for connect() to wire its managers without a
// customerId (so loadConstants short-circuits and no fetch fires on connect).
const html = `
  <div data-controller="entity-form">
    <input data-entity-form-target="entityName">
    <input data-entity-form-target="entityDisplayLabel">
    <input data-entity-form-target="modalName">
    <input data-entity-form-target="modalNameSlug">
    <input data-entity-form-target="modalDisplayLabel">
    <div data-entity-form-target="attributesContainer"></div>
    <input type="hidden" data-entity-form-target="propertySchema">
    <input type="hidden" data-entity-form-target="attributeGroupsInput" value="[]">
    <div data-entity-form-target="emptyState"></div>
    <div data-entity-form-target="optionsContainer"></div>
    <div data-entity-form-target="overwriteModal" class="hidden"></div>
    <span data-entity-form-target="overwriteCount"></span>
    <input name="entity[referenced_template]">
  </div>`

describe("entity-form controller", () => {
  let application, element, ctrl
  beforeEach(async () => {
    ;({ application, element } = await mountController("entity-form", Controller, html))
    ctrl = controllerFor(application, element, "entity-form")
  })
  afterEach(() => vi.restoreAllMocks())

  it("connect() creates a referenceManager", () => {
    expect(ctrl.referenceManager).toBeDefined()
  })

  describe("generateSlug", () => {
    it.each([
      ["Order Item", "order_item"],
      ["  Trimmed  ", "trimmed"],
      ["Price ($)", "price"],
      ["Café Münü", "cafe_munu"],
      ["already_slug", "already_slug"],
      ["Multiple   spaces", "multiple_spaces"],
      ["--leading-trailing--", "leading_trailing"],
    ])("slugifies %s -> %s", (input, expected) => {
      expect(ctrl.generateSlug(input)).toBe(expected)
    })

    it("uses a custom separator", () => {
      expect(ctrl.generateSlug("Order Item", "-")).toBe("order-item")
    })

    it("returns empty string for falsy input", () => {
      expect(ctrl.generateSlug("")).toBe("")
      expect(ctrl.generateSlug(null)).toBe("")
    })
  })

  describe("slug sync actions", () => {
    it("updateEntityDisplayLabel mirrors the entity name until the label is manually edited", () => {
      ctrl.entityNameTarget.value = "Invoice"
      ctrl.updateEntityDisplayLabel()
      expect(ctrl.entityDisplayLabelTarget.value).toBe("Invoice")

      ctrl.markDisplayLabelEdited({ target: ctrl.entityDisplayLabelTarget })
      ctrl.entityNameTarget.value = "Bill"
      ctrl.updateEntityDisplayLabel()
      expect(ctrl.entityDisplayLabelTarget.value).toBe("Invoice")
    })

    it("updateEntityDisplayLabel bails when a target is missing", () => {
      ctrl.entityDisplayLabelTarget.remove()
      expect(() => ctrl.updateEntityDisplayLabel()).not.toThrow()
    })

    it("updateAttributeNameSlug fills slug and display label until label is manually edited", () => {
      ctrl.modalNameTarget.value = "First Name"
      ctrl.updateAttributeNameSlug()
      expect(ctrl.modalNameSlugTarget.value).toBe("first_name")
      expect(ctrl.modalDisplayLabelTarget.value).toBe("First Name")

      ctrl.markDisplayLabelEdited({ target: ctrl.modalDisplayLabelTarget })
      ctrl.modalNameTarget.value = "Last Name"
      ctrl.updateAttributeNameSlug()
      expect(ctrl.modalNameSlugTarget.value).toBe("last_name")
      expect(ctrl.modalDisplayLabelTarget.value).toBe("First Name") // untouched after manual edit
    })
  })

  describe("options management", () => {
    it("addOption appends a row and bumps the index", () => {
      ctrl.addOption(new Event("click"))
      expect(ctrl.optionsContainerTarget.querySelectorAll("[data-option-item]").length).toBe(1)
      expect(ctrl.optionIndex).toBe(1)
    })

    it("removeOption removes the enclosing row", () => {
      ctrl.addOption(new Event("click"))
      const row = ctrl.optionsContainerTarget.querySelector("[data-option-item]")
      const label = row.querySelector("[data-option-label]")
      ctrl.removeOption({ preventDefault() {}, stopPropagation() {}, target: label })
      expect(ctrl.optionsContainerTarget.querySelectorAll("[data-option-item]").length).toBe(0)
    })

    it("updateOptionValue copies the label into the value until the value is manually edited", () => {
      ctrl.addOption(new Event("click"))
      const row = ctrl.optionsContainerTarget.querySelector("[data-option-item]")
      const label = row.querySelector("[data-option-label]")
      const value = row.querySelector("[data-option-value]")
      label.value = "Red"
      ctrl.updateOptionValue({ target: label })
      expect(value.value).toBe("Red")

      ctrl.markValueAsManuallyEdited({ target: value })
      label.value = "Blue"
      ctrl.updateOptionValue({ target: label })
      expect(value.value).toBe("Red") // preserved after manual edit
    })
  })

  describe("template overwrite flow", () => {
    it("shows the overwrite modal when attributes already exist", async () => {
      // Add an attribute row so existingCount > 0.
      ctrl.optionsContainerTarget.insertAdjacentHTML("beforeend", '<div data-attribute-item></div>')
      await ctrl.handleTemplateSelected({ detail: { key: "invoice" } })
      expect(ctrl.overwriteModalTarget.classList.contains("hidden")).toBe(false)
      expect(ctrl.overwriteCountTarget.textContent).toBe("1")
      expect(ctrl._pendingTemplateKey).toBe("invoice")
    })

    it("cancelOverwrite hides the modal and dispatches overwriteCancelled", () => {
      ctrl._pendingTemplateKey = "invoice"
      ctrl.overwriteModalTarget.classList.remove("hidden")
      const spy = vi.fn()
      element.addEventListener("entity-form:overwriteCancelled", spy)
      ctrl.cancelOverwrite()
      expect(ctrl.overwriteModalTarget.classList.contains("hidden")).toBe(true)
      expect(ctrl._pendingTemplateKey).toBeNull()
      expect(spy).toHaveBeenCalledOnce()
    })

    it("ignores a template-selected event with no key", async () => {
      await expect(ctrl.handleTemplateSelected({ detail: {} })).resolves.toBeUndefined()
    })
  })

  describe("extendedModelChanged", () => {
    it("clears reserved names when the model is cleared", async () => {
      ctrl.customerIdValue = "42"
      await ctrl.extendedModelChanged({ target: { value: "" } })
      expect(ctrl.reservedFieldNamesValue).toEqual([])
    })

    it("loads and de-duplicates base-model field names", async () => {
      ctrl.customerIdValue = "42"
      globalThis.fetch = vi.fn(() =>
        Promise.resolve({ ok: true, json: () => Promise.resolve({ fields: ["id", "id", "name"] }) })
      )
      await ctrl.extendedModelChanged({ target: { value: "User" } })
      expect(globalThis.fetch).toHaveBeenCalledWith(
        expect.stringContaining("/42/admin/maintenance/entities/base_model_fields?model=User"),
        expect.any(Object)
      )
      expect(ctrl.reservedFieldNamesValue).toEqual(["id", "name"])
    })
  })

  describe("clearAllAttributes", () => {
    it("removes the attributes table and resets the index", () => {
      ctrl.attributesContainerTarget.innerHTML = "<table><tbody></tbody></table>"
      ctrl.attributeIndex = 5
      ctrl.clearAllAttributes()
      expect(ctrl.attributesContainerTarget.querySelector("table")).toBeNull()
      expect(ctrl.attributeIndex).toBe(0)
      expect(ctrl.emptyStateTarget.classList.contains("hidden")).toBe(false)
    })

    it("bails when there is no attributes container", () => {
      ctrl.attributesContainerTarget.remove()
      expect(() => ctrl.clearAllAttributes()).not.toThrow()
    })
  })

  describe("missing-target guards", () => {
    it("existingAttributeCount is 0 without a container", () => {
      ctrl.attributesContainerTarget.remove()
      expect(ctrl.existingAttributeCount).toBe(0)
    })

    it("updateAttributeNameSlug bails without a modalName target", () => {
      ctrl.modalNameTarget.remove()
      expect(() => ctrl.updateAttributeNameSlug()).not.toThrow()
    })

    it("addOption bails without an options container", () => {
      ctrl.optionsContainerTarget.remove()
      expect(() => ctrl.addOption(new Event("click"))).not.toThrow()
    })

    it("updateOptionValue bails when the row or value input is missing", () => {
      // No enclosing [data-option-item]
      const orphan = document.createElement("input")
      expect(() => ctrl.updateOptionValue({ target: orphan })).not.toThrow()
      // Row present but no value input
      ctrl.optionsContainerTarget.innerHTML = '<div data-option-item><input data-option-label></div>'
      const label = ctrl.optionsContainerTarget.querySelector("[data-option-label]")
      expect(() => ctrl.updateOptionValue({ target: label })).not.toThrow()
    })
  })

  describe("extendedModelChanged edge cases", () => {
    it("clears reserved names when the response is not ok", async () => {
      ctrl.customerIdValue = "42"
      ctrl.reservedFieldNamesValue = ["stale"]
      globalThis.fetch = vi.fn(() => Promise.resolve({ ok: false }))
      await ctrl.extendedModelChanged({ target: { value: "User" } })
      expect(ctrl.reservedFieldNamesValue).toEqual([])
    })

    it("tolerates a payload with no fields key", async () => {
      ctrl.customerIdValue = "42"
      globalThis.fetch = vi.fn(() => Promise.resolve({ ok: true, json: () => Promise.resolve({}) }))
      await ctrl.extendedModelChanged({ target: { value: "User" } })
      expect(ctrl.reservedFieldNamesValue).toEqual([])
    })

    it("silently ignores a thrown fetch", async () => {
      ctrl.customerIdValue = "42"
      globalThis.fetch = vi.fn(() => Promise.reject(new Error("boom")))
      await expect(ctrl.extendedModelChanged({ target: { value: "User" } })).resolves.toBeUndefined()
    })
  })

  describe("disconnect", () => {
    it("removes the keydown listener", () => {
      const spy = vi.spyOn(document, "removeEventListener")
      ctrl.disconnect()
      expect(spy).toHaveBeenCalledWith("keydown", ctrl._handleKeydown)
    })
  })

  describe("delegated actions", () => {
    // Replace each manager with a spy bag, then assert the controller forwards
    // the call (and its event arg) to the right manager method.
    const cases = [
      ["htmlTypeChanged", "typeManager", "htmlTypeChanged", false],
      ["validatorSelectChanged", "validatorManager", "validatorSelectChanged", true],
      ["addValidator", "validatorManager", "addValidator", true],
      ["addValidatorWithConfig", "validatorManager", "addValidatorWithConfig", true],
      ["cancelValidatorConfig", "validatorManager", "cancelValidatorConfig", true],
      ["handleValidatorConfigKeydown", "validatorManager", "handleValidatorConfigKeydown", true],
      ["removeValidator", "validatorManager", "removeValidator", true],
      ["openModal", "modalManager", "openModal", true],
      ["closeModal", "modalManager", "closeModal", true],
      ["viewAttribute", "modalManager", "viewAttribute", true],
      ["closeViewModal", "modalManager", "closeViewModal", true],
      ["visibilityAudienceChanged", "modalManager", "visibilityAudienceChanged", true],
      ["addAttributeFromModal", "attributeManager", "addAttributeFromModal", true],
      ["copyAttribute", "attributeManager", "copyAttribute", true],
      ["editAttribute", "attributeManager", "editAttribute", true],
      ["removeAttribute", "attributeManager", "removeAttribute", true],
      ["toggleAttributeSelection", "groupManager", "toggleAttributeSelection", true],
      ["clearAttributeSelection", "groupManager", "clearAttributeSelection", true],
      ["openMoveToGroup", "groupManager", "openMoveToGroup", true],
      ["chooseGroup", "groupManager", "chooseGroup", true],
      ["openNewGroupModal", "groupManager", "openNewGroupModal", true],
      ["openGroupMenu", "groupManager", "openGroupMenu", true],
      ["editGroup", "groupManager", "editGroup", true],
      ["deleteGroup", "groupManager", "deleteGroup", true],
      ["selectGroupIcon", "groupManager", "selectGroupIcon", true],
      ["selectGroupColor", "groupManager", "selectGroupColor", true],
      ["saveGroupEdit", "groupManager", "saveGroupEdit", true],
      ["closeGroupEditModal", "groupManager", "closeGroupEditModal", true],
      ["closeFloater", "groupManager", "closeFloater", true],
      ["dragStartRow", "dndManager", "dragStartRow", true],
      ["dragOverRow", "dndManager", "dragOverRow", true],
      ["dropRow", "dndManager", "dropRow", true],
      ["dragEndRow", "dndManager", "dragEndRow", true],
      ["dragStartGroup", "dndManager", "dragStartGroup", true],
      ["dragOverGroupHeader", "dndManager", "dragOverGroupHeader", true],
      ["dropGroup", "dndManager", "dropGroup", true],
      ["selectManualOptions", "constantsManager", "selectManualOptions", true],
      ["selectConstantOptions", "constantsManager", "selectConstantOptions", true],
      ["constantChanged", "constantsManager", "constantChanged", true],
      ["selectEntityRecordsOptions", "referenceManager", "selectEntityRecordsOptions", true],
      ["referenceEntityChanged", "referenceManager", "entityChanged", false],
      ["openAssociationModal", "associationManager", "openAssociationModal", false],
      ["closeAssociationModal", "associationManager", "closeAssociationModal", false],
      ["saveAssociation", "associationManager", "saveAssociation", false],
      ["addAssociationAttribute", "associationManager", "addAssociationAttribute", true],
      ["editAssociationAttribute", "associationManager", "editAssociationAttribute", true],
      ["removeAssociationAttributeFromList", "associationManager", "removeAssociationAttributeFromList", true],
      ["editAssociation", "associationManager", "editAssociation", true],
      ["removeAssociation", "associationManager", "removeAssociation", true],
      ["associationTargetEntityChanged", "associationManager", "onTargetEntityChanged", false],
      ["selectInputMode", "computedManager", "selectInputMode", true],
      ["selectComputedMode", "computedManager", "selectComputedMode", true],
      ["computedRelationChanged", "computedManager", "relationChanged", false],
      ["computedFunctionChanged", "computedManager", "functionChanged", false],
      ["computedFilterChanged", "computedManager", "filterChanged", false],
      ["collectAttributes", "schemaManager", "collectAttributes", false],
    ]

    it.each(cases)("%s delegates to %s.%s", (method, manager, target, passesEvent) => {
      ctrl[manager] = { [target]: vi.fn() }
      const event = { detail: "x" }
      passesEvent ? ctrl[method](event) : ctrl[method]()
      if (passesEvent) {
        expect(ctrl[manager][target]).toHaveBeenCalledWith(event)
      } else {
        expect(ctrl[manager][target]).toHaveBeenCalled()
      }
    })

    it("stopPropagation stops the event", () => {
      const event = { stopPropagation: vi.fn() }
      ctrl.stopPropagation(event)
      expect(event.stopPropagation).toHaveBeenCalled()
    })

    it("colorBarClassFor returns the group manager class or a fallback", () => {
      ctrl.groupManager = { colorBarClassFor: vi.fn(() => "bg-indigo-500") }
      expect(ctrl.colorBarClassFor("indigo")).toBe("bg-indigo-500")
      ctrl.groupManager = { colorBarClassFor: vi.fn(() => null) }
      expect(ctrl.colorBarClassFor("nope")).toBe("bg-slate-500")
    })
  })

  describe("template application", () => {
    it("_applyTemplate fetches, stores the reference, and populates attributes", async () => {
      ctrl.customerIdValue = "7"
      const populateSpy = vi.spyOn(ctrl, "populateAttributesFromTemplate").mockImplementation(() => {})
      globalThis.fetch = vi.fn(() =>
        Promise.resolve({
          ok: true,
          // groups omitted -> exercises the `data.groups || []` fallback
          json: () => Promise.resolve({ template: { a: 1 }, fields: [{ name: "F" }] }),
        })
      )
      await ctrl._applyTemplate("invoice")
      const refInput = element.querySelector("input[name='entity[referenced_template]']")
      expect(refInput.value).toBe(JSON.stringify({ a: 1 }))
      expect(populateSpy).toHaveBeenCalledWith([{ name: "F" }], [])
    })

    it("_applyTemplate bails when the response is not ok", async () => {
      ctrl.customerIdValue = "7"
      const populateSpy = vi.spyOn(ctrl, "populateAttributesFromTemplate")
      globalThis.fetch = vi.fn(() => Promise.resolve({ ok: false }))
      await ctrl._applyTemplate("invoice")
      expect(populateSpy).not.toHaveBeenCalled()
    })

    it("_applyTemplate does not populate when there are no fields", async () => {
      ctrl.customerIdValue = "7"
      const populateSpy = vi.spyOn(ctrl, "populateAttributesFromTemplate")
      globalThis.fetch = vi.fn(() =>
        Promise.resolve({ ok: true, json: () => Promise.resolve({ template: {}, fields: [] }) })
      )
      await ctrl._applyTemplate("invoice")
      expect(populateSpy).not.toHaveBeenCalled()
    })

    it("_applyTemplate does not populate when the payload omits fields entirely", async () => {
      ctrl.customerIdValue = "7"
      const populateSpy = vi.spyOn(ctrl, "populateAttributesFromTemplate")
      globalThis.fetch = vi.fn(() =>
        Promise.resolve({ ok: true, json: () => Promise.resolve({ template: {} }) })
      )
      await ctrl._applyTemplate("invoice")
      expect(populateSpy).not.toHaveBeenCalled()
    })

    it("_applyTemplate swallows fetch errors", async () => {
      ctrl.customerIdValue = "7"
      globalThis.fetch = vi.fn(() => Promise.reject(new Error("boom")))
      await expect(ctrl._applyTemplate("invoice")).resolves.toBeUndefined()
    })

    it("handleTemplateSelected applies immediately when no attributes exist", async () => {
      const applySpy = vi.spyOn(ctrl, "_applyTemplate").mockResolvedValue()
      await ctrl.handleTemplateSelected({ detail: { key: "invoice" } })
      expect(applySpy).toHaveBeenCalledWith("invoice")
    })

    it("confirmOverwrite hides the modal and applies the pending template", async () => {
      const applySpy = vi.spyOn(ctrl, "_applyTemplate").mockResolvedValue()
      ctrl._pendingTemplateKey = "invoice"
      ctrl.overwriteModalTarget.classList.remove("hidden")
      await ctrl.confirmOverwrite()
      expect(ctrl.overwriteModalTarget.classList.contains("hidden")).toBe(true)
      expect(ctrl._pendingTemplateKey).toBeNull()
      expect(applySpy).toHaveBeenCalledWith("invoice")
    })

    it("confirmOverwrite is a no-op when nothing is pending", async () => {
      const applySpy = vi.spyOn(ctrl, "_applyTemplate").mockResolvedValue()
      ctrl._pendingTemplateKey = null
      await ctrl.confirmOverwrite()
      expect(applySpy).not.toHaveBeenCalled()
    })

    it("handleTemplateCleared clears the reference input and all attributes", () => {
      const refInput = element.querySelector("input[name='entity[referenced_template]']")
      refInput.value = "something"
      const clearSpy = vi.spyOn(ctrl, "clearAllAttributes")
      ctrl.handleTemplateCleared()
      expect(refInput.value).toBe("")
      expect(clearSpy).toHaveBeenCalled()
    })

    it("populateAttributesFromTemplate builds groups and appends attribute rows", () => {
      ctrl.populateAttributesFromTemplate(
        [
          { name: "First", name_slug: "first", html_type: "text", group_key: "s1" },
          { name: "Second", html_type: "text" },
        ],
        [{ key: "s1", label: "Section One" }]
      )
      const rows = ctrl.attributesContainerTarget.querySelectorAll("[data-attribute-item]")
      expect(rows.length).toBe(2)
      expect(ctrl.attributeIndex).toBe(2)
    })
  })
})

// Escape-key handling and modal open state need the modal/view-modal targets,
// so mount a richer DOM for these.
describe("entity-form controller modal state", () => {
  const modalHtml = `
    <div data-controller="entity-form">
      <div data-entity-form-target="attributesContainer"></div>
      <input type="hidden" data-entity-form-target="propertySchema">
      <input type="hidden" data-entity-form-target="attributeGroupsInput" value="[]">
      <div data-entity-form-target="modal" class="hidden"></div>
      <div data-entity-form-target="viewModal" class="hidden"></div>
    </div>`

  let application, element, ctrl
  beforeEach(async () => {
    ;({ application, element } = await mountController("entity-form", Controller, modalHtml))
    ctrl = controllerFor(application, element, "entity-form")
  })
  afterEach(() => vi.restoreAllMocks())

  it("isModalOpen reflects the modal's hidden class", () => {
    expect(ctrl.isModalOpen).toBe(false)
    ctrl.modalTarget.classList.remove("hidden")
    expect(ctrl.isModalOpen).toBe(true)
  })

  it("Escape closes the view modal when it is open", () => {
    ctrl.viewModalTarget.classList.remove("hidden")
    const spy = vi.spyOn(ctrl.modalManager, "closeViewModal").mockImplementation(() => {})
    ctrl._handleKeydown({ key: "Escape" })
    expect(spy).toHaveBeenCalled()
  })

  it("Escape closes the edit modal when only it is open", () => {
    ctrl.modalTarget.classList.remove("hidden")
    const spy = vi.spyOn(ctrl.modalManager, "closeModal").mockImplementation(() => {})
    ctrl._handleKeydown({ key: "Escape" })
    expect(spy).toHaveBeenCalled()
  })

  it("ignores non-Escape keys", () => {
    const viewSpy = vi.spyOn(ctrl.modalManager, "closeViewModal").mockImplementation(() => {})
    const modalSpy = vi.spyOn(ctrl.modalManager, "closeModal").mockImplementation(() => {})
    ctrl._handleKeydown({ key: "Enter" })
    expect(viewSpy).not.toHaveBeenCalled()
    expect(modalSpy).not.toHaveBeenCalled()
  })
})
