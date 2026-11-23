// app/javascript/controllers/rule_builder_controller.js
import { Controller } from "@hotwired/stimulus"
import { ConditionEvaluator } from "lib/condition_evaluator"

// Full operator label set (matches comp_page_builder.operators in the locale
// files) used both to narrow the operator <select> for a chosen field type and
// as the default set offered on a freshly added condition item.
const OPERATOR_LABELS = {
  equals: "Equals", not_equals: "Not equals", contains: "Contains", not_contains: "Does not contain",
  starts_with: "Starts with", ends_with: "Ends with", greater_than: "Greater than",
  less_than: "Less than", greater_or_equal: "Greater or equal", less_or_equal: "Less or equal",
  between: "Between", is_empty: "Is empty", is_not_empty: "Is not empty",
  is_selected: "Is selected", is_not_selected: "Is not selected", matches_regex: "Matches pattern"
}

// Default operator set offered on a freshly added condition item, before
// onConditionFieldChange narrows it to the chosen field's type.
const DEFAULT_OPERATOR_KEYS = [
  "equals", "not_equals", "contains", "not_contains", "starts_with",
  "ends_with", "matches_regex", "is_empty", "is_not_empty"
]

// Action-type labels (matches comp_page_builder.rule_editor.action_types).
const ACTION_TYPE_LABELS = {
  show_field: "Show field", hide_field: "Hide field", enable_field: "Enable field",
  disable_field: "Disable field", set_required: "Set required", set_value: "Set value",
  show_page: "Show page", hide_page: "Hide page", skip_to_page: "Skip to page"
}

// (value, target, hasValue) metadata for the action-type <select> — labels come
// from actionTypeLabelsValue so translations apply to dynamically built rows.
const ACTION_TYPE_META = [
  ["show_field", "field", false],
  ["hide_field", "field", false],
  ["enable_field", "field", false],
  ["disable_field", "field", false],
  ["set_required", "field", true],
  ["set_value", "field", true],
  ["show_page", "page", false],
  ["hide_page", "page", false],
  ["skip_to_page", "page", false]
]

export default class extends Controller {
  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text == null ? "" : String(text)
    return div.innerHTML
  }

  static targets = [
    "testToggle", "testPanel", "actionResult",
    "conditionsLogic", "conditionGroups", "ruleActions",
    "ruleName", "sampleInputs"
  ]
  static values = {
    fields: Array, actionFields: Array, pages: Array, rule: Object,

    // ── i18n seam: English defaults keep JS specs green without any
    // data-*-value attribute; the mounting component
    // (rule_editor_component.html.erb) supplies translated strings via
    // data-rule-builder-<name>-value="<%= t(...) %>". ──
    selectPlaceholder: { type: String, default: "Select…" },
    selectPageOption: { type: String, default: "Select page…" },
    selectFieldOption: { type: String, default: "Select field…" },
    samplePlaceholder: { type: String, default: "sample value" },
    minPlaceholder: { type: String, default: "Min" },
    maxPlaceholder: { type: String, default: "Max" },
    valuePlaceholder: { type: String, default: "Value" },
    allAndLabel: { type: String, default: "All (AND)" },
    anyOrLabel: { type: String, default: "Any (OR)" },
    addConditionLabel: { type: String, default: "+ Add Condition" },
    emptyGroupHint: { type: String, default: 'Click "+ Add Condition" below' },
    testFiresLabel: { type: String, default: "fires" },
    testSkippedLabel: { type: String, default: "skipped" },
    operatorLabels: { type: Object, default: { ...OPERATOR_LABELS } },
    actionTypeLabels: { type: Object, default: { ...ACTION_TYPE_LABELS } }
  }

  // Action targets may include layout elements (you can show/hide a section);
  // condition fields (fieldsValue) are value-bearing only. Fall back to
  // fieldsValue if action fields weren't provided.
  get actionFields() {
    return this.actionFieldsValue.length ? this.actionFieldsValue : this.fieldsValue
  }

  // -----------------------------------------------------------------------
  // Hydration — rebuild condition groups/items and actions from a saved rule.
  // The editor is cloned from a template rendered empty (rule: nil), so when
  // editing an existing rule the manager passes the rule via rule-value and we
  // reconstruct the DOM here. Without this, editing a rule loses its data.
  // -----------------------------------------------------------------------

  connect() {
    if (this._hydrated) return
    if (this.hasRuleValue && Object.keys(this.ruleValue).length > 0) {
      this._hydrated = true
      this.hydrate(this.ruleValue)
    }
  }

  hydrate(rule) {
    if (this.hasRuleNameTarget && rule.name != null) this.ruleNameTarget.value = rule.name

    const conditions = rule.conditions || {}
    if (this.hasConditionsLogicTarget && conditions.logic) this.conditionsLogicTarget.value = conditions.logic

    const groups = conditions.groups || []
    if (this.hasConditionGroupsTarget && groups.length) {
      this.conditionGroupsTarget.innerHTML = ""
      groups.forEach(group => {
        this.addConditionGroup()
        const gi = this.conditionGroupsTarget.querySelectorAll("[data-condition-group]").length - 1
        const groupEl = this.element.querySelector(`[data-condition-group="${gi}"]`)
        const groupLogic = groupEl?.querySelector(`[data-group-logic="${gi}"]`)
        if (groupLogic && group.logic) groupLogic.value = group.logic

        ;(group.items || []).forEach(item => {
          this.addConditionItem({ currentTarget: { dataset: { groupIndex: String(gi) } } })
          const itemsContainer = this.element.querySelector(`[data-condition-items="${gi}"]`)
          const itemEls = itemsContainer.querySelectorAll("[data-condition-item]")
          const itemEl = itemEls[itemEls.length - 1]
          const key = itemEl.dataset.conditionItem

          const fieldEl = itemEl.querySelector(`[data-condition-field="${key}"]`)
          if (fieldEl && item.field_id) {
            fieldEl.value = item.field_id
            this.onConditionFieldChange({ currentTarget: fieldEl })
          }
          const opEl = itemEl.querySelector(`[data-condition-operator="${key}"]`)
          if (opEl && item.operator) {
            opEl.value = item.operator
            this.onConditionOperatorChange({ currentTarget: opEl })
          }
          // Value editor was (re)built by the field/operator changes above; set values now.
          const valEl = itemEl.querySelector(`[data-condition-value="${key}"]`)
          const valMaxEl = itemEl.querySelector(`[data-condition-value-max="${key}"]`)
          if (Array.isArray(item.value)) {
            if (valEl) valEl.value = item.value[0] ?? ""
            if (valMaxEl) valMaxEl.value = item.value[1] ?? ""
          } else if (valEl && item.value != null) {
            valEl.value = item.value
          }
        })
      })
    }

    const actions = rule.actions || []
    if (this.hasRuleActionsTarget && actions.length) {
      this.ruleActionsTarget.innerHTML = ""
      actions.forEach(action => {
        this.addAction({ currentTarget: {} })
        const actionEls = this.ruleActionsTarget.querySelectorAll("[data-action-item]")
        const actionEl = actionEls[actionEls.length - 1]
        const ai = actionEl.dataset.actionItem

        const typeEl = actionEl.querySelector(`[data-action-type="${ai}"]`)
        if (typeEl && action.type) {
          typeEl.value = action.type
          this.onActionTypeChange({ currentTarget: typeEl })
        }
        const targetEl = actionEl.querySelector(`[data-action-target="${ai}"]`)
        if (targetEl && action.target_id) targetEl.value = action.target_id
        const valueEl = actionEl.querySelector(`[data-action-value="${ai}"]`)
        if (valueEl && action.value != null) valueEl.value = action.value
      })
    }
  }

  // Maps raw field property types (integer/float/string/array/…) to the
  // semantic buckets used for operators + value editors.
  normalizeType(type) {
    const t = (type || "").toString().toLowerCase()
    if (["integer", "float", "decimal", "number", "currency", "range", "rating"].includes(t)) return "number"
    if (["date", "datetime", "datetime-local", "time", "month", "week"].includes(t)) return "date"
    if (["select", "multi-select", "array"].includes(t)) return "select"
    if (t === "radio") return "radio"
    if (["boolean", "checkbox", "switch"].includes(t)) return "boolean"
    return "default"
  }

  // -----------------------------------------------------------------------
  // Test mode
  // -----------------------------------------------------------------------

  toggleTest() {
    const isOn = this.testToggleTarget.checked
    this.testPanelTarget.classList.toggle("hidden", !isOn)
    if (isOn) {
      this.buildSampleInputs()
      this.runTest()
    }
  }

  buildSampleInputs() {
    if (!this.hasSampleInputsTarget) return
    const rule = this.getRule()
    const referencedFieldIds = new Set()
    ;(rule.conditions?.groups || []).forEach(group => {
      ;(group.items || []).forEach(item => {
        if (item.field_id) referencedFieldIds.add(item.field_id)
      })
    })

    this.sampleInputsTarget.innerHTML = ""
    referencedFieldIds.forEach(fieldId => {
      const field = this.fieldsValue.find(f => f.id === fieldId)
      const label = field?.label || fieldId
      const div = document.createElement("div")
      div.className = "flex items-center gap-2"
      const labelEl = document.createElement("label")
      labelEl.className = "text-xs text-gray-600 w-24 truncate"
      labelEl.title = label
      labelEl.textContent = label
      const input = document.createElement("input")
      input.type = "text"
      input.dataset.sampleField = fieldId
      input.placeholder = this.samplePlaceholderValue
      input.className = "flex-1 text-xs border border-gray-200 rounded px-2 py-1 focus:ring-1 focus:ring-indigo-500"
      input.dataset.action = "input->rule-builder#runTest"
      div.appendChild(labelEl)
      div.appendChild(input)
      this.sampleInputsTarget.appendChild(div)
    })
  }

  runTest() {
    const rule = this.getRule()
    const values = this.collectSampleValues()
    let matched = false
    try {
      matched = new ConditionEvaluator(values).evaluate(rule.conditions)
    } catch (_e) {
      // ignore eval errors in test mode
    }
    this.actionResultTargets.forEach(el => {
      el.textContent = matched ? `✓ ${this.testFiresLabelValue}` : `✗ ${this.testSkippedLabelValue}`
      el.className = matched ? "text-green-600 text-xs" : "text-gray-400 text-xs"
    })
  }

  // -----------------------------------------------------------------------
  // getRule — serialises the entire rule from DOM
  // -----------------------------------------------------------------------

  getRule() {
    const ruleId = this.element.dataset.ruleId || null
    const name = this.hasRuleNameTarget ? this.ruleNameTarget.value : ""
    const conditions = this.collectConditions()
    const actions = this.collectActions()
    return { id: ruleId || undefined, name, enabled: true, conditions, actions }
  }

  collectConditions() {
    const logic = this.hasConditionsLogicTarget ? this.conditionsLogicTarget.value : "all"
    const groups = []

    this.element.querySelectorAll("[data-condition-group]").forEach((groupEl, groupIndex) => {
      const groupLogicEl = groupEl.querySelector(`[data-group-logic="${groupIndex}"]`)
      const groupLogic = groupLogicEl?.value || "all"
      const items = []

      groupEl.querySelectorAll("[data-condition-item]").forEach(itemEl => {
        const key = itemEl.dataset.conditionItem
        const fieldEl = itemEl.querySelector(`[data-condition-field="${key}"]`)
        const operatorEl = itemEl.querySelector(`[data-condition-operator="${key}"]`)
        const valueEl = itemEl.querySelector(`[data-condition-value="${key}"]`)
        const valueMaxEl = itemEl.querySelector(`[data-condition-value-max="${key}"]`)

        if (fieldEl?.value) {
          let value
          if (valueMaxEl && valueEl) {
            value = [this.parseValue(valueEl.value), this.parseValue(valueMaxEl.value)]
          } else {
            value = this.parseValue(valueEl?.value || "")
          }
          items.push({
            field_id: fieldEl.value,
            operator: operatorEl?.value || "equals",
            value
          })
        }
      })

      if (items.length > 0) {
        groups.push({ logic: groupLogic, items })
      }
    })

    return { logic, groups }
  }

  collectActions() {
    const actions = []
    this.element.querySelectorAll("[data-action-item]").forEach((actionEl, actionIndex) => {
      const typeEl = actionEl.querySelector(`[data-action-type="${actionIndex}"]`)
      const targetEl = actionEl.querySelector(`[data-action-target="${actionIndex}"]`)
      const valueEl = actionEl.querySelector(`[data-action-value="${actionIndex}"]`)

      if (typeEl?.value && targetEl?.value) {
        const action = { type: typeEl.value, target_id: targetEl.value }
        if (valueEl) action.value = valueEl.value
        actions.push(action)
      }
    })
    return actions
  }

  collectSampleValues() {
    const values = {}
    this.element.querySelectorAll("[data-sample-field]").forEach(input => {
      values[input.dataset.sampleField] = this.parseValue(input.value)
    })
    return values
  }

  parseValue(value) {
    if (value === "true") return true
    if (value === "false") return false
    const num = parseFloat(value)
    if (!isNaN(num) && value.trim() === num.toString()) return num
    return value
  }

  // -----------------------------------------------------------------------
  // onConditionFieldChange — re-render operator + value editor for new type
  // -----------------------------------------------------------------------

  onConditionFieldChange(event) {
    const select = event.currentTarget
    const key = select.dataset.conditionField
    const fieldId = select.value
    const field = this.fieldsValue.find(f => f.id === fieldId)
    const fieldType = this.normalizeType(field?.type)

    const OPERATORS_BY_TYPE = {
      "number"  : ["equals","not_equals","greater_than","less_than","greater_or_equal","less_or_equal","between","is_empty","is_not_empty"],
      "date"    : ["equals","not_equals","greater_than","less_than","between","is_empty","is_not_empty"],
      "select"  : ["is_selected","is_not_selected","equals","not_equals","is_empty","is_not_empty"],
      "radio"   : ["is_selected","is_not_selected","equals","not_equals","is_empty","is_not_empty"],
      "boolean" : ["is_selected","is_not_selected"],
      "default" : ["equals","not_equals","contains","not_contains","starts_with","ends_with","matches_regex","is_empty","is_not_empty"]
    }

    const ops = OPERATORS_BY_TYPE[fieldType]
    const rowEl = this.element.querySelector(`[data-condition-item="${key}"]`)
    if (!rowEl) return

    // Update operator list
    const operatorEl = rowEl.querySelector(`[data-condition-operator="${key}"]`)
    if (operatorEl) {
      operatorEl.innerHTML = ops.map(op => `<option value="${op}">${this.operatorLabelsValue[op]}</option>`).join("")
    }

    // Render the value editor that matches the (new) default operator + field type
    const defaultOp = ops[0]
    this.replaceValueEditor(rowEl, key, this.valueEditorKind(defaultOp, field), field)
  }

  // Mirrors PageBuilder::ConditionRowComponent#value_editor_kind so dynamically
  // added conditions get the same contextual editors as server-rendered ones.
  valueEditorKind(operator, field) {
    const NO_VALUE = ["is_empty", "is_not_empty", "is_selected", "is_not_selected"]
    if (NO_VALUE.includes(operator)) return "none"
    switch (this.normalizeType(field?.type)) {
      case "select":
      case "radio":   return "select"
      case "boolean": return "boolean"
      case "number":  return operator === "between" ? "number_range" : "number"
      case "date":    return operator === "between" ? "date_range" : "date"
      default:        return "text"
    }
  }

  replaceValueEditor(rowEl, key, kind, field) {
    // Remove old value editors
    rowEl.querySelectorAll(`[data-condition-value="${key}"], [data-condition-value-max="${key}"]`).forEach(el => el.remove())

    const removeBtn = rowEl.querySelector('[data-action*="removeConditionItem"]')
    const insert = (el) => removeBtn ? rowEl.insertBefore(el, removeBtn) : rowEl.appendChild(el)
    const baseCls = "flex-1 min-w-[100px] text-sm border border-gray-200 rounded px-2 py-1"

    if (kind === "none") return

    if (kind === "select") {
      const select = document.createElement("select")
      select.className = baseCls
      select.dataset.conditionValue = key
      const blank = document.createElement("option")
      blank.value = ""; blank.textContent = this.selectPlaceholderValue
      select.appendChild(blank)
      ;(field?.options || []).forEach(opt => {
        const o = document.createElement("option")
        o.value = (opt && typeof opt === "object") ? opt.value : opt
        o.textContent = (opt && typeof opt === "object") ? (opt.label || opt.value) : opt
        select.appendChild(o)
      })
      insert(select)
      return
    }

    if (kind === "boolean") {
      const select = document.createElement("select")
      select.className = "text-sm border border-gray-200 rounded px-2 py-1"
      select.dataset.conditionValue = key
      ;[["true", "True"], ["false", "False"]].forEach(([v, l]) => {
        const o = document.createElement("option")
        o.value = v; o.textContent = l
        select.appendChild(o)
      })
      insert(select)
      return
    }

    if (kind === "number_range" || kind === "date_range") {
      const type = kind === "number_range" ? "number" : "date"
      const min = document.createElement("input")
      min.type = type; min.className = "w-24 text-sm border border-gray-200 rounded px-2 py-1"
      min.placeholder = this.minPlaceholderValue; min.dataset.conditionValue = key
      const sep = document.createElement("span")
      sep.className = "text-xs text-gray-400"; sep.textContent = "–"
      const max = document.createElement("input")
      max.type = type; max.className = "w-24 text-sm border border-gray-200 rounded px-2 py-1"
      max.placeholder = this.maxPlaceholderValue; max.dataset.conditionValueMax = key
      insert(min); insert(sep); insert(max)
      return
    }

    // number / date / text
    const input = document.createElement("input")
    input.type = kind === "number" ? "number" : (kind === "date" ? "date" : "text")
    input.className = baseCls
    input.placeholder = this.valuePlaceholderValue
    input.dataset.conditionValue = key
    insert(input)
  }

  onConditionOperatorChange(event) {
    const operatorEl = event.currentTarget
    const key = operatorEl.dataset.conditionOperator
    const rowEl = this.element.querySelector(`[data-condition-item="${key}"]`)
    if (!rowEl) return
    const fieldEl = rowEl.querySelector(`[data-condition-field="${key}"]`)
    const field = this.fieldsValue.find(f => f.id === fieldEl?.value)
    this.replaceValueEditor(rowEl, key, this.valueEditorKind(operatorEl.value, field), field)
  }

  // -----------------------------------------------------------------------
  // onActionTypeChange — swap target options + show/hide value editor
  // -----------------------------------------------------------------------

  onActionTypeChange(event) {
    const select = event.currentTarget
    const actionIndex = select.dataset.actionType
    const selectedOption = select.selectedOptions[0]
    const targetType = selectedOption?.dataset?.target
    const hasValue = selectedOption?.dataset?.hasValue === "true"
    const rowEl = this.element.querySelector(`[data-action-item="${actionIndex}"]`)
    if (!rowEl) return

    const targetEl = rowEl.querySelector(`[data-action-target="${actionIndex}"]`)
    if (targetEl) {
      targetEl.innerHTML = ""
      const blankOpt = document.createElement("option")
      blankOpt.value = ""
      if (targetType === "page") {
        blankOpt.textContent = this.selectPageOptionValue
        targetEl.appendChild(blankOpt)
        this.pagesValue.forEach(p => {
          const opt = document.createElement("option")
          opt.value = p.id
          opt.textContent = p.name || p.id
          targetEl.appendChild(opt)
        })
      } else {
        blankOpt.textContent = this.selectFieldOptionValue
        targetEl.appendChild(blankOpt)
        this.actionFields.forEach(f => {
          const opt = document.createElement("option")
          opt.value = f.id
          opt.textContent = f.label || f.id
          targetEl.appendChild(opt)
        })
      }
    }

    // Show/hide value input
    let valueEl = rowEl.querySelector(`[data-action-value="${actionIndex}"]`)
    if (hasValue && !valueEl) {
      valueEl = document.createElement("input")
      valueEl.type = "text"
      valueEl.className = "w-24 text-sm border border-gray-200 rounded px-2 py-1"
      valueEl.placeholder = this.valuePlaceholderValue
      valueEl.dataset.actionValue = actionIndex
      const removeBtn = rowEl.querySelector('[data-action*="removeAction"]')
      if (removeBtn) rowEl.insertBefore(valueEl, removeBtn)
      else rowEl.appendChild(valueEl)
    } else if (!hasValue && valueEl) {
      valueEl.remove()
    }
  }

  // -----------------------------------------------------------------------
  // Condition group / item management (called from page-builder controller
  // which still owns add/remove actions — we just re-render contextually)
  // -----------------------------------------------------------------------

  addConditionGroup(_event) {
    // Delegate up to page-builder which owns the condition group management
    // (kept for cases where rule-builder is the sole controller)
    const groupsContainer = this.hasConditionGroupsTarget ? this.conditionGroupsTarget : null
    if (!groupsContainer) return
    const groupIndex = groupsContainer.querySelectorAll("[data-condition-group]").length
    const div = document.createElement("div")
    div.className = "p-3 bg-gray-50 rounded-lg border border-gray-200"
    div.dataset.conditionGroup = groupIndex
    div.innerHTML = `
      <div class="flex items-center justify-between mb-2">
        <select class="text-xs border border-gray-200 rounded px-2 py-1" data-group-logic="${groupIndex}">
          <option value="all">${this.allAndLabelValue}</option>
          <option value="any">${this.anyOrLabelValue}</option>
        </select>
        <button type="button" class="p-1 text-gray-400 hover:text-red-500"
                data-action="click->rule-builder#removeConditionGroup" data-group-index="${groupIndex}">
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
      <div class="space-y-2" data-condition-items="${groupIndex}">
        <div class="text-xs text-gray-400 text-center py-1">${this.emptyGroupHintValue}</div>
      </div>
      <button type="button" class="mt-2 w-full px-2 py-1 text-xs text-gray-500 border border-dashed border-gray-300 rounded hover:border-indigo-400 hover:text-indigo-600 transition-colors"
              data-action="click->rule-builder#addConditionItem" data-group-index="${groupIndex}">
        ${this.addConditionLabelValue}
      </button>
    `
    groupsContainer.appendChild(div)
  }

  removeConditionGroup(event) {
    const groupIndex = event.currentTarget.dataset.groupIndex
    const groupEl = this.element.querySelector(`[data-condition-group="${groupIndex}"]`)
    if (groupEl) groupEl.remove()
  }

  addConditionItem(event) {
    const groupIndex = event.currentTarget.dataset.groupIndex
    const itemsContainer = this.element.querySelector(`[data-condition-items="${groupIndex}"]`)
    if (!itemsContainer) return

    // Remove empty placeholder if present
    const placeholder = itemsContainer.querySelector(".text-xs.text-gray-400")
    if (placeholder) placeholder.remove()

    const existingCount = itemsContainer.querySelectorAll("[data-condition-item]").length
    const key = `${groupIndex}-${existingCount}`
    const div = document.createElement("div")
    div.className = "flex flex-wrap items-center gap-2"
    div.dataset.conditionItem = key

    // Field select
    const fieldSelect = document.createElement("select")
    fieldSelect.className = "flex-1 min-w-[120px] text-sm border border-gray-200 rounded px-2 py-1"
    fieldSelect.dataset.conditionField = key
    fieldSelect.dataset.action = "change->rule-builder#onConditionFieldChange"
    const blankFieldOpt = document.createElement("option")
    blankFieldOpt.value = ""
    blankFieldOpt.textContent = this.selectFieldOptionValue
    fieldSelect.appendChild(blankFieldOpt)
    this.fieldsValue.forEach(f => {
      const opt = document.createElement("option")
      opt.value = f.id
      opt.dataset.fieldType = f.type || ""
      opt.textContent = f.label || f.id
      fieldSelect.appendChild(opt)
    })

    // Operator select — full default operator set; onConditionFieldChange will
    // narrow it to the chosen field's type, and onConditionOperatorChange swaps
    // the value editor when the operator changes.
    const operatorSelect = document.createElement("select")
    operatorSelect.className = "text-sm border border-gray-200 rounded px-2 py-1"
    operatorSelect.dataset.conditionOperator = key
    operatorSelect.dataset.action = "change->rule-builder#onConditionOperatorChange"
    DEFAULT_OPERATOR_KEYS.forEach(val => {
      const opt = document.createElement("option")
      opt.value = val
      opt.textContent = this.operatorLabelsValue[val]
      operatorSelect.appendChild(opt)
    })

    // Value input
    const valueInput = document.createElement("input")
    valueInput.type = "text"
    valueInput.className = "flex-1 min-w-[100px] text-sm border border-gray-200 rounded px-2 py-1"
    valueInput.placeholder = this.valuePlaceholderValue
    valueInput.dataset.conditionValue = key

    // Remove button — safe static SVG markup (no user data)
    const removeBtn = document.createElement("button")
    removeBtn.type = "button"
    removeBtn.className = "p-1 text-gray-400 hover:text-red-500"
    removeBtn.dataset.action = "click->rule-builder#removeConditionItem"
    removeBtn.dataset.groupIndex = groupIndex
    removeBtn.dataset.itemIndex = existingCount
    removeBtn.innerHTML = `<svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>`

    div.appendChild(fieldSelect)
    div.appendChild(operatorSelect)
    div.appendChild(valueInput)
    div.appendChild(removeBtn)
    itemsContainer.appendChild(div)
  }

  removeConditionItem(event) {
    const groupIndex = event.currentTarget.dataset.groupIndex
    const itemIndex = event.currentTarget.dataset.itemIndex
    const key = `${groupIndex}-${itemIndex}`
    const itemEl = this.element.querySelector(`[data-condition-item="${key}"]`)
    if (itemEl) itemEl.remove()
  }

  addAction(_event) {
    const actionsContainer = this.hasRuleActionsTarget ? this.ruleActionsTarget : null
    if (!actionsContainer) return

    // Remove empty placeholder
    const placeholder = actionsContainer.querySelector(".text-sm.text-gray-500.text-center")
    if (placeholder) placeholder.remove()

    const actionIndex = actionsContainer.querySelectorAll("[data-action-item]").length

    const div = document.createElement("div")
    div.className = "flex flex-wrap items-center gap-2 p-2 bg-gray-50 rounded-lg"
    div.dataset.actionItem = actionIndex

    // Action type select — static values only, no user data
    const typeSelect = document.createElement("select")
    typeSelect.className = "text-sm border border-gray-200 rounded px-2 py-1"
    typeSelect.dataset.actionType = actionIndex
    typeSelect.dataset.action = "change->rule-builder#onActionTypeChange"
    ACTION_TYPE_META.forEach(([val, target, hasValue]) => {
      const opt = document.createElement("option")
      opt.value = val
      opt.textContent = this.actionTypeLabelsValue[val]
      opt.dataset.target = target
      if (hasValue) opt.dataset.hasValue = "true"
      typeSelect.appendChild(opt)
    })

    // Target select — initially populated with fields (user data escaped via textContent)
    const targetSelect = document.createElement("select")
    targetSelect.className = "flex-1 text-sm border border-gray-200 rounded px-2 py-1"
    targetSelect.dataset.actionTarget = actionIndex
    const blankOpt = document.createElement("option")
    blankOpt.value = ""
    blankOpt.textContent = this.selectFieldOptionValue
    targetSelect.appendChild(blankOpt)
    this.actionFields.forEach(f => {
      const opt = document.createElement("option")
      opt.value = f.id
      opt.textContent = f.label || f.id
      targetSelect.appendChild(opt)
    })

    // Action result badge (Stimulus target)
    const resultSpan = document.createElement("span")
    resultSpan.dataset.ruleBuilderTarget = "actionResult"
    resultSpan.className = "text-xs text-gray-400"

    // Remove button — static SVG, no user data
    const removeBtn = document.createElement("button")
    removeBtn.type = "button"
    removeBtn.className = "p-1 text-gray-400 hover:text-red-500"
    removeBtn.dataset.action = "click->rule-builder#removeAction"
    removeBtn.dataset.actionIndex = actionIndex
    removeBtn.innerHTML = `<svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>`

    div.appendChild(typeSelect)
    div.appendChild(targetSelect)
    div.appendChild(resultSpan)
    div.appendChild(removeBtn)
    actionsContainer.appendChild(div)
  }

  removeAction(event) {
    const actionIndex = event.currentTarget.dataset.actionIndex
    const actionEl = this.element.querySelector(`[data-action-item="${actionIndex}"]`)
    if (actionEl) actionEl.remove()
  }
}
