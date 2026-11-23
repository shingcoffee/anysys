/**
 * Form Builder Module
 * Catalog-driven form construction for the Property Editor.
 */

import { escapeHtml } from "utils"
import { ELEMENT_COLORS } from "flowchart/constants"
import {
  chrome as catalogChrome,
  elementFields,
  elementLabel,
  elementDefaultLabel
} from "flowchart/constants/element_registry"
import { renderCatalogField } from "controllers/property_editor/controls/field_renderer"

const ELEMENT_TYPE_ICONS = {
  start:         "M5 3l14 9-14 9V3z",
  end:           "M21 12a9 9 0 11-18 0 9 9 0 0118 0zM9 10a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1h-4a1 1 0 01-1-1v-4z",
  process:       "M4 6h16M4 12h16M4 18h16",
  decision:      "M12 3l9 9-9 9-9-9 9-9z",
  loop:          "M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15",
  subflow:       "M4 5a1 1 0 011-1h14a1 1 0 011 1v14a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM9 3v18M15 3v18"
}

export class FormBuilder {
  constructor(controller) {
    this.controller = controller
  }

  buildForm() {
    if (!this.controller.currentElement || !this.controller.canvas) return

    const type = this.controller.currentElement.type
    const properties = this.controller.currentElement.properties || {}

    this._updateTitle()
    this._buildFormFields(type, properties)
    this._focusFirstInput()
  }

  _updateTitle() {
    if (!this.controller.hasTitleTarget) return

    const type = this.controller.currentElement.type
    const typeLabel = elementLabel(type) || type
    const colors = ELEMENT_COLORS[type] || ELEMENT_COLORS.process

    this.controller.titleTarget.textContent = typeLabel

    if (this.controller.hasTypeIndicatorTarget) {
      this.controller.typeIndicatorTarget.style.backgroundColor = colors.fill
      this.controller.typeIndicatorTarget.style.borderColor = colors.stroke
    }

    if (this.controller.hasTypeIconTarget) {
      this.controller.typeIconTarget.style.color = colors.stroke
      const iconPath = this.controller.typeIconTarget.querySelector("path")
      if (iconPath) {
        iconPath.setAttribute("d", ELEMENT_TYPE_ICONS[type] || ELEMENT_TYPE_ICONS.process)
      }
    }

    if (this.controller.hasHeaderWrapperTarget) {
      this.controller.headerWrapperTarget.style.backgroundColor = colors.fill
      this.controller.headerWrapperTarget.style.borderBottom = `1px solid ${colors.stroke}33`
    }
  }

  _buildFormFields(type, properties) {
    const fields = elementFields(type)
    const chrome = catalogChrome()
    const labels = this._controlLabels()
    const context = {
      properties,
      fields,
      labels,
      elementId: this.controller.currentElement?.id || "",
      entityAttributes: this.controller.canvas?.entityAttributes || []
    }

    const mainFields = fields.filter((field) => field.group !== "advanced")
    const advancedFields = fields.filter((field) => field.group === "advanced")

    let generalHTML = this._buildLabelField(chrome.label, this.controller.currentElement.label)
    mainFields.forEach((field) => {
      generalHTML += renderCatalogField(field, this._fieldValue(field, properties), context)
    })
    generalHTML += this._buildNotes(chrome.notes, properties[chrome.notes.key])

    let stepsHTML = ""
    if (type === "process" && this.controller.stepManager) {
      stepsHTML = this.controller.stepManager.buildStepsFieldHTML("steps", { type: "steps" }, properties.steps)
    }
    if (type === "decision" && this.controller.branchManager) {
      stepsHTML = this.controller.branchManager.buildBranchesFieldHTML("branches", { type: "branches" }, properties.branches)
    }

    let advancedHTML = ""
    advancedFields.forEach((field) => {
      advancedHTML += renderCatalogField(field, this._fieldValue(field, properties), context)
    })

    const generalContainer = this.controller.getFormFieldsForTab("general")
    const stepsContainer = this.controller.getFormFieldsForTab("steps")
    const ioContainer = this.controller.getFormFieldsForTab("io")
    const advancedContainer = this.controller.getFormFieldsForTab("advanced")

    if (generalContainer) generalContainer.innerHTML = generalHTML
    if (stepsContainer) stepsContainer.innerHTML = stepsHTML
    if (ioContainer) ioContainer.innerHTML = ""
    if (advancedContainer) {
      advancedContainer.innerHTML = advancedHTML
      advancedContainer.classList.remove("grid", "grid-cols-2", "gap-2")
      advancedContainer.classList.add("space-y-2")
    }
  }

  _controlLabels() {
    const c = this.controller
    return {
      noneOptionLabel: c.noneOptionLabelValue,
      addRowLabel: c.addRowLabelValue,
      removeRowTitle: c.removeRowTitleValue,
      searchPlaceholder: c.searchPlaceholderValue,
      localeEnLabel: c.localeEnLabelValue,
      localeZhCnLabel: c.localeZhCnLabelValue,
      referenceLoadingLabel: c.referenceLoadingLabelValue,
      referenceEmptyLabel: c.referenceEmptyLabelValue,
      referenceErrorLabel: c.referenceErrorLabelValue,
      referencePlaceholder: c.referencePlaceholderValue,
      joinAndLabel: c.joinAndLabelValue,
      joinOrLabel: c.joinOrLabelValue,
      valuePlaceholder: c.valuePlaceholderValue,
      defaultPlaceholderFormat: c.defaultPlaceholderFormatValue || "Default: {value}",
      insertVariableTitle: c.insertVariableTitleValue,
      noVariablesAvailable: c.noVariablesAvailableValue,
      usedInThisElement: c.usedInThisElementLabelValue,
      noMatchingVariables: c.noMatchingVariablesLabelValue,
      branchOperatorLabels: c.branchOperatorLabelsValue
    }
  }

  _fieldValue(field, properties) {
    if (Object.prototype.hasOwnProperty.call(properties, field.name)) return properties[field.name]
    if (field.role === "integer" || field.role === "decimal" || field.control === "number") return undefined
    return field.default ?? ""
  }

  _buildLabelField(chromeLabel, currentValue) {
    const label = chromeLabel?.label || "Label"
    const value = currentValue ?? ""
    return `
      <div class="space-y-1" data-element-field="label">
        <label for="prop_label" class="block text-xs font-medium text-slate-500">${escapeHtml(label)}</label>
        <input type="text"
               id="prop_label"
               name="label"
               value="${escapeHtml(value)}"
               class="w-full px-2 py-1.5 text-xs border border-slate-200 bg-white rounded-md placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400">
      </div>`
  }

  _buildNotes(notesChrome, currentValue) {
    const key = notesChrome?.key || "description"
    const label = notesChrome?.label || "Notes"
    const value = currentValue ?? ""
    const open = String(value).trim() !== "" ? " open" : ""
    return `
      <details data-element-field="${escapeHtml(key)}" data-notes-disclosure class="rounded-md border border-slate-200"${open}>
        <summary class="cursor-pointer px-2.5 py-1.5 text-xs font-medium text-slate-700 hover:bg-slate-50">${escapeHtml(label)}</summary>
        <div class="px-2.5 pb-2.5 border-t border-slate-200">
          <textarea id="prop_${escapeHtml(key)}"
                    name="${escapeHtml(key)}"
                    rows="3"
                    class="mt-2 w-full px-2 py-1.5 text-xs border border-slate-200 bg-white rounded-md placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400">${escapeHtml(value)}</textarea>
        </div>
      </details>`
  }

  /**
   * Decide whether later edits should auto-derive the label. Opening the
   * panel must not rewrite the input or mutate the element.
   */
  _autoDeriveLabelOnOpen() {
    const labelInput = this.controller.formTarget?.querySelector('input[name="label"]')
    if (!labelInput) return

    const currentLabel = labelInput.value.trim()
    const type = this.controller.currentElement?.type || ""
    const defaultLabel = elementDefaultLabel(type) || ""
    const isAutomaticBlankOrDefault = currentLabel === "" || (defaultLabel && currentLabel === defaultLabel)

    if (!isAutomaticBlankOrDefault) {
      const properties = this.controller._collectFormData()
      const wouldDerive = this.controller._deriveLabelFromProperties(properties, "")
      if (wouldDerive && currentLabel === wouldDerive) {
        this.controller._labelAutoDerived = true
      } else {
        this.controller._labelAutoDerived = false
      }
      this._attachLabelInputListener(labelInput)
      return
    }

    this.controller._labelAutoDerived = true
    this._attachLabelInputListener(labelInput)
  }

  _attachLabelInputListener(labelInput) {
    if (this._boundLabelInputHandler) {
      labelInput.removeEventListener("input", this._boundLabelInputHandler)
    }

    this._boundLabelInputHandler = () => {
      if (labelInput.value.trim() === "") {
        this.controller._labelAutoDerived = true
        this.controller._performSync()
      } else {
        this.controller._labelAutoDerived = false
      }
    }

    labelInput.addEventListener("input", this._boundLabelInputHandler)
  }

  _focusFirstInput() {
    setTimeout(() => {
      const activeTab = this.controller.tabManager?.activeTab || "general"
      const container = this.controller.getFormFieldsForTab(activeTab)
      if (container) {
        const firstInput = container.querySelector("input, textarea, select")
        if (firstInput) firstInput.focus()
      }
    }, 100)
  }
}

export default FormBuilder
