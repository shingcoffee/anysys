/**
 * Round-3 type-awareness helpers (advisory only — never block, never mutate).
 * Covers: columnTypeOf, looksLikeExpression, buildTypeChip, upsertTypeChip,
 * applySoftTypeValidation, wireSoftTypeValidation.
 */

import { escapeHtml } from "utils"

const SOFT_TYPE_HINT_CLASSES = ["ring-2", "ring-amber-300", "border-amber-400"]
// English default only — this plain module has no controller reference, so
// callers (the shared conditions control, config_fields.js) thread the
// translated string in via the `hintTitle` param. Falling back to this
// constant keeps existing calls/specs byte-identical.
const SOFT_TYPE_HINT_TITLE = "Expected a number or a ctx expression"
const NUMBER_LITERAL_PATTERN = /^-?\d+(\.\d+)?$/

/**
 * Look up a column's type info in an entity schema (canvas.entityAttributes
 * or an entity's property_schema — both carry name/name_slug/type/html_type).
 * @returns {{type: string, htmlType: string}|null} null when unknown — caller
 *   must degrade to today's exact behavior (no chip, no validation).
 */
export function columnTypeOf(schema, slug) {
  if (!slug) return null
  const attr = (schema || []).find(a => a && (a.name_slug || a.name) === slug)
  if (!attr) return null
  return { type: attr.type || "", htmlType: attr.html_type || "" }
}

/**
 * True when a value is a context expression — expressions are ALWAYS valid
 * (round-3 hard constraint: type assistance must never block expressions).
 */
export function looksLikeExpression(value) {
  const v = String(value ?? "").trim()
  // "ctx" only counts as an expression prefix when followed by an accessor —
  // a literal like "ctx_count" (a plausible column slug) is NOT an expression.
  return v === "ctx" || v.startsWith("ctx.") || v.startsWith("ctx[") ||
    v.startsWith("{{") || v.startsWith("$") || v.includes("[:")
}

/**
 * Small advisory type chip (e.g. "number"). Returns "" when htmlType is
 * empty so degraded paths emit no markup at all.
 */
export function buildTypeChip(htmlType) {
  if (!htmlType) return ""
  return `<span data-type-chip class="ml-1 inline-flex items-center px-1 py-px text-xs font-medium text-slate-500 bg-slate-100 border border-slate-200 rounded align-middle">${escapeHtml(htmlType)}</span>`
}

/**
 * Insert/update/remove the type chip inside a container element.
 * Empty htmlType removes the chip (degradation → today's markup).
 */
export function upsertTypeChip(container, htmlType) {
  if (!container) return
  const existing = container.querySelector("[data-type-chip]")
  if (!htmlType) { existing?.remove(); return }
  if (existing) { existing.textContent = htmlType; return }
  container.insertAdjacentHTML("beforeend", buildTypeChip(htmlType))
}

/**
 * Soft validation: amber ring + title hint, applied only when the expected
 * html_type is "number" and the value is neither empty, a numeric literal,
 * nor an expression. NEVER blocks save, NEVER clears the value. Other
 * html_types (text/select/…) are never validated — chip only.
 */
export function applySoftTypeValidation(input, htmlType, hintTitle = SOFT_TYPE_HINT_TITLE) {
  if (!input) return
  const value = String(input.value ?? "").trim()
  const needsHint =
    htmlType === "number" &&
    value !== "" &&
    !NUMBER_LITERAL_PATTERN.test(value) &&
    !looksLikeExpression(value)

  SOFT_TYPE_HINT_CLASSES.forEach(cls => input.classList.toggle(cls, needsHint))
  if (needsHint) {
    // Preserve any pre-existing title so clearing the hint restores it.
    if (input.title !== hintTitle && input.dataset.softTypeOrigTitle === undefined) {
      input.dataset.softTypeOrigTitle = input.title || ""
    }
    input.title = hintTitle
  } else if (input.title === hintTitle) {
    input.title = input.dataset.softTypeOrigTitle || ""
    delete input.dataset.softTypeOrigTitle
  }
}

/**
 * Attach (idempotently) a change-time soft validator to a value input and
 * apply it immediately. Empty htmlType clears the expectation and any
 * existing hint. Listener attaches at most once per input (dataset guard);
 * markup is never modified, so degraded paths stay byte-identical.
 */
export function wireSoftTypeValidation(input, htmlType, hintTitle = SOFT_TYPE_HINT_TITLE) {
  if (!input) return
  if (htmlType) {
    input.dataset.expectedType = htmlType
  } else {
    delete input.dataset.expectedType
  }
  if (!input.dataset.softTypeWired) {
    input.dataset.softTypeWired = "1"
    input.addEventListener("change", () => {
      applySoftTypeValidation(input, input.dataset.expectedType || "", hintTitle)
    })
  }
  applySoftTypeValidation(input, htmlType, hintTitle)
}
