/**
 * Action catalog store.
 *
 * The editor installs the server export once via `setActionCatalog(json)`
 * (flowchart-canvas connect, parent of the property editor — see
 * `_editor.html.erb`). Until that call the store is empty and lookups
 * return undefined / [].
 *
 * Installed actions are the export's objects: key, label, description,
 * icon, color, singleUse, privileged, aliases, fields, capabilities.
 * Unknown keys on those objects are ignored (kept but never read).
 */

let activeCategories = []
let activeCategoryActionMap = {}
let activeAllActions = []
let activeActionMap = Object.create(null)

function isCatalog(json) {
  return json
    && typeof json === "object"
    && Array.isArray(json.categories)
    && Array.isArray(json.actions)
}

function resetEmpty() {
  activeCategories = []
  activeCategoryActionMap = {}
  activeAllActions = []
  activeActionMap = Object.create(null)
}

/**
 * Install (or clear) the catalog. `null` / `undefined` empties the store.
 * Objects that lack `categories` and `actions` arrays are ignored.
 * @param {Object|null|undefined} json
 */
export function setActionCatalog(json) {
  if (json == null) {
    resetEmpty()
    return
  }
  if (!isCatalog(json)) return

  const categories = []
  const seenCategory = Object.create(null)
  json.categories.forEach((raw) => {
    if (!raw || typeof raw !== "object") return
    const key = typeof raw.key === "string" ? raw.key : ""
    if (!key || seenCategory[key]) return
    seenCategory[key] = true
    categories.push({ key, label: typeof raw.label === "string" ? raw.label : key })
  })

  const actions = []
  const byKey = Object.create(null)
  json.actions.forEach((raw) => {
    if (!raw || typeof raw !== "object") return
    const key = typeof raw.key === "string" ? raw.key : ""
    if (!key || byKey[key]) return
    const action = raw
    actions.push(action)
    byKey[key] = action
    const aliases = Array.isArray(raw.aliases) ? raw.aliases : []
    aliases.forEach((alias) => {
      if (typeof alias === "string" && alias && !byKey[alias]) byKey[alias] = action
    })
  })

  const categoryActionMap = {}
  categories.forEach((cat) => { categoryActionMap[cat.key] = [] })
  actions.forEach((action) => {
    const catKey = action.category
    if (!categoryActionMap[catKey]) categoryActionMap[catKey] = []
    categoryActionMap[catKey].push(action)
  })

  activeCategories = categories
  activeCategoryActionMap = categoryActionMap
  activeAllActions = actions
  activeActionMap = byKey
}

/**
 * Returns actions grouped by category.
 * Each entry has `{ category: { key, label }, actions: [...] }`.
 */
export function getActionsByCategory() {
  return activeCategories.map((category) => ({
    category,
    actions: activeCategoryActionMap[category.key] || []
  }))
}

/**
 * Case-insensitive search across label, description, and category label.
 * @param {string} query
 * @returns {Array}
 */
export function searchActions(query) {
  if (!query || typeof query !== "string") return activeAllActions

  const term = query.toLowerCase()
  const categoryLabels = Object.fromEntries(
    activeCategories.map((c) => [c.key, (c.label || "").toLowerCase()])
  )

  return activeAllActions.filter((action) => {
    return (
      String(action.label || "").toLowerCase().includes(term) ||
      String(action.description || "").toLowerCase().includes(term) ||
      (categoryLabels[action.category] || "").includes(term)
    )
  })
}

/**
 * Look up a single action by canonical key or alias.
 * @param {string} actionValue
 * @returns {Object|undefined}
 */
export function getActionConfig(actionValue) {
  if (actionValue == null) return undefined
  return activeActionMap[actionValue]
}

/**
 * Canonical keys of every action marked `singleUse: true`.
 * @returns {string[]}
 */
export function getSingleUseActions() {
  return activeAllActions
    .filter((action) => action.singleUse === true)
    .map((action) => action.key)
}

/**
 * Flat array of installed canonical actions (empty before install).
 * @returns {Array}
 */
export function getAllActions() {
  return activeAllActions
}

/**
 * Installed category descriptors (empty before install).
 * @returns {Array<{key: string, label: string}>}
 */
export function getActionCategories() {
  return activeCategories
}

/**
 * Field list for an installed action (export `fields`). Empty array when missing.
 */
export function actionFields(action) {
  return Array.isArray(action?.fields) ? action.fields : []
}

/**
 * Field identity on an export field (`name`) or a test fake (`key`).
 */
export function fieldName(field) {
  return field?.name || field?.key
}
