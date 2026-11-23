import { describe, it, expect, vi } from "vitest"
import { AttributeManager } from "controllers/entity_form/attribute_manager"
import { SchemaManager } from "controllers/entity_form/schema_manager"
import { TemplateBuilder } from "controllers/entity_form/template_builder"
import { TypeManager } from "controllers/entity_form/type_manager"
import { ValidatorManager } from "controllers/entity_form/validator_manager"
import { buildController, fakeEvent } from "./support.js"

// Rows with a hidden name/slug input, matching the real markup extract*/duplicate
// checks read.
const attrRow = (name, slug = "") =>
  `<div data-attribute-item data-attr-name="${name}" data-attr-name-slug="${slug}">` +
  `<input data-input="name" value="${name}">` +
  (slug ? `<input data-input="name_slug" value="${slug}">` : "") +
  `</div>`

describe("AttributeManager#isReservedFieldName", () => {
  it("only reserved when an extendable model is set and the slug is in the reserved list", () => {
    const { controller } = buildController("", { values: { extendableModelValue: "User", reservedFieldNamesValue: ["id", "email"] } })
    const mgr = new AttributeManager(controller)
    expect(mgr.isReservedFieldName("email")).toBe(true)
    expect(mgr.isReservedFieldName("nickname")).toBe(false)
  })

  it("never reserved without an extendable model", () => {
    const { controller } = buildController("", { values: { extendableModelValue: "", reservedFieldNamesValue: ["id"] } })
    expect(new AttributeManager(controller).isReservedFieldName("id")).toBe(false)
  })
})

describe("AttributeManager duplicate detection", () => {
  function dupController() {
    const { controller } = buildController(
      `<div data-entity-form-target="attributesContainer">${attrRow("Email", "email")}${attrRow("Name", "name")}</div>`
    )
    return controller
  }

  it("getExistingAttributeValues lowercases and excludes the editing row", () => {
    const c = dupController()
    const mgr = new AttributeManager(c)
    expect(mgr.getExistingAttributeValues("name")).toEqual(["email", "name"])
    const emailRow = c.element.querySelector('[data-attr-name="Email"]')
    expect(mgr.getExistingAttributeValues("name", emailRow)).toEqual(["name"])
  })

  it("isDuplicateValue is case-insensitive", () => {
    const mgr = new AttributeManager(dupController())
    expect(mgr.isDuplicateValue("name", "EMAIL")).toBe(true)
    expect(mgr.isDuplicateValue("name", "Phone")).toBe(false)
  })
})

describe("AttributeManager#generateUniqueName", () => {
  it("appends (Copy) then numbered copies to avoid collisions", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="attributesContainer">` +
      attrRow("Field") + attrRow("Field (Copy)") +
      `</div>`
    )
    expect(new AttributeManager(controller).generateUniqueName("Field")).toBe("Field (Copy 2)")
  })

  it("uses the plain (Copy) suffix when free", () => {
    const { controller } = buildController(`<div data-entity-form-target="attributesContainer">${attrRow("Field")}</div>`)
    expect(new AttributeManager(controller).generateUniqueName("Field")).toBe("Field (Copy)")
  })
})

describe("AttributeManager#collectVisibility", () => {
  it("reads the three visibility checkboxes, defaulting to true when absent", () => {
    const { controller } = buildController(
      `<input type="checkbox" data-entity-form-target="modalVisibilityAdmin">` +
      `<input type="checkbox" data-entity-form-target="modalVisibilityMember" checked>`
    )
    expect(new AttributeManager(controller).collectVisibility()).toEqual({ admin: false, member: true, public: true })
  })
})

describe("AttributeManager#collectValidatorApply", () => {
  it("coerces apply false when the matching Visible checkbox is off", () => {
    const { controller } = buildController(
      `<input type="checkbox" checked data-entity-form-target="modalVisibilityAdmin">` +
      `<input type="checkbox" checked data-entity-form-target="modalVisibilityMember">` +
      `<input type="checkbox" data-entity-form-target="modalVisibilityPublic">` +
      `<input type="checkbox" checked data-entity-form-target="modalValidatorApplyAdmin">` +
      `<input type="checkbox" checked data-entity-form-target="modalValidatorApplyMember">` +
      `<input type="checkbox" checked data-entity-form-target="modalValidatorApplyPublic">`
    )
    controller.schemaManager = new SchemaManager(controller)
    expect(new AttributeManager(controller).collectValidatorApply()).toEqual({
      admin: true, member: true, public: false
    })
  })

  it("coerces apply false when Can edit is off even if Visible is on", () => {
    const { controller } = buildController(
      `<input type="checkbox" checked data-entity-form-target="modalVisibilityAdmin">` +
      `<input type="checkbox" checked data-entity-form-target="modalVisibilityMember">` +
      `<input type="checkbox" checked data-entity-form-target="modalVisibilityPublic">` +
      `<input type="checkbox" checked data-entity-form-target="modalEditableAdmin">` +
      `<input type="checkbox" data-entity-form-target="modalEditableMember">` +
      `<input type="checkbox" checked data-entity-form-target="modalEditablePublic">` +
      `<input type="checkbox" checked data-entity-form-target="modalValidatorApplyAdmin">` +
      `<input type="checkbox" checked data-entity-form-target="modalValidatorApplyMember">` +
      `<input type="checkbox" checked data-entity-form-target="modalValidatorApplyPublic">`
    )
    controller.schemaManager = new SchemaManager(controller)
    expect(new AttributeManager(controller).collectValidatorApply()).toEqual({
      admin: true, member: false, public: true
    })
  })
})

describe("AttributeManager#collectEditable", () => {
  it("reads the three editable checkboxes, defaulting to true when absent", () => {
    const { controller } = buildController(
      `<input type="checkbox" data-entity-form-target="modalEditableAdmin">` +
      `<input type="checkbox" data-entity-form-target="modalEditableMember" checked>`
    )
    expect(new AttributeManager(controller).collectEditable()).toEqual({ admin: false, member: true, public: true })
  })
})

describe("AttributeManager#validateAttribute", () => {
  function valController(existing = "") {
    const { controller } = buildController(
      `<div data-entity-form-target="attributesContainer">${existing}</div>` +
      `<div><input data-entity-form-target="modalName"></div>` +
      `<div><input data-entity-form-target="modalDisplayLabel"></div>` +
      `<div><input data-entity-form-target="modalNameSlug"></div>`,
      { values: { extendableModelValue: "User", reservedFieldNamesValue: ["id"], editingRow: null } }
    )
    return controller
  }

  it("fails without a name", () => {
    expect(new AttributeManager(valController()).validateAttribute({ name: "", name_slug: "x", display_label: "X" })).toBe(false)
  })
  it("fails without a display label", () => {
    expect(new AttributeManager(valController()).validateAttribute({ name: "N", name_slug: "n", display_label: "" })).toBe(false)
  })
  it("fails on a reserved slug", () => {
    expect(new AttributeManager(valController()).validateAttribute({ name: "Id", name_slug: "id", display_label: "Id" })).toBe(false)
  })
  it("fails on a duplicate name", () => {
    const c = valController(attrRow("Email", "email"))
    expect(new AttributeManager(c).validateAttribute({ name: "Email", name_slug: "e2", display_label: "Email" })).toBe(false)
  })
  it("fails on a duplicate slug", () => {
    const c = valController(attrRow("Other", "email"))
    expect(new AttributeManager(c).validateAttribute({ name: "New", name_slug: "email", display_label: "New" })).toBe(false)
  })
  it("passes a clean attribute", () => {
    expect(new AttributeManager(valController()).validateAttribute({ name: "Phone", name_slug: "phone", display_label: "Phone" })).toBe(true)
  })
  it("falls back to 'base model' in the reserved-name message when extendableModelValue is unset", () => {
    // isReservedFieldName itself only returns true when extendableModelValue is set, so we
    // stub it directly to exercise the `this.c.extendableModelValue || "base model"` fallback.
    const mgr = new AttributeManager(valController())
    mgr.isReservedFieldName = () => true
    mgr.c.extendableModelValue = ""
    expect(mgr.validateAttribute({ name: "Id", name_slug: "id", display_label: "Id" })).toBe(false)
    expect(mgr.c.modalNameTarget.parentElement.querySelector(".field-error").textContent).toContain("base model")
  })
  it("fails an incomplete computed config and shows the translated message", () => {
    const c = valController()
    c.attributeMode = "computed"
    c.computedManager = { validate: () => "Please complete the computed field configuration" }
    const extra = document.createElement("select")
    extra.setAttribute("data-entity-form-target", "computedRelation")
    c.element.appendChild(extra)
    c.__defineTarget("computedRelation")
    expect(new AttributeManager(c).validateAttribute({ name: "Avg", name_slug: "avg", display_label: "Avg" })).toBe(false)
    expect(c.computedRelationTarget.parentElement.querySelector(".field-error").textContent)
      .toBe("Please complete the computed field configuration")
  })

  it("shows a computed error on the function select when the relation target is missing", () => {
    const c = valController()
    c.attributeMode = "computed"
    c.computedManager = { validate: () => "Please complete the computed field configuration" }
    const extra = document.createElement("select")
    extra.setAttribute("data-entity-form-target", "computedFunction")
    c.element.appendChild(extra)
    c.__defineTarget("computedFunction")
    expect(new AttributeManager(c).validateAttribute({ name: "Avg", name_slug: "avg", display_label: "Avg" })).toBe(false)
    expect(c.computedFunctionTarget.parentElement.querySelector(".field-error")).not.toBeNull()
  })

  it("falls back to the name field for a computed error when no computed targets exist", () => {
    const c = valController()
    c.attributeMode = "computed"
    c.computedManager = { validate: () => "Please complete the computed field configuration" }
    expect(new AttributeManager(c).validateAttribute({ name: "Avg", name_slug: "avg", display_label: "Avg" })).toBe(false)
    expect(c.modalNameTarget.parentElement.querySelector(".field-error")).not.toBeNull()
  })

  it("passes a complete computed attribute", () => {
    const c = valController()
    c.attributeMode = "computed"
    c.computedManager = { validate: () => null }
    expect(new AttributeManager(c).validateAttribute({ name: "Avg", name_slug: "avg", display_label: "Avg" })).toBe(true)
  })

  it("fails entity_entries mode when the reference entity is missing", () => {
    const c = valController()
    c.optionsSourceMode = "entity_entries"
    c.referenceManager = { validate: () => ({ target: "referenceEntitySelect", message: "Pick an entity" }) }
    const extra = document.createElement("select")
    extra.setAttribute("data-entity-form-target", "referenceEntitySelect")
    c.element.appendChild(extra)
    c.__defineTarget("referenceEntitySelect")
    expect(new AttributeManager(c).validateAttribute({ name: "Course", name_slug: "course", display_label: "Course" })).toBe(false)
    expect(c.referenceEntitySelectTarget.parentElement.querySelector(".field-error").textContent).toBe("Pick an entity")
  })

  it("passes entity_entries mode when referenceManager.validate returns null", () => {
    const c = valController()
    c.optionsSourceMode = "entity_entries"
    c.referenceManager = { validate: () => null }
    expect(new AttributeManager(c).validateAttribute({ name: "Course", name_slug: "course", display_label: "Course" })).toBe(true)
  })

  it("treats a missing reservedFieldNamesValue as an empty list", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="attributesContainer"></div>` +
      `<div><input data-entity-form-target="modalName"></div>` +
      `<div><input data-entity-form-target="modalDisplayLabel"></div>` +
      `<div><input data-entity-form-target="modalNameSlug"></div>`,
      { values: { extendableModelValue: "User", editingRow: null } }
    )
    expect(new AttributeManager(controller).isReservedFieldName("id")).toBe(false)
  })
})

describe("AttributeManager#showFieldError", () => {
  it("focuses the field, adds the error ring, and appends an error message", () => {
    const { controller } = buildController(`<div><input data-entity-form-target="modalName"></div>`)
    const field = controller.modalNameTarget
    new AttributeManager(controller).showFieldError(field, "Name is required")
    expect(field.classList.contains("ring-red-500")).toBe(true)
    expect(field.parentElement.querySelector(".field-error").textContent).toBe("Name is required")
  })
})

describe("AttributeManager#generateUniqueName exhaustion path", () => {
  it("increments past a taken numbered copy to find a free one", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="attributesContainer">${attrRow("Field")}${attrRow("Field (Copy)")}${attrRow("Field (Copy 2)")}</div>`
    )
    expect(new AttributeManager(controller).generateUniqueName("Field")).toBe("Field (Copy 3)")
  })

  it("falls back to a timestamp suffix once every numbered copy up to 99 is taken", () => {
    const rows = [attrRow("Field"), attrRow("Field (Copy)")]
    for (let i = 2; i < 100; i++) rows.push(attrRow(`Field (Copy ${i})`))
    const { controller } = buildController(
      `<div data-entity-form-target="attributesContainer">${rows.join("")}</div>`
    )
    const result = new AttributeManager(controller).generateUniqueName("Field")
    expect(result).toMatch(/^Field \(Copy \d+\)$/)
    expect(result).not.toBe("Field (Copy 99)") // every slot 1..99 was taken
  })
})

describe("AttributeManager#collectModalData", () => {
  it("assembles an attribute from the modal targets + collaborators", () => {
    const { controller } = buildController(
      `<input data-entity-form-target="modalName" value="Full Name">` +
      `<select data-entity-form-target="modalHtmlType"><option value="text" selected>text</option></select>` +
      `<input data-entity-form-target="modalDisplayLabel" value="Full Name">` +
      `<input data-entity-form-target="modalDescription" value="desc">` +
      `<input type="checkbox" data-entity-form-target="modalVisibilityAdmin" checked>` +
      `<input type="checkbox" data-entity-form-target="modalVisibilityMember" checked>` +
      `<input type="checkbox" data-entity-form-target="modalVisibilityPublic">` +
      `<input type="checkbox" data-entity-form-target="modalValidatorApplyAdmin" checked>` +
      `<input type="checkbox" data-entity-form-target="modalValidatorApplyMember">` +
      `<input type="checkbox" data-entity-form-target="modalValidatorApplyPublic" checked>`,
      { values: { editingRow: null, optionsSourceMode: "manual" } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.schemaManager = new SchemaManager(controller)
    const data = new AttributeManager(controller).collectModalData()
    expect(data).toMatchObject({
      name: "Full Name",
      name_slug: "full_name", // derived
      display_label: "Full Name",
      html_type: "text",
      description: "desc",
      validators: [],
      visibility: { admin: true, member: true, public: false },
      validator_apply: { admin: true, member: false, public: false },
      group_id: null,
      config: null,
    })
    expect(data).not.toHaveProperty("editable")
  })

  it("includes editable only when a visible audience cannot edit", () => {
    const { controller } = buildController(
      `<input data-entity-form-target="modalName" value="Order Number">` +
      `<input data-entity-form-target="modalDisplayLabel" value="Order Number">` +
      `<input type="checkbox" data-entity-form-target="modalVisibilityAdmin" checked>` +
      `<input type="checkbox" data-entity-form-target="modalVisibilityMember" checked>` +
      `<input type="checkbox" data-entity-form-target="modalVisibilityPublic" checked>` +
      `<input type="checkbox" data-entity-form-target="modalEditableAdmin" checked>` +
      `<input type="checkbox" data-entity-form-target="modalEditableMember">` +
      `<input type="checkbox" data-entity-form-target="modalEditablePublic">`,
      { values: { editingRow: null, optionsSourceMode: "manual" } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.schemaManager = new SchemaManager(controller)
    expect(new AttributeManager(controller).collectModalData().editable).toEqual({
      admin: true, member: false, public: false
    })
  })

  it("defaults html_type to 'text' when the modalHtmlType target is absent", () => {
    const { controller } = buildController(
      `<input data-entity-form-target="modalName" value="X">` +
      `<input data-entity-form-target="modalDisplayLabel" value="X">`,
      { values: { editingRow: null, optionsSourceMode: "manual" } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.schemaManager = new SchemaManager(controller)
    expect(new AttributeManager(controller).collectModalData().html_type).toBe("text")
  })

  it("reads group_id off the editing row's hidden input, falling back to the data attribute", () => {
    const { controller } = buildController(
      `<input data-entity-form-target="modalName" value="X">` +
      `<select data-entity-form-target="modalHtmlType"><option value="text" selected>text</option></select>` +
      `<input data-entity-form-target="modalDisplayLabel" value="X">` +
      `<div data-attribute-item data-attr-group-id="g-from-attr" id="editRow"></div>`,
      { values: { optionsSourceMode: "manual" } }
    )
    controller.editingRow = controller.element.querySelector("#editRow")
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.schemaManager = new SchemaManager(controller)
    expect(new AttributeManager(controller).collectModalData().group_id).toBe("g-from-attr")
  })

  it("prefers the editing row's hidden group_id input over the data attribute", () => {
    const { controller } = buildController(
      `<input data-entity-form-target="modalName" value="X">` +
      `<select data-entity-form-target="modalHtmlType"><option value="text" selected>text</option></select>` +
      `<input data-entity-form-target="modalDisplayLabel" value="X">` +
      `<div data-attribute-item data-attr-group-id="stale" id="editRow"><input data-input="group_id" value="fresh"></div>`,
      { values: { optionsSourceMode: "manual" } }
    )
    controller.editingRow = controller.element.querySelector("#editRow")
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.schemaManager = new SchemaManager(controller)
    expect(new AttributeManager(controller).collectModalData().group_id).toBe("fresh")
  })

  it("emits a Computed payload when the modal is in computed mode", () => {
    const { controller } = buildController(
      `<input data-entity-form-target="modalName" value="Average Score">` +
      `<select data-entity-form-target="modalHtmlType"><option value="text" selected>text</option></select>` +
      `<input data-entity-form-target="modalDisplayLabel" value="Average Score">`,
      { values: { editingRow: null, attributeMode: "computed", optionsSourceMode: "manual" } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.schemaManager = new SchemaManager(controller)
    controller.computedManager = { getComputedConfig: () => ({ bridge_entity_id: 15, function: "avg" }) }
    expect(new AttributeManager(controller).collectModalData()).toMatchObject({
      name: "Average Score",
      type: "Computed",
      html_type: "number",
      readonly: true,
      storage: "computed",
      validators: [],
      config: { bridge_entity_id: 15, function: "avg" },
    })
    expect(new AttributeManager(controller).collectModalData()).not.toHaveProperty("editable")
  })

  it("never carries editable on a computed attribute even when Can edit is cleared", () => {
    const { controller } = buildController(
      `<input data-entity-form-target="modalName" value="Average Score">` +
      `<input data-entity-form-target="modalDisplayLabel" value="Average Score">` +
      `<input type="checkbox" data-entity-form-target="modalVisibilityAdmin" checked>` +
      `<input type="checkbox" data-entity-form-target="modalVisibilityMember" checked>` +
      `<input type="checkbox" data-entity-form-target="modalVisibilityPublic" checked>` +
      `<input type="checkbox" data-entity-form-target="modalEditableAdmin">` +
      `<input type="checkbox" data-entity-form-target="modalEditableMember">` +
      `<input type="checkbox" data-entity-form-target="modalEditablePublic">`,
      { values: { editingRow: null, attributeMode: "computed", optionsSourceMode: "manual" } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.schemaManager = new SchemaManager(controller)
    controller.computedManager = { getComputedConfig: () => ({ function: "avg" }) }
    expect(new AttributeManager(controller).collectModalData()).not.toHaveProperty("editable")
  })

  it("adds owner: true only when the switch is on and the target is a person entity", () => {
    const { controller } = buildController(
      `<input data-entity-form-target="modalName" value="Student">` +
      `<input data-entity-form-target="modalDisplayLabel" value="Student">` +
      `<input type="checkbox" data-entity-form-target="modalOwner" checked>`,
      { values: { editingRow: null, optionsSourceMode: "entity_entries" } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.schemaManager = new SchemaManager(controller)
    controller.referenceManager = { ownerAvailable: () => true }
    expect(new AttributeManager(controller).collectModalData().owner).toBe(true)
  })

  it("omits the owner key when the switch is off", () => {
    const { controller } = buildController(
      `<input data-entity-form-target="modalName" value="Student">` +
      `<input data-entity-form-target="modalDisplayLabel" value="Student">` +
      `<input type="checkbox" data-entity-form-target="modalOwner">`,
      { values: { editingRow: null, optionsSourceMode: "entity_entries" } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.schemaManager = new SchemaManager(controller)
    controller.referenceManager = { ownerAvailable: () => true }
    expect(new AttributeManager(controller).collectModalData()).not.toHaveProperty("owner")
  })

  it("omits the owner key when the target is not a person entity", () => {
    const { controller } = buildController(
      `<input data-entity-form-target="modalName" value="Course">` +
      `<input data-entity-form-target="modalDisplayLabel" value="Course">` +
      `<input type="checkbox" data-entity-form-target="modalOwner" checked>`,
      { values: { editingRow: null, optionsSourceMode: "entity_entries" } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.schemaManager = new SchemaManager(controller)
    controller.referenceManager = { ownerAvailable: () => false }
    expect(new AttributeManager(controller).collectModalData()).not.toHaveProperty("owner")
  })

  it("omits the owner key when referenceManager is missing", () => {
    const { controller } = buildController(
      `<input data-entity-form-target="modalName" value="Student">` +
      `<input data-entity-form-target="modalDisplayLabel" value="Student">` +
      `<input type="checkbox" data-entity-form-target="modalOwner" checked>`,
      { values: { editingRow: null, optionsSourceMode: "entity_entries" } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.schemaManager = new SchemaManager(controller)
    expect(new AttributeManager(controller).collectModalData()).not.toHaveProperty("owner")
  })

  it("omits the owner key without an owner checkbox", () => {
    const { controller } = buildController(
      `<input data-entity-form-target="modalName" value="X">` +
      `<input data-entity-form-target="modalDisplayLabel" value="X">`,
      { values: { editingRow: null, optionsSourceMode: "manual" } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.schemaManager = new SchemaManager(controller)
    expect(new AttributeManager(controller).collectModalData()).not.toHaveProperty("owner")
  })

  it("uses a null computed config when computedManager is missing", () => {
    const { controller } = buildController(
      `<input data-entity-form-target="modalName" value="X">` +
      `<input data-entity-form-target="modalDisplayLabel" value="X">`,
      { values: { editingRow: null, attributeMode: "computed", optionsSourceMode: "manual" } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.schemaManager = new SchemaManager(controller)
    expect(new AttributeManager(controller).collectModalData().config).toBeNull()
  })
})

describe("AttributeManager#removeAttribute", () => {
  it("removes the row, regroups, and re-syncs the schema", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="attributesContainer">${attrRow("A", "a")}</div>`,
      { values: { existingAttributeCount: 0 } }
    )
    const regroup = vi.fn(), sync = vi.fn()
    controller.schemaManager = { regroupAttributeRows: regroup, syncPropertySchema: sync }
    const row = controller.element.querySelector("[data-attribute-item]")
    new AttributeManager(controller).removeAttribute(fakeEvent({ target: row }))
    expect(controller.attributesContainerTarget.querySelector("[data-attribute-item]")).toBeNull()
    expect(regroup).toHaveBeenCalled()
    expect(sync).toHaveBeenCalled()
  })
})

describe("AttributeManager#addAttributeFromModal", () => {
  it("appends a valid new attribute, bumps the index, and closes the modal", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="attributesContainer"></div>` +
      `<input data-entity-form-target="modalName" value="Age">` +
      `<select data-entity-form-target="modalHtmlType"><option value="number" selected>number</option></select>` +
      `<input data-entity-form-target="modalDisplayLabel" value="Age">` +
      `<input data-entity-form-target="modalDescription" value="">` +
      `<button data-entity-form-target="modalSubmitBtn"></button>`,
      { values: { attributeIndex: 0, editingRow: null, optionsSourceMode: "manual", isProcessingModal: false, attributeModalContext: "entity" } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.templateBuilder = new TemplateBuilder(controller)
    controller.schemaManager = new SchemaManager(controller)
    const closeModal = vi.fn()
    controller.modalManager = { closeModal }
    const mgr = new AttributeManager(controller)
    mgr.hideEmptyState = () => {}

    mgr.addAttributeFromModal(fakeEvent())
    expect(controller.attributesContainerTarget.querySelectorAll("[data-attribute-item]").length).toBe(1)
    expect(controller.attributeIndex).toBe(1)
    expect(closeModal).toHaveBeenCalled()
    expect(controller.isProcessingModal).toBe(false)
  })

  it("re-entrancy guard: bails while another modal submit is in flight", () => {
    const { controller } = buildController(`<div data-entity-form-target="attributesContainer"></div>`, {
      values: { isProcessingModal: true },
    })
    let collected = false
    const mgr = new AttributeManager(controller)
    mgr.collectModalData = () => { collected = true; return {} }
    mgr.addAttributeFromModal(fakeEvent())
    expect(collected).toBe(false)
  })

  it("bails without appending when validation fails (missing name)", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="attributesContainer"></div>` +
      `<div><input data-entity-form-target="modalName" value=""></div>` +
      `<div><input data-entity-form-target="modalDisplayLabel" value=""></div>`,
      { values: { editingRow: null, optionsSourceMode: "manual", isProcessingModal: false, attributeModalContext: "entity" } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.schemaManager = new SchemaManager(controller)
    controller.modalManager = { closeModal: vi.fn() }
    new AttributeManager(controller).addAttributeFromModal(fakeEvent())
    expect(controller.attributesContainerTarget.querySelectorAll("[data-attribute-item]").length).toBe(0)
    // resets the re-entrancy guard even on the invalid path
    expect(controller.isProcessingModal).toBe(false)
  })

  it("routes to the association manager when the modal context is association (no submit btn)", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="attributesContainer"></div>` +
      `<input data-entity-form-target="modalName" value="Qty">` +
      `<input data-entity-form-target="modalDisplayLabel" value="Qty">`,
      { values: { editingRow: null, optionsSourceMode: "manual", isProcessingModal: false, attributeModalContext: "association" } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.schemaManager = new SchemaManager(controller)
    const addAttributeToAssociation = vi.fn()
    controller.associationManager = { addAttributeToAssociation }
    controller.modalManager = { closeModal: vi.fn() }
    new AttributeManager(controller).addAttributeFromModal(fakeEvent())
    expect(addAttributeToAssociation).toHaveBeenCalledWith(expect.objectContaining({ name: "Qty" }))
  })

  it("updates the editing row in place instead of appending", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="attributesContainer"><div data-attribute-item id="editRow"></div></div>` +
      `<input data-entity-form-target="modalName" value="Renamed">` +
      `<input data-entity-form-target="modalDisplayLabel" value="Renamed">`,
      { values: { optionsSourceMode: "manual", isProcessingModal: false, attributeModalContext: "entity" } }
    )
    controller.editingRow = controller.element.querySelector("#editRow")
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.schemaManager = new SchemaManager(controller)
    const updateAttributeRow = vi.fn(), syncPropertySchema = vi.fn()
    controller.schemaManager.updateAttributeRow = updateAttributeRow
    controller.schemaManager.syncPropertySchema = syncPropertySchema
    controller.modalManager = { closeModal: vi.fn() }
    new AttributeManager(controller).addAttributeFromModal(fakeEvent())
    expect(updateAttributeRow).toHaveBeenCalledWith(controller.editingRow, expect.objectContaining({ name: "Renamed" }))
    expect(syncPropertySchema).toHaveBeenCalled()
  })
})

describe("AttributeManager#copyAttribute", () => {
  function copyController({ withRow = true } = {}) {
    const { controller } = buildController(
      `<div data-entity-form-target="attributesContainer">` +
      (withRow ? `<div data-attribute-item id="src"><input data-input="name" value="Field"></div>` : "") +
      `</div>` +
      `<div data-entity-form-target="modal" class="hidden"></div>`
    )
    controller.modalManager = { resetModalFields: vi.fn(), prefillModalWithAttribute: vi.fn(), resetModalSectionNav: vi.fn(), focusModalNameField: vi.fn() }
    return controller
  }

  it("clones a row into the modal with a unique name and opens it", () => {
    const c = copyController()
    c.schemaManager = { extractAttributeFromRow: vi.fn(() => ({ name: "Field", name_slug: "field" })) }
    const row = c.element.querySelector("#src")
    new AttributeManager(c).copyAttribute(fakeEvent({ target: row }))
    expect(c.modalManager.resetModalFields).toHaveBeenCalled()
    const prefilled = c.modalManager.prefillModalWithAttribute.mock.calls[0][0]
    expect(prefilled.name).toBe("Field (Copy)")
    expect(prefilled.name_slug).toBe("field_copy")
    expect(c.modalTarget.classList.contains("hidden")).toBe(false)
    expect(c.modalManager.resetModalSectionNav).toHaveBeenCalled()
    expect(c.modalManager.focusModalNameField).toHaveBeenCalled()
  })

  it("bails when the click is not inside a row", () => {
    const c = copyController({ withRow: false })
    c.schemaManager = { extractAttributeFromRow: vi.fn() }
    const orphan = document.createElement("button")
    new AttributeManager(c).copyAttribute(fakeEvent({ target: orphan }))
    expect(c.schemaManager.extractAttributeFromRow).not.toHaveBeenCalled()
  })

  it("bails when the row cannot be extracted", () => {
    const c = copyController()
    c.schemaManager = { extractAttributeFromRow: vi.fn(() => null) }
    const row = c.element.querySelector("#src")
    new AttributeManager(c).copyAttribute(fakeEvent({ target: row }))
    expect(c.modalManager.prefillModalWithAttribute).not.toHaveBeenCalled()
  })
})

describe("AttributeManager#editAttribute", () => {
  function editController({ withRow = true } = {}) {
    const { controller } = buildController(
      `<div data-entity-form-target="attributesContainer">` +
      (withRow ? `<div data-attribute-item id="src"><input data-input="name" value="Field"></div>` : "") +
      `</div>` +
      `<h2 data-entity-form-target="modalTitle"></h2>` +
      `<button data-entity-form-target="modalSubmitBtn"></button>` +
      `<div data-entity-form-target="modal" class="hidden"></div>`
    )
    controller.modalManager = { resetModalFields: vi.fn(), prefillModalWithAttribute: vi.fn(), resetModalSectionNav: vi.fn(), focusModalNameField: vi.fn() }
    return controller
  }

  it("marks the row as editing, switches modal copy, and opens it", () => {
    const c = editController()
    c.schemaManager = { extractAttributeFromRow: vi.fn(() => ({ name: "Field" })) }
    const row = c.element.querySelector("#src")
    new AttributeManager(c).editAttribute(fakeEvent({ target: row }))
    expect(c.editingRow).toBe(row)
    expect(c.modalTitleTarget.textContent).toBe("Edit Attribute")
    expect(c.modalSubmitBtnTarget.textContent).toBe("Save Changes")
    expect(c.modalTarget.classList.contains("hidden")).toBe(false)
    expect(c.modalManager.resetModalSectionNav).toHaveBeenCalled()
    expect(c.modalManager.focusModalNameField).toHaveBeenCalled()
  })

  it("bails when the click is not inside a row", () => {
    const c = editController({ withRow: false })
    c.schemaManager = { extractAttributeFromRow: vi.fn() }
    new AttributeManager(c).editAttribute(fakeEvent({ target: document.createElement("span") }))
    expect(c.schemaManager.extractAttributeFromRow).not.toHaveBeenCalled()
  })

  it("bails when the row cannot be extracted", () => {
    const c = editController()
    c.schemaManager = { extractAttributeFromRow: vi.fn(() => null) }
    const row = c.element.querySelector("#src")
    new AttributeManager(c).editAttribute(fakeEvent({ target: row }))
    expect(c.modalManager.prefillModalWithAttribute).not.toHaveBeenCalled()
  })
})

describe("AttributeManager empty-state helpers", () => {
  it("hideEmptyState hides the empty state and tolerates its absence", () => {
    const { controller } = buildController(`<div data-entity-form-target="emptyState"></div>`)
    new AttributeManager(controller).hideEmptyState()
    expect(controller.emptyStateTarget.classList.contains("hidden")).toBe(true)

    const { controller: bare } = buildController("")
    expect(() => new AttributeManager(bare).hideEmptyState()).not.toThrow()
  })

  it("showEmptyStateIfNeeded reveals the empty state and drops the table when no attributes remain", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="emptyState" class="hidden"></div>` +
      `<table data-entity-form-target="attributesTable"></table>`,
      { values: { existingAttributeCount: 0 } }
    )
    new AttributeManager(controller).showEmptyStateIfNeeded()
    expect(controller.emptyStateTarget.classList.contains("hidden")).toBe(false)
    expect(controller.hasAttributesTableTarget).toBe(false) // removed
  })

  it("showEmptyStateIfNeeded is a no-op while attributes still exist", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="emptyState" class="hidden"></div>`,
      { values: { existingAttributeCount: 2 } }
    )
    new AttributeManager(controller).showEmptyStateIfNeeded()
    expect(controller.emptyStateTarget.classList.contains("hidden")).toBe(true)
  })
})

describe("AttributeManager#removeAttribute guard", () => {
  it("no-ops when the click is not inside a row", () => {
    const { controller } = buildController(`<div data-entity-form-target="attributesContainer"></div>`)
    controller.schemaManager = { regroupAttributeRows: vi.fn(), syncPropertySchema: vi.fn() }
    new AttributeManager(controller).removeAttribute(fakeEvent({ target: document.createElement("span") }))
    expect(controller.schemaManager.regroupAttributeRows).not.toHaveBeenCalled()
  })
})
