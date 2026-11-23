/**
 * Shared catalog-field renderer used by element property forms.
 * Step cards keep their own layout in templates/fields.js; both paths use
 * the same role controls (toggle, list, conditions, reference picker, …).
 */
import { escapeHtml } from "utils"
import {
  configFieldKey,
  configFieldType,
  matchesWhen,
  buildEntityColumnSelect
} from "controllers/property_editor/templates/fields"
import { isVarRefField, buildVarPickButton } from "controllers/property_editor/templates"
import { resolveControlLabels, FIELD_INPUT_CLASSES } from "controllers/property_editor/controls/shared"
import { buildToggleField } from "controllers/property_editor/controls/toggle"
import { buildListField } from "controllers/property_editor/controls/list"
import { buildMappingField } from "controllers/property_editor/controls/mapping"
import { buildConditionsField } from "controllers/property_editor/controls/conditions"
import { buildLocalizedTextField } from "controllers/property_editor/controls/localized_text"
import { buildReferencePickerField } from "controllers/property_editor/controls/reference_picker"

export { configFieldKey, configFieldType, matchesWhen }

const DEFAULT_PLACEHOLDER_FORMAT = "Default: {value}"

function autocompleteI18nAttrs(labels = {}) {
  return [
    ["no-variables-available", labels.noVariablesAvailable],
    ["used-in-this-element-label", labels.usedInThisElement],
    ["no-matching-variables-label", labels.noMatchingVariables]
  ].filter(([, value]) => typeof value === "string" && value !== "")
    .map(([name, value]) => ` data-context-autocomplete-${name}-value="${escapeHtml(value)}"`)
    .join("")
}

function autocompleteWrapperAttrs(elementId, labels = {}) {
  return ` data-controller="context-autocomplete" data-context-autocomplete-element-id-value="${escapeHtml(elementId)}"${autocompleteI18nAttrs(labels)}`
}

function wantsVariablePicker(field, elementId) {
  if (!elementId) return false
  if (field.variablePicker === false) return false
  if (field.variablePicker === true) return true
  return isVarRefField(configFieldKey(field))
}

function displayValue(value) {
  if (value == null) return ""
  if (typeof value === "object") return JSON.stringify(value, null, 2)
  return String(value)
}

function optionValue(opt) {
  return typeof opt === "string" ? opt : opt.value
}

function optionLabel(opt) {
  if (typeof opt === "string") return opt
  return opt.label ?? opt.value ?? ""
}

function numberPlaceholder(field, labels = {}) {
  if (field.default !== undefined && field.default !== null && field.default !== "") {
    const format = labels.defaultPlaceholderFormat || DEFAULT_PLACEHOLDER_FORMAT
    return format.replace("{value}", String(field.default))
  }
  return field.placeholder || ""
}

function withElementName(html, name) {
  const needle = `data-config-input="${escapeHtml(name)}"`
  return html.replace(needle, `${needle} name="${escapeHtml(name)}"`)
}

function buildTextControl(field, value, context, { multiline = false } = {}) {
  const { elementId, labels = {} } = context
  const key = configFieldKey(field)
  const strValue = displayValue(value)
  const placeholder = escapeHtml(field.placeholder || "")
  const required = field.required ? "required" : ""
  const maxLength = field.maxLength ? `maxlength="${field.maxLength}"` : ""
  const extraAction = context.extraAction || ""
  const tag = multiline || field.multiline || field.control === "textarea" || field.control === "code"
    ? "textarea"
    : "input"

  if (wantsVariablePicker(field, elementId)) {
    const pickerClasses = `${FIELD_INPUT_CLASSES} pl-2 pr-7`
    if (tag === "textarea") {
      return `<div class="relative"${autocompleteWrapperAttrs(elementId, labels)}>
    <textarea name="${escapeHtml(key)}"
      data-config-input="${escapeHtml(key)}"
      data-context-autocomplete-target="input"
      rows="${multiline || field.control === "code" ? 3 : 2}"
      placeholder="${placeholder}"
      ${required}
      ${maxLength}
      ${extraAction}
      class="${pickerClasses} resize-none">${escapeHtml(strValue)}</textarea>
    ${buildVarPickButton({ positionClasses: "right-0.5 top-2", title: labels.insertVariableTitle })}
  </div>`
    }
    return `<div class="relative"${autocompleteWrapperAttrs(elementId, labels)}>
    <input type="text"
      name="${escapeHtml(key)}"
      data-config-input="${escapeHtml(key)}"
      data-context-autocomplete-target="input"
      value="${escapeHtml(strValue)}"
      placeholder="${placeholder}"
      ${required}
      ${maxLength}
      ${extraAction}
      class="${pickerClasses}">
    ${buildVarPickButton({ title: labels.insertVariableTitle })}
  </div>`
  }

  if (tag === "textarea") {
    return `<textarea name="${escapeHtml(key)}"
      data-config-input="${escapeHtml(key)}"
      rows="${field.control === "code" ? 3 : 2}"
      placeholder="${placeholder}"
      ${required}
      ${maxLength}
      ${extraAction}
      class="${FIELD_INPUT_CLASSES} resize-none">${escapeHtml(strValue)}</textarea>`
  }

  return `<input type="text"
      name="${escapeHtml(key)}"
      data-config-input="${escapeHtml(key)}"
      value="${escapeHtml(strValue)}"
      placeholder="${placeholder}"
      ${required}
      ${maxLength}
      ${extraAction}
      class="${FIELD_INPUT_CLASSES}">`
}

function buildNumberControl(field, value, context) {
  const key = configFieldKey(field)
  const minAttr = field.min != null ? `min="${field.min}"` : ""
  const maxAttr = field.max != null ? `max="${field.max}"` : ""
  const extraAction = context.extraAction || ""
  const shown = value === undefined || value === null ? "" : String(value)
  return `<input type="number"
    name="${escapeHtml(key)}"
    data-config-input="${escapeHtml(key)}"
    value="${escapeHtml(shown)}"
    ${minAttr}
    ${maxAttr}
    placeholder="${escapeHtml(numberPlaceholder(field, context.labels))}"
    ${extraAction}
    class="${FIELD_INPUT_CLASSES}">`
}

function buildSelectControl(field, value, context) {
  const key = configFieldKey(field)
  const labels = resolveControlLabels(context.labels)
  const required = field.required === true
  let options = [...(field.options || [])]
  const hasEmpty = options.some((opt) => String(optionValue(opt) ?? "") === "")
  if (!required && !hasEmpty) {
    options = [{ value: "", label: labels.noneOptionLabel }, ...options]
  }
  const strValue = String(value ?? "")
  const hasMatch = options.some((opt) => String(optionValue(opt) ?? "") === strValue)
  const placeholder = (!hasMatch && required)
    ? `<option value="" selected disabled hidden></option>`
    : ""
  const optionsHTML = options.map((opt) => {
    const optValue = optionValue(opt)
    const optLabel = optionLabel(opt)
    const selected = hasMatch && strValue === String(optValue ?? "") ? " selected" : ""
    return `<option value="${escapeHtml(optValue)}"${selected}>${escapeHtml(optLabel)}</option>`
  }).join("")
  const extraAction = context.extraAction || ""

  return `<select
    name="${escapeHtml(key)}"
    data-config-input="${escapeHtml(key)}"
    ${required ? "required" : ""}
    ${extraAction}
    class="${FIELD_INPUT_CLASSES}">
    ${placeholder}${optionsHTML}
  </select>`
}

/**
 * True when another catalog field's visibleWhen / requiredWhen depends on `name`.
 */
export function fieldControlsVisibility(name, fields = []) {
  return fields.some((field) => {
    const when = field.visibleWhen || field.requiredWhen
    if (!when) return false
    if (when.field) return when.field === name
    return Object.prototype.hasOwnProperty.call(when, name)
  })
}

function renderRoleControl(field, value, context) {
  const type = configFieldType(field)
  const key = configFieldKey(field)
  const controlLabels = resolveControlLabels(context.labels)
  const controlContext = { ...context, labels: { ...controlLabels, ...context.labels } }
  const useEntityPicker = field.entityField === true || type === "attribute_picker"

  switch (type) {
    case "text":
    case "attribute_picker":
      if (useEntityPicker && (context.entityAttributes || []).length > 0) {
        return buildEntityColumnSelect(field, value, context.entityAttributes, context)
          || buildTextControl(field, value, context)
      }
      return buildTextControl(field, value, context)
    case "textarea":
    case "json_or_expression":
      return buildTextControl(field, type === "json_or_expression" && typeof value === "object"
        ? JSON.stringify(value, null, 2)
        : value, context, { multiline: true })
    case "number":
      return buildNumberControl(field, value, context)
    case "select":
      return buildSelectControl(field, value, context)
    case "key_value_list":
      return withElementName(buildMappingField(field, value, controlContext), key)
    case "toggle":
      return withElementName(buildToggleField(field, value), key)
    case "list":
      return withElementName(buildListField(field, value, controlContext), key)
    case "conditions":
      return buildConditionsField(field, value, controlContext)
    case "localized_text":
      return withElementName(buildLocalizedTextField(field, value, controlContext), key)
    case "reference_picker":
      return withElementName(buildReferencePickerField(field, value, controlContext), key)
    default:
      return buildTextControl(field, value, context)
  }
}

/**
 * Render one catalog field for an element form (label + control + help).
 * @param {Object} field - catalog field
 * @param {*} value - current value
 * @param {Object} context - { properties, fields, labels, elementId, entityAttributes }
 * @returns {string}
 */
export function renderCatalogField(field, value, context = {}) {
  const key = configFieldKey(field)
  if (!key) return ""

  const properties = context.properties || {}
  const isVisible = matchesWhen(field.visibleWhen, properties)
  const hiddenClass = isVisible ? "" : " hidden"
  const requiredWhen = field.requiredWhen
    ? matchesWhen(field.requiredWhen, properties)
    : field.required === true
  const required = isVisible && requiredWhen
  const schemaRequired = field.required === true || Boolean(field.requiredWhen)
  const requiredMark = required ? ' <span class="text-red-500">*</span>' : ""
  const renderedField = { ...field, required }

  const extraActions = []
  if (fieldControlsVisibility(key, context.fields || [])) {
    extraActions.push("change->property-editor#handleVisibilityFieldChange")
  }
  if (context.extraAction) extraActions.push(context.extraAction)
  const extraAction = extraActions.length > 0 ? ` data-action="${extraActions.join(" ")}"` : ""

  const inputHTML = renderRoleControl(renderedField, value, { ...context, extraAction })
  const helpText = field.help || field.helperText
  const helpHTML = helpText
    ? `<p class="mt-0.5 text-xs text-slate-400">${escapeHtml(helpText)}</p>`
    : ""
  const visibleWhenAttr = field.visibleWhen
    ? ` data-visible-when='${escapeHtml(JSON.stringify(field.visibleWhen))}'`
    : ""
  const requiredWhenAttr = field.requiredWhen
    ? ` data-required-when='${escapeHtml(JSON.stringify(field.requiredWhen))}'`
    : ""

  return `
    <div class="space-y-1${hiddenClass}"
         data-element-field="${escapeHtml(key)}"
         data-role="${escapeHtml(field.role || "")}"
         ${schemaRequired ? "data-conditionally-required" : ""}
         data-field-default="${escapeHtml(String(field.default ?? ""))}"
         ${visibleWhenAttr}${requiredWhenAttr}>
      <label for="prop_${escapeHtml(key)}" class="block text-xs font-medium text-slate-500">
        ${escapeHtml(field.label || "")}${requiredMark}
      </label>
      ${inputHTML}
      ${helpHTML}
    </div>`
}
