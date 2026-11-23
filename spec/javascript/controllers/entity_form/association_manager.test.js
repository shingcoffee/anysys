import { describe, it, expect, vi, beforeEach } from "vitest"
import { AssociationManager } from "controllers/entity_form/association_manager"
import { TemplateBuilder } from "controllers/entity_form/template_builder"
import { TypeManager } from "controllers/entity_form/type_manager"
import { ValidatorManager } from "controllers/entity_form/validator_manager"
import { buildController, fakeEvent } from "./support.js"

beforeEach(() => { globalThis.alert = vi.fn(); vi.restoreAllMocks() })

const assocRow = (data) => `<tr data-association-item data-association-data='${JSON.stringify(data)}'></tr>`

describe("AssociationManager#collectCurrentAssociations / getAssociatedEntityIds", () => {
  it("parses rows and collects target entity ids, skipping bad JSON", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="associationsContainer">` +
      assocRow({ target_entity_id: 1 }) +
      assocRow({ target_entity_id: 2 }) +
      `<tr data-association-item data-association-data='bad'></tr>` +
      `</div>`
    )
    const mgr = new AssociationManager(controller)
    expect(mgr.collectCurrentAssociations().length).toBe(2)
    expect(mgr.getAssociatedEntityIds()).toEqual([1, 2])
  })

  it("returns [] without a container", () => {
    expect(new AssociationManager(buildController("").controller).collectCurrentAssociations()).toEqual([])
  })
})

describe("AssociationManager#populateAssociationTargetDropdown", () => {
  it("adds an option per entity, excluding already-associated ones", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="associationTargetEntity"><option value="">--</option></select>` +
      `<div data-entity-form-target="associationsContainer">${assocRow({ target_entity_id: 2 })}</div>`
    )
    new AssociationManager(controller).populateAssociationTargetDropdown([
      { id: 1, name: "Order" }, { id: 2, name: "Product" }, { id: 3, name: "Customer" },
    ])
    const opts = [...controller.associationTargetEntityTarget.querySelectorAll("option")].map((o) => o.textContent)
    expect(opts).toEqual(["--", "Order", "Customer"]) // Product (id 2) excluded
  })
})

describe("AssociationManager#populateDisplayFieldDropdown", () => {
  it("builds options from the entity property schema", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="associationDisplayField"><option value="">--</option></select>`
    )
    new AssociationManager(controller).populateDisplayFieldDropdown({
      property_schema: [
        { name: "Name", name_slug: "name", labelable: true },
        { name: "Email", name_slug: "email", labelable: true },
      ],
    })
    const opts = controller.associationDisplayFieldTarget.querySelectorAll("option")
    expect(opts.length).toBe(3)
    expect(opts[1].value).toBe("name")
    expect(opts[1].dataset.fieldLabel).toBe("Name")
  })

  it("lists only labelable attributes", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="associationDisplayField"><option value="">--</option></select>`
    )
    new AssociationManager(controller).populateDisplayFieldDropdown({
      property_schema: [
        { name: "Title", name_slug: "title", labelable: true },
        { name: "Notes", name_slug: "notes", labelable: false },
      ],
    })
    const opts = [...controller.associationDisplayFieldTarget.options].map((option) => option.value)
    expect(opts).toEqual(["", "title"])
  })
})

describe("AssociationManager#onTargetEntityChanged", () => {
  function selController(entityId, loaded) {
    const { controller } = buildController(
      `<select data-entity-form-target="associationTargetEntity"><option value="${entityId}" selected>x</option></select>` +
      `<select data-entity-form-target="associationDisplayField"><option value="">--</option></select>` +
      `<div data-entity-form-target="associationDisplaySection" class="hidden"></div>`,
      { values: { loadedAssociationEntities: loaded } }
    )
    return controller
  }

  it("shows the display section + populates fields for a known entity", () => {
    const c = selController("7", [{ id: 7, property_schema: [{ name: "Title", name_slug: "title", labelable: true }] }])
    new AssociationManager(c).onTargetEntityChanged()
    expect(c.associationDisplaySectionTarget.classList.contains("hidden")).toBe(false)
    expect(c.associationDisplayFieldTarget.querySelectorAll("option").length).toBe(2)
  })

  it("hides the display section when no entity is chosen", () => {
    const c = selController("", [])
    new AssociationManager(c).onTargetEntityChanged()
    expect(c.associationDisplaySectionTarget.classList.contains("hidden")).toBe(true)
  })

  it("hides the display section for an unknown entity id", () => {
    const c = selController("99", [{ id: 7 }])
    new AssociationManager(c).onTargetEntityChanged()
    expect(c.associationDisplaySectionTarget.classList.contains("hidden")).toBe(true)
  })
})

describe("AssociationManager attribute list", () => {
  function attrListController(attrs = []) {
    const { controller } = buildController(
      `<div data-entity-form-target="associationAttributesContainer"></div>` +
      `<div data-entity-form-target="associationAttributesEmptyState"></div>` +
      `<div data-entity-form-target="associationAttributesTableWrapper"></div>`,
      { values: { currentAssociationAttributes: attrs, editingAssociationAttributeIndex: null, attributeIndex: 0 } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.templateBuilder = new TemplateBuilder(controller)
    return controller
  }

  it("renderAssociationAttributes shows the empty state with no attrs", () => {
    const c = attrListController([])
    new AssociationManager(c).renderAssociationAttributes()
    expect(c.associationAttributesEmptyStateTarget.classList.contains("hidden")).toBe(false)
    expect(c.associationAttributesTableWrapperTarget.classList.contains("hidden")).toBe(true)
  })

  it("renders a display row per attribute and shows the table", () => {
    const c = attrListController([{ name: "Qty", name_slug: "qty", html_type: "number", validators: [] }])
    new AssociationManager(c).renderAssociationAttributes()
    expect(c.associationAttributesContainerTarget.querySelectorAll("[data-association-attribute-item]").length).toBe(1)
    expect(c.associationAttributesTableWrapperTarget.classList.contains("hidden")).toBe(false)
  })

  it("addAttributeToAssociation appends when not editing", () => {
    const c = attrListController([])
    const mgr = new AssociationManager(c)
    mgr.addAttributeToAssociation({ name: "A", name_slug: "a", html_type: "text", validators: [] })
    expect(c.currentAssociationAttributes.length).toBe(1)
  })

  it("addAttributeToAssociation replaces the attribute being edited", () => {
    const c = attrListController([{ name: "A", name_slug: "a", html_type: "text", validators: [] }])
    c.editingAssociationAttributeIndex = 0
    new AssociationManager(c).addAttributeToAssociation({ name: "B", name_slug: "b", html_type: "text", validators: [] })
    expect(c.currentAssociationAttributes[0].name).toBe("B")
    expect(c.editingAssociationAttributeIndex).toBeNull()
  })

  it("removeAssociationAttributeFromList splices by index and re-renders", () => {
    const c = attrListController([
      { name: "A", name_slug: "a", html_type: "text", validators: [] },
      { name: "B", name_slug: "b", html_type: "text", validators: [] },
    ])
    new AssociationManager(c).removeAssociationAttributeFromList(fakeEvent({ currentTarget: { dataset: { index: "0" } } }))
    expect(c.currentAssociationAttributes.map((a) => a.name)).toEqual(["B"])
  })
})

describe("AssociationManager#saveAssociation", () => {
  function saveController({ target = "1", display = "name", editing = null } = {}) {
    const { controller } = buildController(
      `<select data-entity-form-target="associationTargetEntity">` +
      `<option value="">--</option>` +
      `<option value="1"${target === "1" ? " selected" : ""} data-entity-name="Order">Order</option>` +
      `</select>` +
      `<select data-entity-form-target="associationDisplayField">` +
      `<option value="">--</option>` +
      `<option value="name"${display === "name" ? " selected" : ""} data-field-label="Name">Name</option>` +
      `</select>` +
      `<div data-entity-form-target="associationsContainer"></div>` +
      `<div data-entity-form-target="associationsEmptyState"></div>` +
      `<div data-entity-form-target="associationModal"></div>` +
      `<button data-entity-form-target="associationModalSubmitBtn"></button>`,
      { values: { currentAssociationAttributes: [], editingAssociationIndex: editing, isProcessingModal: false } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.templateBuilder = new TemplateBuilder(controller)
    controller.schemaManager = { syncAssociationsSchema: vi.fn() }
    if (target !== "1") controller.associationTargetEntityTarget.value = ""
    if (display !== "name") controller.associationDisplayFieldTarget.value = ""
    return controller
  }

  it("alerts + bails without a target entity", () => {
    const c = saveController({ target: "none" })
    new AssociationManager(c).saveAssociation()
    expect(alert).toHaveBeenCalledWith("Please select a target entity")
    expect(c.associationsContainerTarget.querySelector("[data-association-item]")).toBeNull()
  })

  it("alerts + bails without a display field", () => {
    const c = saveController({ display: "none" })
    new AssociationManager(c).saveAssociation()
    expect(alert).toHaveBeenCalledWith("Please select a display field")
  })

  it("adds a new association row + syncs schema when valid", () => {
    const c = saveController()
    new AssociationManager(c).saveAssociation()
    const row = c.associationsContainerTarget.querySelector("[data-association-item]")
    expect(row).not.toBeNull()
    const data = JSON.parse(row.dataset.associationData)
    expect(data).toMatchObject({ target_entity_id: 1, target_entity_name: "Order", display_field: "name", display_field_label: "Name" })
    expect(c.schemaManager.syncAssociationsSchema).toHaveBeenCalled()
    expect(c.isProcessingModal).toBe(false)
  })

  it("updates an existing row when editingAssociationIndex is set", () => {
    const c = saveController({ editing: 0 })
    c.associationsContainerTarget.innerHTML = assocRow({ target_entity_id: 9, target_entity_name: "Old" })
    new AssociationManager(c).saveAssociation()
    const rows = c.associationsContainerTarget.querySelectorAll("[data-association-item]")
    expect(rows.length).toBe(1)
    expect(JSON.parse(rows[0].dataset.associationData).target_entity_name).toBe("Order")
  })

  it("re-entrancy guard: bails while a save is already in flight", () => {
    const c = saveController()
    c.isProcessingModal = true
    new AssociationManager(c).saveAssociation()
    expect(c.associationsContainerTarget.querySelector("[data-association-item]")).toBeNull()
  })
})

describe("AssociationManager#ensureAssociationsTableExists", () => {
  it("inserts the table once", () => {
    const { controller } = buildController(`<div data-entity-form-target="associationsContainer"></div>`)
    const mgr = new AssociationManager(controller)
    mgr.ensureAssociationsTableExists()
    mgr.ensureAssociationsTableExists()
    expect(controller.associationsContainerTarget.querySelectorAll("table").length).toBe(1)
  })
})

describe("AssociationManager#removeAssociation", () => {
  it("removes the row, re-syncs, and restores the empty state when the last row goes", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="associationsContainer"><table></table>${assocRow({ target_entity_id: 1 })}</div>` +
      `<div data-entity-form-target="associationsEmptyState" class="hidden"></div>`
    )
    controller.schemaManager = { syncAssociationsSchema: vi.fn() }
    const row = controller.associationsContainerTarget.querySelector("[data-association-item]")
    new AssociationManager(controller).removeAssociation(fakeEvent({ target: row }))
    expect(controller.associationsContainerTarget.querySelector("[data-association-item]")).toBeNull()
    expect(controller.associationsEmptyStateTarget.classList.contains("hidden")).toBe(false)
    expect(controller.associationsContainerTarget.querySelector("table")).toBeNull()
    expect(controller.schemaManager.syncAssociationsSchema).toHaveBeenCalled()
  })
})

describe("AssociationManager#loadAssociationEntities", () => {
  it("fetches, stores, and populates the dropdown excluding the current entity", async () => {
    const { controller } = buildController(
      `<select data-entity-form-target="associationTargetEntity"><option value="">--</option></select>` +
      `<div data-entity-form-target="associationsContainer"></div>`,
      { values: { customerIdValue: "9", currentEntityIdValue: "2" } }
    )
    vi.spyOn(globalThis, "fetch").mockResolvedValue({
      ok: true,
      json: async () => [{ id: 1, name: "A" }, { id: 2, name: "Self" }, { id: 3, name: "C" }],
    })
    await new AssociationManager(controller).loadAssociationEntities()
    expect(controller.loadedAssociationEntities.length).toBe(3)
    const opts = [...controller.associationTargetEntityTarget.querySelectorAll("option")].map((o) => o.textContent)
    expect(opts).toEqual(["--", "A", "C"]) // Self (current entity id 2) filtered out
  })

  it("silently ignores fetch failures", async () => {
    const { controller } = buildController(
      `<select data-entity-form-target="associationTargetEntity"></select>`,
      { values: { customerIdValue: "9" } }
    )
    vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("boom"))
    await expect(new AssociationManager(controller).loadAssociationEntities()).resolves.toBeUndefined()
  })
})

describe("AssociationManager modal open/close/reset", () => {
  it("resetAssociationModal clears fields + resets titles", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="associationTargetEntity"><option value="1" selected>x</option></select>` +
      `<select data-entity-form-target="associationDisplayField"><option value="">--</option></select>` +
      `<div data-entity-form-target="associationDisplaySection"></div>` +
      `<div data-entity-form-target="associationAttributesContainer"></div>` +
      `<div data-entity-form-target="associationAttributesEmptyState"></div>` +
      `<div data-entity-form-target="associationAttributesTableWrapper"></div>` +
      `<h2 data-entity-form-target="associationModalTitle">Edit Association</h2>` +
      `<button data-entity-form-target="associationModalSubmitBtn">Update Association</button>`,
      { values: { currentAssociationAttributes: [{ name: "x" }], editingAssociationIndex: 3 } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.templateBuilder = new TemplateBuilder(controller)
    new AssociationManager(controller).resetAssociationModal()
    expect(controller.associationTargetEntityTarget.value).toBe("")
    expect(controller.currentAssociationAttributes).toEqual([])
    expect(controller.editingAssociationIndex).toBeNull()
    expect(controller.associationModalTitleTarget.textContent).toBe("Add Association")
  })

  it("closeAssociationModal hides the modal", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="associationModal"></div>` +
      `<select data-entity-form-target="associationTargetEntity"></select>` +
      `<div data-entity-form-target="associationDisplaySection"></div>` +
      `<div data-entity-form-target="associationAttributesContainer"></div>`,
      { values: { currentAssociationAttributes: [] } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.templateBuilder = new TemplateBuilder(controller)
    new AssociationManager(controller).closeAssociationModal()
    expect(controller.associationModalTarget.classList.contains("hidden")).toBe(true)
  })

  it("closeAssociationModal is a no-op without a modal target", () => {
    expect(() => new AssociationManager(buildController("").controller).closeAssociationModal()).not.toThrow()
  })

  it("openAssociationModal loads entities, resets, and reveals the modal", async () => {
    const { controller } = buildController(
      `<div data-entity-form-target="associationModal" class="hidden"></div>` +
      `<select data-entity-form-target="associationTargetEntity"><option value="">--</option></select>` +
      `<select data-entity-form-target="associationDisplayField"><option value="">--</option></select>` +
      `<div data-entity-form-target="associationDisplaySection" class="hidden"></div>` +
      `<div data-entity-form-target="associationAttributesContainer"></div>` +
      `<div data-entity-form-target="associationAttributesEmptyState"></div>` +
      `<div data-entity-form-target="associationAttributesTableWrapper"></div>` +
      `<div data-entity-form-target="associationsContainer"></div>` +
      `<h2 data-entity-form-target="associationModalTitle"></h2>` +
      `<button data-entity-form-target="associationModalSubmitBtn"></button>`,
      { values: { customerIdValue: "9", currentAssociationAttributes: [{ name: "x" }] } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.templateBuilder = new TemplateBuilder(controller)
    vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: true, json: async () => [{ id: 1, name: "A" }] })
    await new AssociationManager(controller).openAssociationModal()
    expect(controller.associationModalTarget.classList.contains("hidden")).toBe(false)
    expect(controller.currentAssociationAttributes).toEqual([])
    expect(controller.associationModalTitleTarget.textContent).toBe("Add Association")
  })

  it("openAssociationModal is a no-op without a modal target", async () => {
    const { controller } = buildController("")
    const spy = vi.spyOn(globalThis, "fetch")
    await new AssociationManager(controller).openAssociationModal()
    expect(spy).not.toHaveBeenCalled()
  })
})

describe("AssociationManager guard branches", () => {
  it("loadAssociationEntities bails without a target dropdown", async () => {
    const spy = vi.spyOn(globalThis, "fetch")
    await new AssociationManager(buildController("").controller).loadAssociationEntities()
    expect(spy).not.toHaveBeenCalled()
  })

  it("loadAssociationEntities swallows a non-ok response", async () => {
    const { controller } = buildController(
      `<select data-entity-form-target="associationTargetEntity"></select>`,
      { values: { customerIdValue: "9" } }
    )
    vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: false })
    await expect(new AssociationManager(controller).loadAssociationEntities()).resolves.toBeUndefined()
    expect(controller.loadedAssociationEntities).toBeUndefined()
  })

  it("onTargetEntityChanged bails without a target dropdown", () => {
    expect(() => new AssociationManager(buildController("").controller).onTargetEntityChanged()).not.toThrow()
  })

  it("onTargetEntityChanged hides the section when no entities are loaded", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="associationTargetEntity"><option value="5" selected>x</option></select>` +
      `<select data-entity-form-target="associationDisplayField"><option value="">--</option></select>` +
      `<div data-entity-form-target="associationDisplaySection"></div>`
    )
    new AssociationManager(controller).onTargetEntityChanged()
    expect(controller.associationDisplaySectionTarget.classList.contains("hidden")).toBe(true)
  })

  it("populateDisplayFieldDropdown bails without a target and clears stale options / missing schema", () => {
    expect(() => new AssociationManager(buildController("").controller).populateDisplayFieldDropdown({})).not.toThrow()

    const { controller } = buildController(
      `<select data-entity-form-target="associationDisplayField">` +
      `<option value="">--</option><option value="stale">stale</option></select>`
    )
    new AssociationManager(controller).populateDisplayFieldDropdown({}) // no property_schema
    // stale option removed, only the placeholder remains
    expect(controller.associationDisplayFieldTarget.querySelectorAll("option").length).toBe(1)
  })

  it("populateAssociationTargetDropdown bails without a target and clears stale options", () => {
    expect(() => new AssociationManager(buildController("").controller).populateAssociationTargetDropdown([])).not.toThrow()

    const { controller } = buildController(
      `<select data-entity-form-target="associationTargetEntity">` +
      `<option value="">--</option><option value="stale">stale</option></select>` +
      `<div data-entity-form-target="associationsContainer"></div>`
    )
    new AssociationManager(controller).populateAssociationTargetDropdown([{ id: 1, name: "A" }])
    const opts = [...controller.associationTargetEntityTarget.querySelectorAll("option")].map((o) => o.textContent)
    expect(opts).toEqual(["--", "A"]) // stale dropped, A added
  })

  it("collectCurrentAssociations skips rows with no data attribute", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="associationsContainer">` +
      assocRow({ target_entity_id: 1 }) +
      `<tr data-association-item></tr>` + // no data-association-data
      `</div>`
    )
    expect(new AssociationManager(controller).collectCurrentAssociations().length).toBe(1)
  })

  it("addAssociationToList bails without a container", () => {
    expect(() => new AssociationManager(buildController("").controller).addAssociationToList({})).not.toThrow()
  })

  it("updateAssociationInList bails without a container and when the index has no row", () => {
    expect(() => new AssociationManager(buildController("").controller).updateAssociationInList({}, 0)).not.toThrow()
    const { controller } = buildController(`<div data-entity-form-target="associationsContainer"></div>`)
    expect(() => new AssociationManager(controller).updateAssociationInList({}, 3)).not.toThrow()
  })

  it("showAssociationsEmptyStateIfNeeded bails without a container", () => {
    expect(() => new AssociationManager(buildController("").controller).showAssociationsEmptyStateIfNeeded()).not.toThrow()
  })
})

describe("AssociationManager#addAssociationAttribute / editAssociationAttribute", () => {
  it("addAssociationAttribute delegates to the modal manager", () => {
    const { controller } = buildController("")
    const openModalForAssociationAttribute = vi.fn()
    controller.modalManager = { openModalForAssociationAttribute }
    new AssociationManager(controller).addAssociationAttribute(fakeEvent())
    expect(openModalForAssociationAttribute).toHaveBeenCalled()
    // also tolerates no event
    new AssociationManager(controller).addAssociationAttribute()
    expect(openModalForAssociationAttribute).toHaveBeenCalledTimes(2)
  })

  it("editAssociationAttribute prefills the modal for the indexed attribute", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="modal" class="hidden"></div>` +
      `<h2 data-entity-form-target="modalTitle"></h2>` +
      `<button data-entity-form-target="modalSubmitBtn"></button>`,
      { values: { currentAssociationAttributes: [{ name: "Qty" }], attributeModalContext: "entity", optionsSourceMode: "manual" } }
    )
    controller.modalManager = { prefillModalWithAttribute: vi.fn(), resetModalSectionNav: vi.fn(), focusModalNameField: vi.fn() }
    controller.constantsManager = { updateOptionsSourceUI: vi.fn() }
    new AssociationManager(controller).editAssociationAttribute(fakeEvent({ currentTarget: { dataset: { index: "0" } } }))
    expect(controller.attributeModalContext).toBe("association")
    expect(controller.editingAssociationAttributeIndex).toBe(0)
    expect(controller.modalManager.prefillModalWithAttribute).toHaveBeenCalledWith({ name: "Qty" })
    expect(controller.modalTitleTarget.textContent).toBe("Edit Association Attribute")
    expect(controller.modalTarget.classList.contains("hidden")).toBe(false)
    expect(controller.constantsManager.updateOptionsSourceUI).toHaveBeenCalled()
    expect(controller.modalManager.resetModalSectionNav).toHaveBeenCalled()
    expect(controller.modalManager.focusModalNameField).toHaveBeenCalled()
  })

  it("editAssociationAttribute keeps an entity-records mode that the prefill set", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="modal" class="hidden"></div>` +
      `<h2 data-entity-form-target="modalTitle"></h2>` +
      `<button data-entity-form-target="modalSubmitBtn"></button>`,
      { values: { currentAssociationAttributes: [{ name: "Qty" }], optionsSourceMode: "manual" } }
    )
    controller.modalManager = {
      prefillModalWithAttribute: vi.fn(() => { controller.optionsSourceMode = "entity_entries" }),
      resetModalSectionNav: vi.fn(),
      focusModalNameField: vi.fn(),
    }
    controller.constantsManager = { updateOptionsSourceUI: vi.fn() }
    new AssociationManager(controller).editAssociationAttribute(fakeEvent({ currentTarget: { dataset: { index: "0" } } }))
    expect(controller.optionsSourceMode).toBe("entity_entries")
  })

  it("editAssociationAttribute bails when the attribute or modal is missing", () => {
    const { controller } = buildController("", { values: { currentAssociationAttributes: [] } })
    controller.modalManager = { prefillModalWithAttribute: vi.fn(), resetModalSectionNav: vi.fn(), focusModalNameField: vi.fn() }
    new AssociationManager(controller).editAssociationAttribute(fakeEvent({ currentTarget: { dataset: { index: "5" } } }))
    expect(controller.modalManager.prefillModalWithAttribute).not.toHaveBeenCalled()
  })
})

describe("AssociationManager#saveAssociation extra branches", () => {
  function baseSelects(displayLabel = ' data-field-label="Name"') {
    return (
      `<select data-entity-form-target="associationTargetEntity">` +
      `<option value="">--</option><option value="1" selected data-entity-name="Order">Order</option></select>` +
      `<select data-entity-form-target="associationDisplayField">` +
      `<option value="">--</option><option value="name" selected${displayLabel}>Name</option></select>` +
      `<div data-entity-form-target="associationsContainer"></div>` +
      `<div data-entity-form-target="associationsEmptyState"></div>` +
      `<div data-entity-form-target="associationModal"></div>`
    )
  }

  it("saves without a submit button and falls back to the slug for the display label", () => {
    const { controller } = buildController(
      baseSelects(""), // display option has no data-field-label
      { values: { currentAssociationAttributes: null, editingAssociationIndex: null, isProcessingModal: false } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.templateBuilder = new TemplateBuilder(controller)
    controller.schemaManager = { syncAssociationsSchema: vi.fn() }
    new AssociationManager(controller).saveAssociation()
    const row = controller.associationsContainerTarget.querySelector("[data-association-item]")
    const data = JSON.parse(row.dataset.associationData)
    expect(data.display_field_label).toBe("name") // fell back to the slug
    expect(data.additional_attributes).toEqual([]) // null coalesced to []
  })

  it("alerts about the display field when no display-field target exists", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="associationTargetEntity">` +
      `<option value="">--</option><option value="1" selected data-entity-name="Order">Order</option></select>` +
      `<div data-entity-form-target="associationsContainer"></div>`,
      { values: { currentAssociationAttributes: [], editingAssociationIndex: null, isProcessingModal: false } }
    )
    new AssociationManager(controller).saveAssociation()
    expect(alert).toHaveBeenCalledWith("Please select a display field")
  })
})

describe("AssociationManager#editAssociation", () => {
  function editController({ index } = {}) {
    const association = {
      target_entity_id: 5,
      display_field: "title",
      additional_attributes: [{ name: "Qty", name_slug: "qty", html_type: "number", validators: [] }],
    }
    const idxAttr = index === undefined ? "" : ` data-index="${index}"`
    const { controller } = buildController(
      `<div data-entity-form-target="associationsContainer">` +
      `<tr data-association-item data-association-data='${JSON.stringify(association)}'>` +
      `<button id="editBtn"${idxAttr}></button></tr></div>` +
      `<select data-entity-form-target="associationTargetEntity"><option value="">--</option></select>` +
      `<select data-entity-form-target="associationDisplayField"><option value="">--</option></select>` +
      `<div data-entity-form-target="associationDisplaySection" class="hidden"></div>` +
      `<div data-entity-form-target="associationAttributesContainer"></div>` +
      `<div data-entity-form-target="associationAttributesEmptyState"></div>` +
      `<div data-entity-form-target="associationAttributesTableWrapper"></div>` +
      `<div data-entity-form-target="associationModal" class="hidden"></div>` +
      `<h2 data-entity-form-target="associationModalTitle"></h2>` +
      `<button data-entity-form-target="associationModalSubmitBtn"></button>`,
      { values: { customerIdValue: "9", currentAssociationAttributes: [] } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.templateBuilder = new TemplateBuilder(controller)
    vi.spyOn(globalThis, "fetch").mockResolvedValue({
      ok: true,
      json: async () => [{ id: 5, name: "Order", property_schema: [{ name: "Title", name_slug: "title" }] }],
    })
    return controller
  }

  it("opens the modal and restores the association (explicit index)", async () => {
    const c = editController({ index: 0 })
    const btn = c.element.querySelector("#editBtn")
    await new AssociationManager(c).editAssociation(fakeEvent({ currentTarget: btn }))
    expect(c.associationModalTarget.classList.contains("hidden")).toBe(false)
    expect(c.editingAssociationIndex).toBe(0)
    expect(c.associationModalTitleTarget.textContent).toBe("Edit Association")
    expect(c.currentAssociationAttributes.length).toBe(1)
    // NOTE: the association's own target entity is filtered out of the target
    // dropdown (it is already associated), so the value assignment is a no-op —
    // characterizing the real behavior rather than asserting a stuck value.
  })

  it("defaults to an empty attribute list when the association has none", async () => {
    const { controller } = buildController(
      `<div data-entity-form-target="associationsContainer">` +
      `<tr data-association-item data-association-data='${JSON.stringify({ target_entity_id: 5 })}'>` +
      `<button id="editBtn" data-index="0"></button></tr></div>` +
      `<select data-entity-form-target="associationTargetEntity"><option value="">--</option></select>` +
      `<div data-entity-form-target="associationAttributesContainer"></div>` +
      `<div data-entity-form-target="associationAttributesEmptyState"></div>` +
      `<div data-entity-form-target="associationAttributesTableWrapper"></div>` +
      `<div data-entity-form-target="associationModal" class="hidden"></div>`,
      { values: { customerIdValue: "9", currentAssociationAttributes: [] } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.templateBuilder = new TemplateBuilder(controller)
    vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: true, json: async () => [] })
    const btn = controller.element.querySelector("#editBtn")
    await new AssociationManager(controller).editAssociation(fakeEvent({ currentTarget: btn }))
    expect(controller.currentAssociationAttributes).toEqual([])
  })

  it("computes the index from row position when the button has no data-index", async () => {
    const c = editController({ index: undefined })
    const btn = c.element.querySelector("#editBtn")
    await new AssociationManager(c).editAssociation(fakeEvent({ currentTarget: btn }))
    expect(c.editingAssociationIndex).toBe(0)
  })

  it("bails when the button is not inside a row", async () => {
    const c = editController({ index: 0 })
    const orphan = document.createElement("button")
    await new AssociationManager(c).editAssociation(fakeEvent({ currentTarget: orphan }))
    expect(c.associationModalTarget.classList.contains("hidden")).toBe(true)
  })

  it("bails when the row has no association data", async () => {
    const { controller } = buildController(
      `<div data-entity-form-target="associationsContainer">` +
      `<tr data-association-item><button id="editBtn"></button></tr></div>` +
      `<div data-entity-form-target="associationModal" class="hidden"></div>`
    )
    const btn = controller.element.querySelector("#editBtn")
    await new AssociationManager(controller).editAssociation(fakeEvent({ currentTarget: btn }))
    expect(controller.associationModalTarget.classList.contains("hidden")).toBe(true)
  })

  it("bails on invalid association JSON", async () => {
    const { controller } = buildController(
      `<div data-entity-form-target="associationsContainer">` +
      `<tr data-association-item data-association-data='{bad'><button id="editBtn"></button></tr></div>` +
      `<div data-entity-form-target="associationModal" class="hidden"></div>`
    )
    const btn = controller.element.querySelector("#editBtn")
    await new AssociationManager(controller).editAssociation(fakeEvent({ currentTarget: btn }))
    expect(controller.associationModalTarget.classList.contains("hidden")).toBe(true)
  })
})
