import { escapeHtml } from "utils"

export const NO_PRODUCER_SENTINEL = "__none__"

// English defaults only — this plain module has no controller reference, so
// the caller (ElementIoManager, which has `this.controller`) threads the
// translated strings in via the `labels` param on each exported builder,
// sourced from the matching this.controller.*Value on PropertyEditorController.
// Falling back to these defaults keeps existing calls/specs byte-identical
// when `labels` is omitted — mirrors templates/branch.js's DEFAULT_LABELS seam.
const DEFAULT_LABELS = {
  inputsLabel: "Inputs",
  outputsLabel: "Outputs",
  noInputsLabel: "No inputs detected",
  noOutputsLabel: "No outputs detected",
  renamedTitle: "Auto-renamed to avoid a key collision",
  renamedBadgeLabel: "renamed",
  configSourceTitle: "Driven by a config expression",
  configSourceLabel: "config",
  autoSourceTitle: "Generator-supplied literal",
  autoSourceLabel: "auto",
  noProducerLabel: "— no producer —",
  producerAriaLabelFormat: "Producer for {pin}"
}

const SELECT_CLASS = "w-full px-2 py-1.5 text-xs border border-slate-200 bg-white rounded-md placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400"

// Directional glyphs encode flow: data arrives at Inputs, data leaves Outputs.
const ICON_INBOUND = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="w-3 h-3"><path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4"/><polyline points="10 17 15 12 10 7"/><line x1="15" y1="12" x2="3" y2="12"/></svg>`
const ICON_OUTBOUND = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="w-3 h-3"><path d="M9 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>`
const ICON_LINK = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="w-3 h-3 flex-shrink-0"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/></svg>`
const ICON_RENAME = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="w-2.5 h-2.5 flex-shrink-0"><polyline points="17 1 21 5 17 9"/><path d="M3 11V9a4 4 0 0 1 4-4h14"/><polyline points="7 23 3 19 7 15"/><path d="M21 13v2a4 4 0 0 1-4 4H3"/></svg>`

/**
 * Section header: tinted directional icon + label + a count chip.
 * @param {string} label
 * @param {number} count
 * @param {"in"|"out"} direction
 */
function renderSectionHeader(label, count, direction) {
  const isIn = direction === "in"
  const iconWrap = isIn
    ? "bg-indigo-50 text-indigo-500 ring-1 ring-indigo-100"
    : "bg-emerald-50 text-emerald-600 ring-1 ring-emerald-100"
  const icon = isIn ? ICON_INBOUND : ICON_OUTBOUND
  return `
    <div class="flex items-center justify-between mb-2">
      <div class="flex items-center gap-1.5">
        <span class="flex items-center justify-center w-5 h-5 rounded-md ${iconWrap}">${icon}</span>
        <span class="text-xs font-semibold text-slate-700">${escapeHtml(label)}</span>
      </div>
      <span class="text-[10px] font-semibold text-slate-500 bg-slate-100 px-1.5 py-0.5 rounded-full tabular-nums leading-none">${count}</span>
    </div>`
}

function renderEmptyState(label) {
  return `
    <div class="flex flex-col items-center justify-center gap-1 rounded-lg border border-dashed border-slate-200 bg-slate-50/40 py-4 text-center">
      <span class="text-slate-300">${ICON_LINK}</span>
      <p class="text-[11px] text-slate-400">${escapeHtml(label)}</p>
    </div>`
}

/**
 * Renders the full Inputs section HTML.
 * @param {Array} inputPins - Array of {pin, source} objects from IoExtractor
 * @param {Array} overrideList - Array of {pin, override_key} objects
 * @param {Function} renderRow - closure of form (pin, overrideList) => string
 * @param {Object} [labels] - Translated label overrides (see DEFAULT_LABELS).
 * @returns {string}
 */
export function renderInputsSection(inputPins, overrideList, renderRow, labels = {}) {
  const t = { ...DEFAULT_LABELS, ...labels }
  const body = inputPins.length === 0
    ? renderEmptyState(t.noInputsLabel)
    : `<div class="space-y-1.5">${inputPins.map((p) => renderRow(p, overrideList)).join("")}</div>`

  return `
    <section data-element-io-inputs>
      ${renderSectionHeader(t.inputsLabel, inputPins.length, "in")}
      ${body}
    </section>`
}

/**
 * Renders the full Outputs section HTML.
 * @param {Array} outputPins - Array of {pin} objects
 * @param {Array} overrideList - Array of {pin, renamed_to} objects
 * @param {Object} [labels] - Translated label overrides (see DEFAULT_LABELS).
 * @returns {string}
 */
export function renderOutputsSection(outputPins, overrideList, labels = {}) {
  const t = { ...DEFAULT_LABELS, ...labels }
  const body = outputPins.length === 0
    ? renderEmptyState(t.noOutputsLabel)
    : `<div class="space-y-1.5">${outputPins.map((p) => renderOutputRow(p, overrideList, t)).join("")}</div>`

  return `
    <section data-element-io-outputs class="mt-4 pt-4 border-t border-slate-100">
      ${renderSectionHeader(t.outputsLabel, outputPins.length, "out")}
      ${body}
    </section>`
}

// Port marker dot — a small ringed node echoing a connection port.
function portDot(tone) {
  const cls = tone === "out"
    ? "bg-emerald-400 ring-emerald-100"
    : "bg-indigo-400 ring-indigo-100"
  return `<span class="flex-shrink-0 h-2 w-2 rounded-full ring-2 ${cls}"></span>`
}

function renderOutputRow(outputPin, overrideList, t) {
  const rename = overrideList.find((o) => o.pin === outputPin.pin)?.renamed_to
  const badge = rename
    ? `<span class="ml-auto inline-flex items-center gap-1 text-[10px] font-medium bg-amber-50 text-amber-700 px-1.5 py-0.5 rounded-md border border-amber-200" title="${escapeHtml(t.renamedTitle)}" data-element-io-renamed>${ICON_RENAME}<span>${escapeHtml(t.renamedBadgeLabel)}</span><span class="font-mono text-amber-800">${escapeHtml(rename)}</span></span>`
    : ""
  return `
    <div class="group flex items-center gap-2 rounded-lg border border-slate-200 bg-white px-2.5 py-1.5 transition-colors hover:border-slate-300 hover:bg-slate-50/60" data-element-io-output data-pin="${escapeHtml(outputPin.pin)}">
      ${portDot("out")}
      <span class="font-mono text-xs font-medium text-slate-800 truncate">${escapeHtml(outputPin.pin)}</span>
      ${badge}
    </div>`
}

/**
 * Renders the source badge for an input pin.
 */
function renderSourceBadge(source, t) {
  if (source === "config_expr") {
    return `<span class="ml-auto text-[9px] font-semibold uppercase tracking-wide px-1.5 py-0.5 rounded bg-indigo-50 text-indigo-700 border border-indigo-100" title="${escapeHtml(t.configSourceTitle)}">${escapeHtml(t.configSourceLabel)}</span>`
  }
  if (source === "generator_literal") {
    return `<span class="ml-auto text-[9px] font-semibold uppercase tracking-wide px-1.5 py-0.5 rounded bg-slate-50 text-slate-500 border border-slate-200" title="${escapeHtml(t.autoSourceTitle)}">${escapeHtml(t.autoSourceLabel)}</span>`
  }
  return ""
}

/**
 * Renders a read-only input pin row (0 or 1 real candidate).
 * @param {Object} pin
 * @param {Object} [labels] - Translated label overrides (see DEFAULT_LABELS).
 */
export function renderReadOnlyInputRow(pin, labels = {}) {
  const t = { ...DEFAULT_LABELS, ...labels }
  return `
    <div class="group flex items-center gap-2 rounded-lg border border-slate-200 bg-white px-2.5 py-1.5 transition-colors hover:border-slate-300 hover:bg-slate-50/60" data-element-io-input data-pin="${escapeHtml(pin.pin)}">
      ${portDot("in")}
      <span class="font-mono text-xs font-medium text-slate-800 truncate">${escapeHtml(pin.pin)}</span>
      ${renderSourceBadge(pin.source, t)}
    </div>`
}

/**
 * Renders an editable input pin row with producer <select> (2+ real candidates).
 * @param {Object} [labels] - Translated label overrides (see DEFAULT_LABELS).
 */
export function renderEditableInputRow(pin, externals, selfs, selectedKey, labels = {}) {
  const t = { ...DEFAULT_LABELS, ...labels }
  const wired = selectedKey != null && selectedKey !== ""
  const options = [
    `<option value="${NO_PRODUCER_SENTINEL}" ${wired ? "" : "selected"}>${escapeHtml(t.noProducerLabel)}</option>`
  ]
  for (const cand of externals) {
    const selected = selectedKey === cand.effective ? "selected" : ""
    options.push(
      `<option value="${escapeHtml(cand.effective)}" ${selected}>${escapeHtml(cand.label)} • ${escapeHtml(cand.effective)}</option>`
    )
  }
  for (const cand of selfs) {
    const selected = selectedKey === cand.effective ? "selected" : ""
    options.push(
      `<option value="${escapeHtml(cand.effective)}" ${selected}>${escapeHtml(cand.label)} • ${escapeHtml(cand.effective)} (self)</option>`
    )
  }

  const linkTone = wired ? "text-indigo-500" : "text-slate-400"

  return `
    <div class="rounded-lg border border-slate-200 bg-white px-2.5 py-2 transition-colors hover:border-slate-300" data-element-io-input data-pin="${escapeHtml(pin.pin)}">
      <div class="flex items-center gap-2">
        ${portDot("in")}
        <span class="font-mono text-xs font-medium text-slate-800 truncate">${escapeHtml(pin.pin)}</span>
        ${renderSourceBadge(pin.source, t)}
      </div>
      <div class="mt-1.5 flex items-center gap-1.5 pl-4">
        <span class="${linkTone}">${ICON_LINK}</span>
        <select class="${SELECT_CLASS} font-mono" data-element-io-producer-select aria-label="${escapeHtml(t.producerAriaLabelFormat.replace("{pin}", pin.pin))}">
          ${options.join("")}
        </select>
      </div>
    </div>`
}
