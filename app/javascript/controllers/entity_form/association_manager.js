import { BaseManager, CSS, escapeHtml } from "controllers/entity_form/base_manager"

export class AssociationManager extends BaseManager {
  async openAssociationModal() {
    if (!this.c.hasAssociationModalTarget) return
    await this.loadAssociationEntities()
    this.resetAssociationModal()
    this.c.associationModalTarget.classList.remove(CSS.hidden)
  }

  closeAssociationModal() {
    if (!this.c.hasAssociationModalTarget) return
    this.c.associationModalTarget.classList.add(CSS.hidden)
    this.resetAssociationModal()
  }

  resetAssociationModal() {
    if (this.c.hasAssociationTargetEntityTarget) this.c.associationTargetEntityTarget.value = ""
    this.hideDisplaySection()
    this.c.currentAssociationAttributes = []
    this.renderAssociationAttributes()
    this.c.editingAssociationIndex = null
    if (this.c.hasAssociationModalTitleTarget) this.c.associationModalTitleTarget.textContent = this.c.addAssociationLabelValue
    if (this.c.hasAssociationModalSubmitBtnTarget) this.c.associationModalSubmitBtnTarget.textContent = this.c.addAssociationLabelValue
  }

  async loadAssociationEntities() {
    if (!this.c.hasAssociationTargetEntityTarget) return
    try {
      const response = await fetch(`/${this.customerIdValue}/admin/maintenance/entities.json`, {
        headers: { "Accept": "application/json" }
      })
      if (!response.ok) throw new Error("Failed to load entities")
      const entities = await response.json()
      this.c.loadedAssociationEntities = entities
      const currentEntityId = this.c.currentEntityIdValue
      const filteredEntities = entities.filter(entity =>
        !currentEntityId || entity.id.toString() !== currentEntityId.toString()
      )
      this.populateAssociationTargetDropdown(filteredEntities)
    } catch (_error) {
      /* silently ignore */
    }
  }

  onTargetEntityChanged() {
    if (!this.c.hasAssociationTargetEntityTarget) return
    const entityId = this.c.associationTargetEntityTarget.value
    if (!entityId) { this.hideDisplaySection(); return }
    const entities = this.c.loadedAssociationEntities || []
    const entity = entities.find(e => e.id.toString() === entityId.toString())
    if (!entity) { this.hideDisplaySection(); return }
    this.populateDisplayFieldDropdown(entity)
    this.showDisplaySection()
  }

  populateDisplayFieldDropdown(entity) {
    if (!this.c.hasAssociationDisplayFieldTarget) return
    const select = this.c.associationDisplayFieldTarget
    while (select.options.length > 1) select.remove(1)
    const schema = entity.property_schema || []
    schema.filter(prop => prop.labelable).forEach(prop => {
      const option = document.createElement("option")
      option.value = prop.name_slug
      option.textContent = prop.name
      option.dataset.fieldLabel = prop.name
      select.appendChild(option)
    })
  }

  showDisplaySection() {
    if (this.c.hasAssociationDisplaySectionTarget) {
      this.c.associationDisplaySectionTarget.classList.remove(CSS.hidden)
    }
  }

  hideDisplaySection() {
    if (this.c.hasAssociationDisplaySectionTarget) {
      this.c.associationDisplaySectionTarget.classList.add(CSS.hidden)
    }
    if (this.c.hasAssociationDisplayFieldTarget) {
      this.c.associationDisplayFieldTarget.value = ""
    }
  }

  populateAssociationTargetDropdown(entities) {
    if (!this.c.hasAssociationTargetEntityTarget) return
    const select = this.c.associationTargetEntityTarget
    while (select.options.length > 1) select.remove(1)
    const associatedEntityIds = this.getAssociatedEntityIds()
    entities.forEach(entity => {
      if (associatedEntityIds.includes(entity.id)) return
      const option = document.createElement("option")
      option.value = entity.id
      option.textContent = entity.name
      option.dataset.entityName = entity.name
      select.appendChild(option)
    })
  }

  getAssociatedEntityIds() {
    return this.collectCurrentAssociations().map(assoc => assoc.target_entity_id).filter(id => id)
  }

  collectCurrentAssociations() {
    if (!this.c.hasAssociationsContainerTarget) return []
    const rows = this.c.associationsContainerTarget.querySelectorAll("[data-association-item]")
    return Array.from(rows).map(row => {
      try { return row.dataset.associationData ? JSON.parse(row.dataset.associationData) : null }
      catch (_e) { return null }
    }).filter(Boolean)
  }

  addAssociationAttribute(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }
    this.c.modalManager.openModalForAssociationAttribute()
  }

  addAttributeToAssociation(attribute) {
    if (this.c.editingAssociationAttributeIndex !== null) {
      this.c.currentAssociationAttributes[this.c.editingAssociationAttributeIndex] = attribute
      this.c.editingAssociationAttributeIndex = null
    } else {
      this.c.currentAssociationAttributes.push(attribute)
    }
    this.renderAssociationAttributes()
  }

  renderAssociationAttributes() {
    if (!this.c.hasAssociationAttributesContainerTarget) return
    const container = this.c.associationAttributesContainerTarget
    container.innerHTML = ""
    if (this.c.currentAssociationAttributes.length === 0) {
      this.showAssociationAttributesEmptyState()
      this.hideAssociationAttributesTable()
      return
    }
    this.hideAssociationAttributesEmptyState()
    this.showAssociationAttributesTable()
    this.c.currentAssociationAttributes.forEach((attr, index) => {
      container.insertAdjacentHTML("beforeend", this.c.templateBuilder.buildAssociationAttributeDisplayHtml(attr, index))
    })
  }

  editAssociationAttribute(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const attribute = this.c.currentAssociationAttributes[index]
    if (!attribute || !this.c.hasModalTarget) return
    this.c.attributeModalContext = "association"
    this.c.editingAssociationAttributeIndex = index
    this.c.optionsSourceMode = "manual"
    this.c.constantsManager.updateOptionsSourceUI()
    this.c.modalManager.prefillModalWithAttribute(attribute)
    if (this.c.hasModalTitleTarget) this.c.modalTitleTarget.textContent = this.c.editAssociationAttributeLabelValue
    if (this.c.hasModalSubmitBtnTarget) this.c.modalSubmitBtnTarget.textContent = this.c.updateAttributeLabelValue
    this.c.modalTarget.classList.remove(CSS.hidden)
    document.body.style.overflow = CSS.hidden
    this.c.modalManager.resetModalSectionNav()
    this.c.modalManager.focusModalNameField()
  }

  removeAssociationAttributeFromList(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    this.c.currentAssociationAttributes.splice(index, 1)
    this.renderAssociationAttributes()
  }

  hideAssociationAttributesEmptyState() {
    if (this.c.hasAssociationAttributesEmptyStateTarget) this.c.associationAttributesEmptyStateTarget.classList.add(CSS.hidden)
  }

  showAssociationAttributesEmptyState() {
    if (this.c.hasAssociationAttributesEmptyStateTarget) this.c.associationAttributesEmptyStateTarget.classList.remove(CSS.hidden)
  }

  hideAssociationAttributesTable() {
    if (this.c.hasAssociationAttributesTableWrapperTarget) this.c.associationAttributesTableWrapperTarget.classList.add(CSS.hidden)
  }

  showAssociationAttributesTable() {
    if (this.c.hasAssociationAttributesTableWrapperTarget) this.c.associationAttributesTableWrapperTarget.classList.remove(CSS.hidden)
  }

  saveAssociation() {
    if (this.c.isProcessingModal) return
    this.c.isProcessingModal = true
    const submitBtn = this.c.hasAssociationModalSubmitBtnTarget ? this.c.associationModalSubmitBtnTarget : null
    if (submitBtn) submitBtn.disabled = true
    try {
      const targetEntitySelect = this.c.associationTargetEntityTarget
      const targetEntityId = targetEntitySelect.value
      const targetEntityOption = targetEntitySelect.selectedOptions[0]
      if (!targetEntityId) { alert(this.c.selectTargetEntityMsgValue); return }

      const displayFieldSelect = this.c.hasAssociationDisplayFieldTarget ? this.c.associationDisplayFieldTarget : null
      const displayFieldSlug = displayFieldSelect?.value || ""
      if (!displayFieldSlug) { alert(this.c.selectDisplayFieldMsgValue); return }
      const displayFieldOption = displayFieldSelect?.selectedOptions[0]
      const displayFieldLabel = displayFieldOption?.dataset.fieldLabel || displayFieldSlug

      const targetEntityName = targetEntityOption.dataset.entityName
      const additionalAttributes = this.c.currentAssociationAttributes || []

      const association = {
        target_entity_id: parseInt(targetEntityId),
        target_entity_name: targetEntityName,
        display_field: displayFieldSlug,
        display_field_label: displayFieldLabel,
        bridge_entity_id: null,
        bridge_entity_name: null,
        additional_attributes: additionalAttributes
      }

      if (this.c.editingAssociationIndex !== null) {
        this.updateAssociationInList(association, this.c.editingAssociationIndex)
      } else {
        this.addAssociationToList(association)
      }
      this.c.schemaManager.syncAssociationsSchema()
      this.closeAssociationModal()
    } finally {
      this.c.isProcessingModal = false
      if (submitBtn) submitBtn.disabled = false
    }
  }

  addAssociationToList(association) {
    if (!this.c.hasAssociationsContainerTarget) return
    this.hideAssociationsEmptyState()
    this.ensureAssociationsTableExists()
    const tbody = this.c.associationsContainerTarget.querySelector("tbody")
    if (tbody) tbody.insertAdjacentHTML("beforeend", this.c.templateBuilder.buildAssociationRowHtml(association))
  }

  updateAssociationInList(association, index) {
    if (!this.c.hasAssociationsContainerTarget) return
    const rows = this.c.associationsContainerTarget.querySelectorAll("[data-association-item]")
    const row = rows[index]
    if (!row) return
    row.outerHTML = this.c.templateBuilder.buildAssociationRowHtml(association)
  }

  ensureAssociationsTableExists() {
    if (this.c.associationsContainerTarget.querySelector("table")) return
    const tableHtml = `
      <table class="min-w-full divide-y divide-border-subtle" data-entity-form-target="associationsTable">
        <thead class="table-header">
          <tr>
            <th scope="col" class="px-3 py-3 text-left">${escapeHtml(this.c.targetEntityHeaderValue)}</th>
            <th scope="col" class="px-3 py-3 text-left">${escapeHtml(this.c.displayColumnHeaderValue)}</th>
            <th scope="col" class="px-3 py-3 text-left">${escapeHtml(this.c.bridgeEntityHeaderValue)}</th>
            <th scope="col" class="px-3 py-3 text-left">${escapeHtml(this.c.additionalAttributesHeaderValue)}</th>
            <th scope="col" class="px-3 py-3 text-right">${escapeHtml(this.c.actionsHeaderValue)}</th>
          </tr>
        </thead>
        <tbody class="bg-surface divide-y divide-border-subtle"></tbody>
      </table>
    `
    this.c.associationsContainerTarget.insertAdjacentHTML("afterbegin", tableHtml)
  }

  async editAssociation(event) {
    event.preventDefault()
    const button = event.currentTarget
    const row = button.closest("[data-association-item]")
    if (!row) return
    let associationIndex = button.dataset.index
    if (associationIndex === undefined || associationIndex === null) {
      const allRows = Array.from(this.c.associationsContainerTarget.querySelectorAll("[data-association-item]"))
      associationIndex = allRows.indexOf(row)
    }
    const dataAttr = row.getAttribute("data-association-data")
    if (!dataAttr) return
    let association
    try { association = JSON.parse(dataAttr) } catch (_error) { return }

    if (this.c.hasAssociationModalTarget) this.c.associationModalTarget.classList.remove(CSS.hidden)
    await this.loadAssociationEntities()
    this.c.currentAssociationAttributes = []
    this.renderAssociationAttributes()
    this.c.editingAssociationIndex = parseInt(associationIndex)
    if (this.c.hasAssociationModalTitleTarget) this.c.associationModalTitleTarget.textContent = this.c.editAssociationLabelValue
    if (this.c.hasAssociationModalSubmitBtnTarget) this.c.associationModalSubmitBtnTarget.textContent = this.c.updateAssociationLabelValue
    if (this.c.hasAssociationTargetEntityTarget && association.target_entity_id) {
      this.c.associationTargetEntityTarget.value = association.target_entity_id.toString()
    }
    this.onTargetEntityChanged()
    if (association.display_field && this.c.hasAssociationDisplayFieldTarget) {
      this.c.associationDisplayFieldTarget.value = association.display_field
    }
    this.c.currentAssociationAttributes = association.additional_attributes || []
    this.renderAssociationAttributes()
  }

  removeAssociation(event) {
    event.preventDefault()
    const row = event.target.closest("[data-association-item]")
    if (row) {
      row.remove()
      this.showAssociationsEmptyStateIfNeeded()
      this.c.schemaManager.syncAssociationsSchema()
    }
  }

  hideAssociationsEmptyState() {
    if (this.c.hasAssociationsEmptyStateTarget) this.c.associationsEmptyStateTarget.classList.add(CSS.hidden)
  }

  showAssociationsEmptyStateIfNeeded() {
    if (!this.c.hasAssociationsContainerTarget) return
    const items = this.c.associationsContainerTarget.querySelectorAll("[data-association-item]")
    if (items.length === 0) {
      if (this.c.hasAssociationsEmptyStateTarget) this.c.associationsEmptyStateTarget.classList.remove(CSS.hidden)
      const table = this.c.associationsContainerTarget.querySelector("table")
      if (table) table.remove()
    }
  }
}
