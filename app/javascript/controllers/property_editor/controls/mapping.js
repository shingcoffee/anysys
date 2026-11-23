import { escapeHtml } from "utils"
import { addRowButton, entityColumns, FIELD_INPUT_CLASSES, resolveControlLabels } from "controllers/property_editor/controls/shared"

function attributeSelect(value, columns, labels, attr) {
  const placeholder = labels.selectColumnPlaceholder || "Select column…"
  const options = [`<option value="">${escapeHtml(placeholder)}</option>`]
    .concat(columns.map(c => `<option value="${escapeHtml(c.slug)}"${c.slug === value ? " selected" : ""}>${escapeHtml(c.label)}</option>`))
    .join("")
  return `<select ${attr} class="${FIELD_INPUT_CLASSES}">${options}</select>`
}

function keyControl(row, field, context, labels) {
  const value = row.key || ""
  const columns = entityColumns(context.entityAttributes)
  if (field.keyRole === "entity_attribute" && columns.length > 0) {
    return attributeSelect(value, columns, labels, "data-kv-key")
  }
  return `<input type="text" data-kv-key value="${escapeHtml(value)}" placeholder="${escapeHtml(labels.kvKeyPlaceholder)}" class="${FIELD_INPUT_CLASSES}">`
}

function valueControl(row, field, labels) {
  const value = row.value == null ? "" : String(row.value)
  const placeholder = labels.kvValuePlaceholder
  return `<input type="text" data-kv-value value="${escapeHtml(value)}" placeholder="${escapeHtml(placeholder)}" class="${FIELD_INPUT_CLASSES}">`
}

function mappingRow(row, field, context, labels) {
  return `<div data-kv-row class="grid grid-cols-1 sm:grid-cols-[1fr_1fr_auto] gap-1.5 items-center">
      ${keyControl(row, field, context, labels)}
      ${valueControl(row, field, labels)}
      <button type="button"
              data-action="click->property-editor#removeConfigKvRow"
              class="p-0.5 text-slate-400 hover:text-red-500 hover:bg-red-50 rounded transition-colors flex-shrink-0 justify-self-start sm:justify-self-center"
              title="${escapeHtml(labels.kvRemoveRowTitle || labels.removeRowTitle)}">
        <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </div>`
}

/** Rows with a key, in order; a blank value is kept as "". */
export function collectMapping(listEl) {
  return [...listEl.querySelectorAll("[data-kv-row]")].flatMap((row) => {
    const key = row.querySelector("[data-kv-key]")?.value?.trim()
    const value = row.querySelector("[data-kv-value]")?.value?.trim()
    return key ? [{ key, value: value || "" }] : []
  })
}

export function buildMappingField(field, value, context = {}) {
  const labels = resolveControlLabels(context.labels)
  const rows = Array.isArray(value) && value.length > 0 ? value : [{ key: "", value: "" }]
  const keyPlaceholder = field.keyPlaceholder ?? labels.kvKeyPlaceholder ?? "Key"
  const valuePlaceholder = field.valuePlaceholder ?? labels.kvValuePlaceholder ?? "Value"
  const merged = { ...labels, kvKeyPlaceholder: keyPlaceholder, kvValuePlaceholder: valuePlaceholder }
  const rowsHTML = rows.map(row => mappingRow(row, field, context, merged)).join("")
  const template = mappingRow({ key: "", value: "" }, field, context, merged)
  return `<div data-key-value-list data-config-input="${escapeHtml(field.name || field.key)}" data-key-placeholder="${escapeHtml(keyPlaceholder)}" data-value-placeholder="${escapeHtml(valuePlaceholder)}" class="flex flex-col gap-1">
      ${rowsHTML}
      <template data-kv-row-template>${template}</template>
      ${addRowButton("addConfigKvRow", escapeHtml(labels.addRowLabel))}
    </div>`
}
