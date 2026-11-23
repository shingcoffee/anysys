import { Controller } from "@hotwired/stimulus"

/**
 * Condition Builder Controller
 *
 * Manages dynamic condition rule building UI.
 * Used by ConditionBuilderComponent for:
 * - Connection conditions (Decision)
 * - Page display rules
 */
export default class extends Controller {
  static targets = ["rulesList", "rule", "ruleTemplate", "output"]
  static values = {
    target: { type: String, default: "conditions" },
    fields: { type: Array, default: [] },
    operators: { type: Array, default: [] }
  }

  connect() {
    this.syncFromOutput()
  }

  // ─── Actions ─────────────────────────────────────────────

  setOperator(event) {
    const operator = event.params.operator
    this.currentOperator = operator

    // Update button styles
    const buttons = event.target.closest('[role="group"]').querySelectorAll('button')
    buttons.forEach(btn => {
      const btnOp = btn.dataset.conditionBuilderOperatorParam
      if (btnOp === operator) {
        btn.className = btn.className
          .replace(/bg-white text-gray-700 border-gray-300 hover:bg-gray-50/g, '')
          .replace(/bg-indigo-600 text-white border-indigo-600/g, '')
          + ' bg-indigo-600 text-white border-indigo-600'
      } else {
        btn.className = btn.className
          .replace(/bg-indigo-600 text-white border-indigo-600/g, '')
          .replace(/bg-white text-gray-700 border-gray-300 hover:bg-gray-50/g, '')
          + ' bg-white text-gray-700 border-gray-300 hover:bg-gray-50'
      }
    })

    this.serialize()
  }

  addRule() {
    if (!this.hasRuleTemplateTarget) return

    const template = this.ruleTemplateTarget.content.cloneNode(true)
    this.rulesListTarget.appendChild(template)
    this.serialize()
  }

  removeRule(event) {
    const ruleEl = event.target.closest('[data-condition-builder-target="rule"]')
    if (ruleEl) {
      ruleEl.remove()
      this.serialize()
    }
  }

  updateRule() {
    this.serialize()

    // Show/hide value input based on operator
    this.ruleTargets.forEach(rule => {
      const operator = rule.querySelector('[data-condition-builder-role="operator"]')
      const value = rule.querySelector('[data-condition-builder-role="value"]')
      if (operator && value) {
        const noValueOps = ['blank?', 'present?']
        value.style.display = noValueOps.includes(operator.value) ? 'none' : ''
      }
    })
  }

  // ─── Serialization ───────────────────────────────────────

  serialize() {
    const rules = this.ruleTargets.map(ruleEl => {
      const field = ruleEl.querySelector('[data-condition-builder-role="field"]')?.value || ""
      const op = ruleEl.querySelector('[data-condition-builder-role="operator"]')?.value || "=="
      const value = ruleEl.querySelector('[data-condition-builder-role="value"]')?.value || ""

      return { field, op, value }
    }).filter(r => r.field)

    const condition = {
      operator: this.currentOperator || "AND",
      rules
    }

    if (this.hasOutputTarget) {
      this.outputTarget.value = JSON.stringify(condition)
      this.outputTarget.dispatchEvent(new Event('change', { bubbles: true }))
    }

    // Dispatch custom event for parent controllers to listen to
    this.dispatch("changed", { detail: { condition } })
  }

  syncFromOutput() {
    if (!this.hasOutputTarget) return

    try {
      const data = JSON.parse(this.outputTarget.value || '{}')
      this.currentOperator = data.operator || "AND"
    } catch {
      this.currentOperator = "AND"
    }
  }
}
