import { describe, it, expect, vi } from "vitest"
import { ModalManager } from "controllers/entity_form/modal_manager"
import { SchemaManager } from "controllers/entity_form/schema_manager"
import { TemplateBuilder } from "controllers/entity_form/template_builder"
import { TypeManager } from "controllers/entity_form/type_manager"
import { ValidatorManager } from "controllers/entity_form/validator_manager"
import { buildController, fakeEvent } from "./support.js"

// getValidatorLabel already falls back to the raw key for unknown validators, so
// modal_manager's own `getValidatorLabel(...) || validator` fallback can only be
// exercised by forcing the lookup itself to return a falsy value. VALIDATOR_LABELS
// (used by the real ValidatorManager elsewhere in this file) is left untouched.
vi.mock("constants/validator_labels", async (importOriginal) => {
  const actual = await importOriginal()
  return { ...actual, getValidatorLabel: (key) => actual.VALIDATOR_LABELS[key] }
})

// ModalManager fans out into several sibling managers. Provide light stubs for
// the collaborators whose internals we are not exercising in a given test.
function stubbedSiblings(controller) {
  controller.constantsManager = { updateOptionsSourceUI: vi.fn(), hideConstantPreview: vi.fn() }
  controller.validatorManager = controller.validatorManager || {
    hideValidatorConfigSection: vi.fn(),
    appendValidatorBadge: vi.fn(),
    buildValidatorLabelWithConfig: vi.fn()
  }
  controller.typeManager = controller.typeManager || { hideConfigSection: vi.fn(), hideAllConfigContainers: vi.fn() }
  controller.computedManager = controller.computedManager || {
    reset: vi.fn(),
    selectInputMode: vi.fn(),
    selectComputedMode: vi.fn(),
    applyComputedConfig: vi.fn(),
    updateModeUI: vi.fn(),
  }
}

describe("ModalManager#openModal / closeModal", () => {
  it("openModal reveals the modal, locks scroll, and seeds manual mode", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="modal" class="hidden"></div>` +
      `<input data-entity-form-target="modalName">`
    )
    stubbedSiblings(controller)
    new ModalManager(controller).openModal(fakeEvent())
    expect(controller.modalTarget.classList.contains("hidden")).toBe(false)
    expect(document.body.style.overflow).toBe("hidden")
    expect(controller.attributeModalContext).toBe("entity")
    expect(controller.inclusionManuallyRemoved).toBe(false)
    expect(controller.optionsSourceMode).toBe("manual")
    expect(controller.constantsManager.updateOptionsSourceUI).toHaveBeenCalled()
    expect(controller.computedManager.updateModeUI).toHaveBeenCalled()
  })

  it("openModal resets the reference manager when one is attached", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="modal" class="hidden"></div>`
    )
    stubbedSiblings(controller)
    controller.referenceManager = { reset: vi.fn() }
    new ModalManager(controller).openModal(fakeEvent())
    expect(controller.referenceManager.reset).toHaveBeenCalled()
  })

  it("openModal no-ops without a modal target", () => {
    const { controller } = buildController("")
    stubbedSiblings(controller)
    expect(() => new ModalManager(controller).openModal(fakeEvent())).not.toThrow()
    expect(controller.constantsManager.updateOptionsSourceUI).not.toHaveBeenCalled()
  })

  it("openModalForAssociationAttribute no-ops without a modal target", () => {
    const { controller } = buildController("")
    stubbedSiblings(controller)
    expect(() => new ModalManager(controller).openModalForAssociationAttribute(fakeEvent())).not.toThrow()
    expect(controller.constantsManager.updateOptionsSourceUI).not.toHaveBeenCalled()
  })

  it("openModalForAssociationAttribute tolerates being called without an event", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="modal" class="hidden"></div>`
    )
    stubbedSiblings(controller)
    expect(() => new ModalManager(controller).openModalForAssociationAttribute()).not.toThrow()
  })

  it("closeModal no-ops without a modal target", () => {
    const { controller } = buildController("")
    stubbedSiblings(controller)
    expect(() => new ModalManager(controller).closeModal(fakeEvent())).not.toThrow()
  })

  it("openModalForAssociationAttribute sets association context + titles", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="modal" class="hidden"></div>` +
      `<h2 data-entity-form-target="modalTitle"></h2>` +
      `<button data-entity-form-target="modalSubmitBtn"></button>`
    )
    stubbedSiblings(controller)
    new ModalManager(controller).openModalForAssociationAttribute(fakeEvent())
    expect(controller.attributeModalContext).toBe("association")
    expect(controller.editingAssociationAttributeIndex).toBeNull()
    expect(controller.modalTitleTarget.textContent).toBe("Add Association Attribute")
    expect(controller.modalSubmitBtnTarget.textContent).toBe("Add Attribute")
    expect(controller.computedManager.updateModeUI).toHaveBeenCalled()
  })

  it("openModalForAssociationAttribute resets the reference manager when one is attached", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="modal" class="hidden"></div>`
    )
    stubbedSiblings(controller)
    controller.referenceManager = { reset: vi.fn() }
    new ModalManager(controller).openModalForAssociationAttribute(fakeEvent())
    expect(controller.referenceManager.reset).toHaveBeenCalled()
  })

  it("closeModal hides the modal, restores scroll, and resets titles", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="modal"></div>` +
      `<h2 data-entity-form-target="modalTitle">Edit Attribute</h2>` +
      `<button data-entity-form-target="modalSubmitBtn">Save Changes</button>`
    )
    stubbedSiblings(controller)
    document.body.style.overflow = "hidden"
    new ModalManager(controller).closeModal(fakeEvent())
    expect(controller.modalTarget.classList.contains("hidden")).toBe(true)
    expect(document.body.style.overflow).toBe("")
    expect(controller.modalTitleTarget.textContent).toBe("Add Attribute")
    expect(controller.attributeModalContext).toBe("entity")
  })

  it("closeModal no-ops when the modal is already hidden", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="modal" class="hidden"></div>` +
      `<h2 data-entity-form-target="modalTitle">Edit Attribute</h2>`
    )
    stubbedSiblings(controller)
    new ModalManager(controller).closeModal(fakeEvent())
    expect(controller.modalTitleTarget.textContent).toBe("Edit Attribute")
  })

  it("openModal clicks the definition section tab when present", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="modal" class="hidden">` +
      `<button data-tabs-target="tab" data-tabs-id="definition">Field</button>` +
      `</div>` +
      `<input data-entity-form-target="modalName">`
    )
    stubbedSiblings(controller)
    const tab = controller.modalTarget.querySelector("[data-tabs-id='definition']")
    const click = vi.spyOn(tab, "click")
    new ModalManager(controller).openModal(fakeEvent())
    expect(click).toHaveBeenCalled()
  })

  it("resetModalSectionNav no-ops without a modal target", () => {
    const { controller } = buildController("")
    stubbedSiblings(controller)
    expect(() => new ModalManager(controller).resetModalSectionNav()).not.toThrow()
  })

  it("resetModalSectionNav no-ops without a definition tab", () => {
    const { controller } = buildController(`<div data-entity-form-target="modal"></div>`)
    stubbedSiblings(controller)
    expect(() => new ModalManager(controller).resetModalSectionNav()).not.toThrow()
  })
})

describe("ModalManager visibility↔validator_apply sync", () => {
  const visHtml =
    `<input type="checkbox" checked data-entity-form-target="modalVisibilityAdmin">` +
    `<input type="checkbox" checked data-entity-form-target="modalVisibilityMember">` +
    `<input type="checkbox" checked data-entity-form-target="modalVisibilityPublic">` +
    `<input type="checkbox" checked data-entity-form-target="modalEditableAdmin">` +
    `<input type="checkbox" checked data-entity-form-target="modalEditableMember">` +
    `<input type="checkbox" checked data-entity-form-target="modalEditablePublic">` +
    `<input type="checkbox" checked data-entity-form-target="modalValidatorApplyAdmin">` +
    `<input type="checkbox" checked data-entity-form-target="modalValidatorApplyMember">` +
    `<input type="checkbox" checked data-entity-form-target="modalValidatorApplyPublic">`

  it("unchecks and disables Apply when Visible is off", () => {
    const { controller } = buildController(visHtml)
    const mm = new ModalManager(controller)
    controller.modalVisibilityPublicTarget.checked = false
    mm.syncValidatorApplyWithVisibility()
    expect(controller.modalValidatorApplyPublicTarget.checked).toBe(false)
    expect(controller.modalValidatorApplyPublicTarget.disabled).toBe(true)
    expect(controller.modalValidatorApplyAdminTarget.disabled).toBe(false)
    expect(controller.modalEditablePublicTarget.checked).toBe(false)
    expect(controller.modalEditablePublicTarget.disabled).toBe(true)
  })

  it("unchecks and disables Apply when Can edit is off while Visible stays on", () => {
    const { controller } = buildController(visHtml)
    const mm = new ModalManager(controller)
    controller.modalEditableMemberTarget.checked = false
    mm.syncValidatorApplyWithVisibility()
    expect(controller.modalEditableMemberTarget.disabled).toBe(false)
    expect(controller.modalValidatorApplyMemberTarget.checked).toBe(false)
    expect(controller.modalValidatorApplyMemberTarget.disabled).toBe(true)
    expect(controller.modalValidatorApplyAdminTarget.disabled).toBe(false)
  })

  it("enables and checks Apply when Visible Admin turns on via visibilityAudienceChanged", () => {
    const { controller } = buildController(visHtml)
    const mm = new ModalManager(controller)
    controller.modalVisibilityAdminTarget.checked = false
    mm.syncValidatorApplyWithVisibility()
    controller.modalVisibilityAdminTarget.checked = true
    mm.visibilityAudienceChanged({ target: controller.modalVisibilityAdminTarget })
    expect(controller.modalEditableAdminTarget.disabled).toBe(false)
    expect(controller.modalEditableAdminTarget.checked).toBe(true)
    expect(controller.modalValidatorApplyAdminTarget.disabled).toBe(false)
    expect(controller.modalValidatorApplyAdminTarget.checked).toBe(true)
  })

  it("enables and checks Apply when Visible Member turns on via visibilityAudienceChanged", () => {
    const { controller } = buildController(visHtml)
    const mm = new ModalManager(controller)
    controller.modalVisibilityMemberTarget.checked = false
    mm.syncValidatorApplyWithVisibility()
    controller.modalVisibilityMemberTarget.checked = true
    mm.visibilityAudienceChanged({ target: controller.modalVisibilityMemberTarget })
    expect(controller.modalEditableMemberTarget.checked).toBe(true)
    expect(controller.modalValidatorApplyMemberTarget.disabled).toBe(false)
    expect(controller.modalValidatorApplyMemberTarget.checked).toBe(true)
  })

  it("enables and checks Apply when Visible Public turns on via visibilityAudienceChanged", () => {
    const { controller } = buildController(visHtml)
    const mm = new ModalManager(controller)
    controller.modalVisibilityPublicTarget.checked = false
    mm.syncValidatorApplyWithVisibility()
    controller.modalVisibilityPublicTarget.checked = true
    mm.visibilityAudienceChanged({
      target: controller.modalVisibilityPublicTarget,
      preventDefault() {},
      stopPropagation() {}
    })
    expect(controller.modalEditablePublicTarget.checked).toBe(true)
    expect(controller.modalValidatorApplyPublicTarget.disabled).toBe(false)
    expect(controller.modalValidatorApplyPublicTarget.checked).toBe(true)
  })

  it("enables and checks Apply when Can edit Admin turns on via visibilityAudienceChanged", () => {
    const { controller } = buildController(visHtml)
    const mm = new ModalManager(controller)
    controller.modalEditableAdminTarget.checked = false
    mm.syncValidatorApplyWithVisibility()
    controller.modalEditableAdminTarget.checked = true
    mm.visibilityAudienceChanged({ target: controller.modalEditableAdminTarget })
    expect(controller.modalValidatorApplyAdminTarget.disabled).toBe(false)
    expect(controller.modalValidatorApplyAdminTarget.checked).toBe(true)
  })

  it("enables and checks Apply when Can edit Member turns on via visibilityAudienceChanged", () => {
    const { controller } = buildController(visHtml)
    const mm = new ModalManager(controller)
    controller.modalEditableMemberTarget.checked = false
    mm.syncValidatorApplyWithVisibility()
    controller.modalEditableMemberTarget.checked = true
    mm.visibilityAudienceChanged({ target: controller.modalEditableMemberTarget })
    expect(controller.modalValidatorApplyMemberTarget.disabled).toBe(false)
    expect(controller.modalValidatorApplyMemberTarget.checked).toBe(true)
  })

  it("enables and checks Apply when Can edit Public turns on via visibilityAudienceChanged", () => {
    const { controller } = buildController(visHtml)
    const mm = new ModalManager(controller)
    controller.modalEditablePublicTarget.checked = false
    mm.syncValidatorApplyWithVisibility()
    controller.modalEditablePublicTarget.checked = true
    mm.visibilityAudienceChanged({ target: controller.modalEditablePublicTarget })
    expect(controller.modalValidatorApplyPublicTarget.disabled).toBe(false)
    expect(controller.modalValidatorApplyPublicTarget.checked).toBe(true)
  })

  it("visibilityAudienceChanged unchecks and disables Apply when Visible turns off (early return)", () => {
    const { controller } = buildController(visHtml)
    const mm = new ModalManager(controller)
    controller.modalVisibilityAdminTarget.checked = true
    controller.modalValidatorApplyAdminTarget.checked = true
    controller.modalValidatorApplyAdminTarget.disabled = false
    controller.modalVisibilityAdminTarget.checked = false
    mm.visibilityAudienceChanged({ target: controller.modalVisibilityAdminTarget })
    expect(controller.modalEditableAdminTarget.checked).toBe(false)
    expect(controller.modalEditableAdminTarget.disabled).toBe(true)
    expect(controller.modalValidatorApplyAdminTarget.checked).toBe(false)
    expect(controller.modalValidatorApplyAdminTarget.disabled).toBe(true)
  })

  it("visibilityAudienceChanged unchecks and disables Apply when Can edit turns off", () => {
    const { controller } = buildController(visHtml)
    const mm = new ModalManager(controller)
    controller.modalEditableAdminTarget.checked = false
    mm.visibilityAudienceChanged({ target: controller.modalEditableAdminTarget })
    expect(controller.modalEditableAdminTarget.disabled).toBe(false)
    expect(controller.modalValidatorApplyAdminTarget.checked).toBe(false)
    expect(controller.modalValidatorApplyAdminTarget.disabled).toBe(true)
  })

  it("visibilityAudienceChanged no-ops restore when the event or target is missing", () => {
    const { controller } = buildController(visHtml)
    const mm = new ModalManager(controller)
    expect(() => mm.visibilityAudienceChanged()).not.toThrow()
    expect(() => mm.visibilityAudienceChanged({})).not.toThrow()
    expect(() => mm.visibilityAudienceChanged({ target: { checked: true } })).not.toThrow()
  })

  it("visibilityAudienceChanged restores Apply when Visible turns on even if Can edit is missing", () => {
    const { controller } = buildController(
      `<input type="checkbox" data-entity-form-target="modalVisibilityAdmin">` +
      `<input type="checkbox" data-entity-form-target="modalValidatorApplyAdmin">`
    )
    const mm = new ModalManager(controller)
    controller.modalVisibilityAdminTarget.checked = false
    mm.syncValidatorApplyWithVisibility()
    controller.modalVisibilityAdminTarget.checked = true
    mm.visibilityAudienceChanged({ target: controller.modalVisibilityAdminTarget })
    expect(controller.modalValidatorApplyAdminTarget.checked).toBe(true)
    expect(controller.modalValidatorApplyAdminTarget.disabled).toBe(false)
  })

  it("visibilityAudienceChanged restores nothing extra when Apply is missing", () => {
    const { controller } = buildController(
      `<input type="checkbox" data-entity-form-target="modalVisibilityMember">` +
      `<input type="checkbox" data-entity-form-target="modalEditableMember">`
    )
    const mm = new ModalManager(controller)
    controller.modalVisibilityMemberTarget.checked = true
    expect(() => mm.visibilityAudienceChanged({ target: controller.modalVisibilityMemberTarget })).not.toThrow()
    expect(controller.modalEditableMemberTarget.checked).toBe(true)
    controller.modalEditableMemberTarget.checked = true
    expect(() => mm.visibilityAudienceChanged({ target: controller.modalEditableMemberTarget })).not.toThrow()
  })

  it("syncValidatorApplyWithVisibility no-ops pairs with missing visibility or apply targets", () => {
    const { controller } = buildController(
      `<input type="checkbox" checked data-entity-form-target="modalVisibilityAdmin">` +
      `<input type="checkbox" checked data-entity-form-target="modalVisibilityMember">` +
      `<input type="checkbox" checked data-entity-form-target="modalValidatorApplyMember">`
    )
    const mm = new ModalManager(controller)
    expect(() => mm.syncValidatorApplyWithVisibility()).not.toThrow()
    controller.modalVisibilityMemberTarget.checked = false
    mm.syncValidatorApplyWithVisibility()
    expect(controller.modalValidatorApplyMemberTarget.checked).toBe(false)
    expect(controller.modalValidatorApplyMemberTarget.disabled).toBe(true)
  })

  it("treats a missing Visible checkbox as on when syncing Apply from Can edit", () => {
    const { controller } = buildController(
      `<input type="checkbox" checked data-entity-form-target="modalEditableAdmin">` +
      `<input type="checkbox" checked data-entity-form-target="modalValidatorApplyAdmin">`
    )
    new ModalManager(controller).syncValidatorApplyWithVisibility()
    expect(controller.modalEditableAdminTarget.disabled).toBe(false)
    expect(controller.modalValidatorApplyAdminTarget.disabled).toBe(false)
  })

  it("disables Apply from Can edit alone when Visible is missing", () => {
    const { controller } = buildController(
      `<input type="checkbox" data-entity-form-target="modalEditableAdmin">` +
      `<input type="checkbox" checked data-entity-form-target="modalValidatorApplyAdmin">`
    )
    new ModalManager(controller).syncValidatorApplyWithVisibility()
    expect(controller.modalValidatorApplyAdminTarget.checked).toBe(false)
    expect(controller.modalValidatorApplyAdminTarget.disabled).toBe(true)
  })

  it("prefill coerces Apply off+disabled when visibility is false", () => {
    const { controller } = buildController(
      visHtml +
      `<input data-entity-form-target="modalName">` +
      `<input data-entity-form-target="modalNameSlug">` +
      `<input data-entity-form-target="modalDisplayLabel">` +
      `<select data-entity-form-target="modalHtmlType"><option value="text">text</option></select>` +
      `<textarea data-entity-form-target="modalDescription"></textarea>` +
      `<div data-entity-form-target="validatorsContainer"></div>`
    )
    stubbedSiblings(controller)
    new ModalManager(controller).prefillModalWithAttribute({
      name: "X", name_slug: "x", display_label: "X", html_type: "text",
      description: "", validators: [],
      visibility: { admin: true, member: true, public: false },
      validator_apply: { admin: true, member: true, public: true },
      config: null
    })
    expect(controller.modalVisibilityPublicTarget.checked).toBe(false)
    expect(controller.modalEditablePublicTarget.checked).toBe(false)
    expect(controller.modalEditablePublicTarget.disabled).toBe(true)
    expect(controller.modalValidatorApplyPublicTarget.checked).toBe(false)
    expect(controller.modalValidatorApplyPublicTarget.disabled).toBe(true)
  })

  it("prefill coerces Apply off+disabled when Can edit is false", () => {
    const { controller } = buildController(
      visHtml +
      `<input data-entity-form-target="modalName">` +
      `<input data-entity-form-target="modalNameSlug">` +
      `<input data-entity-form-target="modalDisplayLabel">` +
      `<select data-entity-form-target="modalHtmlType"><option value="text">text</option></select>` +
      `<textarea data-entity-form-target="modalDescription"></textarea>` +
      `<div data-entity-form-target="validatorsContainer"></div>`
    )
    stubbedSiblings(controller)
    new ModalManager(controller).prefillModalWithAttribute({
      name: "X", name_slug: "x", display_label: "X", html_type: "text",
      description: "", validators: [],
      visibility: { admin: true, member: true, public: true },
      editable: { admin: true, member: false, public: true },
      validator_apply: { admin: true, member: true, public: true },
      config: null
    })
    expect(controller.modalEditableMemberTarget.checked).toBe(false)
    expect(controller.modalEditableMemberTarget.disabled).toBe(false)
    expect(controller.modalValidatorApplyMemberTarget.checked).toBe(false)
    expect(controller.modalValidatorApplyMemberTarget.disabled).toBe(true)
  })
})

describe("ModalManager visibility helpers", () => {
  const visHtml =
    `<input type="checkbox" data-entity-form-target="modalVisibilityAdmin">` +
    `<input type="checkbox" data-entity-form-target="modalVisibilityMember">` +
    `<input type="checkbox" data-entity-form-target="modalVisibilityPublic">` +
    `<input type="checkbox" data-entity-form-target="modalEditableAdmin">` +
    `<input type="checkbox" data-entity-form-target="modalEditableMember">` +
    `<input type="checkbox" data-entity-form-target="modalEditablePublic">` +
    `<input type="checkbox" data-entity-form-target="modalValidatorApplyAdmin">` +
    `<input type="checkbox" data-entity-form-target="modalValidatorApplyMember">` +
    `<input type="checkbox" data-entity-form-target="modalValidatorApplyPublic">`

  it("resetModalVisibility sets all three checkboxes", () => {
    const { controller } = buildController(visHtml)
    new ModalManager(controller).resetModalVisibility(true)
    expect(controller.modalVisibilityAdminTarget.checked).toBe(true)
    expect(controller.modalVisibilityPublicTarget.checked).toBe(true)
  })

  it("applyVisibility respects explicit false, defaults the rest to checked", () => {
    const { controller } = buildController(visHtml)
    new ModalManager(controller).applyVisibility({ admin: false, member: true })
    expect(controller.modalVisibilityAdminTarget.checked).toBe(false)
    expect(controller.modalVisibilityMemberTarget.checked).toBe(true)
    expect(controller.modalVisibilityPublicTarget.checked).toBe(true)
  })

  it("applyVisibility with a non-object defaults everything on", () => {
    const { controller } = buildController(visHtml)
    new ModalManager(controller).applyVisibility(null)
    expect(controller.modalVisibilityAdminTarget.checked).toBe(true)
  })

  it("resetModalValidatorApply sets all three checkboxes", () => {
    const { controller } = buildController(visHtml)
    new ModalManager(controller).resetModalValidatorApply(true)
    expect(controller.modalValidatorApplyAdminTarget.checked).toBe(true)
    expect(controller.modalValidatorApplyMemberTarget.checked).toBe(true)
    expect(controller.modalValidatorApplyPublicTarget.checked).toBe(true)
  })

  it("applyValidatorApply respects explicit false, defaults the rest to checked", () => {
    const { controller } = buildController(visHtml)
    new ModalManager(controller).applyValidatorApply({ admin: false, member: true })
    expect(controller.modalValidatorApplyAdminTarget.checked).toBe(false)
    expect(controller.modalValidatorApplyMemberTarget.checked).toBe(true)
    expect(controller.modalValidatorApplyPublicTarget.checked).toBe(true)
  })

  it("applyValidatorApply with a non-object defaults everything on", () => {
    const { controller } = buildController(visHtml)
    new ModalManager(controller).applyValidatorApply(null)
    expect(controller.modalValidatorApplyAdminTarget.checked).toBe(true)
  })

  it("resetModalEditable sets all three checkboxes and re-enables them", () => {
    const { controller } = buildController(visHtml)
    controller.modalEditableAdminTarget.disabled = true
    new ModalManager(controller).resetModalEditable(true)
    expect(controller.modalEditableAdminTarget.checked).toBe(true)
    expect(controller.modalEditableMemberTarget.checked).toBe(true)
    expect(controller.modalEditablePublicTarget.checked).toBe(true)
    expect(controller.modalEditableAdminTarget.disabled).toBe(false)
  })

  it("resetModalEditable no-ops when editable targets are missing", () => {
    const { controller } = buildController(
      `<input type="checkbox" data-entity-form-target="modalVisibilityAdmin">`
    )
    expect(() => new ModalManager(controller).resetModalEditable(true)).not.toThrow()
  })

  it("applyEditable respects explicit false, defaults the rest to checked", () => {
    const { controller } = buildController(visHtml)
    new ModalManager(controller).applyEditable({ admin: false, member: true })
    expect(controller.modalEditableAdminTarget.checked).toBe(false)
    expect(controller.modalEditableMemberTarget.checked).toBe(true)
    expect(controller.modalEditablePublicTarget.checked).toBe(true)
  })

  it("applyEditable with a non-object defaults everything on", () => {
    const { controller } = buildController(visHtml)
    new ModalManager(controller).applyEditable(null)
    expect(controller.modalEditableAdminTarget.checked).toBe(true)
  })

  it("applyEditable skips missing editable targets", () => {
    const { controller } = buildController(
      `<input type="checkbox" data-entity-form-target="modalVisibilityAdmin">`
    )
    expect(() => new ModalManager(controller).applyEditable({ admin: false })).not.toThrow()
  })
})

describe("ModalManager#resetModalFields", () => {
  it("clears name/description, empties validators + options, resets indices", () => {
    const { controller } = buildController(
      `<input data-entity-form-target="modalName" value="X">` +
      `<input data-entity-form-target="modalNameSlug" value="x">` +
      `<input data-entity-form-target="modalDescription" value="d">` +
      `<div data-entity-form-target="validatorsContainer"><span>badge</span></div>` +
      `<div data-entity-form-target="optionsContainer"><div>opt</div></div>` +
      `<h2 data-entity-form-target="modalTitle">Edit Attribute</h2>` +
      `<button data-entity-form-target="modalSubmitBtn">Save Changes</button>`,
      { values: { optionIndex: 5, optionsSourceMode: "constant", editingRow: {} } }
    )
    stubbedSiblings(controller)
    new ModalManager(controller).resetModalFields()
    expect(controller.modalNameTarget.value).toBe("")
    expect(controller.modalDescriptionTarget.value).toBe("")
    expect(controller.validatorsContainerTarget.innerHTML).toBe("")
    expect(controller.optionsContainerTarget.innerHTML).toBe("")
    expect(controller.optionIndex).toBe(0)
    expect(controller.optionsSourceMode).toBe("manual")
    expect(controller.editingRow).toBeNull()
    expect(controller.modalTitleTarget.textContent).toBe("Add Attribute")
    expect(controller.computedManager.reset).toHaveBeenCalled()
  })

  it("resetModalFields resets the reference manager when one is attached", () => {
    const { controller } = buildController("")
    stubbedSiblings(controller)
    controller.referenceManager = { reset: vi.fn() }
    new ModalManager(controller).resetModalFields()
    expect(controller.referenceManager.reset).toHaveBeenCalled()
  })

  it("also clears the display label, html type, validator select, constant select, and file config when present", () => {
    const { controller } = buildController(
      `<input data-entity-form-target="modalDisplayLabel" value="X" data-manually-edited="true">` +
      `<select data-entity-form-target="modalHtmlType"><option value="text">text</option><option value="select" selected>select</option></select>` +
      `<select data-entity-form-target="modalValidatorSelect"><option value="">--</option><option value="presence" selected>presence</option></select>` +
      `<select data-entity-form-target="constantSelect"><option value="">--</option><option value="1" selected>C</option></select>` +
      `<input data-entity-form-target="configAccept" value=".pdf">` +
      `<input type="checkbox" data-entity-form-target="configMultiple" checked>`
    )
    stubbedSiblings(controller)
    new ModalManager(controller).resetModalFields()
    expect(controller.modalDisplayLabelTarget.value).toBe("")
    expect(controller.modalDisplayLabelTarget.dataset.manuallyEdited).toBeUndefined()
    expect(controller.modalHtmlTypeTarget.selectedIndex).toBe(0)
    expect(controller.modalValidatorSelectTarget.selectedIndex).toBe(0)
    expect(controller.constantSelectTarget.selectedIndex).toBe(0)
    expect(controller.configAcceptTarget.value).toBe("")
    expect(controller.configMultipleTarget.checked).toBe(false)
  })

  it("unchecks the owner switch", () => {
    const { controller } = buildController(
      `<input type="checkbox" data-entity-form-target="modalOwner" checked>`
    )
    stubbedSiblings(controller)
    new ModalManager(controller).resetModalFields()
    expect(controller.modalOwnerTarget.checked).toBe(false)
  })
})

describe("ModalManager#prefillModalWithAttribute", () => {
  function prefillController(extra = "") {
    const { controller } = buildController(
      `<input data-entity-form-target="modalName">` +
      `<input data-entity-form-target="modalNameSlug">` +
      `<input data-entity-form-target="modalDisplayLabel">` +
      `<select data-entity-form-target="modalHtmlType"><option value="text">text</option><option value="select">select</option></select>` +
      `<input data-entity-form-target="modalDescription">` +
      `<div data-entity-form-target="validatorsContainer"></div>` +
      `<div data-entity-form-target="optionsContainer"></div>` +
      extra,
      { values: { optionIndex: 0, optionsSourceMode: "manual" } }
    )
    controller.schemaManager = new SchemaManager(controller)
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.templateBuilder = new TemplateBuilder(controller)
    controller.constantsManager = { updateOptionsSourceUI: vi.fn(), hideConstantPreview: vi.fn() }
    controller.computedManager = {
      reset: vi.fn(),
      selectInputMode: vi.fn(),
      selectComputedMode: vi.fn(),
      applyComputedConfig: vi.fn(),
    }
    return controller
  }

  it("fills basic fields and renders validator badges", () => {
    const c = prefillController()
    new ModalManager(c).prefillModalWithAttribute({
      name: "Email", name_slug: "email", display_label: "", html_type: "text",
      description: "work", validators: ["presence", { type: "greater_than", config: { value: 1 } }],
      visibility: {}, config: null,
    })
    expect(c.modalNameTarget.value).toBe("Email")
    expect(c.modalDisplayLabelTarget.value).toBe("Email") // falls back to name
    expect(c.modalDisplayLabelTarget.dataset.manuallyEdited).toBe("true")
    expect(c.modalHtmlTypeTarget.value).toBe("text")
    expect(c.validatorsContainerTarget.querySelectorAll("[data-validator-item]").length).toBe(2)
  })

  it("rebuilds manual selection option rows from config", () => {
    const c = prefillController(
      `<div data-entity-form-target="optionsSection" class="hidden"></div>` +
      `<div data-entity-form-target="selectionConfig" class="hidden"></div>`
    )
    new ModalManager(c).prefillModalWithAttribute({
      name: "Color", name_slug: "color", display_label: "Color", html_type: "select",
      description: "", validators: [], visibility: {},
      config: { source: "manual", options: [{ label: "Red", value: "red", default: true }, { label: "Blue", value: "blue" }] },
    })
    const rows = c.optionsContainerTarget.querySelectorAll("[data-option-item]")
    expect(rows.length).toBe(2)
    expect(rows[0].querySelector("[data-option-label]").value).toBe("Red")
    expect(rows[0].querySelector("[data-option-default]").checked).toBe(true)
    expect(c.optionsSectionTarget.classList.contains("hidden")).toBe(false)
  })

  it("tolerates a missing name/name_slug target and blanks the display label without a name", () => {
    const { controller } = buildController(
      `<input data-entity-form-target="modalDisplayLabel">` +
      `<div data-entity-form-target="validatorsContainer"></div>` +
      `<div data-entity-form-target="optionsContainer"></div>`,
      { values: { optionIndex: 0 } }
    )
    controller.schemaManager = new SchemaManager(controller)
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.templateBuilder = new TemplateBuilder(controller)
    controller.constantsManager = { updateOptionsSourceUI: vi.fn(), hideConstantPreview: vi.fn() }
    expect(() => new ModalManager(controller).prefillModalWithAttribute({
      name: "", name_slug: "", display_label: "", html_type: "", description: "",
      validators: [], visibility: {}, config: null,
    })).not.toThrow()
    expect(controller.modalDisplayLabelTarget.value).toBe("")
  })

  it("blanks name/name_slug when they are falsy, even with the targets present", () => {
    const c = prefillController()
    new ModalManager(c).prefillModalWithAttribute({
      name: "", name_slug: "", display_label: "", html_type: "text",
      description: "", validators: [], visibility: {}, config: null,
    })
    expect(c.modalNameTarget.value).toBe("")
    expect(c.modalNameSlugTarget.value).toBe("")
  })

  it("falls back to html_type 'text' when html_type is falsy", () => {
    const c = prefillController()
    new ModalManager(c).prefillModalWithAttribute({
      name: "X", name_slug: "x", display_label: "X", html_type: "",
      description: "", validators: [], visibility: {}, config: null,
    })
    expect(c.modalHtmlTypeTarget.value).toBe("text")
  })

  it("clears file config inputs unconditionally when they are present", () => {
    const c = prefillController(
      `<input data-entity-form-target="configAccept" value=".pdf">` +
      `<input type="checkbox" data-entity-form-target="configMultiple" checked>`
    )
    new ModalManager(c).prefillModalWithAttribute({
      name: "X", name_slug: "x", display_label: "X", html_type: "text",
      description: "", validators: [], visibility: {}, config: null,
    })
    expect(c.configAcceptTarget.value).toBe("")
    expect(c.configMultipleTarget.checked).toBe(false)
  })

  it("selects the constant source and re-selects the matching constant option", () => {
    const c = prefillController(
      `<div data-entity-form-target="optionsSection" class="hidden"></div>` +
      `<div data-entity-form-target="selectionConfig" class="hidden"></div>` +
      `<select data-entity-form-target="constantSelect"><option value="">--</option><option value="7">C</option></select>`
    )
    const changeHandler = vi.fn()
    c.constantSelectTarget.addEventListener("change", changeHandler)
    new ModalManager(c).prefillModalWithAttribute({
      name: "Color", name_slug: "color", display_label: "Color", html_type: "select",
      description: "", validators: [], visibility: {},
      // happy-dom's <select>.value setter, unlike a real browser, does not stringify
      // a numeric assignment before matching option values — use a string id here.
      config: { source: "constant", constant_id: "7", options: ["red", "blue"] },
    })
    expect(c.optionsSourceMode).toBe("constant")
    expect(c.constantSelectTarget.value).toBe("7")
    expect(changeHandler).toHaveBeenCalled()
  })

  it("treats a constant config without a constant_id as manual", () => {
    const c = prefillController(
      `<div data-entity-form-target="optionsSection" class="hidden"></div>` +
      `<div data-entity-form-target="selectionConfig" class="hidden"></div>`
    )
    new ModalManager(c).prefillModalWithAttribute({
      name: "Color", name_slug: "color", display_label: "Color", html_type: "select",
      description: "", validators: [], visibility: {},
      config: { source: "constant", options: [{ label: "Red", value: "red" }] },
    })
    expect(c.optionsSourceMode).toBe("manual")
    expect(c.optionsContainerTarget.querySelectorAll("[data-option-item]").length).toBe(1)
  })

  it("tolerates missing file config targets for a file-type attribute", () => {
    const c = prefillController(
      `<div data-entity-form-target="optionsSection" class="hidden"></div>` +
      `<div data-entity-form-target="fileConfig" class="hidden"></div>`
    )
    expect(() => new ModalManager(c).prefillModalWithAttribute({
      name: "Upload", name_slug: "upload", display_label: "Upload", html_type: "file",
      description: "", validators: [], visibility: {},
      config: { accept: ".png", multiple: true },
    })).not.toThrow()
  })

  it("skips writing label/value onto an option row that lacks those inputs", () => {
    const c = prefillController(
      `<div data-entity-form-target="optionsSection" class="hidden"></div>` +
      `<div data-entity-form-target="selectionConfig" class="hidden"></div>`
    )
    vi.spyOn(c.templateBuilder, "buildOptionRowHtml").mockReturnValue(`<div data-option-item></div>`)
    expect(() => new ModalManager(c).prefillModalWithAttribute({
      name: "Color", name_slug: "color", display_label: "Color", html_type: "select",
      description: "", validators: [], visibility: {},
      config: { source: "manual", options: [{ label: "Red", value: "red", default: true }] },
    })).not.toThrow()
    const row = c.optionsContainerTarget.querySelector("[data-option-item]")
    expect(row.querySelector("[data-option-label]")).toBeNull()
  })

  it("defaults an option row's label/value to blank when the option data omits them", () => {
    const c = prefillController(
      `<div data-entity-form-target="optionsSection" class="hidden"></div>` +
      `<div data-entity-form-target="selectionConfig" class="hidden"></div>`
    )
    new ModalManager(c).prefillModalWithAttribute({
      name: "Color", name_slug: "color", display_label: "Color", html_type: "select",
      description: "", validators: [], visibility: {},
      config: { source: "manual", options: [{}] },
    })
    const row = c.optionsContainerTarget.querySelector("[data-option-item]")
    expect(row.querySelector("[data-option-label]").value).toBe("")
    expect(row.querySelector("[data-option-value]").value).toBe("")
  })

  it("defaults accept/multiple to blank/false when the file config omits them", () => {
    const c = prefillController(
      `<div data-entity-form-target="optionsSection" class="hidden"></div>` +
      `<div data-entity-form-target="fileConfig" class="hidden"></div>` +
      `<input data-entity-form-target="configAccept">` +
      `<input type="checkbox" data-entity-form-target="configMultiple">`
    )
    new ModalManager(c).prefillModalWithAttribute({
      name: "Upload", name_slug: "upload", display_label: "Upload", html_type: "file",
      description: "", validators: [], visibility: {},
      config: {},
    })
    expect(c.configAcceptTarget.value).toBe("")
    expect(c.configMultipleTarget.checked).toBe(false)
  })

  it("populates the file config fields for a file-type attribute", () => {
    const c = prefillController(
      `<div data-entity-form-target="optionsSection" class="hidden"></div>` +
      `<div data-entity-form-target="fileConfig" class="hidden"></div>` +
      `<input data-entity-form-target="configAccept">` +
      `<input type="checkbox" data-entity-form-target="configMultiple">`
    )
    new ModalManager(c).prefillModalWithAttribute({
      name: "Upload", name_slug: "upload", display_label: "Upload", html_type: "file",
      description: "", validators: [], visibility: {},
      config: { accept: ".png,.jpg", multiple: true },
    })
    expect(c.configAcceptTarget.value).toBe(".png,.jpg")
    expect(c.configMultipleTarget.checked).toBe(true)
    expect(c.optionsSectionTarget.classList.contains("hidden")).toBe(false)
    expect(c.fileConfigTarget.classList.contains("hidden")).toBe(false)
  })

  it("renders a fallback label for an unrecognized string validator (getValidatorLabel returns falsy)", () => {
    const c = prefillController()
    new ModalManager(c).prefillModalWithAttribute({
      name: "X", name_slug: "x", display_label: "X", html_type: "text",
      description: "", validators: ["totally_unknown"], visibility: {}, config: null,
    })
    const badge = c.validatorsContainerTarget.querySelector("[data-validator-item]")
    expect(badge).not.toBeNull()
  })

  it("renders a fallback label for an unrecognized object validator without config", () => {
    const c = prefillController()
    new ModalManager(c).prefillModalWithAttribute({
      name: "X", name_slug: "x", display_label: "X", html_type: "text",
      description: "", validators: [{ type: "totally_unknown" }], visibility: {}, config: null,
    })
    const badge = c.validatorsContainerTarget.querySelector("[data-validator-item]")
    expect(badge).not.toBeNull()
  })

  it("switches to computed mode and applies config when type is Computed", () => {
    const c = prefillController()
    const config = { bridge_entity_id: 15, bridge_role: "source", source_slug: "score", function: "avg", precision: 2 }
    new ModalManager(c).prefillModalWithAttribute({
      name: "Average Score", name_slug: "average_score", display_label: "Average Score",
      html_type: "number", description: "", validators: [], visibility: {}, config, type: "Computed",
    })
    expect(c.computedManager.selectComputedMode).toHaveBeenCalled()
    expect(c.computedManager.applyComputedConfig).toHaveBeenCalledWith(config)
    expect(c.computedManager.selectInputMode).not.toHaveBeenCalled()
  })

  it("applies an entity_entries config without adding manual option rows", () => {
    const c = prefillController(
      `<div data-entity-form-target="optionsSection" class="hidden"></div>` +
      `<div data-entity-form-target="selectionConfig" class="hidden"></div>`
    )
    c.referenceManager = { applyConfig: vi.fn() }
    const config = { options_source: "entity_entries", entity_id: "7", label_field: "title" }
    new ModalManager(c).prefillModalWithAttribute({
      html_type: "select",
      config,
    })
    expect(c.referenceManager.applyConfig).toHaveBeenCalledWith(config)
    expect(c.optionsContainerTarget.querySelectorAll("[data-option-item]").length).toBe(0)
  })

  it("stays in data mode when type is not Computed", () => {
    const c = prefillController()
    new ModalManager(c).prefillModalWithAttribute({
      name: "X", name_slug: "x", display_label: "X", html_type: "text",
      description: "", validators: [], visibility: {}, config: null,
    })
    expect(c.computedManager.selectInputMode).toHaveBeenCalled()
    expect(c.computedManager.selectComputedMode).not.toHaveBeenCalled()
  })

  it("restores the owner switch on and off", () => {
    const c = prefillController(`<input type="checkbox" data-entity-form-target="modalOwner">`)
    const manager = new ModalManager(c)

    manager.prefillModalWithAttribute({
      name: "Student", name_slug: "student", display_label: "Student", html_type: "select",
      description: "", validators: [], visibility: {}, config: null, owner: true,
    })
    expect(c.modalOwnerTarget.checked).toBe(true)

    manager.prefillModalWithAttribute({
      name: "Student", name_slug: "student", display_label: "Student", html_type: "select",
      description: "", validators: [], visibility: {}, config: null,
    })
    expect(c.modalOwnerTarget.checked).toBe(false)
  })

  it("applyOwner no-ops without the checkbox", () => {
    const { controller } = buildController("")
    expect(() => new ModalManager(controller).applyOwner(true)).not.toThrow()
  })
})

describe("ModalManager view modal", () => {
  function viewController() {
    const { controller } = buildController(
      `<div data-entity-form-target="attributesContainer">` +
      `<div data-attribute-item><input data-input="name" value="Email"><input data-input="html_type" value="email"></div>` +
      `</div>` +
      `<div data-entity-form-target="viewModal" class="hidden"></div>` +
      `<div data-entity-form-target="viewModalContent"></div>` +
      `<div data-entity-form-target="viewModalTitle"></div>` +
      `<div data-entity-form-target="viewModalSubtitle"></div>`,
      { values: { attributeIndex: 0 } }
    )
    controller.schemaManager = new SchemaManager(controller)
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.templateBuilder = new TemplateBuilder(controller)
    return controller
  }

  it("viewAttribute renders the attribute view + title/subtitle and opens the modal", () => {
    const c = viewController()
    const row = c.element.querySelector("[data-attribute-item]")
    new ModalManager(c).viewAttribute(fakeEvent({ target: row }))
    expect(c.viewModalTarget.classList.contains("hidden")).toBe(false)
    expect(c.viewModalTitleTarget.textContent).toBe("Email")
    expect(c.viewModalSubtitleTarget.textContent).toBe("email")
    expect(c.viewModalContentTarget.innerHTML).toContain("Email")
    expect(document.body.style.overflow).toBe("hidden")
  })

  it("viewAttribute no-ops when the click target has no attribute row ancestor", () => {
    const c = viewController()
    const stray = document.createElement("div")
    new ModalManager(c).viewAttribute(fakeEvent({ target: stray }))
    expect(c.viewModalTarget.classList.contains("hidden")).toBe(true)
  })

  it("viewAttribute no-ops when the row has no extractable attribute", () => {
    const c = viewController()
    const row = c.element.querySelector("[data-attribute-item]")
    vi.spyOn(c.schemaManager, "extractAttributeFromRow").mockReturnValue(null)
    new ModalManager(c).viewAttribute(fakeEvent({ target: row }))
    expect(c.viewModalTarget.classList.contains("hidden")).toBe(true)
  })

  it("viewAttribute falls back to empty title/subtitle when the attribute has no name", () => {
    const c = viewController()
    const row = c.element.querySelector("[data-attribute-item]")
    vi.spyOn(c.schemaManager, "extractAttributeFromRow").mockReturnValue({ name: "", html_type: "text" })
    new ModalManager(c).viewAttribute(fakeEvent({ target: row }))
    expect(c.viewModalTitleTarget.textContent).toBe("")
    expect(c.viewModalSubtitleTarget.textContent).toBe("")
  })

  it("viewAttribute uses display_label as subtitle when it differs from name", () => {
    const c = viewController()
    const row = c.element.querySelector("[data-attribute-item]")
    vi.spyOn(c.schemaManager, "extractAttributeFromRow").mockReturnValue({
      name: "Email", display_label: "Work Email", name_slug: "email", html_type: "email",
      description: "", validators: [], visibility: {}, validator_apply: {}, group_id: null, config: null,
    })
    new ModalManager(c).viewAttribute(fakeEvent({ target: row }))
    expect(c.viewModalTitleTarget.textContent).toBe("Email")
    expect(c.viewModalSubtitleTarget.textContent).toBe("Work Email")
  })

  it("closeViewModal hides + clears content and restores scroll", () => {
    const c = viewController()
    c.viewModalContentTarget.innerHTML = "stuff"
    c.viewModalTitleTarget.textContent = "Title"
    document.body.style.overflow = "hidden"
    new ModalManager(c).closeViewModal(fakeEvent())
    expect(c.viewModalTarget.classList.contains("hidden")).toBe(true)
    expect(c.viewModalContentTarget.innerHTML).toBe("")
    expect(c.viewModalTitleTarget.textContent).toBe("")
    expect(document.body.style.overflow).toBe("")
  })
})
