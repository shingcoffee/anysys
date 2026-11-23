/**
 * BreadcrumbMixin provides breadcrumb navigation rendering and interaction
 * for the property panel.
 * Apply to a class using Object.assign(YourClass.prototype, BreadcrumbMixin)
 */
export const BreadcrumbMixin = {
  _renderBreadcrumb(field) {
    if (!this.c.hasBreadcrumbBarTarget) return

    const trail = this._buildBreadcrumbTrail(field)

    if (trail.length <= 1) {
      this.c.breadcrumbBarTarget.classList.add("hidden")
      return
    }

    this.c.breadcrumbBarTarget.classList.remove("hidden")

    const html = trail.map((item, idx) => {
      const isLast = idx === trail.length - 1
      const chevron = isLast ? "" : '<svg class="w-3 h-3 text-gray-300 mx-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/></svg>'

      if (isLast) {
        return `<span class="text-gray-700 font-medium truncate">${item.label}</span>`
      }
      return `<button type="button" class="hover:text-indigo-600 transition-colors truncate"
                      data-action="click->page-builder#breadcrumbNavigate mouseenter->page-builder#breadcrumbHighlight mouseleave->page-builder#breadcrumbUnhighlight"
                      data-field-id="${item.id || ''}">${item.label}</button>${chevron}`
    }).join("")

    this.c.breadcrumbContentTarget.innerHTML = html
  },

  _buildBreadcrumbTrail(field) {
    const trail = []
    const pageName = this.c.currentPage?.name || this.c.breadcrumbPageFallbackValue
    trail.push({ label: pageName, id: null })

    const fields = this.c.currentPageFields

    // Check if field is inside a field_group
    for (const f of fields) {
      if (f.type === "field_group" && f.fields) {
        const child = f.fields.find(cf => cf.id === field.id)
        if (child) {
          trail.push({ label: f.label || this.c.fieldGroupLabelValue, id: f.id })
          break
        }
      }

      // Check if field is inside columns
      if (f.field_type === "columns" && f.columns) {
        for (let colIdx = 0; colIdx < f.columns.length; colIdx++) {
          const col = f.columns[colIdx]
          if (col.fields?.find(cf => cf.id === field.id)) {
            trail.push({ label: f.label || this.c.breadcrumbColumnsLabelValue, id: f.id })
            trail.push({ label: this.c.breadcrumbColumnNumberFormatValue.replace("{number}", colIdx + 1), id: `${f.id}_col_${colIdx}` })
            break
          }
        }
      }
    }

    // Check if field is inside a section (section is a visual grouping marker)
    for (let i = 0; i < fields.length; i++) {
      if (fields[i].field_type === "section") {
        const sectionIdx = i
        const fieldIdx = fields.findIndex(ff => ff.id === field.id)
        if (fieldIdx > sectionIdx) {
          const nextSection = fields.slice(sectionIdx + 1).find(nf => nf.field_type === "section")
          const nextIdx = nextSection ? fields.indexOf(nextSection) : fields.length
          if (fieldIdx < nextIdx) {
            trail.push({ label: fields[i].label || this.c.breadcrumbSectionLabelValue, id: fields[i].id })
            break
          }
        }
      }
    }

    trail.push({ label: field.label || field.field_type, id: field.id })
    return trail
  },

  breadcrumbNavigate(event) {
    const fieldId = event.currentTarget.dataset.fieldId
    if (fieldId) this.c.fieldManager.selectFieldById(fieldId)
  },

  breadcrumbHighlight(event) {
    const fieldId = event.currentTarget.dataset.fieldId
    if (!fieldId) return
    const card = this.c.fieldsContainerTarget.querySelector(`[data-field-id="${fieldId}"]`)
    if (card) card.classList.add("ring-2", "ring-indigo-300", "ring-offset-1")
  },

  breadcrumbUnhighlight(event) {
    const fieldId = event.currentTarget.dataset.fieldId
    if (!fieldId) return
    const card = this.c.fieldsContainerTarget.querySelector(`[data-field-id="${fieldId}"]`)
    if (card) card.classList.remove("ring-2", "ring-indigo-300", "ring-offset-1")
  }
}
