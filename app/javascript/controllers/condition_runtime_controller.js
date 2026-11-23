import { Controller } from "@hotwired/stimulus"
import { ConditionEvaluator } from "lib/condition_evaluator"
import { FormulaEngine } from "lib/formula_engine"

/**
 * Condition Runtime Controller
 *
 * Evaluates conditional logic and calculations at form runtime.
 * Attached to the form wrapper element.
 */
export default class extends Controller {
  static values = {
    rules: { type: Array, default: [] },
    calculations: { type: Array, default: [] }
  }

  connect() {
    this.fieldElements = new Map()
    this.cacheFieldElements()
    this.bindFieldListeners()
    this.evaluateAll()
  }

  disconnect() {
    this.unbindFieldListeners()
  }

  cacheFieldElements() {
    this.element.querySelectorAll('[data-field-id]').forEach(el => {
      this.fieldElements.set(el.dataset.fieldId, el)
    })
  }

  bindFieldListeners() {
    this.fieldChangeHandler = this.debounce((_event) => {
      this.evaluateAll()
    }, 100)

    this.element.addEventListener('input', this.fieldChangeHandler)
    this.element.addEventListener('change', this.fieldChangeHandler)
  }

  unbindFieldListeners() {
    if (this.fieldChangeHandler) {
      this.element.removeEventListener('input', this.fieldChangeHandler)
      this.element.removeEventListener('change', this.fieldChangeHandler)
    }
  }

  evaluateAll() {
    const values = this.collectFieldValues()
    this.applyRules(values)
    this.applyCalculations(values)
  }

  collectFieldValues() {
    const values = {}

    this.fieldElements.forEach((wrapper, fieldId) => {
      const input = wrapper.querySelector('input, select, textarea')
      if (input) {
        if (input.type === 'checkbox') {
          values[fieldId] = input.checked
        } else if (input.type === 'radio') {
          const checked = wrapper.querySelector('input[type="radio"]:checked')
          values[fieldId] = checked?.value ?? null
        } else {
          values[fieldId] = input.value
        }
      }
    })

    return values
  }

  applyRules(values) {
    const evaluator = new ConditionEvaluator(values)

    this.rulesValue.forEach(rule => {
      if (!rule.enabled) return

      const matched = evaluator.evaluate(rule.conditions)

      rule.actions.forEach(action => {
        this.executeAction(action, matched)
      })
    })
  }

  executeAction(action, shouldApply) {
    const wrapper = this.fieldElements.get(action.target_id)
    if (!wrapper) return

    switch (action.type) {
      case 'show_field':
        wrapper.classList.toggle('hidden', !shouldApply)
        wrapper.setAttribute('aria-hidden', !shouldApply)
        break

      case 'hide_field':
        wrapper.classList.toggle('hidden', shouldApply)
        wrapper.setAttribute('aria-hidden', shouldApply)
        break

      case 'enable_field': {
        const input = wrapper.querySelector('input, select, textarea')
        if (input) {
          input.disabled = !shouldApply
          wrapper.classList.toggle('field-disabled', !shouldApply)
        }
        break
      }

      case 'disable_field': {
        const input = wrapper.querySelector('input, select, textarea')
        if (input) {
          input.disabled = shouldApply
          wrapper.classList.toggle('field-disabled', shouldApply)
        }
        break
      }

      case 'set_required': {
        const input = wrapper.querySelector('input, select, textarea')
        if (!input) break
        if (input.dataset.originalRequired === undefined) {
          input.dataset.originalRequired = input.required ? 'true' : 'false'
        }
        if (shouldApply) {
          input.required = !!action.value
          input.setAttribute('aria-required', String(!!action.value))
        } else {
          const orig = input.dataset.originalRequired === 'true'
          input.required = orig
          if (orig) input.setAttribute('aria-required', 'true')
          else input.removeAttribute('aria-required')
        }
        break
      }

      case 'set_value': {
        const input = wrapper.querySelector('input, select, textarea')
        if (input && shouldApply && input.value !== String(action.value ?? '')) {
          input.value = action.value
          input.dispatchEvent(new Event('change', { bubbles: true }))
        }
        break
      }
    }
  }

  applyCalculations(values) {
    const engine = new FormulaEngine(values)

    this.calculationsValue.forEach(calc => {
      const result = engine.evaluate(calc.formula)
      const wrapper = this.fieldElements.get(calc.target_field_id)

      if (wrapper) {
        const input = wrapper.querySelector('input, select, textarea')
        if (input && result !== null) {
          let displayValue = result
          const fmt = calc.format || {}
          if (fmt.type === 'currency' || fmt.type === 'number') {
            displayValue = Number(result).toFixed(fmt.decimals ?? 2)
          } else if (fmt.type === 'percent') {
            displayValue = `${(Number(result) * 100).toFixed(fmt.decimals ?? 0)}%`
          }
          if (fmt.prefix) displayValue = `${fmt.prefix}${displayValue}`
          if (fmt.suffix) displayValue = `${displayValue}${fmt.suffix}`
          input.value = displayValue
        }
      }
    })
  }

  debounce(func, wait) {
    let timeout
    return (...args) => {
      clearTimeout(timeout)
      timeout = setTimeout(() => func.apply(this, args), wait)
    }
  }
}
