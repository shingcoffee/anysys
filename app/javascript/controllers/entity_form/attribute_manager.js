import { BaseManager, CSS } from "controllers/entity_form/base_manager"

export class AttributeManager extends BaseManager {
  addAttributeFromModal(event) {
    event.preventDefault()
    event.stopPropagation()
    if (this.c.isProcessingModal) return
    this.c.isProcessingModal = true
    const submitBtn = this.c.hasModalSubmitBtnTarget ? this.c.modalSubmitBtnTarget : null
    if (submitBtn) submitBtn.disabled = true
    try {
      const attribute = this.collectModalData()
      if (!this.validateAttribute(attribute)) return

      if (this.c.attributeModalContext === "association") {
        this.c.associationManager.addAttributeToAssociation(attribute)
      } else {
        if (this.c.editingRow) {
          this.c.schemaManager.updateAttributeRow(this.c.editingRow, attribute)
        } else {
          this.hideEmptyState()
          this.c.schemaManager.appendAttribute(attribute)
          this.c.attributeIndex++
        }
        this.c.schemaManager.syncPropertySchema()
      }
      this.c.modalManager.closeModal()
    } finally {
      this.c.isProcessingModal = false
      if (submitBtn) submitBtn.disabled = false
    }
  }

  collectModalData() {
    const name = this.getTargetValue("modalName")
    const htmlType = this.getTargetValue("modalHtmlType") || "text"
    const displayLabel = this.getTargetValue("modalDisplayLabel")

    const visibility = this.collectVisibility()
    const editable = this.c.schemaManager.coerceEditable(visibility, this.collectEditable())

    const base = {
      name,
      name_slug: this.getTargetValue("modalNameSlug") || this.generateSlug(name),
      display_label: displayLabel,
      html_type: htmlType,
      description: this.getTargetValue("modalDescription"),
      validators: this.c.validatorManager.getSelectedValidators(),
      visibility,
      validator_apply: this.collectValidatorApply(),
      group_id: this.c.editingRow
        ? (this.c.editingRow.querySelector('input[data-input="group_id"]')?.value || this.c.editingRow.getAttribute("data-attr-group-id") || null)
        : null,
      config: this.c.typeManager.getConfigForType(htmlType)
    }

    if (this.c.attributeMode !== "computed") {
      if (this.c.schemaManager.shouldStoreEditable(visibility, editable)) {
        base.editable = editable
      }
      if (this.ownerChecked()) base.owner = true
      return base
    }

    return {
      ...base,
      type: "Computed",
      html_type: "number",
      readonly: true,
      storage: "computed",
      validators: [],
      config: this.c.computedManager ? this.c.computedManager.getComputedConfig() : null
    }
  }

  collectVisibility() {
    return {
      admin: this.c.hasModalVisibilityAdminTarget ? this.c.modalVisibilityAdminTarget.checked : true,
      member: this.c.hasModalVisibilityMemberTarget ? this.c.modalVisibilityMemberTarget.checked : true,
      public: this.c.hasModalVisibilityPublicTarget ? this.c.modalVisibilityPublicTarget.checked : true
    }
  }

  collectEditable() {
    return {
      admin: this.c.hasModalEditableAdminTarget ? this.c.modalEditableAdminTarget.checked : true,
      member: this.c.hasModalEditableMemberTarget ? this.c.modalEditableMemberTarget.checked : true,
      public: this.c.hasModalEditablePublicTarget ? this.c.modalEditablePublicTarget.checked : true
    }
  }

  ownerChecked() {
    if (!this.c.hasModalOwnerTarget || !this.c.modalOwnerTarget.checked) return false
    return this.c.referenceManager?.ownerAvailable?.() === true
  }

  collectValidatorApply() {
    const visibility = this.collectVisibility()
    const editable = this.c.schemaManager.coerceEditable(visibility, this.collectEditable())
    const raw = {
      admin: this.c.hasModalValidatorApplyAdminTarget ? this.c.modalValidatorApplyAdminTarget.checked : true,
      member: this.c.hasModalValidatorApplyMemberTarget ? this.c.modalValidatorApplyMemberTarget.checked : true,
      public: this.c.hasModalValidatorApplyPublicTarget ? this.c.modalValidatorApplyPublicTarget.checked : true
    }
    return this.c.schemaManager.coerceValidatorApply(visibility, raw, editable)
  }

  validateAttribute({ name, name_slug, display_label }) {
    if (!name) {
      this.showFieldError(this.c.modalNameTarget, this.c.nameRequiredMsgValue)
      return false
    }
    if (!display_label) {
      this.showFieldError(this.c.modalDisplayLabelTarget, this.c.displayLabelRequiredMsgValue)
      return false
    }
    if (this.isReservedFieldName(name_slug)) {
      const modelName = this.c.extendableModelValue || "base model"
      const message = this.c.fieldReservedMsgValue.replace("{name}", name_slug).replace("{model}", modelName)
      this.showFieldError(this.c.modalNameTarget, message)
      return false
    }
    if (this.isDuplicateValue("name", name, this.c.editingRow)) {
      this.showFieldError(this.c.modalNameTarget, this.c.duplicateNameMsgValue)
      return false
    }
    if (this.isDuplicateValue("name_slug", name_slug, this.c.editingRow)) {
      this.showFieldError(this.c.modalNameTarget, this.c.duplicateSlugMsgValue)
      return false
    }
    if (this.c.attributeMode === "computed") {
      const message = this.c.computedManager?.validate()
      if (message) {
        const field = this.c.hasComputedRelationTarget
          ? this.c.computedRelationTarget
          : (this.c.hasComputedFunctionTarget ? this.c.computedFunctionTarget : this.c.modalNameTarget)
        this.showFieldError(field, message)
        return false
      }
    }
    if (this.c.attributeMode !== "computed" && this.c.optionsSourceMode === "entity_entries") {
      const problem = this.c.referenceManager.validate()
      if (problem) {
        this.showFieldError(this.c[`${problem.target}Target`], problem.message)
        return false
      }
    }
    return true
  }

  isReservedFieldName(nameSlug) {
    if (!this.c.extendableModelValue) return false
    return (this.c.reservedFieldNamesValue || []).includes(nameSlug)
  }

  isDuplicateValue(inputType, value, excludeRow = null) {
    return this.getExistingAttributeValues(inputType, excludeRow).includes(value.toLowerCase())
  }

  getExistingAttributeValues(inputType, excludeRow = null) {
    const items = this.c.attributesContainerTarget.querySelectorAll("[data-attribute-item]")
    return Array.from(items)
      .filter(item => item !== excludeRow)
      .map(item => item.querySelector(`input[data-input="${inputType}"]`)?.value.trim().toLowerCase())
      .filter(Boolean)
  }

  generateUniqueName(baseName) {
    const existingNames = this.getExistingAttributeValues("name")
    let newName = `${baseName} (Copy)`
    if (!existingNames.includes(newName.toLowerCase())) return newName
    let counter = 2
    while (counter < 100) {
      newName = `${baseName} (Copy ${counter})`
      if (!existingNames.includes(newName.toLowerCase())) return newName
      counter++
    }
    return `${baseName} (Copy ${Date.now()})`
  }

  removeAttribute(event) {
    event.preventDefault()
    event.stopPropagation()
    const row = event.target.closest("[data-attribute-item]")
    if (!row) return
    row.remove()
    this.c.schemaManager.regroupAttributeRows()
    this.showEmptyStateIfNeeded()
    this.c.schemaManager.syncPropertySchema()
  }

  copyAttribute(event) {
    event.preventDefault()
    event.stopPropagation()
    this.c.modalManager.resetModalFields()
    const row = event.target.closest("[data-attribute-item]")
    if (!row) return
    const attribute = this.c.schemaManager.extractAttributeFromRow(row)
    if (!attribute) return
    attribute.name = this.generateUniqueName(attribute.name)
    attribute.name_slug = this.generateSlug(attribute.name)
    this.c.modalManager.prefillModalWithAttribute(attribute)
    if (this.c.hasModalTarget) {
      this.c.modalTarget.classList.remove(CSS.hidden)
      document.body.style.overflow = CSS.hidden
      this.c.modalManager.resetModalSectionNav()
      this.c.modalManager.focusModalNameField()
    }
  }

  editAttribute(event) {
    event.preventDefault()
    event.stopPropagation()
    this.c.modalManager.resetModalFields()
    const row = event.target.closest("[data-attribute-item]")
    if (!row) return
    const attribute = this.c.schemaManager.extractAttributeFromRow(row)
    if (!attribute) return
    this.c.editingRow = row
    this.c.modalManager.prefillModalWithAttribute(attribute)
    if (this.c.hasModalTitleTarget) this.c.modalTitleTarget.textContent = this.c.editAttributeLabelValue
    if (this.c.hasModalSubmitBtnTarget) this.c.modalSubmitBtnTarget.textContent = this.c.saveChangesLabelValue
    if (this.c.hasModalTarget) {
      this.c.modalTarget.classList.remove(CSS.hidden)
      document.body.style.overflow = CSS.hidden
      this.c.modalManager.resetModalSectionNav()
      this.c.modalManager.focusModalNameField()
    }
  }

  // Empty state management
  hideEmptyState() {
    if (this.c.hasEmptyStateTarget) this.c.emptyStateTarget.classList.add(CSS.hidden)
  }

  showEmptyStateIfNeeded() {
    const hasAttributes = this.c.existingAttributeCount > 0
    if (!hasAttributes && this.c.hasEmptyStateTarget) {
      this.c.emptyStateTarget.classList.remove(CSS.hidden)
      if (this.c.hasAttributesTableTarget) this.c.attributesTableTarget.remove()
    }
  }

  // Field validation UI
  showFieldError(field, message) {
    field.focus()
    field.classList.add(...CSS.errorRing)
    const errorEl = this.createOrGetErrorElement(field)
    errorEl.textContent = message
    setTimeout(() => { field.classList.remove(...CSS.errorRing); errorEl?.remove() }, 3000)
  }

  createOrGetErrorElement(field) {
    let errorEl = field.parentElement.querySelector(".field-error")
    if (!errorEl) {
      errorEl = document.createElement("p")
      errorEl.className = "field-error text-xs text-red-500 mt-1"
      field.parentElement.appendChild(errorEl)
    }
    return errorEl
  }
}
