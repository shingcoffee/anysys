/**
 * Shared chrome for step-form field controls. English defaults stay
 * byte-identical to the Stimulus Values on property_editor_controller.js.
 */
export const FIELD_INPUT_CLASSES =
  "w-full min-w-0 px-2 py-1.5 text-xs border border-slate-200 bg-white rounded-md placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400"

export const DEFAULT_CONTROL_LABELS = {
  noneOptionLabel: "None",
  addRowLabel: "Add row",
  removeRowTitle: "Remove",
  searchPlaceholder: "Search…",
  localeEnLabel: "English",
  localeZhCnLabel: "Chinese",
  referenceLoadingLabel: "Loading…",
  referenceEmptyLabel: "No matches",
  referenceErrorLabel: "Could not load options",
  referencePlaceholder: "Select…",
  joinAndLabel: "AND",
  joinOrLabel: "OR",
  valuePlaceholder: "value"
}

export function compactLabels(labels = {}) {
  return Object.fromEntries(
    Object.entries(labels).filter(([, value]) => typeof value === "string" && value !== "")
  )
}

/**
 * Read server-passed translations off the property-editor mount.
 * Missing attributes fall through to DEFAULT_CONTROL_LABELS.
 */
export function labelsFromEditor(root = document) {
  const el = root.querySelector?.("[data-controller~='property-editor']")
  if (!el) return {}
  const d = el.dataset
  return compactLabels({
    noneOptionLabel: d.propertyEditorNoneOptionLabelValue,
    addRowLabel: d.propertyEditorAddRowLabelValue,
    removeRowTitle: d.propertyEditorRemoveRowTitleValue,
    searchPlaceholder: d.propertyEditorSearchPlaceholderValue,
    localeEnLabel: d.propertyEditorLocaleEnLabelValue,
    localeZhCnLabel: d.propertyEditorLocaleZhCnLabelValue,
    referenceLoadingLabel: d.propertyEditorReferenceLoadingLabelValue,
    referenceEmptyLabel: d.propertyEditorReferenceEmptyLabelValue,
    referenceErrorLabel: d.propertyEditorReferenceErrorLabelValue,
    referencePlaceholder: d.propertyEditorReferencePlaceholderValue,
    joinAndLabel: d.propertyEditorJoinAndLabelValue,
    joinOrLabel: d.propertyEditorJoinOrLabelValue,
    valuePlaceholder: d.propertyEditorValuePlaceholderValue
  })
}

export function resolveControlLabels(labels = {}, root = document) {
  return { ...DEFAULT_CONTROL_LABELS, ...labelsFromEditor(root), ...compactLabels(labels) }
}

export function entityColumns(entityAttributes) {
  return (entityAttributes || [])
    .map(attr => ({
      slug: typeof attr === "string" ? attr : (attr.name_slug || attr.name || String(attr)),
      label: typeof attr === "string" ? attr : (attr.name || attr.name_slug || String(attr))
    }))
    .filter(c => Boolean(c.slug))
}

export function addRowButton(action, label) {
  return `<button type="button"
              data-action="click->property-editor#${action}"
              class="mt-1 inline-flex items-center px-2 py-0.5 text-xs font-medium text-indigo-600 hover:text-indigo-700 hover:bg-indigo-50 rounded transition-colors">
        <svg class="w-3 h-3 mr-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
        </svg>
        ${label}
      </button>`
}
