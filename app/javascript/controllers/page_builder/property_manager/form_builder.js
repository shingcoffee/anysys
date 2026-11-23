// Condition-operator dropdown option words — English source of truth for the
// conditionOperatorLabels i18n Value (see page_builder_controller.js).
export const CONDITION_OPERATOR_LABELS = {
  equals: "Equals", not_equals: "Not equals", contains: "Contains", not_contains: "Not contains",
  greater_than: "Greater than", less_than: "Less than", is_empty: "Is empty", is_not_empty: "Is not empty"
}

/**
 * FormBuilderMixin provides HTML generation methods for the property panel:
 * options editor, conditions UI, and options CRUD operations.
 * Apply to a class using Object.assign(YourClass.prototype, FormBuilderMixin)
 */
export const FormBuilderMixin = {
  // Options editor
  addOption(event) {
    const fieldId = event.currentTarget.dataset.fieldId || this.c.selectedFieldId
    if (!fieldId) return

    const field = this.c.currentPageFields.find(f => f.id === fieldId)
    if (!field) return

    this.c.undoRedoManager.saveState()

    field.options = field.options || []
    const optionIndex = field.options.length + 1
    field.options.push({
      label: this.c.newOptionLabelFormatValue.replace("{number}", optionIndex),
      value: `option_${optionIndex}`
    })

    this.renderOptionsEditor(field)
    this.c.saveManager.markDirty()
  },

  removeOption(event) {
    const fieldId = event.currentTarget.dataset.fieldId
    const optionIndex = parseInt(event.currentTarget.dataset.optionIndex, 10)

    const field = this.c.currentPageFields.find(f => f.id === fieldId)
    if (!field || !field.options) return

    this.c.undoRedoManager.saveState()

    field.options.splice(optionIndex, 1)

    this.renderOptionsEditor(field)
    this.c.saveManager.markDirty()
  },

  updateOption(event) {
    const fieldId = event.target.dataset.fieldId
    const optionIndex = parseInt(event.target.dataset.optionIndex, 10)
    const property = event.target.dataset.property
    const value = event.target.value

    const field = this.c.currentPageFields.find(f => f.id === fieldId)
    if (!field || !field.options || !field.options[optionIndex]) return

    field.options[optionIndex][property] = value
    this.c.saveManager.markDirty()
  },

  renderOptionsEditor(field) {
    if (!this.c.hasOptionsListTarget) return

    const options = field.options || []

    const optionsHtml = options.map((option, index) => `
      <div class="flex items-center gap-2 group" data-option-index="${index}">
        <button type="button" class="cursor-grab text-gray-400 hover:text-gray-600">
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M4 8h16M4 16h16" />
          </svg>
        </button>
        <input type="text"
               class="flex-1 px-3 py-2 text-sm border border-gray-300 rounded-md focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500"
               placeholder="${this.c.labelPlaceholderValue}"
               value="${option.label || ""}"
               data-action="input->page-builder#updateOption"
               data-field-id="${field.id}"
               data-option-index="${index}"
               data-property="label">
        <input type="text"
               class="w-24 px-3 py-2 text-sm border border-gray-300 rounded-md focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500"
               placeholder="${this.c.valuePlaceholderValue}"
               value="${option.value || ""}"
               data-action="input->page-builder#updateOption"
               data-field-id="${field.id}"
               data-option-index="${index}"
               data-property="value">
        <button type="button"
                class="p-1 text-gray-400 hover:text-red-500 opacity-0 group-hover:opacity-100 transition-opacity"
                data-action="click->page-builder#removeOption"
                data-field-id="${field.id}"
                data-option-index="${index}">
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
    `).join("")

    this.c.optionsListTarget.innerHTML = optionsHtml
  },

  // Condition management
  addCondition() {
    const fieldId = this.c.selectedFieldValue || this.c.selectedFieldId
    if (!fieldId) return

    const field = this.c.currentPageFields.find(f => f.id === fieldId)
    if (!field) return

    field.conditions = field.conditions || []
    field.conditions.push({
      field_id: "",
      operator: "equals",
      value: "",
      logic: "and"
    })

    this.renderConditionsUI(field)
    this.c.saveManager.markDirty()
  },

  updateCondition(event) {
    const fieldId = event.target.dataset.fieldId
    const conditionIndex = parseInt(event.target.dataset.conditionIndex, 10)
    const property = event.target.dataset.property
    const value = event.target.value

    const field = this.c.currentPageFields.find(f => f.id === fieldId)
    if (!field || !field.conditions || !field.conditions[conditionIndex]) return

    field.conditions[conditionIndex][property] = value

    // Toggle value input visibility when operator changes
    if (property === "operator") {
      const conditionItem = event.target.closest(".condition-item")
      const valueInput = conditionItem?.querySelector("[data-property='value']")
      if (valueInput) {
        const hideValue = value === "is_empty" || value === "is_not_empty"
        valueInput.classList.toggle("hidden", hideValue)
        if (hideValue) {
          field.conditions[conditionIndex].value = ""
          valueInput.value = ""
        }
      }
    }

    this.c.saveManager.markDirty()
  },

  removeCondition(event) {
    event.stopPropagation()
    const fieldId = event.target.dataset.fieldId || event.currentTarget.dataset.fieldId
    const conditionIndex = parseInt(event.target.dataset.conditionIndex || event.currentTarget.dataset.conditionIndex, 10)

    const field = this.c.currentPageFields.find(f => f.id === fieldId)
    if (!field || !field.conditions) return

    field.conditions.splice(conditionIndex, 1)
    this.renderConditionsUI(field)
    this.c.saveManager.markDirty()
  },

  renderConditionsUI(field) {
    if (!this.c.hasConditionsContainerTarget) return

    const conditions = field.conditions || []

    if (conditions.length === 0) {
      this.c.conditionsContainerTarget.innerHTML = ""
      return
    }

    const otherFields = this.c.currentPageFields.filter(f => f.id !== field.id)
    const operatorLabels = this.c.conditionOperatorLabelsValue

    const conditionsHtml = conditions.map((condition, index) => {
      const fieldOptions = otherFields
        .map(f => `<option value="${f.id}" ${condition.field_id === f.id ? "selected" : ""}>${f.label || f.property_slug}</option>`)
        .join("")

      const hideValue = condition.operator === "is_empty" || condition.operator === "is_not_empty"

      return `
      <div class="condition-item p-3 bg-gray-50 rounded-lg border border-gray-200 space-y-2">
        <div class="flex items-center justify-between">
          <span class="text-xs font-medium text-gray-500">
            ${index === 0 ? this.c.conditionIfLabelValue : (condition.logic === "or" ? this.c.conditionOrLabelValue : this.c.conditionAndLabelValue)}
          </span>
          <button type="button"
                  class="text-gray-400 hover:text-red-500 transition-colors"
                  data-field-id="${field.id}"
                  data-condition-index="${index}"
                  data-action="click->page-builder#removeCondition">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <select class="w-full text-sm border border-gray-200 rounded-md px-2 py-1.5"
                data-field-id="${field.id}"
                data-condition-index="${index}"
                data-property="field_id"
                data-action="change->page-builder#updateCondition">
          <option value="">${this.c.conditionSelectFieldOptionValue}</option>
          ${fieldOptions}
        </select>

        <select class="w-full text-sm border border-gray-200 rounded-md px-2 py-1.5"
                data-field-id="${field.id}"
                data-condition-index="${index}"
                data-property="operator"
                data-action="change->page-builder#updateCondition">
          <option value="equals" ${condition.operator === "equals" ? "selected" : ""}>${operatorLabels.equals}</option>
          <option value="not_equals" ${condition.operator === "not_equals" ? "selected" : ""}>${operatorLabels.not_equals}</option>
          <option value="contains" ${condition.operator === "contains" ? "selected" : ""}>${operatorLabels.contains}</option>
          <option value="not_contains" ${condition.operator === "not_contains" ? "selected" : ""}>${operatorLabels.not_contains}</option>
          <option value="greater_than" ${condition.operator === "greater_than" ? "selected" : ""}>${operatorLabels.greater_than}</option>
          <option value="less_than" ${condition.operator === "less_than" ? "selected" : ""}>${operatorLabels.less_than}</option>
          <option value="is_empty" ${condition.operator === "is_empty" ? "selected" : ""}>${operatorLabels.is_empty}</option>
          <option value="is_not_empty" ${condition.operator === "is_not_empty" ? "selected" : ""}>${operatorLabels.is_not_empty}</option>
        </select>

        <input type="text"
               class="w-full text-sm border border-gray-200 rounded-md px-2 py-1.5 ${hideValue ? "hidden" : ""}"
               placeholder="${this.c.valuePlaceholderValue}"
               value="${condition.value || ""}"
               data-field-id="${field.id}"
               data-condition-index="${index}"
               data-property="value"
               data-action="input->page-builder#updateCondition">

        ${index > 0 ? `
          <select class="w-full text-sm border border-gray-200 rounded-md px-2 py-1.5"
                  data-field-id="${field.id}"
                  data-condition-index="${index}"
                  data-property="logic"
                  data-action="change->page-builder#updateCondition">
            <option value="and" ${condition.logic === "and" ? "selected" : ""}>${this.c.conditionAndLabelValue}</option>
            <option value="or" ${condition.logic === "or" ? "selected" : ""}>${this.c.conditionOrLabelValue}</option>
          </select>
        ` : ""}
      </div>
    `}).join("")

    this.c.conditionsContainerTarget.innerHTML = conditionsHtml
  }
}
