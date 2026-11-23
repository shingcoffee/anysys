/**
 * Condition row HTML — field rows, record-count panels, AND/OR joins, and
 * WHERE filters. Used by the shared conditions control (steps + elements).
 * Catalog operators supply labels; right operands hide when the operator is unary.
 */

import { escapeHtml } from "utils"
import { conditionOperators } from "flowchart/constants/element_registry"
import { FIELD_INPUT_CLASSES } from "controllers/property_editor/controls/shared"

export const CONDITIONS_CONTROLLER = "property-editor--controls--conditions"

const FALLBACK_OPERATORS = [
  { value: "==", label: "==", unary: false, count: true },
  { value: "!=", label: "!=", unary: false, count: true },
  { value: ">", label: ">", unary: false, count: true },
  { value: ">=", label: ">=", unary: false, count: true },
  { value: "\u003c", label: "\u003c", unary: false, count: true },
  { value: "\u003c=", label: "\u003c=", unary: false, count: true }
]

const ACTION = (name) => `click->${CONDITIONS_CONTROLLER}#${name}`
const CHANGE = (name) => `change->${CONDITIONS_CONTROLLER}#${name}`
const CLICK_SWITCH = ACTION("switchKind")
const CLICK_REMOVE_ROW = ACTION("removeRow")
const CLICK_REMOVE_WHERE = ACTION("removeWhere")
const CLICK_WHERE_TO_SELECT = ACTION("whereFieldToSelect")
const CLICK_ADD_WHERE = ACTION("addWhere")
const CHANGE_OPERATOR = CHANGE("operatorChanged")
const CHANGE_WHERE_FIELD = CHANGE("whereFieldChanged")
const CHANGE_WHERE_OP = CHANGE("whereOperatorChanged")
const CHANGE_ENTITY = CHANGE("entityChanged")

export function catalogOperators() {
  const list = conditionOperators()
  return list.length > 0 ? list : FALLBACK_OPERATORS
}

export function isUnaryOperator(value) {
  const op = catalogOperators().find((item) => item.value === value)
  return Boolean(op?.unary)
}

export function countOperators() {
  return catalogOperators().filter((op) => op.count)
}

function operatorList(selected, { countOnly = false, wordLabels = {} } = {}) {
  const ops = countOnly ? countOperators() : catalogOperators()
  const wanted = String(selected || "")
  const hasMatch = ops.some((op) => op.value === wanted)
  const first = ops[0]?.value || "=="
  const effective = hasMatch ? wanted : (countOnly ? (ops.find((op) => op.value === ">")?.value || first) : first)
  return ops.map((op) => {
    const label = wordLabels[op.value] || op.label || op.value
    const selectedAttr = op.value === effective ? " selected" : ""
    const unaryAttr = op.unary ? ' data-unary="true"' : ""
    return `<option value="${escapeHtml(op.value)}"${unaryAttr}${selectedAttr}>${escapeHtml(label)}</option>`
  }).join("")
}

function autocompleteI18nAttrs(labels = {}) {
  return [
    ["no-variables-available", labels.noVariablesAvailable],
    ["used-in-this-element-label", labels.usedInThisElement],
    ["no-matching-variables-label", labels.noMatchingVariables]
  ].filter(([, value]) => typeof value === "string" && value !== "")
    .map(([name, value]) => ` data-context-autocomplete-${name}-value="${escapeHtml(value)}"`)
    .join("")
}

function varPickButton(title) {
  return `<button type="button"
        tabindex="-1"
        title="${escapeHtml(title || "")}"
        data-action="mousedown->context-autocomplete#keepFocus click->context-autocomplete#picker"
        class="absolute right-0.5 top-1/2 -translate-y-1/2 flex items-center justify-center w-5 h-5 text-xs font-mono font-bold text-slate-400 hover:text-indigo-600 hover:bg-indigo-50 active:bg-indigo-100 active:text-indigo-700 rounded transition-colors cursor-pointer">{x}</button>`
}

function operandInput({ value, placeholder, attr, elementId, stepIndex, labels, listId }) {
  const str = value == null ? "" : String(value)
  const listAttr = listId ? ` list="${escapeHtml(listId)}"` : ""
  if (!elementId) {
    return `<input type="text" ${attr} value="${escapeHtml(str)}" placeholder="${escapeHtml(placeholder || "")}"${listAttr}
              class="${FIELD_INPUT_CLASSES} font-mono">`
  }
  const stepAttr = stepIndex == null ? "" : ` data-context-autocomplete-step-index-value="${escapeHtml(String(stepIndex))}"`
  return `<div class="relative" data-controller="context-autocomplete" data-context-autocomplete-element-id-value="${escapeHtml(elementId)}"${stepAttr}${autocompleteI18nAttrs(labels)}>
    <input type="text" ${attr} data-context-autocomplete-target="input" value="${escapeHtml(str)}"
           placeholder="${escapeHtml(placeholder || "")}"${listAttr}
           class="${FIELD_INPUT_CLASSES} font-mono pl-2 pr-7">
    ${varPickButton(labels.insertVariableTitle)}
  </div>`
}

export function entityAttributeDatalist(id, entityAttributes = []) {
  const options = (entityAttributes || [])
    .map((attr) => {
      const slug = typeof attr === "string" ? attr : (attr.name_slug || attr.name || "")
      return slug ? `ctx.model.${slug}` : ""
    })
    .filter(Boolean)
  if (!id || options.length === 0) return ""
  return `<datalist id="${escapeHtml(id)}">${options.map((value) => `<option value="${escapeHtml(value)}">`).join("")}</datalist>`
}

export function buildJoinSelect(join, labels) {
  const op = join === "OR" ? "OR" : "AND"
  return `<select data-condition-join class="self-start px-2 py-1.5 text-xs border border-slate-200 bg-white rounded-md">
      <option value="AND"${op === "AND" ? " selected" : ""}>${escapeHtml(labels.joinAndLabel)}</option>
      <option value="OR"${op === "OR" ? " selected" : ""}>${escapeHtml(labels.joinOrLabel)}</option>
    </select>`
}

function kindToggle(isQc, labels) {
  const on = "bg-white text-slate-900 shadow-sm ring-1 ring-black/5"
  const off = "text-slate-500 hover:text-slate-700 hover:bg-white/50"
  return `<div data-condition-row-type-toggle role="group" class="inline-flex gap-0.5 p-0.5 bg-slate-100 rounded-md">
      <button type="button" data-action="${CLICK_SWITCH}" data-row-type="field"
              class="px-2 py-0.5 text-xs font-medium rounded transition-all ${isQc ? off : on}">${escapeHtml(labels.fieldTypeLabel)}</button>
      <button type="button" data-action="${CLICK_SWITCH}" data-row-type="query_count"
              class="px-2 py-0.5 text-xs font-medium rounded transition-all ${isQc ? on : off}">${escapeHtml(labels.countTypeLabel)}</button>
    </div>`
}

function removeRowButton(title) {
  return `<button type="button" data-action="${CLICK_REMOVE_ROW}"
              class="p-0.5 text-slate-400 hover:text-red-500 hover:bg-red-50 rounded transition-colors flex-shrink-0"
              title="${escapeHtml(title)}">
      <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true">
        <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
      </svg>
    </button>`
}

export function buildFieldPanel(condition, labels, context = {}, { hidden = false } = {}) {
  const left = condition?.leftOperand
  const operator = condition?.operator || ""
  const right = condition?.rightOperand
  const unary = isUnaryOperator(operator)
  const listId = context.leftListId || ""
  return `<div data-condition-row-field-panel${hidden ? ` class="hidden"` : ""}>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-1.5">
        ${operandInput({
          value: left,
          placeholder: "ctx.field",
          attr: `data-condition-left`,
          elementId: context.elementId,
          stepIndex: context.stepIndex,
          labels,
          listId
        })}
        <select data-condition-op data-action="${CHANGE_OPERATOR}" class="${FIELD_INPUT_CLASSES}">
          ${operatorList(operator, { wordLabels: labels.branchOperatorLabels || {} })}
        </select>
        <div data-condition-right-wrap class="${unary ? "hidden " : ""}sm:col-span-2">
          ${operandInput({
            value: right,
            placeholder: labels.valuePlaceholder,
            attr: `data-condition-right`,
            elementId: context.elementId,
            stepIndex: context.stepIndex,
            labels
          })}
        </div>
      </div>
    </div>`
}

function whereFieldOptions(schema, labels, selected = "") {
  let html = `<option value="">${escapeHtml(labels.selectFieldPlaceholder)}</option>`
  ;(schema || []).forEach((field) => {
    const slug = field.name_slug || field.name
    if (!slug) return
    const htmlType = field.html_type || ""
    const baseLabel = field.name || slug
    const label = htmlType ? `${baseLabel} — ${htmlType}` : baseLabel
    const value = `data.${slug}`
    const selectedAttr = value === selected ? " selected" : ""
    html += `<option value="${escapeHtml(value)}"${selectedAttr}${htmlType ? ` data-col-type="${escapeHtml(htmlType)}"` : ""}>${escapeHtml(label)}</option>`
  })
  html += `<option value="created_at"${selected === "created_at" ? " selected" : ""}>created_at</option>`
  html += `<option value="updated_at"${selected === "updated_at" ? " selected" : ""}>updated_at</option>`
  html += `<optgroup label="${escapeHtml(labels.otherGroupLabel)}"><option value="__manual__">${escapeHtml(labels.enterManuallyLabel)}</option></optgroup>`
  return html
}

export function buildWhereRow({ schema = [], rule = {}, labels, context = {}, removable = false } = {}) {
  const field = rule.field || ""
  const op = rule.op || "=="
  const value = rule.value ?? ""
  const schemaValues = new Set(
    (schema || []).map((item) => `data.${item.name_slug || item.name}`).concat(["created_at", "updated_at", ""])
  )
  const manual = field !== "" && !schemaValues.has(field)
  const unary = isUnaryOperator(op)
  const removeButton = removable ? `
      <button type="button" data-action="${CLICK_REMOVE_WHERE}"
              class="absolute -top-1 -right-1 p-0.5 text-slate-400 hover:text-red-500 bg-white border border-slate-200 rounded-full shadow-sm hover:bg-red-50 transition-colors"
              title="${escapeHtml(labels.removeFilterTitle)}">
        <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>` : ""

  return `<div data-cond-qc-where-row class="relative p-2 bg-white rounded border border-slate-200">
      ${removeButton}
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-2">
        <div>
          <select data-cond-qc-where-field data-action="${CHANGE_WHERE_FIELD}"
                  class="${manual ? "hidden " : ""}${FIELD_INPUT_CLASSES}">
            ${whereFieldOptions(schema, labels, manual ? "" : field)}
          </select>
          <div data-cond-qc-where-field-manual class="${manual ? "flex" : "hidden"} gap-1">
            <input type="text" data-cond-qc-where-field-input value="${manual ? escapeHtml(field) : ""}"
                   placeholder="${escapeHtml(labels.columnNamePlaceholder)}"
                   class="${FIELD_INPUT_CLASSES} font-mono">
            <button type="button" data-action="${CLICK_WHERE_TO_SELECT}"
                    title="${escapeHtml(labels.switchToDropdownTitle)}"
                    class="px-2 py-1 text-xs text-slate-500 hover:text-slate-700 border border-slate-200 rounded hover:bg-slate-50 flex-shrink-0">&#x25B2;</button>
          </div>
        </div>
        <div>
          <select data-cond-qc-where-op data-action="${CHANGE_WHERE_OP}" class="${FIELD_INPUT_CLASSES}">
            ${operatorList(op, { wordLabels: labels.branchOperatorLabels || {} })}
          </select>
        </div>
        <div data-cond-qc-where-value-wrap class="${unary ? "hidden" : ""}">
          ${operandInput({
            value,
            placeholder: labels.valuePlaceholder,
            attr: `data-cond-qc-where-value`,
            elementId: context.elementId,
            stepIndex: context.stepIndex,
            labels
          })}
        </div>
      </div>
    </div>`
}

export function buildQueryCountPanel(condition, labels, context = {}, { hidden = false } = {}) {
  const qc = condition?.kind === "query_count" ? condition : null
  const savedEntityId = qc?.queryConfig?.entityId ? String(qc.queryConfig.entityId) : ""
  const savedEntityName = qc?.queryConfig?.entityName || ""
  const savedRules = qc?.queryConfig?.conditions?.rules || []
  const savedCountOp = qc ? (qc.countOperator || ">") : ">"
  const savedCountValue = qc ? (qc.countValue ?? 0) : 0
  const savedDataAttrs = savedEntityId
    ? ` data-cond-qc-saved-entity-id="${escapeHtml(savedEntityId)}"` +
      ` data-cond-qc-saved-entity-name="${escapeHtml(savedEntityName)}"` +
      ` data-cond-qc-saved-rules="${escapeHtml(JSON.stringify(savedRules))}"`
    : ""
  const savedEntityOption = savedEntityId
    ? `<option value="${escapeHtml(savedEntityId)}" selected>${escapeHtml(savedEntityName)}</option>`
    : ""
  const schema = []
  const whereRows = savedRules.length > 0
    ? savedRules.filter((rule) => rule?.field).map((rule, index) => buildWhereRow({
      schema, rule, labels, context, removable: index > 0
    })).join("")
    : ""

  return `<div data-condition-row-query-panel${savedDataAttrs}${hidden ? ` class="hidden"` : ""}>
      <div class="space-y-2">
        <div>
          <label class="block text-xs font-medium text-slate-500 mb-1">${escapeHtml(labels.entityLabel)}</label>
          <select data-cond-qc-entity data-action="${CHANGE_ENTITY}" class="${FIELD_INPUT_CLASSES}">
            <option value="">${escapeHtml(labels.selectEntityPlaceholder)}</option>
            ${savedEntityOption}
          </select>
        </div>
        <div>
          <label class="block text-xs font-medium text-slate-500 mb-1">${escapeHtml(labels.whereOptionalLabel)}</label>
          <div data-cond-qc-where-rows class="space-y-1.5">${whereRows}</div>
          <button type="button" data-action="${CLICK_ADD_WHERE}"
                  class="mt-1 inline-flex items-center text-xs font-medium text-indigo-600 hover:text-indigo-700">
            <svg class="w-3 h-3 mr-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
            </svg>
            ${escapeHtml(labels.addFilterLabel)}
          </button>
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
          <div>
            <label class="block text-xs font-medium text-slate-500 mb-1">${escapeHtml(labels.countOperatorLabel)}</label>
            <select data-cond-qc-count-op class="${FIELD_INPUT_CLASSES}">
              ${operatorList(savedCountOp, { countOnly: true })}
            </select>
          </div>
          <div>
            <label class="block text-xs font-medium text-slate-500 mb-1">${escapeHtml(labels.countValueLabel)}</label>
            <input type="number" data-cond-qc-count-value value="${escapeHtml(String(savedCountValue))}" min="0"
                   class="${FIELD_INPUT_CLASSES} font-mono" placeholder="0">
          </div>
        </div>
      </div>
    </div>`
}

export function buildConditionRow(condition, labels, context = {}) {
  const isQc = (condition?.kind || "field") === "query_count"
  return `<div data-condition-row data-condition-kind="${isQc ? "query_count" : "field"}" class="p-2 bg-white rounded-md border border-slate-200">
      <div class="flex items-center justify-between gap-2 mb-1.5">
        ${kindToggle(isQc, labels)}
        ${removeRowButton(labels.removeRowTitle)}
      </div>
      ${buildFieldPanel(isQc ? {} : condition, labels, context, { hidden: isQc })}
      ${buildQueryCountPanel(isQc ? condition : null, labels, context, { hidden: !isQc })}
    </div>`
}
