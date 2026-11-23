/**
 * Common / shared template builders.
 * Covers: buildEmptyState, buildSectionHeader, buildCompactItem.
 */

import { escapeHtml } from "utils"

/**
 * Build an empty state placeholder matching EmptyStateComponent.
 * @param {string} message - The message to display
 * @param {string|null} iconSvg - Optional icon HTML (not escaped)
 * @returns {string} Empty state HTML
 */
export function buildEmptyState(message, iconSvg = null) {
  return `
    <div class="border border-dashed border-slate-200 rounded-md py-3 text-center">
      ${iconSvg ? `<div class="flex justify-center mb-2">${iconSvg}</div>` : ""}
      <p class="text-[11px] text-slate-400">${escapeHtml(message)}</p>
    </div>
  `.trim()
}

/**
 * Build a section header matching SectionHeaderComponent.
 * @param {Object} params - Section header parameters
 * @param {string} params.label - Section label
 * @param {number|null} params.count - Optional count badge
 * @param {string|null} params.addAction - Optional add button with data-action attribute
 * @param {string} [params.addLabel] - Translated title override for the add
 *   button. English default only — no caller passes addAction today (this
 *   branch is unwired), so this completes the i18n seam for if/when one does,
 *   mirroring the conditionsInlineOperatorLabels pattern on the controller.
 * @returns {string} Section header HTML
 */
export function buildSectionHeader({ label, count = null, addAction = null, addLabel = "Add" }) {
  const countBadge = count !== null
    ? `<span class="inline-flex items-center justify-center min-w-[1.25rem] h-5 px-1.5 text-[10px] font-semibold text-slate-600 bg-slate-100 rounded" data-section-count>${count}</span>`
    : ""

  const addButton = addAction
    ? `<button type="button"
         data-action="${escapeHtml(addAction)}"
         class="inline-flex items-center gap-0.5 px-1.5 py-0.5 text-[10px] font-medium text-indigo-600 hover:text-indigo-700 hover:bg-indigo-50 rounded transition-colors"
         title="${escapeHtml(addLabel)}">
        <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
        </svg>
      </button>`
    : ""

  return `
    <div class="flex items-center justify-between mb-1.5">
      <div class="flex items-center gap-1.5">
        <span class="text-xs font-semibold text-slate-700">${escapeHtml(label)}</span>
        ${countBadge}
      </div>
      ${addButton}
    </div>
  `.trim()
}

/**
 * Unified card used by both step and branch items: accent border, header row
 * (leading | color dot | title + subtitle | trailing actions), optional body
 * and hidden inputs. Trailing actions reveal on hover.
 * @param {Object} params
 * @param {string} params.accentColor - Tailwind color name (e.g. "indigo", "amber")
 * @param {string} params.title - Card title (escaped here)
 * @param {string} params.subtitleHTML - Pre-built HTML under the title (NOT escaped)
 * @param {string} params.leadingHTML - HTML before the color dot (NOT escaped)
 * @param {string} params.trailingHTML - HTML in the trailing actions slot (NOT escaped)
 * @param {string} params.bodyHTML - Expandable/extra body HTML after the header row
 * @param {string} params.hiddenInputsHTML - Hidden form inputs kept inside the card root
 * @param {string} params.headerAttrs - Extra attributes on the header row div
 * @param {string} params.extraClasses - Extra classes on the card root
 * @param {string} params.extraAttrs - Extra attributes on the card root
 * @returns {string}
 */
const ACCENT_COLOR_CLASSES = {
  blue:    { border: "border-blue-400",    dot: "bg-blue-500" },
  cyan:    { border: "border-cyan-400",    dot: "bg-cyan-500" },
  green:   { border: "border-green-400",   dot: "bg-green-500" },
  red:     { border: "border-red-400",     dot: "bg-red-500" },
  indigo:  { border: "border-indigo-400",  dot: "bg-indigo-500" },
  purple:  { border: "border-purple-400",  dot: "bg-purple-500" },
  emerald: { border: "border-emerald-400", dot: "bg-emerald-500" },
  amber:   { border: "border-amber-400",   dot: "bg-amber-500" },
  pink:    { border: "border-pink-400",    dot: "bg-pink-500" },
  teal:    { border: "border-teal-400",    dot: "bg-teal-500" },
  gray:    { border: "border-gray-400",    dot: "bg-gray-500" },
  slate:   { border: "border-slate-400",   dot: "bg-slate-500" }
}

export function buildCompactItem({
  accentColor,
  title,
  subtitleHTML = "",
  leadingHTML = "",
  trailingHTML = "",
  bodyHTML = "",
  hiddenInputsHTML = "",
  headerAttrs = "",
  extraClasses = "",
  extraAttrs = ""
}) {
  const accent = ACCENT_COLOR_CLASSES[accentColor] || ACCENT_COLOR_CLASSES.blue
  return `
    <div class="relative border-l-2 ${accent.border} border-b border-b-slate-100 px-2.5 py-2 hover:bg-slate-50 transition-colors group ${extraClasses}" ${extraAttrs}>
      <div class="flex items-center gap-2" ${headerAttrs}>
        ${leadingHTML}
        <div class="w-2 h-2 rounded-full ${accent.dot} flex-shrink-0"></div>
        <div class="flex-1 min-w-0 cursor-pointer">
          <div class="text-xs font-medium text-slate-800 truncate">${escapeHtml(title)}</div>
          ${subtitleHTML}
        </div>
        <div class="ml-auto flex items-center gap-0.5 flex-shrink-0">${trailingHTML}</div>
      </div>
      ${bodyHTML}
      ${hiddenInputsHTML}
    </div>
  `.trim()
}
