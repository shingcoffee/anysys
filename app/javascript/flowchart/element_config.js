/**
 * Catalog-driven element-property helpers.
 *
 * `CodeGenerators::ElementCatalog.export` (installed via
 * `setElementCatalog`) is the source of truth for what an element type can
 * be configured with. This module derives defaults, coercion, visibility,
 * and the persist allow-list used by the property editor.
 */

import { elementFields, fieldsByName, fieldName } from "flowchart/constants/element_registry"

/** `label` lives on the element itself, never in `properties`. */
const NON_PROPERTY_FIELDS = new Set(["label"])

const PERSIST_EXTRAS = ["description", "io_overrides", "steps", "condition"]

export function schemaFor(elementType) {
  return fieldsByName(elementType)
}

function fieldDefault(field) {
  return field?.default
}

function valueMatches(current, allowed) {
  const matchValues = (Array.isArray(allowed) ? allowed : [allowed]).map(String)
  return matchValues.includes(String(current))
}

function resolveControllingValue(properties, schema, name) {
  const raw = properties?.[name]
  const fallback = fieldDefault(schema?.[name])
  if (raw === undefined || raw === null || raw === "") return fallback ?? ""
  return raw
}

function isLegacyWhen(when) {
  return when && Object.prototype.hasOwnProperty.call(when, "field")
    && (Object.prototype.hasOwnProperty.call(when, "values")
      || Object.prototype.hasOwnProperty.call(when, "value"))
}

/**
 * Resolve a `visibleWhen` clause against a property bag.
 * Accepts the catalog object form `{ otherField: value|[values] }` and the
 * legacy `{ field, value | values }` shape.
 * @param {Object|undefined} visibleWhen
 * @param {Object} properties
 * @param {Object} schema - name-keyed fields, for default fallback
 * @returns {boolean}
 */
export function isFieldApplicable(visibleWhen, properties, schema = {}) {
  if (!visibleWhen) return true

  if (isLegacyWhen(visibleWhen)) {
    const current = resolveControllingValue(properties, schema, visibleWhen.field)
    return valueMatches(current, visibleWhen.values ?? visibleWhen.value)
  }

  return Object.entries(visibleWhen).every(([name, allowed]) => {
    const current = resolveControllingValue(properties, schema, name)
    return valueMatches(current, allowed)
  })
}

export function getDefaultPropertiesForType(elementType) {
  return defaultPropertiesFor(elementType)
}

/**
 * Default properties for a newly-added element, derived from the type's
 * catalog fields. Only fields that apply under those same defaults are
 * seeded. Inputs/outputs are auto-detected and never appear here.
 *
 * @param {string} elementType
 * @returns {Object} a fresh object (never a shared reference)
 */
export function defaultPropertiesFor(elementType) {
  const fields = elementFields(elementType)
  const schema = fieldsByName(elementType)
  const seeded = { description: "" }

  fields.forEach((field) => {
    const name = fieldName(field)
    if (!name || NON_PROPERTY_FIELDS.has(name) || field.visibleWhen) return
    if (field.default !== undefined && field.default !== null) seeded[name] = field.default
  })

  fields.forEach((field) => {
    const name = fieldName(field)
    if (!name || NON_PROPERTY_FIELDS.has(name) || !field.visibleWhen) return
    if (field.default === undefined || field.default === null) return
    if (!isFieldApplicable(field.visibleWhen, seeded, schema)) return
    seeded[name] = field.default
  })

  return seeded
}

function isNumberField(field) {
  return field?.role === "integer" || field?.role === "decimal" || field?.control === "number"
}

function isFlagField(field) {
  return field?.role === "flag" || field?.control === "toggle"
}

/**
 * Coerce catalog number / flag fields. A blank or non-numeric number drops
 * the key entirely rather than persisting `""` or `NaN`.
 * @param {string} elementType
 * @param {Object} properties
 * @returns {Object} a new object; the input is not mutated
 */
export function coerceElementProperties(elementType, properties = {}) {
  const fields = elementFields(elementType)
  const coerced = { ...properties }

  fields.forEach((field) => {
    const name = fieldName(field)
    if (!name || !(name in coerced)) return

    if (isNumberField(field)) {
      const raw = coerced[name]
      if (typeof raw === "number") {
        if (!Number.isFinite(raw)) delete coerced[name]
        return
      }
      const trimmed = String(raw ?? "").trim()
      if (trimmed === "") {
        delete coerced[name]
        return
      }
      const parsed = Number(trimmed)
      if (Number.isFinite(parsed)) coerced[name] = parsed
      else delete coerced[name]
      return
    }

    if (isFlagField(field)) {
      const raw = coerced[name]
      if (raw === true || raw === "true" || raw === "on" || raw === "1") coerced[name] = true
      else if (raw === false || raw === "false" || raw === "off" || raw === "0" || raw === "") coerced[name] = false
    }
  })

  return coerced
}

/**
 * Drop properties whose catalog `visibleWhen` is not satisfied.
 * @param {string} elementType
 * @param {Object} properties
 * @returns {Object} a new object; the input is not mutated
 */
export function pruneInapplicableProperties(elementType, properties = {}) {
  const schema = fieldsByName(elementType)
  const pruned = { ...properties }

  Object.entries(schema).forEach(([name, field]) => {
    if (!field.visibleWhen || !(name in pruned)) return
    if (isFieldApplicable(field.visibleWhen, properties, schema)) return
    delete pruned[name]
  })

  return pruned
}

/**
 * Persist allow-list: visible catalog fields plus notes, I/O overrides,
 * steps, and condition (when visible). Unknown legacy keys are dropped.
 * @param {string} elementType
 * @param {Object} properties
 * @returns {Object}
 */
export function persistableProperties(elementType, properties = {}) {
  const schema = fieldsByName(elementType)
  const visible = pruneInapplicableProperties(elementType, properties)
  const allowed = new Set(PERSIST_EXTRAS)
  Object.keys(schema).forEach((name) => {
    if (!NON_PROPERTY_FIELDS.has(name)) allowed.add(name)
  })

  const out = {}
  allowed.forEach((key) => {
    if (key in visible) out[key] = visible[key]
  })

  const conditionField = schema.condition
  if (conditionField && !isFieldApplicable(conditionField.visibleWhen, properties, schema)) {
    delete out.condition
  }

  return coerceElementProperties(elementType, out)
}

/**
 * Full normalisation pass for properties collected from the editor form.
 * Live sync keeps hidden-mode values; Save (`persist: true`) writes only
 * the visible allow-list.
 * @param {string} elementType
 * @param {Object} properties
 * @param {{persist?: boolean}} [options]
 * @returns {Object}
 */
export function normalizeElementProperties(elementType, properties = {}, options = {}) {
  const coerced = coerceElementProperties(elementType, properties)
  if (options.persist) return persistableProperties(elementType, coerced)
  return coerced
}

/**
 * Read a property as an integer regardless of whether it arrived as a number
 * or as the string a FormData round-trip produces. Returns null when the
 * value is absent, blank, or not a whole number.
 * @param {Object} properties
 * @param {string} key
 * @returns {number|null}
 */
export function intProperty(properties, key) {
  const raw = properties?.[key]
  if (raw === undefined || raw === null) return null
  const trimmed = String(raw).trim()
  if (trimmed === "") return null
  if (!/^-?\d+$/.test(trimmed)) return null
  return Number(trimmed)
}

/**
 * Whether a property holds a non-blank value. Numbers (including 0) count as
 * present; `null`, `undefined`, and whitespace-only strings do not.
 * @param {Object} properties
 * @param {string} key
 * @returns {boolean}
 */
export function hasValue(properties, key) {
  const raw = properties?.[key]
  if (raw === undefined || raw === null) return false
  if (typeof raw === "number") return Number.isFinite(raw)
  if (Array.isArray(raw)) return raw.length > 0
  return String(raw).trim() !== ""
}

/** The declared catalog default for a field, or undefined. */
export function schemaDefault(elementType, fieldKey) {
  return schemaFor(elementType)[fieldKey]?.default
}
