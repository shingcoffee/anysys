import { BaseManager } from "controllers/page_builder/base_manager"

export const FORMULA_FUNCTIONS = {
  "Math": ["SUM", "SUBTRACT", "MULTIPLY", "DIVIDE", "MIN", "MAX", "AVERAGE", "ROUND", "FLOOR", "CEIL", "ABS"],
  "Logic": ["IF", "AND", "OR", "NOT", "SWITCH"],
  "Text": ["CONCAT", "UPPER", "LOWER", "TRIM", "LENGTH", "LEFT", "RIGHT"],
  "Date": ["TODAY", "NOW", "YEAR", "MONTH", "DAY", "DATE_DIFF", "DATE_ADD"]
}

export class CalculationsManager extends BaseManager {
  // -----------------------------------------------------------------------
  // Open / close
  // -----------------------------------------------------------------------

  openFormulaEditor(event) {
    const calcId = event?.currentTarget?.dataset?.calculationId
    this.c.editingCalculationIdValue = calcId || ""

    const calc = calcId
      ? this.c.configuration.calculations?.find(c => c.id === calcId)
      : { id: null, target_field_id: "", formula: "", format: {} }

    this.c.currentEditingCalculation = JSON.parse(JSON.stringify(calc || {}))
    this.renderFormulaEditorModal()
  }

  renderFormulaEditorModal() {
    if (!this.c.hasFormulaEditorModalTarget) return
    if (!this.c.hasCalculationEditorTemplateTarget) {
      // Fallback: clear so stale content isn't shown
      this.c.formulaEditorModalTarget.innerHTML = ""
      return
    }

    const calc = this.c.currentEditingCalculation
    const modal = this.c.formulaEditorModalTarget

    // Clone the server-rendered template
    const tpl = this.c.calculationEditorTemplateTarget.content.cloneNode(true)
    modal.innerHTML = ""
    modal.appendChild(tpl)

    // Hydrate: set target field selection
    const targetSelect = modal.querySelector('[data-page-builder-target="calculationTargetField"]')
    if (targetSelect && calc.target_field_id) {
      const opt = targetSelect.querySelector(`option[value="${CSS.escape(calc.target_field_id)}"]`)
      if (opt) opt.selected = true
    }

    // Update title
    const titleEl = modal.querySelector("[data-calc-editor-title]")
    if (titleEl) titleEl.textContent = calc.id ? this.c.calcModalTitleEditValue : this.c.calcModalTitleNewValue

    // Hydrate: pill editor formula value
    const formulaEditorRoot = modal.querySelector('[data-controller~="formula-editor"]')
    if (formulaEditorRoot && calc.formula) {
      formulaEditorRoot.dataset.formulaEditorFormulaValue = calc.formula
      // Re-trigger connect if already connected (Stimulus will pick up changed value)
    }

    // Hydrate: format controls
    const fmt = calc.format || {}
    const fmtType = modal.querySelector('[data-calc-format="type"]')
    if (fmtType && fmt.type) fmtType.value = fmt.type
    const fmtDecimals = modal.querySelector('[data-calc-format="decimals"]')
    if (fmtDecimals && fmt.decimals != null) fmtDecimals.value = fmt.decimals
    const fmtPrefix = modal.querySelector('[data-calc-format="prefix"]')
    if (fmtPrefix && fmt.prefix) fmtPrefix.value = fmt.prefix
    const fmtSuffix = modal.querySelector('[data-calc-format="suffix"]')
    if (fmtSuffix && fmt.suffix) fmtSuffix.value = fmt.suffix

    // Switch drawer to editor state
    this.c.tabManager?.showDrawerEditor("calculations")
  }

  closeFormulaEditor() {
    this.c.editingCalculationIdValue = ""
    this.c.currentEditingCalculation = null
    if (this.c.hasFormulaEditorModalTarget) {
      this.c.formulaEditorModalTarget.innerHTML = ""
    }
    // Switch drawer back to list state
    this.c.tabManager?.showDrawerList("calculations")
  }

  closeFormulaEditorOnBackdrop(event) {
    if (event.target === event.currentTarget) {
      this.closeFormulaEditor()
    }
  }

  editCalculation(event) {
    this.openFormulaEditor(event)
  }

  // -----------------------------------------------------------------------
  // Save
  // -----------------------------------------------------------------------

  saveCalculation() {
    const modal = this.c.hasFormulaEditorModalTarget ? this.c.formulaEditorModalTarget : null
    if (!modal) return

    const targetSelect = modal.querySelector('[data-page-builder-target="calculationTargetField"]')
    const targetFieldId = targetSelect?.value || ""

    // Read formula from the pill editor via its controller API
    let formula = ""
    const formulaEditorRoot = modal.querySelector('[data-controller~="formula-editor"]')
    if (formulaEditorRoot) {
      const formulaCtrl = this.application?.getControllerForElementAndIdentifier(formulaEditorRoot, "formula-editor")
      formula = formulaCtrl ? formulaCtrl.getFormula() : ""
    }

    // Read format controls
    const format = {}
    const fmtType = modal.querySelector('[data-calc-format="type"]')?.value
    if (fmtType && fmtType !== "plain") format.type = fmtType
    const fmtDecimals = modal.querySelector('[data-calc-format="decimals"]')?.value
    if (fmtDecimals !== "") format.decimals = parseInt(fmtDecimals) || 0
    const fmtPrefix = modal.querySelector('[data-calc-format="prefix"]')?.value
    if (fmtPrefix) format.prefix = fmtPrefix
    const fmtSuffix = modal.querySelector('[data-calc-format="suffix"]')?.value
    if (fmtSuffix) format.suffix = fmtSuffix

    if (!targetFieldId || !formula) {
      alert(this.c.calcSelectTargetFormulaMsgValue)
      return
    }

    const calc = {
      id: this.c.editingCalculationIdValue || `calc_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
      target_field_id: targetFieldId,
      formula,
      format: Object.keys(format).length ? format : {}
    }

    if (!this.c.configuration.calculations) {
      this.c.configuration.calculations = []
    }

    if (this.c.editingCalculationIdValue) {
      const idx = this.c.configuration.calculations.findIndex(c => c.id === this.c.editingCalculationIdValue)
      if (idx >= 0) {
        this.c.configuration.calculations[idx] = calc
      }
    } else {
      this.c.configuration.calculations.push(calc)
    }

    this.c.undoRedoManager.saveHistory()
    this.closeFormulaEditor()
    this.renderCalculationsPanel()
    this.c.saveManager.markDirty()
  }

  // -----------------------------------------------------------------------
  // Delete
  // -----------------------------------------------------------------------

  deleteCalculation(event) {
    const calcId = event.currentTarget.dataset.calculationId
    if (!confirm(this.c.deleteCalculationConfirmValue)) return

    this.c.configuration.calculations = (this.c.configuration.calculations || []).filter(c => c.id !== calcId)
    this.c.undoRedoManager.saveHistory()
    this.renderCalculationsPanel()
    this.c.saveManager.markDirty()
  }

  // -----------------------------------------------------------------------
  // Panel render (Tailwind list — no HTML strings for the modal)
  // -----------------------------------------------------------------------

  renderCalculationsPanel() {
    if (!this.c.hasCalculationsPanelTarget) return

    const calculations = this.c.configuration.calculations || []
    const fields = this.c.allFields

    const getFieldLabel = (fieldId) => {
      const field = fields.find(f => f.id === fieldId)
      return field?.label || fieldId
    }

    const formulaSummary = (formula) => {
      if (!formula) return ""
      return formula.length > 40 ? formula.substring(0, 40) + "…" : formula
    }

    let html = `<div data-calculations-panel class="px-4 py-4">`

    // Top bar
    html += `
      <div class="flex items-center justify-between mb-3">
        <p class="text-xs text-gray-500">${this.escapeHtml((calculations.length === 1 ? this.c.calcConfiguredSingularValue : this.c.calcConfiguredPluralValue).replace("{count}", calculations.length))}</p>
        <button type="button"
                class="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-purple-600 bg-purple-50 hover:bg-purple-100 rounded-md transition-colors"
                data-action="click->page-builder#openFormulaEditor">
          <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
          </svg>
          ${this.escapeHtml(this.c.addCalculationLabelValue)}
        </button>
      </div>
    `

    if (calculations.length === 0) {
      html += `
        <div class="flex flex-col items-center justify-center py-16 text-center px-4">
          <div class="w-12 h-12 bg-purple-50 rounded-xl flex items-center justify-center mb-3">
            <svg class="w-6 h-6 text-purple-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
              <path stroke-linecap="round" stroke-linejoin="round" d="M9 7h6m0 10v-3m-3 3h.01M9 17h.01M9 14h.01M12 14h.01M15 11h.01M12 11h.01M9 11h.01M7 21h10a2 2 0 002-2V5a2 2 0 00-2-2H7a2 2 0 00-2 2v14a2 2 0 002 2z" />
            </svg>
          </div>
          <p class="text-sm font-medium text-gray-900 mb-1">${this.escapeHtml(this.c.noCalculatedFieldsLabelValue)}</p>
          <p class="text-xs text-gray-500 max-w-[240px] mb-5">${this.escapeHtml(this.c.noCalculatedFieldsHintValue)}</p>
          <button type="button"
                  class="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium bg-purple-600 hover:bg-purple-700 text-white rounded-lg transition-colors"
                  data-action="click->page-builder#openFormulaEditor">
            ${this.escapeHtml(this.c.addCalculationLabelValue)}
          </button>
        </div>
      `
    } else {
      if (calculations.length > 6) {
        html += `
          <div class="mb-3">
            <input type="text" placeholder="${this.escapeHtml(this.c.searchCalculationsPlaceholderValue)}"
                   class="w-full px-2.5 py-1.5 text-xs border border-gray-200 rounded-md focus:outline-none focus:ring-1 focus:ring-purple-500"
                   data-action="input->page-builder#filterPanel"
                   data-filter-panel="calculations-panel"
                   data-filter-items="calculation-id">
          </div>
        `
      }
      html += `<div class="space-y-2">`
      calculations.forEach(calc => {
        const fmt = calc.format || {}
        const formatBadge = fmt.type && fmt.type !== "plain"
          ? `<span class="px-1.5 py-0.5 text-[10px] rounded-md bg-purple-100 text-purple-700 font-medium">${this.escapeHtml(fmt.type)}</span>`
          : ""
        html += `
          <div data-calculation-id="${calc.id}"
               class="group flex items-center justify-between p-3 bg-white rounded-lg border border-gray-200 hover:border-purple-200 hover:shadow-sm transition-all">
            <div class="min-w-0 flex flex-col gap-0.5">
              <div class="flex items-center gap-1.5">
                <span class="text-sm font-medium text-gray-800 truncate">${this.escapeHtml(getFieldLabel(calc.target_field_id))}</span>
                ${formatBadge}
              </div>
              <span class="text-xs text-gray-500 font-mono block truncate max-w-[300px]">= ${this.escapeHtml(formulaSummary(calc.formula))}</span>
            </div>
            <div class="flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity flex-shrink-0">
              <button type="button"
                      class="p-1.5 text-gray-400 hover:text-purple-600 hover:bg-purple-50 rounded-md transition-colors"
                      data-action="click->page-builder#editCalculation" data-calculation-id="${calc.id}" title="${this.escapeHtml(this.c.actionEditTitleValue)}">
                <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                </svg>
              </button>
              <button type="button"
                      class="p-1.5 text-gray-400 hover:text-red-500 hover:bg-red-50 rounded-md transition-colors"
                      data-action="click->page-builder#deleteCalculation" data-calculation-id="${calc.id}" title="${this.escapeHtml(this.c.actionDeleteTitleValue)}">
                <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                </svg>
              </button>
            </div>
          </div>
        `
      })
      html += `</div>`
    }
    html += `</div>`

    this.c.calculationsPanelTarget.innerHTML = html
  }

  // Accessor for the Stimulus application instance, used when looking up
  // sibling controllers (e.g. formula-editor) via getControllerForElementAndIdentifier.
  get application() {
    return this.c.application || window.Stimulus
  }
}
