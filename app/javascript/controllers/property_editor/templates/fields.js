/**
 * Form field / config-input template builders.
 * Covers: buildDisclosureSection, buildSetCountBadge, buildVarPickButton, buildEntityColumnSelect,
 * buildStepConfigFieldsHTML, buildStepPickerTemplate, getColorClasses,
 * and all private config-field helpers.
 */

import { escapeHtml } from "utils"
import { isVarRefField } from "controllers/property_editor/templates/var_refs"
import { resolveControlLabels } from "controllers/property_editor/controls/shared"
import { buildToggleField } from "controllers/property_editor/controls/toggle"
import { buildListField } from "controllers/property_editor/controls/list"
import { buildMappingField } from "controllers/property_editor/controls/mapping"
import { buildConditionsField } from "controllers/property_editor/controls/conditions"
import { buildLocalizedTextField } from "controllers/property_editor/controls/localized_text"
import { buildReferencePickerField } from "controllers/property_editor/controls/reference_picker"

/**
 * Build a collapsible disclosure section (chevron header + body + optional badge).
 * Used by the step card "Advanced" sub-section.
 * @param {Object} params
 * @param {string} params.id - Stable identifier written to data-disclosure-id
 * @param {string} params.label - Header label
 * @param {string} params.badgeHTML - Optional pre-built badge HTML (not escaped)
 * @param {string} params.bodyHTML - Body content HTML (not escaped)
 * @param {boolean} params.startOpen - Render expanded (default collapsed)
 * @returns {string} Disclosure section HTML
 */
export function buildDisclosureSection({ id, label, badgeHTML = "", bodyHTML = "", startOpen = false }) {
  return `
    <div class="border border-slate-200 rounded-md" data-disclosure data-disclosure-id="${escapeHtml(id)}">
      <button type="button"
              data-action="click->property-editor#toggleDisclosure"
              class="w-full flex items-center justify-between px-2.5 py-1.5 text-xs font-medium text-slate-700 hover:bg-slate-50 transition-colors rounded-md">
        <span class="flex items-center gap-1.5">
          <span>${escapeHtml(label)}</span>
          ${badgeHTML}
        </span>
        <svg data-disclosure-chevron class="w-3.5 h-3.5 text-slate-400 transition-transform duration-150 ${startOpen ? "rotate-180" : ""}"
             fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
        </svg>
      </button>
      <div data-disclosure-body class="${startOpen ? "" : "hidden"} px-2.5 pb-2.5 border-t border-slate-200">
        ${bodyHTML}
      </div>
    </div>
  `.trim()
}

/**
 * "N set" badge for the step "More options" disclosure. Counts non-default
 * values inside the disclosure body. Hidden (not omitted) at 0 so JS can
 * update it in place.
 * English default format is byte-identical to the live-update format
 * config_fields.js reads off this.controller.stepConfigSetCountFormatValue.
 * @param {number} count
 * @param {string} [format] - "{count} set"-shaped template
 * @returns {string} Badge HTML
 */
export function buildSetCountBadge(count, format = "{count} set") {
  const hiddenClass = count > 0 ? "" : " hidden"
  return `<span data-set-count-badge class="flex items-center justify-center min-w-[1.25rem] h-5 px-1.5 text-[10px] font-semibold text-slate-600 bg-slate-100 border border-slate-200 rounded${hiddenClass}">${format.replace("{count}", count)}</span>`
}

/**
 * data-controller attributes for a context-autocomplete wrapper div.
 * Returns "" when elementId is absent so markup degrades to today's exact output.
 */
function autocompleteI18nAttrs(labels = {}) {
  return [
    ["no-variables-available", labels.noVariablesAvailable],
    ["used-in-this-element-label", labels.usedInThisElement],
    ["no-matching-variables-label", labels.noMatchingVariables]
  ].filter(([, value]) => typeof value === "string" && value !== "")
    .map(([name, value]) => ` data-context-autocomplete-${name}-value="${escapeHtml(value)}"`)
    .join("")
}

function autocompleteWrapperAttrs(elementId, stepIndex, labels = {}) {
  if (!elementId) return ""
  return ` data-controller="context-autocomplete" data-context-autocomplete-element-id-value="${escapeHtml(elementId)}" data-context-autocomplete-step-index-value="${stepIndex ?? -1}"${autocompleteI18nAttrs(labels)}`
}

/**
 * The {x} variable-pick button. Must be rendered inside a `relative` wrapper
 * that carries data-controller="context-autocomplete"; the input in the same
 * wrapper carries data-context-autocomplete-target="input" and pl-2 pr-7.
 * tabindex="-1" keeps Tab flow on the input; mousedown->keepFocus prevents
 * the click from blurring the input.
 * @param {Object} params
 * @param {string} params.positionClasses - absolute positioning classes
 * @param {string} [params.title] - Translated title override (English
 *   default keeps existing callers that don't thread a controller Value).
 * @returns {string}
 */
export function buildVarPickButton({ positionClasses = "right-0.5 top-1/2 -translate-y-1/2", title = "Insert variable" } = {}) {
  return `<button type="button"
        tabindex="-1"
        title="${escapeHtml(title)}"
        data-action="mousedown->context-autocomplete#keepFocus click->context-autocomplete#picker"
        class="absolute ${escapeHtml(positionClasses)} flex items-center justify-center w-5 h-5 text-[10px] font-mono font-bold text-slate-400 hover:text-indigo-600 hover:bg-indigo-50 active:bg-indigo-100 active:text-indigo-700 rounded transition-colors cursor-pointer">{x}</button>`
}

// ===================
// Color Classes
// ===================

/**
 * Color class mappings for step items.
 * Used internally for consistent styling.
 */
const STEP_COLOR_CLASSES = {
  emerald: { bg: "bg-slate-50", border: "border-slate-200", hover: "hover:border-slate-200", icon: "text-emerald-600", badge: "bg-emerald-50 text-emerald-700 border-emerald-200" },
  green: { bg: "bg-slate-50", border: "border-slate-200", hover: "hover:border-slate-200", icon: "text-green-600", badge: "bg-green-50 text-green-700 border-green-200" },
  blue: { bg: "bg-slate-50", border: "border-slate-200", hover: "hover:border-slate-200", icon: "text-blue-600", badge: "bg-blue-50 text-blue-700 border-blue-200" },
  indigo: { bg: "bg-slate-50", border: "border-slate-200", hover: "hover:border-slate-200", icon: "text-indigo-600", badge: "bg-indigo-50 text-indigo-700 border-indigo-200" },
  amber: { bg: "bg-slate-50", border: "border-slate-200", hover: "hover:border-slate-200", icon: "text-amber-600", badge: "bg-amber-50 text-amber-700 border-amber-200" },
  red: { bg: "bg-slate-50", border: "border-slate-200", hover: "hover:border-slate-200", icon: "text-red-600", badge: "bg-red-50 text-red-700 border-red-200" },
  purple: { bg: "bg-slate-50", border: "border-slate-200", hover: "hover:border-slate-200", icon: "text-purple-600", badge: "bg-purple-50 text-purple-700 border-purple-200" },
  cyan: { bg: "bg-slate-50", border: "border-slate-200", hover: "hover:border-slate-200", icon: "text-cyan-600", badge: "bg-cyan-50 text-cyan-700 border-cyan-200" },
  pink: { bg: "bg-slate-50", border: "border-slate-200", hover: "hover:border-slate-200", icon: "text-pink-600", badge: "bg-pink-50 text-pink-700 border-pink-200" },
  teal: { bg: "bg-slate-50", border: "border-slate-200", hover: "hover:border-slate-200", icon: "text-teal-600", badge: "bg-teal-50 text-teal-700 border-teal-200" }
}

/**
 * Get color classes for a given color name, with fallback to blue.
 */
export function getColorClasses(colorName) {
  return STEP_COLOR_CLASSES[colorName] || STEP_COLOR_CLASSES.blue
}

// ===================
// Step Picker Template
// ===================

/**
 * Inline searchable action picker for the Process Step tab.
 * Mounts the searchable-select controller; committing fires a `change` on the
 * hidden input which property-editor#stepPickerCommit handles.
 * @param {string} optionsJSON - JSON.stringify'd grouped options (raw; escaped here)
 * @param {string} [searchPlaceholder] - Translated placeholder override
 * @returns {string}
 */
export function buildStepPickerTemplate(optionsJSON, searchPlaceholder = "Search actions…") {
  return `
    <div data-step-picker
         data-controller="searchable-select"
         data-searchable-select-options-value="${escapeHtml(optionsJSON)}"
         class="relative border border-slate-200 rounded-lg bg-white shadow-sm">
      <svg class="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-slate-400 pointer-events-none" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
      </svg>
      <input type="text"
             data-searchable-select-target="search"
             data-action="input->searchable-select#filter keydown->searchable-select#keydown focus->searchable-select#open keydown.esc->property-editor#stepPickerEscape"
             placeholder="${escapeHtml(searchPlaceholder)}"
             autocomplete="off"
             class="w-full pl-8 pr-3 py-1.5 text-xs text-slate-800 placeholder:text-slate-400 bg-transparent border-0 focus:outline-none focus:ring-0">
      <input type="hidden"
             data-searchable-select-target="hidden"
             data-action="change->property-editor#stepPickerCommit">
      <div data-searchable-select-target="dropdown"
           class="hidden absolute z-50 mt-1 w-full bg-white border border-slate-200 rounded-md shadow-lg max-h-72 overflow-y-auto"></div>
    </div>
  `.trim()
}

// ===================
// Config Field Renderers (private helpers)
// ===================

/**
 * Config-field identity. Export fields use `name`; the legacy renderer used `key`.
 */
export function configFieldKey(field) {
  return field?.name || field?.key
}

/**
 * Map an export `control` (or a legacy `type`) onto the renderer switch.
 */
export function configFieldType(field) {
  if (field?.type) return field.type
  switch (field?.control) {
    case "textarea": return "textarea"
    case "select": return "select"
    case "number": return "number"
    case "mapping": return "key_value_list"
    case "code": return "json_or_expression"
    case "toggle": return "toggle"
    case "list": return "list"
    case "conditions": return "conditions"
    case "attribute_picker": return "attribute_picker"
    case "reference_picker": return "reference_picker"
    case "localized_text": return "localized_text"
    default: return "text"
  }
}

function isLegacyWhen(when) {
  return when && Object.prototype.hasOwnProperty.call(when, "field")
    && (Object.prototype.hasOwnProperty.call(when, "values")
      || Object.prototype.hasOwnProperty.call(when, "value"))
}

function valueMatches(current, allowed) {
  const matchValues = (Array.isArray(allowed) ? allowed : [allowed]).map(String)
  return matchValues.includes(String(current ?? ""))
}

/**
 * Evaluate a `visibleWhen` / `requiredWhen` clause against current config.
 * Accepts the export shape `{ fieldName: allowed }` (scalar or array) and the
 * legacy `{ field, value | values }` shape.
 */
export function matchesWhen(when, currentConfig) {
  if (!when) return true
  if (isLegacyWhen(when)) {
    return valueMatches(currentConfig[when.field], when.values ?? when.value)
  }
  return Object.entries(when).every(([name, allowed]) => valueMatches(currentConfig[name], allowed))
}

/**
 * Check if a config field should be visible based on visibleWhen condition.
 */
function shouldFieldBeVisible(field, currentConfig) {
  return matchesWhen(field.visibleWhen, currentConfig)
}

function shouldFieldBeRequired(field, currentConfig, isVisible) {
  if (!isVisible) return false
  if (field.requiredWhen) return matchesWhen(field.requiredWhen, currentConfig)
  return field.required === true
}

function wantsVariablePicker(field, elementId) {
  if (!elementId) return false
  if (field.variablePicker === false) return false
  if (field.variablePicker === true) return true
  return isVarRefField(configFieldKey(field))
}

function displayValue(value) {
  if (typeof value === "object") return JSON.stringify(value, null, 2)
  return String(value)
}

const CONFIG_INPUT_CLASSES = "w-full px-2 py-1.5 text-xs border border-slate-200 bg-white rounded-md placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400"
// Same as CONFIG_INPUT_CLASSES but pl-2 pr-7 so text never underlaps the {x} button (UX flag #2).
const CONFIG_INPUT_VARPICK_CLASSES = "w-full pl-2 pr-7 py-1.5 text-xs border border-slate-200 bg-white rounded-md placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400"

function buildConfigTextField(field, value, context = {}) {
  const { elementId, stepIndex, labels = {} } = context
  const key = configFieldKey(field)
  const strValue = displayValue(value)

  if (wantsVariablePicker(field, elementId)) {
    return `<div class="relative"${autocompleteWrapperAttrs(elementId, stepIndex, labels)}>
    <input type="text"
      data-config-input="${escapeHtml(key)}"
      data-context-autocomplete-target="input"
      value="${escapeHtml(strValue)}"
      placeholder="${escapeHtml(field.placeholder || "")}"
      ${field.required ? "required" : ""}
      ${field.maxLength ? `maxlength="${field.maxLength}"` : ""}
      class="${CONFIG_INPUT_VARPICK_CLASSES}">
    ${buildVarPickButton({ title: labels.insertVariableTitle })}
  </div>`
  }

  const controllerAttrs = autocompleteWrapperAttrs(elementId, stepIndex, labels)

  return `<input type="text"
    data-config-input="${escapeHtml(key)}"${controllerAttrs}
    value="${escapeHtml(strValue)}"
    placeholder="${escapeHtml(field.placeholder || "")}"
    ${field.required ? "required" : ""}
    ${field.maxLength ? `maxlength="${field.maxLength}"` : ""}
    class="${CONFIG_INPUT_CLASSES}">`
}

function buildConfigTextareaField(field, value, context = {}) {
  const { elementId, stepIndex, labels = {} } = context
  const key = configFieldKey(field)
  const strValue = displayValue(value)

  if (wantsVariablePicker(field, elementId)) {
    return `<div class="relative"${autocompleteWrapperAttrs(elementId, stepIndex, labels)}>
    <textarea
      data-config-input="${escapeHtml(key)}"
      data-context-autocomplete-target="input"
      rows="2"
      placeholder="${escapeHtml(field.placeholder || "")}"
      ${field.required ? "required" : ""}
      ${field.maxLength ? `maxlength="${field.maxLength}"` : ""}
      class="${CONFIG_INPUT_VARPICK_CLASSES} resize-none">${escapeHtml(strValue)}</textarea>
    ${buildVarPickButton({ positionClasses: "right-0.5 top-2", title: labels.insertVariableTitle })}
  </div>`
  }

  const controllerAttrs = autocompleteWrapperAttrs(elementId, stepIndex, labels)

  return `<textarea
    data-config-input="${escapeHtml(key)}"${controllerAttrs}
    rows="2"
    placeholder="${escapeHtml(field.placeholder || "")}"
    ${field.required ? "required" : ""}
    ${field.maxLength ? `maxlength="${field.maxLength}"` : ""}
    class="${CONFIG_INPUT_CLASSES} resize-none">${escapeHtml(strValue)}</textarea>`
}

function buildConfigNumberField(field, value) {
  const key = configFieldKey(field)
  const minAttr = field.min != null ? `min="${field.min}"` : ""
  const maxAttr = field.max != null ? `max="${field.max}"` : ""
  return `<input type="number"
    data-config-input="${escapeHtml(key)}"
    value="${escapeHtml(String(value))}"
    ${minAttr}
    ${maxAttr}
    placeholder="${escapeHtml(field.placeholder || "")}"
    class="${CONFIG_INPUT_CLASSES}">`
}

function optionValue(opt) {
  return typeof opt === "string" ? opt : opt.value
}

function optionLabel(opt) {
  if (typeof opt === "string") return opt
  return opt.label ?? opt.value ?? ""
}

function buildConfigSelectField(field, value, labels = {}) {
  const key = configFieldKey(field)
  const required = field.required === true
  let options = [...(field.options || [])]
  const hasEmpty = options.some(opt => String(optionValue(opt) ?? "") === "")
  if (!required && !hasEmpty) {
    options = [{ value: "", label: labels.noneOptionLabel }, ...options]
  }
  const strValue = String(value)
  const hasMatch = options.some(opt => String(optionValue(opt) ?? "") === strValue)
  const placeholder = (!hasMatch && required)
    ? `<option value="" selected disabled hidden></option>`
    : ""
  const optionsHTML = options.map(opt => {
    const optValue = optionValue(opt)
    const optLabel = optionLabel(opt)
    const selected = hasMatch && strValue === String(optValue ?? "") ? " selected" : ""
    return `<option value="${escapeHtml(optValue)}"${selected}>${escapeHtml(optLabel)}</option>`
  }).join("")

  return `<select
    data-config-input="${escapeHtml(key)}"
    data-action="change->property-editor#handleConfigFieldChange"
    class="${CONFIG_INPUT_CLASSES}">
    ${placeholder}${optionsHTML}
  </select>`
}

/**
 * Entity-aware column select with "enter manually…" escape hatch.
 * Renders for configSchema fields annotated entityField: true when the
 * flowchart has a bound entity (canvas.entityAttributes non-empty).
 * Returns null when no columns are available — caller falls back to the
 * plain text field (today's exact markup).
 *
 * Value contract: a single hidden <input data-config-input> holds the value
 * read by collectStepConfig(); the select / manual input mirror into it via
 * property-editor#handleEntityColumnSelectChange / #syncEntityColumnManual.
 * Emits the bare attribute slug (e.g. "email"), same as manual typing today.
 */
export function buildEntityColumnSelect(field, value, entityAttributes, context = {}) {
  const columns = (entityAttributes || [])
    .map(attr => ({
      slug: attr.name_slug || attr.name || String(attr),
      label: attr.name || attr.name_slug || String(attr),
      htmlType: attr.html_type || ""
    }))
    .filter(c => Boolean(c.slug))
  if (columns.length === 0) return null

  const strValue = String(value ?? "")
  const valueInColumns = strValue === "" || columns.some(c => c.slug === strValue)
  const { elementId, stepIndex, labels = {} } = context
  const selectColumnPlaceholder = labels.selectColumnPlaceholder ?? "Select column…"
  const otherOptgroupLabel = labels.otherOptgroupLabel ?? "Other"
  const enterManuallyOptionLabel = labels.enterManuallyOptionLabel ?? "enter manually…"
  const columnNamePlaceholder = labels.columnNamePlaceholder ?? "column name"
  const switchToDropdownTitle = labels.switchToDropdownTitle ?? "Switch to dropdown"

  // Type suffix is label-only and conditional: option VALUE stays the bare
  // slug, and unknown-type columns render today's exact <option> markup.
  const optionsHTML =
    `<option value="">${escapeHtml(selectColumnPlaceholder)}</option>` +
    columns.map(c => {
      const label = c.htmlType ? `${c.label} — ${c.htmlType}` : c.label
      return `<option value="${escapeHtml(c.slug)}"${c.slug === strValue ? " selected" : ""}${c.htmlType ? ` data-col-type="${escapeHtml(c.htmlType)}"` : ""}>${escapeHtml(label)}</option>`
    }).join("")

  return `
    <div data-entity-field-wrapper>
      <select data-entity-column-select
              ${field.required && valueInColumns ? "required" : ""}
              data-action="change->property-editor#handleEntityColumnSelectChange"
              class="${valueInColumns ? "" : "hidden "}w-full px-2 py-1.5 text-xs bg-white border border-slate-200 rounded-md shadow-sm focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400">
        ${optionsHTML}
        <optgroup label="${escapeHtml(otherOptgroupLabel)}"><option value="__manual__">${escapeHtml(enterManuallyOptionLabel)}</option></optgroup>
      </select>
      <div data-entity-manual-wrap class="${valueInColumns ? "hidden " : ""}relative flex gap-1"${autocompleteWrapperAttrs(elementId, stepIndex, labels)}>
        <input type="text"
               data-entity-column-manual
               ${field.required && !valueInColumns ? "required" : ""}
               ${elementId ? `data-context-autocomplete-target="input"` : ""}
               data-action="input->property-editor#syncEntityColumnManual change->property-editor#handleConfigFieldChange"
               value="${valueInColumns ? "" : escapeHtml(strValue)}"
               placeholder="${escapeHtml(columnNamePlaceholder)}"
               class="flex-1 min-w-0 pl-2 pr-7 py-1.5 text-xs font-mono bg-white border border-slate-200 rounded-md shadow-sm placeholder:text-slate-400 focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-400">
        ${elementId ? buildVarPickButton({ positionClasses: "right-9 top-1/2 -translate-y-1/2", title: labels.insertVariableTitle }) : ""}
        <button type="button"
                data-action="click->property-editor#swapEntityColumnToSelect"
                title="${escapeHtml(switchToDropdownTitle)}"
                class="px-2 py-1 text-[10px] text-slate-500 hover:text-slate-700 border border-slate-200 rounded hover:bg-slate-50 flex-shrink-0">&#x25B2;</button>
      </div>
      <input type="hidden" data-config-input="${escapeHtml(configFieldKey(field))}" value="${escapeHtml(strValue)}">
    </div>
  `.trim()
}

/** True when `value` differs from the field's schema default (UX 2.3c). */
function isFieldValueNonDefault(field, value) {
  const type = configFieldType(field)
  if (type === "key_value_list") {
    return Array.isArray(value) && value.some(row => String(row.key || "").trim() !== "")
  }
  if (type === "list") {
    return Array.isArray(value) && value.some(item => String(item ?? "").trim() !== "")
  }
  if (type === "conditions") {
    const rows = value?.conditions
    return Array.isArray(rows) && rows.some((row) => {
      if (!row) return false
      if (row.kind === "query_count") return Boolean(row.queryConfig?.entityId)
      return Boolean(row.leftOperand || row.operator || row.rightOperand)
    })
  }
  if (type === "localized_text") {
    return JSON.stringify(value || {}) !== JSON.stringify(field.default || {})
  }
  if (type === "toggle") return Boolean(value) !== Boolean(field.default)
  return String(value ?? "") !== String(field.default ?? "")
}

function isCoreGroup(field) {
  return field.group === "core" || field.group === "main"
}

function buildSingleConfigFieldHTML(field, currentConfig, context, visibilityConfig) {
  const key = configFieldKey(field)
  const type = configFieldType(field)
  const value = currentConfig[key] ?? field.default ?? ""
  const isVisible = shouldFieldBeVisible(field, visibilityConfig)
  const hiddenClass = isVisible ? "" : " hidden"
  const required = shouldFieldBeRequired(field, visibilityConfig, isVisible)
  const schemaRequired = field.required === true || Boolean(field.requiredWhen)
  const requiredMark = (field.required === true || (field.requiredWhen && required)) ? ' <span class="text-red-500">*</span>' : ""
  field = { ...field, required }

  const useEntityPicker = field.entityField === true || type === "attribute_picker"
  const controlLabels = resolveControlLabels(context.labels)
  const controlContext = { ...context, labels: { ...controlLabels, ...context.labels } }

  let inputHTML
  switch (type) {
    case "text":
    case "attribute_picker":
      // entityField / attribute_picker: with a bound entity render the
      // column select; otherwise degrade silently to today's plain text input.
      inputHTML = (useEntityPicker && (context.entityAttributes || []).length > 0)
        ? (buildEntityColumnSelect(field, value, context.entityAttributes, context)
            || buildConfigTextField(field, value, context))
        : buildConfigTextField(field, value, context)
      break
    case "textarea":  inputHTML = buildConfigTextareaField(field, value, context); break
    case "json_or_expression":
      inputHTML = buildConfigTextareaField(field, typeof value === "object" ? JSON.stringify(value, null, 2) : value, context)
      break
    case "number":    inputHTML = buildConfigNumberField(field, value); break
    case "select":    inputHTML = buildConfigSelectField(field, value, controlLabels); break
    case "key_value_list": inputHTML = buildMappingField(field, value, controlContext); break
    case "toggle":    inputHTML = buildToggleField(field, value); break
    case "list":      inputHTML = buildListField(field, value, controlContext); break
    case "conditions": inputHTML = buildConditionsField(field, value, controlContext); break
    case "localized_text": inputHTML = buildLocalizedTextField(field, value, controlContext); break
    case "reference_picker": inputHTML = buildReferencePickerField(field, value, controlContext); break
    default:          inputHTML = buildConfigTextField(field, value, context)
  }

  const helpHTML = field.help
    ? `<p class="mt-0.5 text-[10px] text-slate-400">${escapeHtml(field.help)}</p>`
    : ""
  const jsonAttr = type === "json_or_expression" ? " data-json-or-expression" : ""
  const requiredWhenAttr = field.requiredWhen
    ? ` data-required-when='${escapeHtml(JSON.stringify(field.requiredWhen))}'`
    : ""

  return `
    <div class="step-config-field${hiddenClass}"
         data-config-field="${escapeHtml(key)}"
         ${jsonAttr}
         ${schemaRequired ? "data-conditionally-required" : ""}
         data-field-default="${escapeHtml(String(field.default ?? ""))}"
         ${field.visibleWhen ? `data-visible-when='${escapeHtml(JSON.stringify(field.visibleWhen))}'` : ""}${requiredWhenAttr}>
      <label class="block text-[11px] font-medium text-slate-500 mb-1">
        ${escapeHtml(field.label || "")}${requiredMark}
      </label>
      ${inputHTML}
      ${helpHTML}
    </div>`
}

/**
 * Build HTML for action-specific config fields in expanded step item.
 * Actions with > 6 currently-visible fields are partitioned: core fields
 * (group:"core", or required without visibleWhen) render flat; the rest go
 * into a collapsed "More options" disclosure with an "N set" badge.
 * The partition and the `group` hint are render-time only — never serialized.
 * @param {Array} configSchema - Array of field schema objects from the action registry
 * @param {Object} currentConfig - Current config values (from step.config)
 * @param {Object} context - { elementId, stepIndex, entityAttributes, moreOpen, labels }
 * @returns {string} HTML string for all config fields
 */
export function buildStepConfigFieldsHTML(configSchema, currentConfig = {}, context = {}) {
  if (!configSchema || configSchema.length === 0) return ""

  // Visibility must see the same defaults as the controls themselves. Saved
  // configs may omit default-valued selectors; their dependents still apply.
  const visibilityConfig = { ...currentConfig, ...Object.fromEntries(configSchema.map(field => {
    const key = configFieldKey(field)
    return [key, currentConfig[key] ?? field.default ?? ""]
  })) }
  const renderAll = fields =>
    fields.map(field => buildSingleConfigFieldHTML(field, currentConfig, context, visibilityConfig)).join("")

  const visibleCount = configSchema.filter(f => shouldFieldBeVisible(f, visibilityConfig)).length
  if (visibleCount <= 6) {
    return `<div data-step-config-fields class="space-y-2">${renderAll(configSchema)}</div>`
  }

  const core = []
  const more = []
  configSchema.forEach(field => {
    if (isCoreGroup(field)) { core.push(field); return }
    if (field.group === "advanced") { more.push(field); return }
    if (field.required && !field.visibleWhen) { core.push(field) } else { more.push(field) }
  })

  // Degenerate partitions render flat (UX 3.9 failure table + plan resolution).
  if (core.length === 0 || more.length === 0) {
    return `<div data-step-config-fields class="space-y-2">${renderAll(configSchema)}</div>`
  }

  const setCount = more.filter(f => {
    const key = configFieldKey(f)
    return (key in currentConfig) && isFieldValueNonDefault(f, currentConfig[key])
  }).length

  const labels = context.labels || {}
  return `<div data-step-config-fields class="space-y-2">${renderAll(core)}${buildDisclosureSection({
    id: `step-more-${context.stepIndex ?? 0}`,
    label: labels.moreOptionsLabel ?? "More options",
    badgeHTML: buildSetCountBadge(setCount, labels.setCountFormat),
    bodyHTML: `<div class="space-y-2 pt-2.5">${renderAll(more)}</div>`,
    startOpen: context.moreOpen === true
  })}</div>`
}
