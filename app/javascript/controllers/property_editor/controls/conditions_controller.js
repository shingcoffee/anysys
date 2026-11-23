import { Controller } from "@hotwired/stimulus"
import { escapeHtml } from "utils"
import {
  appendEntityLoadError,
  collectConditions,
  emptyFieldCondition,
  entitySchemaUrl,
  fillEntitySelect,
  loadEntityOptions,
  parsePanelSchema,
  parseSavedRules,
  resolveConditionLabels
} from "controllers/property_editor/controls/conditions"
import {
  buildJoinSelect,
  buildWhereRow,
  isUnaryOperator
} from "controllers/property_editor/templates/conditions"
import { upsertTypeChip, wireSoftTypeValidation } from "controllers/property_editor/templates/type_validation"

const TOGGLE_ON = ["bg-white", "text-slate-900", "shadow-sm", "ring-1", "ring-black/5"]
const TOGGLE_OFF = ["text-slate-500", "hover:text-slate-700", "hover:bg-white/50"]

function detach(node) {
  node?.parentNode?.removeChild(node)
}

export default class extends Controller {
  static values = {
    elementId: { type: String, default: "" },
    stepIndex: { type: Number, default: -1 },
    fieldTypeLabel: { type: String, default: "Field" },
    countTypeLabel: { type: String, default: "Count" },
    addRowLabel: { type: String, default: "Add row" },
    removeRowTitle: { type: String, default: "Remove" },
    joinAndLabel: { type: String, default: "AND" },
    joinOrLabel: { type: String, default: "OR" },
    valuePlaceholder: { type: String, default: "value" },
    insertVariableTitle: { type: String, default: "Insert variable" },
    noVariablesAvailable: { type: String, default: "No variables available" },
    usedInThisElementLabel: { type: String, default: "Used in this element" },
    noMatchingVariablesLabel: { type: String, default: "No matching variables" },
    entityLabel: { type: String, default: "Entity" },
    selectEntityPlaceholder: { type: String, default: "Select entity..." },
    whereOptionalLabel: { type: String, default: "Where (optional)" },
    addFilterLabel: { type: String, default: "Add Filter" },
    countOperatorLabel: { type: String, default: "Count Operator" },
    countValueLabel: { type: String, default: "Count Value" },
    selectFieldPlaceholder: { type: String, default: "Select field..." },
    enterManuallyLabel: { type: String, default: "enter manually…" },
    removeFilterTitle: { type: String, default: "Remove filter" },
    switchToDropdownTitle: { type: String, default: "Switch to dropdown" },
    schemaUnavailableLabel: { type: String, default: "Schema unavailable — enter field names manually" },
    columnNamePlaceholder: { type: String, default: "column name" },
    couldNotLoadEntitiesLabel: { type: String, default: "Could not load entities" },
    otherGroupLabel: { type: String, default: "Other" }
  }

  connect() {
    this._entityCache = null
    this._fetchSeq = 0
    this._softTypeHint = this._softTypeHintTitle()
    this.prefillSavedQueryCounts()
  }

  labels() {
    return resolveConditionLabels({
      fieldTypeLabel: this.fieldTypeLabelValue,
      countTypeLabel: this.countTypeLabelValue,
      addRowLabel: this.addRowLabelValue,
      removeRowTitle: this.removeRowTitleValue,
      joinAndLabel: this.joinAndLabelValue,
      joinOrLabel: this.joinOrLabelValue,
      valuePlaceholder: this.valuePlaceholderValue,
      insertVariableTitle: this.insertVariableTitleValue,
      noVariablesAvailable: this.noVariablesAvailableValue,
      usedInThisElement: this.usedInThisElementLabelValue,
      noMatchingVariables: this.noMatchingVariablesLabelValue,
      entityLabel: this.entityLabelValue,
      selectEntityPlaceholder: this.selectEntityPlaceholderValue,
      whereOptionalLabel: this.whereOptionalLabelValue,
      addFilterLabel: this.addFilterLabelValue,
      countOperatorLabel: this.countOperatorLabelValue,
      countValueLabel: this.countValueLabelValue,
      selectFieldPlaceholder: this.selectFieldPlaceholderValue,
      enterManuallyLabel: this.enterManuallyLabelValue,
      removeFilterTitle: this.removeFilterTitleValue,
      switchToDropdownTitle: this.switchToDropdownTitleValue,
      schemaUnavailableLabel: this.schemaUnavailableLabelValue,
      columnNamePlaceholder: this.columnNamePlaceholderValue,
      couldNotLoadEntitiesLabel: this.couldNotLoadEntitiesLabelValue,
      otherGroupLabel: this.otherGroupLabelValue
    }, this.element)
  }

  rowContext() {
    return {
      elementId: this.elementIdValue,
      stepIndex: this.stepIndexValue,
      labels: this.labels()
    }
  }

  addRow(event) {
    event.preventDefault()
    const rows = this.element.querySelector("[data-condition-rows]")
    const template = this.element.querySelector("[data-condition-row-template]")
    const seed = template?.content?.firstElementChild
    if (!rows || !seed) return
    if (rows.querySelector("[data-condition-row]")) {
      rows.insertAdjacentHTML("beforeend", this._joinHtml())
    }
    const node = seed.cloneNode(true)
    this._resetRow(node)
    rows.appendChild(node)
    node.querySelector("[data-condition-left]")?.focus()
    this._notify()
  }

  removeRow(event) {
    event.preventDefault()
    const row = event.target.closest("[data-condition-row]")
    if (!row || !this.element.contains(row)) return
    const joinBefore = row.previousElementSibling?.hasAttribute("data-condition-join")
      ? row.previousElementSibling
      : null
    const joinAfter = row.nextElementSibling?.hasAttribute("data-condition-join")
      ? row.nextElementSibling
      : null
    if (joinBefore) detach(joinBefore)
    else if (joinAfter) detach(joinAfter)
    detach(row)
    const live = this.element.querySelectorAll("[data-condition-rows] > [data-condition-row]")
    if (live.length === 0) this.addRow({ preventDefault() {} })
    this._notify()
  }

  switchKind(event) {
    event.preventDefault()
    const row = event.target.closest("[data-condition-row]")
    const selected = event.target.closest("[data-row-type]")?.dataset?.rowType
    if (!row || !selected) return
    const isQc = selected === "query_count"
    row.dataset.conditionKind = isQc ? "query_count" : "field"
    row.querySelectorAll("[data-condition-row-type-toggle] [data-row-type]").forEach((btn) => {
      const on = btn.dataset.rowType === selected
      TOGGLE_ON.forEach((cls) => btn.classList.toggle(cls, on))
      TOGGLE_OFF.forEach((cls) => btn.classList.toggle(cls, !on))
    })
    row.querySelector("[data-condition-row-field-panel]")?.classList.toggle("hidden", isQc)
    row.querySelector("[data-condition-row-query-panel]")?.classList.toggle("hidden", !isQc)
    if (isQc) this.loadEntities(row)
    this._notify()
  }

  operatorChanged(event) {
    const row = event.target.closest("[data-condition-row]")
    if (!row) return
    this._toggleUnary(row.querySelector("[data-condition-right-wrap]"), event.target)
  }

  whereOperatorChanged(event) {
    const whereRow = event.target.closest("[data-cond-qc-where-row]")
    if (!whereRow) return
    this._toggleUnary(whereRow.querySelector("[data-cond-qc-where-value-wrap]"), event.target)
  }

  async entityChanged(event) {
    const row = event.target.closest("[data-condition-row]")
    if (!row) return
    const whereRows = row.querySelector("[data-cond-qc-where-rows]")
    if (!whereRows) return
    whereRows.innerHTML = ""
    this._clearSchemaError(row)
    const entityId = event.target.value
    if (!entityId) return
    await this._loadSchema(row, entityId, { addEmptyWhere: true })
  }

  addWhere(event) {
    event.preventDefault()
    const row = event.target.closest("[data-condition-row]")
    const whereRows = row?.querySelector("[data-cond-qc-where-rows]")
    if (!whereRows) return
    this._appendWhere(whereRows, parsePanelSchema(row.querySelector("[data-condition-row-query-panel]")))
  }

  removeWhere(event) {
    event.preventDefault()
    event.target.closest("[data-cond-qc-where-row]")?.remove()
  }

  whereFieldChanged(event) {
    if (event.target.value === "__manual__") {
      this._swapWhereToManual(event)
      return
    }
    const whereRow = event.target.closest("[data-cond-qc-where-row]")
    if (!whereRow) return
    const colType = event.target.selectedOptions?.[0]?.dataset?.colType || ""
    if (colType) whereRow.dataset.condQcColType = colType
    else delete whereRow.dataset.condQcColType
    const valueInput = whereRow.querySelector("[data-cond-qc-where-value]")
    if (!valueInput) return
    upsertTypeChip(valueInput.parentElement, colType)
    wireSoftTypeValidation(valueInput, colType, this._softTypeHint)
  }

  whereFieldToSelect(event) {
    event.preventDefault()
    const whereRow = event.target.closest("[data-cond-qc-where-row]")
    if (!whereRow) return
    const select = whereRow.querySelector("[data-cond-qc-where-field]")
    const manual = whereRow.querySelector("[data-cond-qc-where-field-manual]")
    if (manual) {
      manual.classList.add("hidden")
      manual.classList.remove("flex")
      const input = manual.querySelector("[data-cond-qc-where-field-input]")
      if (input) input.value = ""
    }
    if (select) {
      select.classList.remove("hidden")
      select.value = ""
    }
  }

  async loadEntities(row) {
    const entitySelect = row?.querySelector("[data-cond-qc-entity]")
    if (!entitySelect) return
    const preserved = entitySelect.value || ""
    const realCount = [...entitySelect.options].filter((opt) => opt.value !== "").length
    if (realCount > 1) {
      if (preserved) entitySelect.value = preserved
      return
    }
    let options = this._entityCache
    if (!options) {
      const result = await loadEntityOptions()
      if (!result.ok) {
        appendEntityLoadError(entitySelect, this.couldNotLoadEntitiesLabelValue)
        return
      }
      options = result.options
      this._entityCache = options
    }
    fillEntitySelect(entitySelect, options, preserved)
  }

  async prefillSavedQueryCounts() {
    const panels = [...this.element.querySelectorAll("[data-condition-row-query-panel][data-cond-qc-saved-entity-id]")]
    for (const panel of panels) {
      const row = panel.closest("[data-condition-row]")
      const entityId = panel.dataset.condQcSavedEntityId
      if (!row || !entityId) continue
      await this.loadEntities(row)
      const rules = parseSavedRules(panel)
      await this._loadSchema(row, entityId, { rules })
    }
  }

  serialized() {
    return collectConditions(this.element)
  }

  _joinHtml() {
    return buildJoinSelect("AND", this.labels())
  }

  _resetRow(row) {
    row.dataset.conditionKind = "field"
    row.querySelector("[data-condition-row-field-panel]")?.classList.remove("hidden")
    row.querySelector("[data-condition-row-query-panel]")?.classList.add("hidden")
    row.querySelectorAll("input, select, textarea").forEach((el) => {
      if (el.tagName === "SELECT") el.selectedIndex = 0
      else el.value = ""
    })
    const empty = emptyFieldCondition()
    const op = row.querySelector("[data-condition-op]")
    if (op) op.value = empty.operator
    this._toggleUnary(row.querySelector("[data-condition-right-wrap]"), op)
  }

  _toggleUnary(wrap, select) {
    if (!wrap || !select) return
    const match = [...select.options].find((opt) => opt.value === select.value)
    const unary = Boolean(match?.hasAttribute("data-unary")) || isUnaryOperator(select.value)
    wrap.classList.toggle("hidden", unary)
    wrap.querySelectorAll("input, textarea, select").forEach((input) => {
      if (input.type === "checkbox" || input.type === "hidden") return
      if (unary) {
        input.required = false
        return
      }
      const field = wrap.closest("[data-conditionally-required], [data-visible-when]")
      input.required = Boolean(field && !field.classList.contains("hidden"))
    })
  }

  _appendWhere(container, schema, rule = {}) {
    const removable = container.querySelectorAll("[data-cond-qc-where-row]").length > 0
    container.insertAdjacentHTML("beforeend", buildWhereRow({
      schema,
      rule,
      labels: this.labels(),
      context: this.rowContext(),
      removable
    }))
  }

  _swapWhereToManual(event) {
    const whereRow = event.target.closest("[data-cond-qc-where-row]")
    if (!whereRow) return
    const select = whereRow.querySelector("[data-cond-qc-where-field]")
    const manual = whereRow.querySelector("[data-cond-qc-where-field-manual]")
    if (select) {
      select.classList.add("hidden")
      select.value = ""
    }
    if (manual) {
      manual.classList.remove("hidden")
      manual.classList.add("flex")
      const input = manual.querySelector("[data-cond-qc-where-field-input]")
      if (input) {
        input.value = ""
        input.focus()
      }
    }
    delete whereRow.dataset.condQcColType
    const valueInput = whereRow.querySelector("[data-cond-qc-where-value]")
    if (valueInput) {
      upsertTypeChip(valueInput.parentElement, "")
      wireSoftTypeValidation(valueInput, "", this._softTypeHint)
    }
  }

  async _loadSchema(row, entityId, { addEmptyWhere = false, rules = null } = {}) {
    const whereRows = row.querySelector("[data-cond-qc-where-rows]")
    const panel = row.querySelector("[data-condition-row-query-panel]")
    if (!whereRows) return
    const url = entitySchemaUrl(entityId)
    if (!url) return
    const seq = ++this._fetchSeq
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (seq !== this._fetchSeq) return
      if (!response.ok) {
        this._showSchemaError(whereRows)
        return
      }
      const entity = await response.json()
      const schema = entity.property_schema || []
      if (panel) {
        panel.dataset.condQcSchema = JSON.stringify(schema)
        if (entity.name) panel.dataset.condQcSavedEntityName = entity.name
      }
      if (Array.isArray(rules)) {
        if (rules.length === 0) return
        whereRows.innerHTML = ""
        rules.forEach((rule) => {
          if (!rule.field) return
          this._appendWhere(whereRows, schema, rule)
          this._applyWhereRule(whereRows.querySelector("[data-cond-qc-where-row]:last-child"), rule)
        })
        return
      }
      if (addEmptyWhere) this._appendWhere(whereRows, schema)
    } catch (_error) {
      if (seq === this._fetchSeq) this._showSchemaError(whereRows)
    }
  }

  _applyWhereRule(whereRow, rule) {
    if (!whereRow) return
    const fieldSelect = whereRow.querySelector("[data-cond-qc-where-field]")
    const matching = fieldSelect && [...fieldSelect.options].find((opt) => opt.value === rule.field)
    if (matching) {
      fieldSelect.value = rule.field
      const colType = matching.dataset.colType || ""
      if (colType) {
        whereRow.dataset.condQcColType = colType
        const valueInput = whereRow.querySelector("[data-cond-qc-where-value]")
        if (valueInput) {
          upsertTypeChip(valueInput.parentElement, colType)
          wireSoftTypeValidation(valueInput, colType, this._softTypeHint)
        }
      }
    } else if (rule.field) {
      this._swapWhereToManual({ target: whereRow })
      const input = whereRow.querySelector("[data-cond-qc-where-field-input]")
      if (input) input.value = rule.field
    }
    const opSelect = whereRow.querySelector("[data-cond-qc-where-op]")
    const valueInput = whereRow.querySelector("[data-cond-qc-where-value]")
    if (opSelect) opSelect.value = rule.op || "=="
    if (valueInput) valueInput.value = rule.value || ""
    this._toggleUnary(whereRow.querySelector("[data-cond-qc-where-value-wrap]"), opSelect)
  }

  _showSchemaError(whereRows) {
    if (!whereRows || whereRows.parentElement?.querySelector("[data-cond-qc-schema-error]")) return
    whereRows.insertAdjacentHTML("afterend", `
      <div data-cond-qc-schema-error class="mt-1 flex items-center gap-1 text-xs text-amber-700">
        <svg class="w-3 h-3 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
        </svg>
        <span>${escapeHtml(this.schemaUnavailableLabelValue)}</span>
      </div>`)
  }

  _clearSchemaError(row) {
    row?.querySelector("[data-cond-qc-schema-error]")?.remove()
  }

  _softTypeHintTitle() {
    let node = this.element
    while (node) {
      const value = node.getAttribute?.("data-property-editor-soft-type-hint-title-value")
      if (value) return value
      node = node.parentElement
    }
    return "Expected a number or a ctx expression"
  }

  _notify() {
    this.element.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
