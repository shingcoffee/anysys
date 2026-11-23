/**
 * Step Manager Module
 * Handles step operations for Process elements in the Property Editor.
 */

import { escapeHtml, generateStepId } from "utils"
import {
  buildStepItemTemplate,
  buildSectionHeader,
  buildStepConfigFieldsHTML
} from "controllers/property_editor/templates"
import { ModalMixin } from "controllers/property_editor/modal_mixin"
import { BaseManager } from "controllers/property_editor/base_manager"
import { actionFields, getActionConfig } from "flowchart/constants/action_registry"
import { DragDropMixin } from "controllers/property_editor/step_manager/drag_drop"
import { ActionPickerMixin } from "controllers/property_editor/step_manager/action_picker"
import { ConfigFieldsMixin } from "controllers/property_editor/step_manager/config_fields"

export class StepManager extends BaseManager {
  constructor(controller) {
    super(controller, 'stepIndex')
    this._draggedItem = null
    this._changeSnapshot = null
    this._pickerLeafMap = {}
  }

  // ===================
  // Public API
  // ===================

  reset() {
    super.reset()
    this._changeSnapshot = null
    this._disarmChangeOutsideClick()
  }

  // ===================
  // Step Toggle/Remove
  // ===================

  toggleStep(event) {
    // Don't toggle if clicking on the remove button, drag handle, or form elements
    if (event.target.closest("button") || event.target.closest("[data-drag-handle]") || event.target.closest("select") || event.target.closest("textarea") || event.target.closest("input")) {
      return
    }

    const stepItem = event.currentTarget.closest("[data-step-item]")
    if (!stepItem) return

    // Check if step has details to expand
    const detailsSection = stepItem.querySelector("[data-step-details]")
    if (!detailsSection) return

    const isExpanded = stepItem.classList.contains("step-expanded")
    const willExpand = !isExpanded
    this._setStepExpanded(stepItem, willExpand)
  }

  removeStep(event) {
    event.preventDefault()
    const stepItem = event.target.closest("[data-step-item]")
    if (!stepItem) return

    stepItem.remove()

    // Re-open the picker — it is the empty state
    this._changeSnapshot = null
    this._showStepPicker()

    // Dispatch event to trigger auto-sync to canvas
    this._dispatchEvent("stepRemoved")
  }

  // ===================
  // Data Collection
  // ===================

  collectSteps() {
    const container = this.controller.formFieldsTarget.querySelector("[data-steps-container]")
    if (!container) return null

    const steps = []
    // Change temporarily detaches the live card. Until a replacement is
    // committed, its edited fields still belong to the element being saved.
    const stepItems = this._changeSnapshot ? [this._changeSnapshot] : container.querySelectorAll("[data-step-item]")

    stepItems.forEach(item => {
      // Match on the bare token (not the bracketed form) so happy-dom's selector
      // engine parses it correctly — `[name*='[action]']` mis-resolves there.
      const actionInput = item.querySelector("input[name*='action']")
      const suboptionInput = item.querySelector("input[name*='suboption']")
      const selectionLabelsInput = item.querySelector("input[name*='selectionLabels']")
      const keywordParamsInput = item.querySelector("input[name*='keywordParams']")
      const descInput = item.querySelector("[data-step-description]")

      const action = actionInput?.value || item.dataset.stepAction || ""
      const suboption = suboptionInput?.value || ""
      const description = descInput?.value?.trim() || ""

      if (action) {
        // Preserve the step's stable id across the DOM round-trip. If the
        // item somehow lost its id (e.g. rendered by legacy code before
        // this change shipped), mint one now and write it back onto the
        // DOM so subsequent collects stay stable.
        let stepId = item.dataset.stepId
        if (!stepId) {
          stepId = generateStepId()
          item.dataset.stepId = stepId
        }
        const stepData = { id: stepId, action, description }
        if (suboption) {
          stepData.suboption = suboption
        }
        if (selectionLabelsInput?.value) {
          try {
            stepData.selectionLabels = JSON.parse(selectionLabelsInput.value)
          } catch {
            // Ignore parse errors
          }
        }
        if (keywordParamsInput?.value) {
          try {
            stepData.keywordParams = JSON.parse(keywordParamsInput.value)
          } catch {
            // Ignore parse errors
          }
        }

        // Collect config from expanded config fields (live DOM values)
        const liveConfig = this.collectStepConfig(item)
        // Also read the stored config from hidden input as fallback for keys
        // that are not currently rendered (e.g. fields hidden by visibleWhen).
        const storedConfigInput = item.querySelector("[data-step-config]")
        let storedConfig = {}
        if (storedConfigInput?.value) {
          try { storedConfig = JSON.parse(storedConfigInput.value) } catch { /* ignore */ }
        }
        // A field that IS rendered is authoritative: its liveConfig entry
        // wins, and if it was intentionally cleared (not in liveConfig) the
        // stored value must be dropped rather than resurrected.
        const renderedKeys = this.collectRenderedConfigFieldKeys(item)
        const baseConfig = { ...storedConfig }
        renderedKeys.forEach(k => { delete baseConfig[k] })
        const mergedConfig = { ...baseConfig, ...liveConfig }
        if (Object.keys(mergedConfig).length > 0) {
          stepData.config = mergedConfig
        }

        steps.push(stepData)
      }
    })

    return steps
  }

  /**
   * Return the set of config-field keys currently rendered for a step item.
   * Used to distinguish "user cleared this field" from "field was never shown"
   * during save — cleared fields should drop the stored value, hidden fields
   * should preserve it.
   */
  collectRenderedConfigFieldKeys(stepItem) {
    const keys = new Set()
    stepItem.querySelectorAll("[data-config-field]").forEach(fieldEl => {
      const key = fieldEl.dataset.configField
      if (key) keys.add(key)
    })
    return keys
  }

  // Get list of single-use actions that are already used in the steps list
  getUsedSingleUseActions() {
    const container = this.controller.formFieldsTarget?.querySelector("[data-steps-container]")
    if (!container) return []

    const usedActions = []
    const stepItems = container.querySelectorAll("[data-step-item]")

    stepItems.forEach(item => {
      const action = item.dataset.stepAction
      const entry = getActionConfig(action)
      if (entry?.singleUse === true) usedActions.push(entry.key)
    })

    return usedActions
  }

  // ===================
  // HTML Building
  // ===================

  buildStepsFieldHTML(fieldName, fieldSchema, currentValue) {
    const steps = Array.isArray(currentValue) ? currentValue : []

    let stepsHTML = `
      <div class="space-y-3">
        <section>
          ${buildSectionHeader({ label: fieldSchema.label || this.controller.tabStepsLabelValue })}
          <div data-steps-container class="space-y-1"
               data-action="dragover->property-editor#handleStepDragOver drop->property-editor#handleStepDrop">
    `

    // Render existing steps (collapsed — reload state)
    steps.forEach((step, index) => {
      const actionOption = getActionConfig(step.action)
      let selectionLabels = null
      if (step.selectionLabels) {
        try {
          selectionLabels = typeof step.selectionLabels === "string"
            ? JSON.parse(step.selectionLabels) : step.selectionLabels
        } catch { selectionLabels = null }
      }
      let keywordParams = []
      if (step.keywordParams) {
        try {
          keywordParams = typeof step.keywordParams === "string"
            ? JSON.parse(step.keywordParams) : step.keywordParams
        } catch { keywordParams = [] }
      }
      let currentConfig = {}
      if (step.config) {
        try {
          currentConfig = typeof step.config === "string" ? JSON.parse(step.config) : step.config
        } catch { currentConfig = {} }
      }
      stepsHTML += this.buildStepItemHTML(
        index, step.action || "", step.description || "", null,
        false, // collapsed on reload
        step.suboption || "", actionOption, selectionLabels, keywordParams,
        currentConfig,
        step.id || generateStepId()
      )
      this.stepIndex = index + 1
    })

    stepsHTML += `
          </div>
          <div data-step-picker-mount class="${steps.length >= 1 ? "hidden" : "mt-1"}">
            ${this.buildStepPickerHTML()}
          </div>
        </section>
      </div>
    `
    queueMicrotask(() => {
      this.refreshAllCapabilityChrome()
      this.applyConfigProblemsFromCanvas()
    })
    return stepsHTML
  }

  buildStepItemHTML(index, action, description, actionOptions = null, expanded = false, suboption = "", actionOptionData = null, selectionLabels = null, keywordParams = [], currentConfig = {}, id = "") {
    if (!actionOptionData && action) {
      actionOptionData = getActionConfig(action)
    }

    // Every step DOM item must carry a stable id in data-step-id so it
    // survives DOM round-trips (collectSteps reads it back).
    // Callers generate an id once at creation; backfill here if missing.
    const resolvedId = id || generateStepId()

    // Build config fields HTML for the expanded step item
    const context = {
      elementId: this.controller.currentElement?.id || "",
      stepIndex: index,
      entityAttributes: this.controller.canvas?.entityAttributes || [],
      moreOpen: this.controller.disclosureState?.get(`${resolvedId}:more`) === true,
      labels: this._stepFieldLabels()
    }
    const configFieldsHTML = this.buildStepConfigHTML(action, currentConfig, suboption, context)

    // Use template from templates.js
    return buildStepItemTemplate({
      id: resolvedId,
      index,
      action,
      description,
      actionOptionData,
      selectionLabels,
      suboption,
      keywordParams,
      configFieldsHTML,
      currentConfig,
      expanded,
      labels: this._stepItemLabels()
    })
  }

  /**
   * Translated label overrides threaded into templates/step.js's
   * buildStepItemTemplate (plain function, no controller ref). Mirrors
   * BranchManager#_branchLabels().
   * @private
   */
  _stepItemLabels() {
    const c = this.controller
    return {
      dragToReorderTitle: c.stepDragToReorderTitleValue,
      changeButtonLabel: c.stepChangeButtonLabelValue,
      changeActionTitle: c.stepChangeActionTitleValue,
      removeButtonLabel: c.stepRemoveButtonLabelValue,
      removeButtonTitle: c.stepRemoveButtonTitleValue,
      errorBadgeLabel: c.stepErrorBadgeLabelValue,
      paramsPrefixLabel: c.stepParamsPrefixLabelValue
    }
  }

  /**
   * Translated label overrides threaded into templates/fields.js's config
   * field builders (plain functions, no controller ref) via context.labels.
   * otherOptgroupLabel/enterManuallyOptionLabel/switchToDropdownTitle/
   * columnNamePlaceholder reuse the identical English already keyed for
   * query_count.js's entity-column chrome.
   * @private
   */
  _stepFieldLabels() {
    const c = this.controller
    return {
      moreOptionsLabel: c.stepMoreOptionsLabelValue,
      setCountFormat: c.stepConfigSetCountFormatValue,
      insertVariableTitle: c.insertVariableTitleValue,
      noVariablesAvailable: c.noVariablesAvailableValue,
      usedInThisElement: c.usedInThisElementLabelValue,
      noMatchingVariables: c.noMatchingVariablesLabelValue,
      selectColumnPlaceholder: c.selectColumnPlaceholderValue,
      otherOptgroupLabel: c.otherGroupLabelValue,
      enterManuallyOptionLabel: c.enterManuallyLabelValue,
      switchToDropdownTitle: c.switchToDropdownTitleValue,
      columnNamePlaceholder: c.columnNamePlaceholderValue,
      kvKeyPlaceholder: c.kvKeyPlaceholderValue,
      kvValuePlaceholder: c.kvValuePlaceholderValue,
      kvRemoveRowTitle: c.kvRemoveRowTitleValue,
      addLabel: c.addLabelValue,
      retryNotIdempotentHint: c.stepRetryNotIdempotentHintValue,
      timeoutGivesUpFormat: c.stepTimeoutGivesUpFormatValue,
      branchOperatorLabels: c.branchOperatorLabelsValue,
      valuePlaceholder: c.valuePlaceholderValue
    }
  }

  /**
   * Build config field HTML for a specific action.
   * Reads configSchema from registry and renders fields with current values.
   * @param {string} actionValue - Action identifier
   * @param {Object} currentConfig - Current config values
   * @param {string} subOption - Sub-option path if applicable
   * @param {Object} context - Context for autocomplete (elementId, stepIndex, labels)
   */
  buildStepConfigHTML(actionValue, currentConfig = {}, subOption = "", context = {}) {
    const actionEntry = getActionConfig(actionValue)
    if (!actionEntry) return ""

    const configSchema = actionFields(actionEntry)
    const fieldsHTML = configSchema.length === 0
      ? ""
      : buildStepConfigFieldsHTML(configSchema, currentConfig, context)
    const chromeHTML = this.capabilityChromeHTML(actionEntry, currentConfig, context.labels || {})
    return `${fieldsHTML}${chromeHTML}`
  }
}

// Apply ModalMixin to add shared modal utilities
Object.assign(StepManager.prototype, ModalMixin)

// Apply DragDropMixin to add drag-and-drop reordering
Object.assign(StepManager.prototype, DragDropMixin)

// Apply ActionPickerMixin to add inline action picker and output-variable logic
Object.assign(StepManager.prototype, ActionPickerMixin)

// Apply ConfigFieldsMixin to add config field change handling and entity helpers
Object.assign(StepManager.prototype, ConfigFieldsMixin)

export default StepManager
