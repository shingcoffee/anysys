/**
 * Step item template builder.
 * Covers: buildStepItemTemplate.
 */

import { escapeHtml } from "utils"
import { buildCompactItem } from "controllers/property_editor/templates/common"

// English defaults only — this plain module has no controller reference, so
// the caller (StepManager, which has `this.controller`) threads the
// translated strings in via the `labels` param, sourced from the matching
// this.controller.*Value on PropertyEditorController. Falling back to these
// defaults keeps existing calls/specs byte-identical when `labels` is
// omitted — mirrors templates/branch.js's DEFAULT_LABELS seam.
const DEFAULT_LABELS = {
  dragToReorderTitle: "Drag to reorder",
  changeButtonLabel: "Change",
  changeActionTitle: "Change action",
  removeButtonLabel: "Remove",
  removeButtonTitle: "Remove step",
  errorBadgeLabel: "Error",
  paramsPrefixLabel: "Params:"
}

/**
 * Build a step item card. Newly-committed steps render expanded; reloaded
 * steps render collapsed.
 * @param {Object} params
 * @param {Object} [params.labels] - Translated label overrides (see DEFAULT_LABELS).
 */
export function buildStepItemTemplate(params) {
  const {
    id = "", index, action, description, actionOptionData, selectionLabels, suboption,
    keywordParams = [], configFieldsHTML = "", currentConfig = {}, expanded = false,
    labels = {}
  } = params
  const t = { ...DEFAULT_LABELS, ...labels }

  const colorName = actionOptionData?.color || "blue"
  const breadcrumbLabels = Array.isArray(selectionLabels) && selectionLabels.length > 0
    ? selectionLabels
    : [actionOptionData?.label || action]
  const breadcrumbTitle = breadcrumbLabels.join(" › ")

  const keywordParamsHTML = keywordParams.length > 0
    ? `<div class="text-[10px] text-slate-400">${escapeHtml(t.paramsPrefixLabel)} ${keywordParams.map(p => escapeHtml(p)).join(", ")}</div>`
    : ""

  const bodyHTML = `
    <div data-step-details class="${expanded ? "" : "hidden"} pl-6 mt-1.5 pt-1.5 border-t border-slate-100 space-y-2">
      ${configFieldsHTML}
      ${description ? `<div class="text-[10px] text-slate-400">${escapeHtml(description)}</div>` : ""}
      ${keywordParamsHTML}
    </div>
  `

  const leadingHTML = `
    <div class="flex-shrink-0 cursor-grab active:cursor-grabbing text-slate-300 hover:text-slate-500"
         data-drag-handle title="${escapeHtml(t.dragToReorderTitle)}">
      <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M4 8h16M4 16h16" />
      </svg>
    </div>
  `

  const trailingHTML = `
    <span data-step-error-badge class="hidden flex items-center rounded-md border border-red-200 bg-red-50 px-1.5 text-[10px] font-medium text-red-700">${escapeHtml(t.errorBadgeLabel)}</span>
    <button type="button"
            data-action="click->property-editor#changeStep"
            class="inline-flex min-h-10 min-w-10 items-center justify-center rounded-md px-2 text-[11px] font-medium text-indigo-600 hover:bg-indigo-50 hover:text-indigo-700"
            title="${escapeHtml(t.changeActionTitle)}">${escapeHtml(t.changeButtonLabel)}</button>
    <button type="button"
            data-action="click->property-editor#removeStep"
            class="inline-flex min-h-10 min-w-10 flex-shrink-0 items-center justify-center gap-1 rounded-md px-2 text-[11px] font-medium text-red-600 hover:bg-red-50 hover:text-red-700"
            title="${escapeHtml(t.removeButtonTitle)}">
      <svg class="size-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true">
        <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
      </svg>
      <span>${escapeHtml(t.removeButtonLabel)}</span>
    </button>
    <span data-step-expand-icon class="flex-shrink-0 inline-flex">
      <svg class="w-3 h-3 text-slate-300 group-hover:text-slate-500 transition-transform duration-150 ${expanded ? "rotate-90" : ""}"
           fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7" />
      </svg>
    </span>
  `

  const hiddenInputsHTML = `
    <input type="hidden" name="steps[${index}][action]" value="${escapeHtml(action)}">
    <input type="hidden" name="steps[${index}][suboption]" value="${escapeHtml(suboption || "")}">
    <input type="hidden" name="steps[${index}][description]" value="${escapeHtml(description || "")}" data-step-description>
    ${selectionLabels ? `<input type="hidden" name="steps[${index}][selectionLabels]" value="${escapeHtml(JSON.stringify(selectionLabels))}">` : ""}
    <input type="hidden" name="steps[${index}][keywordParams]" value="${escapeHtml(JSON.stringify(keywordParams))}">
    <input type="hidden" name="steps[${index}][config]" value="${escapeHtml(JSON.stringify(currentConfig || {}))}" data-step-config>
  `

  return buildCompactItem({
    accentColor: colorName,
    title: breadcrumbTitle,
    leadingHTML,
    trailingHTML,
    bodyHTML,
    hiddenInputsHTML,
    headerAttrs: `data-action="click->property-editor#toggleStep"`,
    extraClasses: expanded ? "step-expanded" : "",
    extraAttrs: `data-step-item draggable="true" data-step-index="${index}" data-step-id="${escapeHtml(id)}" data-step-action="${escapeHtml(action)}" data-action="dragstart->property-editor#handleStepDragStart dragend->property-editor#handleStepDragEnd"`
  })
}
