import { BaseManager } from "controllers/entity_form/base_manager"

// A status lifecycle is only kept on the choice controls that can carry one.
const LIFECYCLE_HTML_TYPES = ["select", "radio"]

export class SchemaManager extends BaseManager {
  ensureTableExists() {
    const existingTable = this.c.attributesContainerTarget.querySelector('table')
    if (existingTable) {
      if (!existingTable.hasAttribute('data-entity-form-target')) {
        existingTable.setAttribute('data-entity-form-target', 'attributesTable')
      }
      return
    }
    const tableHtml = this.c.templateBuilder.buildTableHtml()
    this.c.attributesContainerTarget.insertAdjacentHTML("beforeend", tableHtml)
  }

  appendAttribute(attribute) {
    this.ensureTableExists()
    const rowHtml = this.c.templateBuilder.buildAttributeRowHtml(attribute)
    const table = this.c.attributesContainerTarget.querySelector('table')
    if (table) {
      const tbody = table.querySelector("tbody")
      if (tbody) tbody.insertAdjacentHTML("beforeend", rowHtml)
    }
    this.regroupAttributeRows()
  }

  updateAttributeRow(row, { name, name_slug, display_label, html_type, description, validators, visibility, validator_apply, editable, group_id, config, type, owner }) {
    const displayHtmlType = this.c.typeManager.formatHtmlTypeName(html_type)
    const normalizedVisibility = this.normalizeVisibility(visibility)
    const normalizedEditable = this.coerceEditable(visibility, editable)
    const normalizedValidatorApply = this.coerceValidatorApply(visibility, validator_apply, normalizedEditable)
    row.setAttribute("data-attr-group-id", group_id || "")

    const nameEl = row.querySelector("[data-field='name']")
    if (nameEl) { nameEl.textContent = name; nameEl.title = name }

    const nameSlugEl = row.querySelector("[data-field='name_slug']")
    if (nameSlugEl) nameSlugEl.textContent = name_slug

    const displayLabelEl = row.querySelector("[data-field='display_label']")
    if (displayLabelEl) { displayLabelEl.textContent = display_label || name; displayLabelEl.title = display_label || name }

    const htmlTypeEl = row.querySelector("[data-field='html_type']")
    if (htmlTypeEl) htmlTypeEl.textContent = displayHtmlType
    this._syncTypeBadge(row, type, htmlTypeEl)
    row.setAttribute("data-attr-type", type || "")

    const validatorsEl = row.querySelector("[data-field='validators']")
    if (validatorsEl) validatorsEl.innerHTML = this.c.templateBuilder.buildValidatorBadgesHtml(validators)

    const visibilityEl = row.querySelector("[data-field='visibility']")
    if (visibilityEl) visibilityEl.innerHTML = this.c.templateBuilder.buildVisibilityBadgesHtml(normalizedVisibility)

    const descriptionEl = row.querySelector("[data-field='description']")
    if (descriptionEl) descriptionEl.innerHTML = this.c.templateBuilder.buildTruncatedDescriptionHtml(description)

    const setInput = (inputType, value) => {
      const input = row.querySelector(`input[data-input="${inputType}"]`)
      if (input) input.value = value
    }
    setInput("name", name)
    setInput("name_slug", name_slug)
    setInput("display_label", display_label || name || "")
    setInput("html_type", html_type || "")
    setInput("type", type || "")
    setInput("description", description || "")
    setInput("validators", JSON.stringify(validators))
    setInput("visibility", JSON.stringify(normalizedVisibility))
    setInput("validator_apply", JSON.stringify(normalizedValidatorApply))
    setInput("editable", JSON.stringify(normalizedEditable))
    setInput("group_id", group_id || "")
    setInput("config", JSON.stringify(config || null))
    setInput("owner", owner === true ? "true" : "")
    row.setAttribute("data-attr-visibility", JSON.stringify(normalizedVisibility))
    row.setAttribute("data-attr-owner", owner === true ? "true" : "")
    row.setAttribute("data-attr-validator-apply", JSON.stringify(normalizedValidatorApply))
    row.setAttribute("data-attr-editable", JSON.stringify(normalizedEditable))
    this.regroupAttributeRows()
  }

  syncPropertySchema() {
    if (!this.c.hasAttributesContainerTarget || !this.c.hasPropertySchemaTarget) return
    const attributes = this.collectAllAttributes()
    this.c.propertySchemaTarget.value = JSON.stringify(attributes)
  }

  collectAttributes() {
    this.syncPropertySchema()
    this.syncAssociationsSchema()
  }

  collectAllAttributes() {
    if (!this.c.hasAttributesContainerTarget) return []
    const items = this.c.attributesContainerTarget.querySelectorAll("[data-attribute-item]")
    return Array.from(items).map(item => this.extractAttributeFromRow(item)).filter(Boolean)
  }

  extractAttributeFromRow(row) {
    const getValue = (type) => {
      const input = row.querySelector(`input[data-input="${type}"]`)
      if (input) return input.value.trim()
      const dataAttr = row.getAttribute(`data-attr-${type.replace(/_/g, '-')}`)
      return dataAttr || ""
    }

    const name = getValue("name")
    if (!name) return null

    const config = this.parseConfigJson(getValue("config"))
    const visibility = this.normalizeVisibility(this.parseVisibilityJson(getValue("visibility")))
    const editable = this.coerceEditable(visibility, this.parseVisibilityJson(getValue("editable")))
    const validatorApply = this.coerceValidatorApply(
      visibility,
      this.parseVisibilityJson(getValue("validator_apply")),
      editable
    )
    const displayLabel = getValue("display_label") || name
    const groupId = getValue("group_id")
    const type = getValue("type")

    const attribute = {
      name,
      name_slug: getValue("name_slug") || this.generateSlug(name),
      display_label: displayLabel,
      html_type: getValue("html_type") || "text",
      description: getValue("description"),
      validators: this.parseValidatorsJson(getValue("validators")),
      visibility,
      validator_apply: validatorApply,
      group_id: groupId || null,
      config
    }
    if (type) {
      attribute.type = type
      if (type === "Computed") {
        attribute.readonly = true
        attribute.storage = "computed"
      }
    }
    if (type !== "Computed" && this.shouldStoreEditable(visibility, editable)) {
      attribute.editable = editable
    }
    if (getValue("owner") === "true") attribute.owner = true
    const lifecycle = this.parseConfigJson(getValue("lifecycle"))
    if (lifecycle && !Array.isArray(lifecycle) && LIFECYCLE_HTML_TYPES.includes(attribute.html_type)) {
      attribute.lifecycle = lifecycle
    }
    return attribute
  }

  _syncTypeBadge(row, type, htmlTypeEl) {
    let typeBadge = row.querySelector("[data-field='attr_type']")
    if (type === "Computed") {
      const label = this.c.computedTypeBadgeValue
      if (typeBadge) {
        typeBadge.textContent = label
      } else if (htmlTypeEl) {
        typeBadge = document.createElement("span")
        typeBadge.setAttribute("data-field", "attr_type")
        typeBadge.className = "ml-1 inline-flex items-center px-2 py-0.5 text-xs font-medium text-violet-700 bg-violet-100 rounded"
        typeBadge.textContent = label
        htmlTypeEl.insertAdjacentElement("afterend", typeBadge)
      }
    } else if (typeBadge) {
      typeBadge.remove()
    }
  }

  regroupAttributeRows() {
    if (!this.c.hasAttributesContainerTarget) return
    const table = this.c.attributesContainerTarget.querySelector("table")
    if (!table) return
    const tbody = table.querySelector("tbody")
    if (!tbody) return

    const groups = this.readAttributeGroups()
    const rows = Array.from(tbody.querySelectorAll("[data-attribute-item]"))

    tbody.querySelectorAll("[data-attribute-group-header]").forEach(h => h.remove())

    const groupedRows = new Map()
    groups.forEach(g => groupedRows.set(g.id, []))
    groupedRows.set(null, [])

    rows.forEach(row => {
      const gid = row.getAttribute("data-attr-group-id") || null
      const key = gid && groupedRows.has(gid) ? gid : null
      groupedRows.get(key).push(row)
    })

    groups.forEach(g => {
      const items = groupedRows.get(g.id)
      const headerHtml = this.c.templateBuilder.buildAttributeGroupHeaderHtml(g, items.length)
      tbody.insertAdjacentHTML("beforeend", headerHtml)
      items.forEach(row => tbody.appendChild(row))
    })

    const ungrouped = groupedRows.get(null)
    if (ungrouped.length > 0) {
      const headerHtml = this.c.templateBuilder.buildAttributeGroupHeaderHtml(null, ungrouped.length)
      tbody.insertAdjacentHTML("beforeend", headerHtml)
      ungrouped.forEach(row => tbody.appendChild(row))
    }
  }

  readAttributeGroups() {
    if (!this.c.hasAttributeGroupsInputTarget) return []
    try {
      const parsed = JSON.parse(this.c.attributeGroupsInputTarget.value || "[]")
      return Array.isArray(parsed) ? parsed : []
    } catch { return [] }
  }

  writeAttributeGroups(groups) {
    if (!this.c.hasAttributeGroupsInputTarget) return
    this.c.attributeGroupsInputTarget.value = JSON.stringify(groups)
  }

  syncAttributeGroups() {
    // No DOM-derived state for groups; writes go through writeAttributeGroups directly.
  }

  moveRowTo(rowEl, { groupId, beforeRow }) {
    if (!rowEl) return
    rowEl.setAttribute("data-attr-group-id", groupId || "")
    const groupIdInput = rowEl.querySelector('input[data-input="group_id"]')
    if (groupIdInput) groupIdInput.value = groupId || ""

    if (beforeRow && beforeRow.parentElement) {
      beforeRow.parentElement.insertBefore(rowEl, beforeRow)
    } else {
      const tbody = this.c.attributesContainerTarget.querySelector("table tbody")
      if (tbody) tbody.appendChild(rowEl)
    }
    this.regroupAttributeRows()
    this.syncPropertySchema()
  }

  moveGroupTo(groupId, beforeGroupId) {
    const groups = this.readAttributeGroups()
    const moving = groups.find(g => g.id === groupId)
    if (!moving) return
    const remaining = groups.filter(g => g.id !== groupId)
    const insertAt = beforeGroupId
      ? remaining.findIndex(g => g.id === beforeGroupId)
      : remaining.length
    remaining.splice(insertAt < 0 ? remaining.length : insertAt, 0, moving)
    this.writeAttributeGroups(remaining)
    this.regroupAttributeRows()
  }

  parseVisibilityJson(json) {
    if (!json) return null
    try { const parsed = JSON.parse(json); return parsed && typeof parsed === "object" ? parsed : null }
    catch { return null }
  }

  normalizeVisibility(visibility) {
    const v = visibility && typeof visibility === "object" ? visibility : {}
    return {
      admin: v.admin !== false,
      member: v.member !== false,
      public: v.public !== false
    }
  }

  coerceEditable(visibility, editable) {
    const v = this.normalizeVisibility(visibility)
    const e = this.normalizeVisibility(editable)
    return {
      admin: v.admin && e.admin,
      member: v.member && e.member,
      public: v.public && e.public
    }
  }

  shouldStoreEditable(visibility, editable) {
    const v = this.normalizeVisibility(visibility)
    const e = this.coerceEditable(visibility, editable)
    return (v.admin && !e.admin) || (v.member && !e.member) || (v.public && !e.public)
  }

  coerceValidatorApply(visibility, validatorApply, editable) {
    const v = this.normalizeVisibility(visibility)
    const e = this.normalizeVisibility(editable)
    const a = this.normalizeVisibility(validatorApply)
    return {
      admin: v.admin && e.admin && a.admin,
      member: v.member && e.member && a.member,
      public: v.public && e.public && a.public
    }
  }

  parseValidatorsJson(json) {
    if (!json) return []
    try { const parsed = JSON.parse(json); return Array.isArray(parsed) ? parsed : [] }
    catch { return [] }
  }

  parseConfigJson(json) {
    if (!json || json === "null") return null
    try { const parsed = JSON.parse(json); return parsed && typeof parsed === "object" ? parsed : null }
    catch { return null }
  }

  syncAssociationsSchema() {
    if (!this.c.hasAssociationsSchemaTarget) return
    const associations = this.collectAllAssociations()
    this.c.associationsSchemaTarget.value = JSON.stringify(associations)
  }

  collectAllAssociations() {
    if (!this.c.hasAssociationsContainerTarget) return []
    const items = this.c.associationsContainerTarget.querySelectorAll("[data-association-item]")
    const associations = []
    items.forEach(item => {
      const dataAttr = item.getAttribute("data-association-data")
      if (dataAttr) {
        try { associations.push(JSON.parse(dataAttr)) }
        catch (_error) { /* skip invalid data */ }
      }
    })
    return associations
  }
}
