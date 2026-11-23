import { BaseManager } from "controllers/page_builder/base_manager"

export const OPERATORS = [
  { value: "equals", label: "Equals" },
  { value: "not_equals", label: "Not equals" },
  { value: "contains", label: "Contains" },
  { value: "not_contains", label: "Does not contain" },
  { value: "starts_with", label: "Starts with" },
  { value: "ends_with", label: "Ends with" },
  { value: "greater_than", label: "Greater than" },
  { value: "less_than", label: "Less than" },
  { value: "greater_or_equal", label: "Greater or equal" },
  { value: "less_or_equal", label: "Less or equal" },
  { value: "is_empty", label: "Is empty" },
  { value: "is_not_empty", label: "Is not empty" },
  { value: "is_selected", label: "Is selected" },
  { value: "is_not_selected", label: "Is not selected" }
]

export const ACTION_TYPES = [
  { value: "show_field",   label: "Show field",   target: "field" },
  { value: "hide_field",   label: "Hide field",   target: "field" },
  { value: "enable_field", label: "Enable field", target: "field" },
  { value: "disable_field",label: "Disable field",target: "field" },
  { value: "set_required", label: "Set required", target: "field" },
  { value: "show_page",    label: "Show page",    target: "page" },
  { value: "hide_page",    label: "Hide page",    target: "page" },
  { value: "skip_to_page", label: "Skip to page", target: "page" }
]

export class RulesManager extends BaseManager {
  // -----------------------------------------------------------------------
  // Open / close
  // -----------------------------------------------------------------------

  openRuleEditor(event) {
    const ruleId = event?.currentTarget?.dataset?.ruleId
    this.c.editingRuleIdValue = ruleId || ""

    const prefillTargetField = event?.currentTarget?.dataset?.prefillTargetField

    const rule = ruleId
      ? this.c.configuration.rules?.find(r => r.id === ruleId)
      : {
          id: null, name: "", enabled: true,
          conditions: { logic: "all", groups: [{ logic: "all", items: [] }] },
          actions: prefillTargetField
            ? [{ type: "show_field", target_id: prefillTargetField }]
            : []
        }

    this.c.currentEditingRule = JSON.parse(JSON.stringify(rule || {}))

    if (!this.c.currentEditingRule.conditions?.groups?.length) {
      this.c.currentEditingRule.conditions = {
        logic: "all",
        groups: [{ logic: "all", items: [] }]
      }
    }

    this.renderRuleEditorModal()
  }

  renderRuleEditorModal() {
    if (!this.c.hasRuleEditorModalTarget) return
    if (!this.c.hasRuleEditorTemplateTarget) {
      this.c.ruleEditorModalTarget.innerHTML = ""
      return
    }

    const rule = this.c.currentEditingRule
    const modal = this.c.ruleEditorModalTarget

    // Clone the server-rendered template
    const tpl = this.c.ruleEditorTemplateTarget.content.cloneNode(true)
    modal.innerHTML = ""
    modal.appendChild(tpl)

    // Hydrate: rule name
    const nameInput = modal.querySelector("[data-rule-builder-target='ruleName']")
    if (nameInput) nameInput.value = rule.name || ""

    // Hydrate: update title
    const titleEl = modal.querySelector("[data-rule-editor-title]")
    if (titleEl) titleEl.textContent = rule.id ? this.c.ruleModalTitleEditValue : this.c.ruleModalTitleNewValue

    // Hydrate: set rule id + full rule data BEFORE Stimulus connects the
    // rule-builder controller, so connect() can rebuild condition/action rows.
    const ruleBuilderEl = modal.querySelector("[data-controller~='rule-builder']")
    if (ruleBuilderEl) {
      ruleBuilderEl.dataset.ruleId = rule.id || ""
      ruleBuilderEl.dataset.ruleBuilderRuleValue = JSON.stringify(rule)
    }

    // Switch drawer to editor state (hide list, show editor)
    this.c.tabManager?.showDrawerEditor("rules")
  }

  closeRuleEditor() {
    this.c.editingRuleIdValue = ""
    this.c.currentEditingRule = null
    if (this.c.hasRuleEditorModalTarget) {
      this.c.ruleEditorModalTarget.innerHTML = ""
    }
    // Switch drawer back to list state
    this.c.tabManager?.showDrawerList("rules")
  }

  closeRuleEditorOnBackdrop(event) {
    if (event.target === event.currentTarget) {
      this.closeRuleEditor()
    }
  }

  editRule(event) {
    this.openRuleEditor(event)
  }

  // -----------------------------------------------------------------------
  // Save
  // -----------------------------------------------------------------------

  saveRule() {
    const modal = this.c.hasRuleEditorModalTarget ? this.c.ruleEditorModalTarget : null
    if (!modal) return

    // Read rule from rule-builder controller API
    const ruleBuilderEl = modal.querySelector("[data-controller~='rule-builder']")
    let rule
    if (ruleBuilderEl) {
      const ruleBuilderCtrl = this.application?.getControllerForElementAndIdentifier(ruleBuilderEl, "rule-builder")
      rule = ruleBuilderCtrl ? ruleBuilderCtrl.getRule() : this.collectRuleFallback(modal)
    } else {
      rule = this.collectRuleFallback(modal)
    }

    rule.id = this.c.editingRuleIdValue || `rule_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`

    if (!this.c.configuration.rules) {
      this.c.configuration.rules = []
    }

    if (this.c.editingRuleIdValue) {
      const idx = this.c.configuration.rules.findIndex(r => r.id === this.c.editingRuleIdValue)
      if (idx >= 0) {
        this.c.configuration.rules[idx] = rule
      }
    } else {
      this.c.configuration.rules.push(rule)
    }

    this.c.undoRedoManager.saveHistory()
    this.closeRuleEditor()
    this.renderRulesPanel()
    this.c.saveManager.markDirty()
  }

  // Fallback if rule-builder controller isn't connected yet
  collectRuleFallback(modal) {
    const nameInput = modal.querySelector("[data-rule-builder-target='ruleName']")
    return {
      name: nameInput?.value || this.c.unnamedRuleFallbackValue,
      enabled: true,
      conditions: { logic: "all", groups: [] },
      actions: []
    }
  }

  // -----------------------------------------------------------------------
  // Delete / Toggle / Duplicate
  // -----------------------------------------------------------------------

  deleteRule(event) {
    const ruleId = event.currentTarget.dataset.ruleId
    if (!confirm(this.c.deleteRuleConfirmValue)) return

    this.c.configuration.rules = (this.c.configuration.rules || []).filter(r => r.id !== ruleId)
    this.c.undoRedoManager.saveHistory()
    this.renderRulesPanel()
    this.c.saveManager.markDirty()
  }

  toggleRule(event) {
    const ruleId = event.currentTarget.dataset.ruleId
    const rule = this.c.configuration.rules?.find(r => r.id === ruleId)
    if (rule) {
      rule.enabled = !rule.enabled
      this.c.undoRedoManager.saveHistory()
      this.renderRulesPanel()
      this.c.saveManager.markDirty()
    }
  }

  duplicateRule(event) {
    const ruleId = event.currentTarget.dataset.ruleId
    const rule = this.c.configuration.rules?.find(r => r.id === ruleId)
    if (!rule) return
    const copy = JSON.parse(JSON.stringify(rule))
    copy.id = `rule_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`
    copy.name = `${rule.name} (copy)`
    this.c.configuration.rules.push(copy)
    this.c.undoRedoManager.saveHistory()
    this.renderRulesPanel()
    this.c.saveManager.markDirty()
  }

  // -----------------------------------------------------------------------
  // Panel render
  // -----------------------------------------------------------------------

  renderRulesPanel() {
    if (!this.c.hasRulesPanelTarget) return

    const rules = this.c.configuration.rules || []
    const fields = this.c.allFields

    const getFieldLabel = (id) => fields.find(f => f.id === id)?.label || id
    const ruleSummary = (rule) => {
      const condCount = (rule.conditions?.groups || []).reduce((n, g) => n + (g.items?.length || 0), 0)
      const actCount = (rule.actions || []).length
      if (!condCount && !actCount) return ""
      const parts = []
      if (condCount) {
        const firstItem = rule.conditions?.groups?.[0]?.items?.[0]
        if (firstItem) {
          parts.push(this.c.ruleWhenFormatValue.replace("{field}", getFieldLabel(firstItem.field_id)).replace("{operator}", firstItem.operator))
        }
      }
      if (actCount) {
        const first = rule.actions[0]
        parts.push(this.c.ruleActionArrowFormatValue.replace("{action}", first.type.replace(/_/g, " ")).replace("{field}", getFieldLabel(first.target_id)))
      }
      return parts.join(" ")
    }

    let html = `<div data-rules-panel class="px-4 py-4">`

    // Top bar
    html += `
      <div class="flex items-center justify-between mb-3">
        <p class="text-xs text-gray-500">${this.escapeHtml((rules.length === 1 ? this.c.rulesConfiguredSingularValue : this.c.rulesConfiguredPluralValue).replace("{count}", rules.length))}</p>
        <button type="button"
                class="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-indigo-600 bg-indigo-50 hover:bg-indigo-100 rounded-md transition-colors"
                data-action="click->page-builder#openRuleEditor">
          <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
          </svg>
          ${this.escapeHtml(this.c.addRuleLabelValue)}
        </button>
      </div>
    `

    if (rules.length > 6) {
      html += `
        <div class="mb-3">
          <input type="text" placeholder="${this.escapeHtml(this.c.searchRulesPlaceholderValue)}"
                 class="w-full px-2.5 py-1.5 text-xs border border-gray-200 rounded-md focus:outline-none focus:ring-1 focus:ring-indigo-500"
                 data-action="input->page-builder#filterPanel"
                 data-filter-panel="rules-panel"
                 data-filter-items="rule-id">
        </div>
      `
    }

    if (rules.length === 0) {
      html += `
        <div class="flex flex-col items-center justify-center py-16 text-center px-4">
          <div class="w-12 h-12 bg-indigo-50 rounded-xl flex items-center justify-center mb-3">
            <svg class="w-6 h-6 text-indigo-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
              <path stroke-linecap="round" stroke-linejoin="round" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4" />
            </svg>
          </div>
          <p class="text-sm font-medium text-gray-900 mb-1">${this.escapeHtml(this.c.noRulesDefinedLabelValue)}</p>
          <p class="text-xs text-gray-500 max-w-[240px] mb-5">${this.escapeHtml(this.c.noRulesDefinedHintValue)}</p>
          <button type="button"
                  class="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium bg-indigo-600 hover:bg-indigo-700 text-white rounded-lg transition-colors"
                  data-action="click->page-builder#openRuleEditor">
            ${this.escapeHtml(this.c.addRuleLabelValue)}
          </button>
        </div>
      `
    } else {
      html += `<div class="space-y-2">`
      rules.forEach(rule => {
        const summary = ruleSummary(rule)
        html += `
          <div data-rule-id="${rule.id}"
               class="group p-3 bg-white rounded-lg border border-gray-200 hover:border-indigo-200 hover:shadow-sm transition-all">
            <div class="flex items-center justify-between gap-2">
              <div class="flex items-center gap-2 min-w-0">
                <button type="button" class="flex-shrink-0" title="${rule.enabled ? this.escapeHtml(this.c.ruleDisableTitleValue) : this.escapeHtml(this.c.ruleEnableTitleValue)}"
                        data-action="click->page-builder#toggleRule" data-rule-id="${rule.id}">
                  <span class="block w-2 h-2 rounded-full ${rule.enabled ? "bg-emerald-500" : "bg-gray-300"}"></span>
                </button>
                <span class="text-sm font-medium text-gray-800 truncate">${this.escapeHtml(rule.name || this.c.unnamedRuleFallbackValue)}</span>
              </div>
              <div class="flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity flex-shrink-0">
                <button type="button"
                        class="p-1.5 text-gray-400 hover:text-amber-500 hover:bg-amber-50 rounded-md transition-colors"
                        data-action="click->page-builder#duplicateRule" data-rule-id="${rule.id}" title="${this.escapeHtml(this.c.actionDuplicateTitleValue)}">
                  <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M8 7v8a2 2 0 002 2h6M8 7V5a2 2 0 012-2h4.586a1 1 0 01.707.293l4.414 4.414a1 1 0 01.293.707V15a2 2 0 01-2 2h-2M8 7H6a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2v-2" />
                  </svg>
                </button>
                <button type="button"
                        class="p-1.5 text-gray-400 hover:text-indigo-600 hover:bg-indigo-50 rounded-md transition-colors"
                        data-action="click->page-builder#editRule" data-rule-id="${rule.id}" title="${this.escapeHtml(this.c.actionEditTitleValue)}">
                  <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                  </svg>
                </button>
                <button type="button"
                        class="p-1.5 text-gray-400 hover:text-red-500 hover:bg-red-50 rounded-md transition-colors"
                        data-action="click->page-builder#deleteRule" data-rule-id="${rule.id}" title="${this.escapeHtml(this.c.actionDeleteTitleValue)}">
                  <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                  </svg>
                </button>
              </div>
            </div>
            ${summary ? `<div class="mt-1 text-xs text-gray-400 truncate">${this.escapeHtml(summary)}</div>` : ""}
          </div>
        `
      })
      html += `</div>`
    }
    html += `</div>`

    this.c.rulesPanelTarget.innerHTML = html
  }

  // -----------------------------------------------------------------------
  // Legacy action handlers still delegated by page-builder controller
  // (addConditionGroup, removeConditionGroup, addConditionItem, removeConditionItem,
  //  addAction, removeAction, onActionTypeChange) are now handled by
  //  rule_builder_controller.js and no longer needed here.
  // Kept as empty stubs to avoid breaking the page-builder delegation table.
  // -----------------------------------------------------------------------

  addConditionGroup()        {}
  removeConditionGroup()     {}
  addConditionItem()         {}
  removeConditionItem()      {}
  addAction()                {}
  removeAction()             {}
  onActionTypeChange()       {}

  get application() {
    return this.c.application || window.Stimulus
  }
}
