import { escapeHtml } from "utils"
import { resolveControlLabels } from "controllers/property_editor/controls/shared"

/**
 * Searchable reference picker (shadcn combobox pattern). The Stimulus
 * controller `property-editor--controls--reference-picker` fetches A6 once
 * per source and writes the stored id/key into a hidden data-config-input.
 */
export function buildReferencePickerField(field, value, context = {}) {
  const labels = resolveControlLabels(context.labels)
  const key = field.name || field.key
  const source = field.source || ""
  const strValue = value == null ? "" : String(value)
  const shown = strValue || labels.referencePlaceholder
  return `<div data-controller="property-editor--controls--reference-picker"
              data-reference-picker
              data-property-editor--controls--reference-picker-source-value="${escapeHtml(source)}"
              data-property-editor--controls--reference-picker-selected-value="${escapeHtml(strValue)}"
              data-property-editor--controls--reference-picker-search-placeholder-value="${escapeHtml(labels.searchPlaceholder)}"
              data-property-editor--controls--reference-picker-loading-label-value="${escapeHtml(labels.referenceLoadingLabel)}"
              data-property-editor--controls--reference-picker-empty-label-value="${escapeHtml(labels.referenceEmptyLabel)}"
              data-property-editor--controls--reference-picker-error-label-value="${escapeHtml(labels.referenceErrorLabel)}"
              data-property-editor--controls--reference-picker-placeholder-value="${escapeHtml(labels.referencePlaceholder)}"
              class="relative">
      <input type="hidden" data-config-input="${escapeHtml(key)}" data-property-editor--controls--reference-picker-target="hidden" value="${escapeHtml(strValue)}" data-action="change->property-editor#handleConfigFieldChange">
      <button type="button" role="combobox" aria-expanded="false"
              data-property-editor--controls--reference-picker-target="trigger"
              data-action="click->property-editor--controls--reference-picker#toggle"
              class="flex w-full items-center justify-between gap-2 px-2 py-1.5 text-xs bg-white border border-slate-200 rounded-md text-left ${strValue ? "text-slate-800" : "text-slate-400"}">
        <span data-property-editor--controls--reference-picker-target="label" class="truncate">${escapeHtml(shown)}</span>
        <svg class="h-3.5 w-3.5 shrink-0 text-slate-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M8 9l4-4 4 4M8 15l4 4 4-4" />
        </svg>
      </button>
      <div data-property-editor--controls--reference-picker-target="dropdown"
           class="hidden absolute z-50 mt-1 w-full bg-white border border-slate-200 rounded-md shadow-lg">
        <input type="text"
               data-property-editor--controls--reference-picker-target="search"
               data-action="input->property-editor--controls--reference-picker#filter keydown->property-editor--controls--reference-picker#keydown"
               placeholder="${escapeHtml(labels.searchPlaceholder)}"
               class="w-full px-2 py-1.5 text-xs border-0 border-b border-slate-200 rounded-t-md placeholder:text-slate-400 focus:outline-none focus:ring-0">
        <div data-property-editor--controls--reference-picker-target="status"
             class="px-2 py-2 text-[11px] text-slate-400"></div>
        <div data-property-editor--controls--reference-picker-target="list"
             class="max-h-48 overflow-y-auto"></div>
      </div>
    </div>`
}
