/**
 * Element label helpers shared by every path that creates an element (palette
 * add, insert-next-to, edge "+" insert, paste/duplicate) and by the
 * duplicate-label auto-fix.
 */

export const DEFAULT_UNIQUE_LABEL_FORMAT = "{label} {n}"

const escapeRegExp = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")

const normalize = (label) => String(label ?? "").trim().toLowerCase()

/** The `{label}` part of a label already in `format`, e.g. "End" for "End 2". */
function labelRoot(label, format) {
  const pattern = escapeRegExp(format)
    .replace(escapeRegExp("{label}"), "(.+)")
    .replace(escapeRegExp("{n}"), "\\d+")
  const match = label.match(new RegExp(`^${pattern}$`))
  return match ? match[1].trim() : label
}

/**
 * `base` when no element in `elements` uses it (case-insensitive), otherwise
 * the first free `format` label counting from 2 — "End", "End 2", "End 3".
 * A base already in `format` restarts from its root ("End 2" → "End 3").
 * Blank labels are never duplicates, so a blank base comes back unchanged.
 * @param {Array<{label: string}>} elements - elements whose labels are taken
 * @param {string} base - the wanted label
 * @param {string} [format] - translated "{label} {n}" template
 * @returns {string}
 */
export function uniqueLabel(elements, base, format = DEFAULT_UNIQUE_LABEL_FORMAT) {
  const label = String(base ?? "").trim()
  const taken = new Set((elements || []).map(el => normalize(el.label)))
  if (!label || !taken.has(normalize(label))) return label

  const template = format?.includes("{n}") ? format : DEFAULT_UNIQUE_LABEL_FORMAT
  const root = labelRoot(label, template)
  const build = (n) => template.replace("{n}", String(n)).replace("{label}", () => root)
  let n = 2
  while (taken.has(normalize(build(n)))) n += 1
  return build(n)
}
