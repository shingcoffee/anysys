/**
 * Element catalog store.
 *
 * The editor installs the server export once via `setElementCatalog(json)`
 * (flowchart-canvas connect, parent of the property editor — see
 * `_editor.html.erb`). Until that call the store is empty and lookups
 * return undefined / [].
 *
 * Installed types are the export's objects: type, label, defaultLabel,
 * tabs, fields. Connection fields, condition operators, and chrome labels
 * come from the same payload.
 */

let active = emptyState()

function emptyState() {
  return {
    types: Object.create(null),
    connection: { fields: [] },
    operators: [],
    chrome: {
      label: { label: "Label" },
      notes: { key: "description", label: "Notes" }
    },
    locale: null,
    digest: null
  }
}

function isCatalog(json) {
  return json
    && typeof json === "object"
    && json.types
    && typeof json.types === "object"
}

function normalizeFields(raw) {
  if (!Array.isArray(raw)) return []
  return raw.filter((field) => field && typeof field === "object" && fieldName(field))
}

function normalizeType(key, raw) {
  if (!raw || typeof raw !== "object") return null
  const type = typeof raw.type === "string" && raw.type ? raw.type : key
  return {
    type,
    label: typeof raw.label === "string" ? raw.label : type,
    defaultLabel: typeof raw.defaultLabel === "string"
      ? raw.defaultLabel
      : (typeof raw.label === "string" ? raw.label : type),
    tabs: Array.isArray(raw.tabs) ? raw.tabs.filter((tab) => typeof tab === "string") : [],
    fields: normalizeFields(raw.fields)
  }
}

/**
 * Install (or clear) the catalog. `null` / `undefined` empties the store.
 * Objects that lack a `types` object are ignored.
 * @param {Object|null|undefined} json
 */
export function setElementCatalog(json) {
  if (json == null) {
    active = emptyState()
    return
  }
  if (!isCatalog(json)) return

  const types = Object.create(null)
  Object.entries(json.types).forEach(([key, raw]) => {
    if (typeof key !== "string" || !key) return
    const entry = normalizeType(key, raw)
    if (!entry || types[entry.type]) return
    types[entry.type] = entry
  })

  const chrome = json.chrome && typeof json.chrome === "object" ? json.chrome : {}
  const notes = chrome.notes && typeof chrome.notes === "object" ? chrome.notes : {}
  const label = chrome.label && typeof chrome.label === "object" ? chrome.label : {}

  active = {
    types,
    connection: { fields: normalizeFields(json.connection?.fields) },
    operators: Array.isArray(json.operators)
      ? json.operators.filter((op) => op && typeof op === "object" && typeof op.value === "string")
      : [],
    chrome: {
      label: { label: typeof label.label === "string" ? label.label : "Label" },
      notes: {
        key: typeof notes.key === "string" && notes.key ? notes.key : "description",
        label: typeof notes.label === "string" ? notes.label : "Notes"
      }
    },
    locale: typeof json.locale === "string" ? json.locale : null,
    digest: typeof json.digest === "string" ? json.digest : null
  }
}

/**
 * Field identity on an export field (`name`) or a test fake (`key`).
 */
export function fieldName(field) {
  return field?.name || field?.key
}

/**
 * Installed type descriptor, or undefined.
 * @param {string} type
 */
export function elementType(type) {
  if (type == null) return undefined
  return active.types[type]
}

/**
 * Field list for an installed type. Empty array when missing.
 * @param {string} type
 * @returns {Array}
 */
export function elementFields(type) {
  return elementType(type)?.fields || []
}

/**
 * Declared tab keys for an installed type. Empty array when missing.
 * @param {string} type
 * @returns {string[]}
 */
export function elementTabs(type) {
  return elementType(type)?.tabs || []
}

/**
 * Translated type label (header), or undefined.
 * @param {string} type
 */
export function elementLabel(type) {
  return elementType(type)?.label
}

/**
 * Translated default canvas label, or undefined.
 * @param {string} type
 */
export function elementDefaultLabel(type) {
  return elementType(type)?.defaultLabel
}

/**
 * Connection field list (empty before install).
 * @returns {Array}
 */
export function connectionFields() {
  return active.connection.fields
}

/**
 * Condition operators from the catalog (empty before install).
 * @returns {Array<{value: string, label: string, unary?: boolean, count?: boolean}>}
 */
export function conditionOperators() {
  return active.operators
}

/**
 * Chrome labels (`label`, `notes`) from the catalog.
 */
export function chrome() {
  return active.chrome
}

/**
 * Catalog locale string, or null before install.
 */
export function catalogLocale() {
  return active.locale
}

/**
 * Catalog digest string, or null before install.
 */
export function catalogDigest() {
  return active.digest
}

/**
 * Name-keyed field map for a type (empty object when missing).
 * @param {string} type
 * @returns {Object}
 */
export function fieldsByName(type) {
  const map = {}
  elementFields(type).forEach((field) => {
    const name = fieldName(field)
    if (name) map[name] = field
  })
  return map
}

/**
 * Snapshot of every installed type as a name-keyed field map.
 * Used by FlowchartCanvas#elementSchemas.
 * @returns {Object}
 */
export function elementSchemaMap() {
  const map = {}
  Object.keys(active.types).forEach((type) => {
    map[type] = fieldsByName(type)
  })
  return map
}
