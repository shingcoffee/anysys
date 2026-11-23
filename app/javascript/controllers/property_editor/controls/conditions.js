import { escapeHtml } from "utils"
import { compactLabels, resolveControlLabels } from "controllers/property_editor/controls/shared"
import { customerIdFromPath } from "controllers/property_editor/customer_id"
import { fetchReferenceOptions } from "controllers/property_editor/controls/reference_options"
import {
  CONDITIONS_CONTROLLER,
  buildConditionRow,
  buildJoinSelect,
  buildWhereRow,
  catalogOperators,
  entityAttributeDatalist,
  isUnaryOperator
} from "controllers/property_editor/templates/conditions"

const EMPTY_GROUP = { type: "group", joins: [], conditions: [] }

const DEFAULT_CONDITION_LABELS = {
  fieldTypeLabel: "Field",
  countTypeLabel: "Count",
  entityLabel: "Entity",
  selectEntityPlaceholder: "Select entity...",
  whereOptionalLabel: "Where (optional)",
  addFilterLabel: "Add Filter",
  countOperatorLabel: "Count Operator",
  countValueLabel: "Count Value",
  selectFieldPlaceholder: "Select field...",
  enterManuallyLabel: "enter manually…",
  removeFilterTitle: "Remove filter",
  switchToDropdownTitle: "Switch to dropdown",
  schemaUnavailableLabel: "Schema unavailable — enter field names manually",
  columnNamePlaceholder: "column name",
  couldNotLoadEntitiesLabel: "Could not load entities",
  otherGroupLabel: "Other",
  insertVariableTitle: "Insert variable"
}

function conditionLabelsFromEditor(root = document) {
  const el = root.querySelector?.("[data-controller~='property-editor']")
  if (!el) return {}
  const d = el.dataset
  return compactLabels({
    fieldTypeLabel: d.propertyEditorConditionFieldTypeLabelValue,
    countTypeLabel: d.propertyEditorConditionCountTypeLabelValue,
    entityLabel: d.propertyEditorEntityLabelValue,
    selectEntityPlaceholder: d.propertyEditorSelectEntityPlaceholderValue,
    whereOptionalLabel: d.propertyEditorWhereOptionalLabelValue,
    addFilterLabel: d.propertyEditorAddFilterLabelValue,
    countOperatorLabel: d.propertyEditorCountOperatorLabelValue,
    countValueLabel: d.propertyEditorCountValueLabelValue,
    selectFieldPlaceholder: d.propertyEditorSelectFieldPlaceholderValue,
    enterManuallyLabel: d.propertyEditorEnterManuallyLabelValue,
    removeFilterTitle: d.propertyEditorRemoveFilterTitleValue,
    switchToDropdownTitle: d.propertyEditorSwitchToDropdownTitleValue,
    schemaUnavailableLabel: d.propertyEditorSchemaUnavailableLabelValue,
    columnNamePlaceholder: d.propertyEditorColumnNamePlaceholderValue,
    couldNotLoadEntitiesLabel: d.propertyEditorCouldNotLoadEntitiesLabelValue,
    otherGroupLabel: d.propertyEditorOtherGroupLabelValue,
    insertVariableTitle: d.propertyEditorInsertVariableTitleValue,
    noVariablesAvailable: d.propertyEditorNoVariablesAvailableValue,
    usedInThisElement: d.propertyEditorUsedInThisElementLabelValue,
    noMatchingVariables: d.propertyEditorNoMatchingVariablesLabelValue
  })
}

export function resolveConditionLabels(labels = {}, root = document) {
  const wordLabels = labels.branchOperatorLabels && typeof labels.branchOperatorLabels === "object"
    ? labels.branchOperatorLabels
    : {}
  return {
    ...DEFAULT_CONDITION_LABELS,
    ...resolveControlLabels(labels, root),
    ...conditionLabelsFromEditor(root),
    ...compactLabels(labels),
    branchOperatorLabels: wordLabels
  }
}

export function normalizeGroup(value) {
  if (!value || typeof value !== "object" || value.type !== "group" || !Array.isArray(value.conditions)) {
    return { ...EMPTY_GROUP, conditions: [] }
  }
  return {
    type: "group",
    joins: Array.isArray(value.joins) ? value.joins : [],
    conditions: value.conditions.filter((row) => row && typeof row === "object" && row.type !== "group")
  }
}

function joinOf(el) {
  if (!el?.hasAttribute?.("data-condition-join")) return "AND"
  const raw = el.tagName === "SELECT" ? el.value : el.dataset.conditionJoin
  return raw === "OR" ? "OR" : "AND"
}

function rowKind(row) {
  if (row.dataset.conditionKind === "query_count") return "query_count"
  const panel = row.querySelector("[data-condition-row-query-panel]")
  if (panel && !panel.classList.contains("hidden")) return "query_count"
  return "field"
}

export function collectQueryCountRow(row) {
  const panel = row.querySelector("[data-condition-row-query-panel]")
  const entitySelect = row.querySelector("[data-cond-qc-entity]")
  const liveEntityId = entitySelect?.value || ""
  let entityId = liveEntityId
  let entityName = liveEntityId
    ? (entitySelect?.options[entitySelect.selectedIndex]?.textContent || "")
    : ""

  if (!entityId && panel?.dataset?.condQcSavedEntityId) {
    entityId = panel.dataset.condQcSavedEntityId
    entityName = panel.dataset.condQcSavedEntityName || ""
  }
  if (!entityId) return null

  const liveWhereRows = row.querySelectorAll("[data-cond-qc-where-row]")
  const rules = []
  if (liveWhereRows.length > 0) {
    liveWhereRows.forEach((whereRow) => {
      const manualWrap = whereRow.querySelector("[data-cond-qc-where-field-manual]")
      const manualVisible = manualWrap && !manualWrap.classList.contains("hidden")
      const field = manualVisible
        ? (whereRow.querySelector("[data-cond-qc-where-field-input]")?.value?.trim() || "")
        : (whereRow.querySelector("[data-cond-qc-where-field]")?.value || "")
      const op = whereRow.querySelector("[data-cond-qc-where-op]")?.value || "=="
      const value = whereRow.querySelector("[data-cond-qc-where-value]")?.value?.trim() || ""
      if (field) rules.push({ field, op, value })
    })
  } else if (panel?.dataset?.condQcSavedRules) {
    try {
      const saved = JSON.parse(panel.dataset.condQcSavedRules)
      if (Array.isArray(saved)) saved.forEach((rule) => { if (rule.field) rules.push(rule) })
    } catch (_error) { /* malformed JSON — ignore */ }
  }

  const countOp = row.querySelector("[data-cond-qc-count-op]")?.value || ">"
  const countValue = parseInt(row.querySelector("[data-cond-qc-count-value]")?.value || "0", 10) || 0
  const member = {
    kind: "query_count",
    queryConfig: {
      entityId: parseInt(entityId, 10),
      entityName
    },
    countOperator: countOp,
    countValue
  }
  if (rules.length > 0) {
    member.queryConfig.conditions = { operator: "AND", rules }
  }
  return member
}

function collectFieldRow(row) {
  const leftOperand = row.querySelector("[data-condition-left]")?.value?.trim() || ""
  const operator = row.querySelector("[data-condition-op]")?.value || ""
  const rightWrap = row.querySelector("[data-condition-right-wrap]")
  const rightHidden = rightWrap?.classList.contains("hidden") || isUnaryOperator(operator)
  const rightOperand = rightHidden
    ? ""
    : (row.querySelector("[data-condition-right]")?.value?.trim() || "")
  if (!leftOperand && !rightOperand) return null
  return { kind: "field", leftOperand, operator, rightOperand }
}

export function collectConditions(editor) {
  const rows = [...editor.querySelectorAll("[data-condition-rows] > [data-condition-row], :scope > [data-condition-row]")]
  const liveRows = rows.length > 0 ? rows : [...editor.querySelectorAll("[data-condition-row]")]
  const conditions = []
  const joins = []
  liveRows.forEach((row) => {
    if (row.closest("[data-condition-row-template], template")) return
    const collected = rowKind(row) === "query_count" ? collectQueryCountRow(row) : collectFieldRow(row)
    if (!collected) return
    if (conditions.length > 0) {
      const joinEl = row.previousElementSibling?.hasAttribute("data-condition-join")
        ? row.previousElementSibling
        : null
      joins.push(joinOf(joinEl))
    }
    conditions.push(collected)
  })
  return { type: "group", joins, conditions }
}

export function canvasCustomerId() {
  const el = document.querySelector('[data-controller~="flowchart-canvas"]')
  return el?.getAttribute("data-flowchart-canvas-customer-id-value") || customerIdFromPath()
}

export function entitySchemaUrl(entityId) {
  const customerId = canvasCustomerId()
  if (!customerId || !entityId) return null
  return `/${customerId}/admin/maintenance/entities/${encodeURIComponent(String(entityId))}.json`
}

export async function loadEntityOptions() {
  return fetchReferenceOptions("entities")
}

export function appendEntityLoadError(entitySelect, label) {
  if (!entitySelect || entitySelect.querySelector("option[data-entity-load-error]")) return
  const option = document.createElement("option")
  option.value = ""
  option.disabled = true
  option.setAttribute("data-entity-load-error", "")
  option.textContent = label
  entitySelect.appendChild(option)
}

export function fillEntitySelect(entitySelect, options, preservedValue = "") {
  if (!entitySelect) return
  const kept = preservedValue || entitySelect.value || ""
  options.forEach((opt) => {
    const value = String(opt.value ?? opt.id ?? "")
    if (!value || String(value) === String(kept)) return
    if ([...entitySelect.options].some((item) => item.value === value)) return
    const option = document.createElement("option")
    option.value = value
    option.textContent = opt.label ?? opt.name ?? value
    entitySelect.appendChild(option)
  })
  if (kept) entitySelect.value = kept
}

export function parsePanelSchema(panel) {
  try {
    const parsed = JSON.parse(panel?.dataset?.condQcSchema || "[]")
    return Array.isArray(parsed) ? parsed : []
  } catch (_error) {
    return []
  }
}

export function parseSavedRules(panel) {
  try {
    const parsed = JSON.parse(panel?.dataset?.condQcSavedRules || "[]")
    return Array.isArray(parsed) ? parsed : []
  } catch (_error) {
    return []
  }
}

function valueAttrs(name, value) {
  if (value == null || value === "") return ""
  return ` data-${CONDITIONS_CONTROLLER}-${name}-value="${escapeHtml(String(value))}"`
}

function controllerAttrs(labels, context) {
  return [
    valueAttrs("element-id", context.elementId || ""),
    valueAttrs("step-index", context.stepIndex ?? -1),
    valueAttrs("field-type-label", labels.fieldTypeLabel),
    valueAttrs("count-type-label", labels.countTypeLabel),
    valueAttrs("add-row-label", labels.addRowLabel),
    valueAttrs("remove-row-title", labels.removeRowTitle),
    valueAttrs("join-and-label", labels.joinAndLabel),
    valueAttrs("join-or-label", labels.joinOrLabel),
    valueAttrs("value-placeholder", labels.valuePlaceholder),
    valueAttrs("insert-variable-title", labels.insertVariableTitle),
    valueAttrs("no-variables-available", labels.noVariablesAvailable),
    valueAttrs("used-in-this-element-label", labels.usedInThisElement),
    valueAttrs("no-matching-variables-label", labels.noMatchingVariables),
    valueAttrs("entity-label", labels.entityLabel),
    valueAttrs("select-entity-placeholder", labels.selectEntityPlaceholder),
    valueAttrs("where-optional-label", labels.whereOptionalLabel),
    valueAttrs("add-filter-label", labels.addFilterLabel),
    valueAttrs("count-operator-label", labels.countOperatorLabel),
    valueAttrs("count-value-label", labels.countValueLabel),
    valueAttrs("select-field-placeholder", labels.selectFieldPlaceholder),
    valueAttrs("enter-manually-label", labels.enterManuallyLabel),
    valueAttrs("remove-filter-title", labels.removeFilterTitle),
    valueAttrs("switch-to-dropdown-title", labels.switchToDropdownTitle),
    valueAttrs("schema-unavailable-label", labels.schemaUnavailableLabel),
    valueAttrs("column-name-placeholder", labels.columnNamePlaceholder),
    valueAttrs("could-not-load-entities-label", labels.couldNotLoadEntitiesLabel),
    valueAttrs("other-group-label", labels.otherGroupLabel)
  ].join("")
}

export function emptyFieldCondition() {
  const first = catalogOperators()[0]?.value || "=="
  return { kind: "field", leftOperand: "", operator: first, rightOperand: "" }
}

export function buildConditionsField(field, value, context = {}) {
  const labels = resolveConditionLabels(context.labels)
  const group = normalizeGroup(value)
  const conditions = group.conditions.length > 0 ? group.conditions : [emptyFieldCondition()]
  const joins = group.joins
  const fieldName = field?.name || field?.key || "condition"
  const leftListId = `cond-left-${escapeHtml(fieldName)}`
  const rowContext = {
    elementId: context.elementId,
    stepIndex: context.stepIndex,
    leftListId,
    entityAttributes: context.entityAttributes || []
  }
  let body = ""
  conditions.forEach((condition, index) => {
    if (index > 0) body += buildJoinSelect(joins[index - 1], labels)
    body += buildConditionRow(condition, labels, rowContext)
  })
  const template = buildConditionRow(emptyFieldCondition(), labels, rowContext)
  const whereTemplate = buildWhereRow({ labels, context: rowContext, removable: true })
  return `<div data-conditions-editor data-controller="${CONDITIONS_CONTROLLER}"${controllerAttrs(labels, context)}
               class="flex flex-col gap-1.5 p-2 rounded-md border border-slate-200 bg-slate-50">
      ${entityAttributeDatalist(leftListId, context.entityAttributes)}
      <div data-condition-rows class="flex flex-col gap-1.5">${body}</div>
      <template data-condition-row-template>${template}</template>
      <template data-condition-where-template>${whereTemplate}</template>
      <button type="button" data-action="click->${CONDITIONS_CONTROLLER}#addRow"
              class="mt-1 inline-flex items-center px-2 py-0.5 text-xs font-medium text-indigo-600 hover:text-indigo-700 hover:bg-indigo-50 rounded transition-colors">
        <svg class="w-3 h-3 mr-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
        </svg>
        ${escapeHtml(labels.addRowLabel)}
      </button>
    </div>`
}

export { buildWhereRow, isUnaryOperator }
