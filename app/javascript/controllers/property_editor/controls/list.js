import { escapeHtml } from "utils"
import { addRowButton, entityColumns, FIELD_INPUT_CLASSES, resolveControlLabels } from "controllers/property_editor/controls/shared"

function itemControl(value, field, context, labels) {
  const str = value == null ? "" : String(value)
  const itemRole = field.itemRole
  const columns = entityColumns(context.entityAttributes)
  if (itemRole === "entity_attribute" && columns.length > 0) {
    const placeholder = labels.selectColumnPlaceholder || "Select column…"
    const options = [`<option value="">${escapeHtml(placeholder)}</option>`]
      .concat(columns.map(c => `<option value="${escapeHtml(c.slug)}"${c.slug === str ? " selected" : ""}>${escapeHtml(c.label)}</option>`))
      .join("")
    return `<select data-list-value class="${FIELD_INPUT_CLASSES}">${options}</select>`
  }
  return `<input type="text" data-list-value value="${escapeHtml(str)}" class="${FIELD_INPUT_CLASSES}">`
}

function listRow(value, field, context, labels) {
  return `<div data-list-row class="flex items-center gap-1.5">
      ${itemControl(value, field, context, labels)}
      <button type="button"
              data-action="click->property-editor#removeConfigListRow"
              class="p-0.5 text-slate-400 hover:text-red-500 hover:bg-red-50 rounded transition-colors flex-shrink-0"
              title="${escapeHtml(labels.removeRowTitle)}">
        <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </div>`
}

export function buildListField(field, value, context = {}) {
  const labels = resolveControlLabels(context.labels)
  const items = Array.isArray(value) && value.length > 0 ? value : [""]
  const rows = items.map(item => listRow(item, field, context, labels)).join("")
  const template = listRow("", field, context, labels)
  return `<div data-list-editor class="flex flex-col gap-1">
      ${rows}
      <template data-list-row-template>${template}</template>
      ${addRowButton("addConfigListRow", escapeHtml(labels.addRowLabel))}
    </div>`
}

export function collectList(listEl) {
  return [...listEl.querySelectorAll("[data-list-row]")]
    .map(row => row.querySelector("[data-list-value]")?.value?.trim())
    .filter(Boolean)
}
