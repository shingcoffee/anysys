/**
 * Decision Branches tab row template.
 * One row per outgoing connection: Name, Match value, Otherwise, Remove.
 */

import { escapeHtml } from "utils"
import { FIELD_INPUT_CLASSES } from "controllers/property_editor/controls/shared"

const DEFAULT_LABELS = {
  matchValueLabel: "Match Value",
  matchValuePlaceholder: "e.g. active",
  branchNameLabel: "Branch Name",
  branchNamePlaceholder: "e.g. Active",
  otherwiseLabel: "Otherwise",
  yesMatchLabel: "Yes",
  noMatchLabel: "No",
  removeBranchItemTitle: "Remove branch"
}

/**
 * Build one inline branch row.
 * @param {Object} params
 * @param {Object} [params.labels]
 * @returns {string}
 */
export function buildBranchItemTemplate(params) {
  const {
    index,
    branchValue = "",
    branchElementId = "",
    connectionId = "",
    matchValue = "",
    routeBy = "condition",
    labels = {}
  } = params
  const t = { ...DEFAULT_LABELS, ...labels }
  const otherwise = String(matchValue || "").trim() === ""
  const conditionMode = routeBy === "condition"
  const name = branchValue || ""

  const matchControl = conditionMode
    ? `<select data-branch-match-value
               name="branches[${index}][matchValue]"
               ${otherwise ? "disabled" : ""}
               class="${FIELD_INPUT_CLASSES} ${otherwise ? "hidden" : ""}">
         <option value="true"${matchValue === "true" ? " selected" : ""}>${escapeHtml(t.yesMatchLabel)}</option>
         <option value="false"${matchValue === "false" ? " selected" : ""}>${escapeHtml(t.noMatchLabel)}</option>
       </select>`
    : `<input type="text" data-branch-match-value
              name="branches[${index}][matchValue]"
              value="${escapeHtml(otherwise ? "" : matchValue)}"
              placeholder="${escapeHtml(t.matchValuePlaceholder)}"
              ${otherwise ? "disabled" : ""}
              class="${FIELD_INPUT_CLASSES} ${otherwise ? "hidden" : ""}">`

  return `
    <div data-branch-item data-branch-index="${index}"
         data-connection-id="${escapeHtml(connectionId)}"
         ${branchElementId ? `data-branch-element-id="${escapeHtml(branchElementId)}"` : ""}
         class="flex flex-col gap-2 rounded-md border border-slate-200 bg-white p-2 sm:flex-row sm:items-end">
      <div class="min-w-0 flex-1">
        <label class="mb-1 block text-xs font-medium text-slate-500">${escapeHtml(t.branchNameLabel)}</label>
        <input type="text" data-branch-name
               name="branches[${index}][name]"
               value="${escapeHtml(name)}"
               placeholder="${escapeHtml(t.branchNamePlaceholder)}"
               class="${FIELD_INPUT_CLASSES}">
      </div>
      <div class="min-w-0 flex-1" data-branch-match-wrap>
        <label class="mb-1 block text-xs font-medium text-slate-500">${escapeHtml(t.matchValueLabel)}</label>
        ${matchControl}
      </div>
      <label class="flex items-center gap-1.5 text-xs text-slate-600 sm:pb-1.5">
        <input type="checkbox" data-branch-otherwise
               ${otherwise ? "checked" : ""}
               class="h-3.5 w-3.5 rounded border-slate-300 text-amber-600 focus:ring-amber-500/30">
        ${escapeHtml(t.otherwiseLabel)}
      </label>
      <button type="button"
              data-action="click->property-editor#removeBranch"
              class="inline-flex items-center justify-center self-start rounded-md p-1.5 text-slate-400 hover:bg-red-50 hover:text-red-500 sm:self-end"
              title="${escapeHtml(t.removeBranchItemTitle)}">
        <svg class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
        </svg>
      </button>
      ${branchElementId ? `<input type="hidden" name="branches[${index}][elementId]" value="${escapeHtml(branchElementId)}">` : ""}
      ${connectionId ? `<input type="hidden" name="branches[${index}][connectionId]" value="${escapeHtml(connectionId)}">` : ""}
    </div>
  `
}
