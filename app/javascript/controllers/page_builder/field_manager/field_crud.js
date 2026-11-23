import { FIELD_TYPE_MAPPING, LAYOUT_DEFAULTS } from "controllers/page_builder/field_manager"

/**
 * FieldCrudMixin provides field creation, duplication, deletion, and related
 * source-order / section-header helpers.
 * Apply to a class using Object.assign(YourClass.prototype, FieldCrudMixin)
 */
export const FieldCrudMixin = {
  createField(data, overrides = null) {
    const id = `field_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`
    const propertyType = data.propertyType || this.mapFieldTypeToPropertyType(data.type)
    const isLayout = propertyType === "layout"
    const layoutDefaults = isLayout ? (LAYOUT_DEFAULTS[data.type] || {}) : {}

    let slug = data.propertySlug || this.generateSlug(data.label || data.type)
    if (isLayout) {
      const existingSlugs = new Set(this.c.allFields.map(f => f.property_slug))
      let baseSlug = slug
      let counter = 1
      while (existingSlugs.has(slug)) {
        slug = `${baseSlug}_${counter}`
        counter++
      }
    }

    const htmlType = isLayout ? null : (data.type === "entity" ? data.htmlType : (data.htmlType || data.type))
    const layout = this.c.layoutTemplateValue
    const hasLayout = layout && Object.keys(layout).length > 0
    const templateWidth = (!isLayout && hasLayout)
      ? (layout.field_width_rules?.[htmlType] || layout.default_width || null)
      : null

    const field = {
      id,
      field_type: data.type,
      property_slug: slug,
      property_type: propertyType,
      label: data.label || this.c.layoutDefaultLabelsValue[data.type] || layoutDefaults.label || this.formatLabel(data.type),
      placeholder: "",
      help_text: "",
      required: false,
      width: templateWidth || data.width || "full",
      order: this.c.fields.length,
      source: data.source || null,
      source_section: data.sourceSection || null
    }

    if (isLayout) {
      field.content = this.c.layoutDefaultContentsValue[data.type] || layoutDefaults.content || ""
      if (data.type === "heading") {
        field.heading_level = layoutDefaults.heading_level || "h3"
      }
      if (data.type === "spacer") {
        field.spacer_height = layoutDefaults.spacer_height || "md"
      }
      if (data.type === "alert") {
        field.alert_variant = layoutDefaults.alert_variant || "info"
      }
      if (data.type === "image") {
        field.image_url = layoutDefaults.image_url || ""
        field.alt_text = layoutDefaults.alt_text || ""
      }
      if (data.type === "quote") {
        field.attribution = layoutDefaults.attribution || ""
      }
      if (data.type === "button") {
        field.button_url = layoutDefaults.button_url || "#"
        field.button_variant = layoutDefaults.button_variant || "primary"
        field.button_size = layoutDefaults.button_size || "md"
        field.alignment = layoutDefaults.alignment || "left"
      }
      if (data.type === "video") {
        field.video_url = layoutDefaults.video_url || ""
        field.alignment = layoutDefaults.alignment || "center"
      }
      if (data.type === "list") {
        field.list_style = layoutDefaults.list_style || "bullet"
      }
      if (data.type === "code_block") {
        field.code_language = layoutDefaults.code_language || ""
      }
      if (data.type === "progress_bar") {
        field.progress_value = layoutDefaults.progress_value ?? 50
        field.progress_color = layoutDefaults.progress_color || "indigo"
      }
      if (data.type === "columns") {
        field.column_layout = layoutDefaults.column_layout || "50-50"
        field.columns = JSON.parse(JSON.stringify(layoutDefaults.columns || [{ fields: [] }, { fields: [] }]))
      }
    }

    // Data field type-specific defaults
    if (!isLayout) {
      // For entity fields, htmlType comes from the entity property schema (no fallback).
      // For non-entity (palette) fields, data.type IS the html type.
      const htmlType = data.type === "entity" ? data.htmlType : (data.htmlType || data.type)
      if (htmlType) field.html_type = htmlType
      if (htmlType === "textarea") field.rows = "3"
      if (htmlType === "range") {
        field.min_value = "0"; field.max_value = "100"; field.step = "1"; field.show_value = true
      }
      if (htmlType === "currency") { field.currency_symbol = "$"; field.decimal_places = "2" }
      if (htmlType === "rating") { field.max_rating = "5"; field.allow_half = false }
      if (htmlType === "switch") { field.on_label = "Yes"; field.off_label = "No" }
      if (data.options && Array.isArray(data.options) && data.options.length > 0) {
        field.options = data.options
      }
      if (data.dynamicOptions && data.dynamicOptions.options_source) {
        field.dynamic_options = data.dynamicOptions
      }
    }

    // Merge any extra saved configuration (e.g. from a field template) on top of
    // the computed defaults, so presets keep their validation/options/placeholder/
    // type-specific settings. Identity/type/slug stay managed so a template can't
    // introduce a duplicate id or a colliding slug.
    if (overrides && typeof overrides === "object") {
      const { id: _id, order: _order, type: _t, field_type: _ft,
              property_type: _pt, property_slug: _ps, ...rest } = overrides
      Object.assign(field, rest)
    }

    return field
  },

  mapFieldTypeToPropertyType(type) {
    return FIELD_TYPE_MAPPING[type] || "string"
  },

  addField(event) {
    const element = event.currentTarget
    const data = {
      type: element.dataset.fieldType,
      label: element.dataset.fieldLabel || element.dataset.propertyName,
      propertySlug: element.dataset.propertySlug,
      propertyType: element.dataset.propertyType,
      htmlType: element.dataset.propertyHtmlType,
      source: element.dataset.source || null,
      sourceSection: element.dataset.sourceSection || null,
      options: element.dataset.fieldOptions ? JSON.parse(element.dataset.fieldOptions) : null,
      dynamicOptions: element.dataset.dynamicOptions ? JSON.parse(element.dataset.dynamicOptions) : null
    }

    if (data.propertySlug && this.getUsedPropertySlugs().has(data.propertySlug)) return
    if (data.type === "entity" && !data.htmlType) return

    const field = this.createField(data)

    this.c.undoRedoManager.saveState()

    // Insert at the correct position based on source section grouping
    this._insertFieldInSourceOrder(field)

    this.renderFields()
    this.selectFieldById(field.id)

    this.c.tabManager.closeAllTabPanels()
  },

  addFieldAtIndex(fieldData, index, overrides = null) {
    const field = this.createField(fieldData, overrides)

    this.c.undoRedoManager.saveState()

    const clampedIndex = Math.min(index, this.c.currentPage.fields.length)
    field.order = clampedIndex
    this.c.currentPage.fields.splice(clampedIndex, 0, field)
    // Re-number all fields to maintain correct order
    this.c.currentPage.fields.forEach((f, i) => { f.order = i })
    this.c.fields = this.c.currentPageFields

    this.renderFields()
    this.selectFieldById(field.id)
  },

  addAllFieldsFromSection(event) {
    event.stopPropagation()
    const section = event.currentTarget.closest("[data-searchable-section]")
    if (!section) return

    const usedSlugs = this.getUsedPropertySlugs()
    const items = section.querySelectorAll(".entity-field-item:not(.entity-field-item--disabled)")
    const newFields = []

    items.forEach(item => {
      const slug = item.dataset.propertySlug
      if (usedSlugs.has(slug)) return

      const htmlType = item.dataset.propertyHtmlType
      if (item.dataset.fieldType === "entity" && !htmlType) return

      newFields.push(this.createField({
        type: item.dataset.fieldType,
        label: item.dataset.propertyName,
        propertySlug: slug,
        propertyType: item.dataset.propertyType,
        htmlType: htmlType,
        source: item.dataset.source || null,
        sourceSection: item.dataset.sourceSection || null,
        options: item.dataset.fieldOptions ? JSON.parse(item.dataset.fieldOptions) : null,
        dynamicOptions: item.dataset.dynamicOptions ? JSON.parse(item.dataset.dynamicOptions) : null
      }))
    })

    if (newFields.length === 0) return

    this.c.undoRedoManager.saveState()

    // For associated entity sections, ensure a section header exists
    const sectionId = section.dataset.searchableSection || ""
    if (sectionId.startsWith("bridge-")) {
      const sourceSection = newFields[0].source_section
      if (sourceSection) {
        this._ensureSectionHeaderInFields(sourceSection)
      }
    }

    newFields.forEach(field => this._insertFieldInSourceOrder(field))
    this.renderFields()
    this.c.tabManager.closeAllTabPanels()
  },

  removeAllFieldsFromSection(event) {
    event.stopPropagation()
    const section = event.currentTarget.closest("[data-searchable-section]")
    if (!section) return

    const sectionSlugs = new Set(
      Array.from(section.querySelectorAll(".entity-field-item"))
        .map(item => item.dataset.propertySlug)
        .filter(Boolean)
    )

    if (sectionSlugs.size === 0) return

    const fieldsToRemove = this.c.allFields.filter(f => f.property_slug && sectionSlugs.has(f.property_slug))
    if (fieldsToRemove.length === 0) return

    this.c.undoRedoManager.saveState()

    const removeIds = new Set(fieldsToRemove.map(f => f.id))

    // Deselect if selected field is being removed
    if (this.c.selectedFieldId && removeIds.has(this.c.selectedFieldId)) {
      this.deselectField()
    }

    // For associated sections, also mark section headers for removal across all pages
    const sectionId = section.dataset.searchableSection || ""
    if (sectionId.startsWith("bridge-")) {
      const firstItem = section.querySelector(".entity-field-item")
      const sourceSection = firstItem?.dataset.sourceSection
      if (sourceSection) {
        for (const page of this.c.configuration.pages) {
          page.fields.forEach(f => {
            if (f.field_type === "section" && f.property_type === "layout" &&
                f.source === "bridge" && f.source_section === sourceSection) {
              removeIds.add(f.id)
            }
          })
        }
      }
    }

    // Remove fields from all pages
    for (const page of this.c.configuration.pages) {
      page.fields = page.fields.filter(f => !removeIds.has(f.id))

      // Remove from column fields
      page.fields.forEach(field => {
        if (field.field_type === "columns" && field.columns) {
          field.columns.forEach(col => {
            col.fields = (col.fields || []).filter(f => !removeIds.has(f.id))
          })
        }
      })

      page.fields.forEach((f, i) => f.order = i)
    }

    // If multiple pages, remove pages that have no input fields left
    this._pruneEmptyPages()

    this.c.fields = this.c.currentPageFields
    this.c.fields.forEach((f, i) => f.order = i)
    this.c.pageManager.renderPageTabs()
    this.renderFields()
  },

  // Produce a property_slug that is unique across all fields, suffixing
  // `_copy`/`_copy_N`. Shared by every duplicate path so two copies never
  // collide on the slug (which maps to the generated form/model attribute).
  _uniqueCopySlug(baseSlug) {
    const clean = String(baseSlug || "field").replace(/_copy(_\d+)?$/, "")
    const existing = new Set(this.c.allFields.map(f => f.property_slug))
    let slug = `${clean}_copy`
    let counter = 2
    while (existing.has(slug)) {
      slug = `${clean}_copy_${counter}`
      counter++
    }
    return slug
  },

  duplicateField() {
    if (!this.c.selectedFieldId) return

    const field = this.c.currentPageFields.find(f => f.id === this.c.selectedFieldId)
    if (!field) return

    this.c.undoRedoManager.saveState()

    const duplicate = {
      ...field,
      id: `field_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      label: this.c.duplicateSuffixFormatValue.replace("{name}", field.label),
      property_slug: this._uniqueCopySlug(field.property_slug),
      order: field.order + 1
    }

    const index = this.c.currentPage.fields.findIndex(f => f.id === this.c.selectedFieldId)
    this.c.currentPage.fields.splice(index + 1, 0, duplicate)
    this.c.fields = this.c.currentPageFields

    this.c.fields.forEach((f, i) => f.order = i)

    this.renderFields()
    this.selectFieldById(duplicate.id)
  },

  deleteField() {
    const sm = this.c.selectionManager
    if (sm.isEmpty) return

    this.c.undoRedoManager.saveState()

    const idsToRemove = sm.getSelectedFieldIds()
    // Resolve the field objects before removal so rule/calculation references
    // (including nested column/group children) can be pruned afterwards.
    const removedFields = idsToRemove.map(id => this.findFieldById(id)).filter(Boolean)
    for (const fieldId of idsToRemove) {
      const topIdx = this.c.currentPage.fields.findIndex(f => f.id === fieldId)
      if (topIdx !== -1) {
        this.c.currentPage.fields.splice(topIdx, 1)
      } else {
        this.removeFieldFromAnyColumn(fieldId)
      }
    }

    this.c.pageManager.pruneReferencesToDeletedFields(removedFields)

    this.c.fields = this.c.currentPageFields
    this.c.fields.forEach((f, i) => f.order = i)

    this.deselectField()
    this.renderFields()
  },

  duplicateSelectedField() {
    this.duplicateField()
  },

  deleteSelectedField() {
    this.c.propertyManager.hideFloatingPanel()
    this.deleteField()
  },

  duplicateFieldFromCard(event) {
    event.stopPropagation()
    const fieldId = event.currentTarget.dataset.fieldId
    const field = this.c.currentPageFields.find(f => f.id === fieldId)
    if (!field) return

    this.c.undoRedoManager.saveState()

    const clone = JSON.parse(JSON.stringify(field))
    clone.id = `field_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`
    clone.property_slug = this._uniqueCopySlug(field.property_slug)

    const idx = this.c.currentPage.fields.indexOf(field)
    this.c.currentPage.fields.splice(idx + 1, 0, clone)
    this.c.fields = this.c.currentPageFields
    this.c.fields.forEach((f, i) => f.order = i)

    this.renderFields()
    this.selectFieldById(clone.id)
    this.c.saveManager.markDirty()
  },

  removeFieldFromCard(event) {
    event.stopPropagation()

    const fieldId = event.currentTarget.dataset.fieldId
    if (!fieldId) return

    this.c.undoRedoManager.saveState()

    if (this.c.selectedFieldId === fieldId) {
      this.deselectField()
    }

    const removedField = this.findFieldById(fieldId)

    const topIdx = this.c.currentPage.fields.findIndex(f => f.id === fieldId)
    if (topIdx !== -1) {
      this.c.currentPage.fields.splice(topIdx, 1)
    } else {
      this.removeFieldFromAnyColumn(fieldId)
    }

    if (removedField) this.c.pageManager.pruneReferencesToDeletedFields([removedField])

    this.c.fields = this.c.currentPageFields
    this.c.fields.forEach((f, i) => f.order = i)

    this.renderFields()
  },

  saveFieldAsTemplate(event) {
    event.stopPropagation()
    const fieldId = event.currentTarget.dataset.fieldId
    const field = this.c.allFields.find(f => f.id === fieldId)
    if (!field) return

    const name = prompt(this.c.templateNamePromptLabelValue)
    if (!name) return

    const config = JSON.parse(JSON.stringify(field))
    delete config.id
    delete config.order

    fetch(`/${this.c.customerIdValue}/admin/maintenance/pages/field_templates`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("[name='csrf-token']")?.content
      },
      body: JSON.stringify({ field_template: { name, configuration: config } })
    })
    .then(r => r.ok ? r.json() : Promise.reject(r))
    .then(() => alert(this.c.templateSavedMsgValue))
    .catch(() => alert(this.c.templateSaveFailedMsgValue))
  },

  ungroupFields(event) {
    event.stopPropagation()
    const groupId = event.currentTarget.dataset.groupId
    const fields = this.c.currentPageFields
    const groupIdx = fields.findIndex(f => f.id === groupId && f.type === "field_group")
    if (groupIdx === -1) return

    this.c.undoRedoManager.saveState()
    const group = fields[groupIdx]
    const ungroupedFields = group.fields || []
    this.c.currentPage.fields.splice(groupIdx, 1, ...ungroupedFields)
    this.c.fields = this.c.currentPageFields
    this.c.fields.forEach((f, i) => f.order = i)
    this.renderFields()
    this.c.saveManager.markDirty()
  },

  findFieldById(fieldId) {
    for (const field of this.c.fields) {
      if (field.id === fieldId) return field
      if (field.field_type === "columns" && field.columns) {
        for (const col of field.columns) {
          const found = (col.fields || []).find(f => f.id === fieldId)
          if (found) return found
        }
      }
      if (field.type === "field_group" && field.fields) {
        const found = field.fields.find(f => f.id === fieldId)
        if (found) return found
      }
    }
    return null
  },

  removeFieldFromAnyColumn(fieldId) {
    for (const field of this.c.fields) {
      if (field.field_type === "columns" && field.columns) {
        for (const col of field.columns) {
          const idx = (col.fields || []).findIndex(f => f.id === fieldId)
          if (idx !== -1) {
            col.fields.splice(idx, 1)
            return true
          }
        }
      }
    }
    return false
  },

  // Check if a section header already exists for an associated source section
  // in the current page fields; if not, insert one at the correct position.
  _ensureSectionHeaderInFields(sectionName) {
    const fields = this.c.currentPage.fields
    const hasHeader = fields.some(f =>
      f.field_type === "section" &&
      f.property_type === "layout" &&
      f.source === "bridge" &&
      f.source_section === sectionName
    )
    if (hasHeader) return

    const header = {
      id: `section_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      field_type: "section",
      property_slug: sectionName.toLowerCase().replace(/\s+/g, '_'),
      property_type: "layout",
      label: sectionName,
      placeholder: "",
      help_text: "",
      required: false,
      width: "full",
      order: 0,
      source: "bridge",
      source_section: sectionName
    }

    // Insert at end (fields will follow via _insertFieldInSourceOrder)
    fields.push(header)
    this.c.fields = this.c.currentPageFields
  },

  // Insert a field at the correct position based on its source/source_section,
  // placing it at the end of its source group.
  _insertFieldInSourceOrder(field) {
    const fields = this.c.currentPage.fields
    const source = field.source
    const section = field.source_section

    if (source === "bridge" && section) {
      // Find the last field in this associated section
      let lastIdx = -1
      for (let i = fields.length - 1; i >= 0; i--) {
        if (fields[i].source === "bridge" && fields[i].source_section === section) {
          lastIdx = i
          break
        }
      }
      if (lastIdx >= 0) {
        fields.splice(lastIdx + 1, 0, field)
      } else {
        // No existing fields for this section - append at the end
        fields.push(field)
      }
    } else {
      // Entity field: insert after the last entity-source field (before first associated section)
      let insertIdx = fields.length
      for (let i = 0; i < fields.length; i++) {
        if (fields[i].source === "bridge") {
          insertIdx = i
          break
        }
      }
      fields.splice(insertIdx, 0, field)
    }

    this.c.fields = this.c.currentPageFields
  },

  _pageHasInputFields(page) {
    return (page.fields || []).some(f => {
      if (f.field_type === "columns") {
        return (f.columns || []).some(col =>
          (col.fields || []).some(cf => cf.property_type !== "layout")
        )
      }
      return f.property_type !== "layout"
    })
  },

  _pruneEmptyPages() {
    const pages = this.c.configuration.pages
    if (pages.length <= 1) return

    const pagesToRemove = pages.filter(p => !this._pageHasInputFields(p))

    // Never remove all pages — keep at least one
    if (pagesToRemove.length >= pages.length) return

    const removePageIds = new Set(pagesToRemove.map(p => p.id))
    this.c.configuration.pages = pages.filter(p => !removePageIds.has(p.id))

    // If active page was removed, switch to the first remaining page
    if (removePageIds.has(this.c.activePageValue)) {
      this.c.activePageValue = this.c.configuration.pages[0].id
    }
  }
}
