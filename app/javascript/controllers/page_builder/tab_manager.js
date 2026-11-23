import { BaseManager } from "controllers/page_builder/base_manager"

const HTML_TYPE_ICONS = {
  text:             '<path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 10h16M4 14h16M4 18h16" />',
  textarea:         '<path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 10h16M4 14h10" />',
  search:           '<path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />',
  password:         '<path stroke-linecap="round" stroke-linejoin="round" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />',
  hidden:           '<path stroke-linecap="round" stroke-linejoin="round" d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.878 9.878L3 3m6.878 6.878L21 21" />',
  select:           '<path stroke-linecap="round" stroke-linejoin="round" d="M8 9l4-4 4 4m0 6l-4 4-4-4" />',
  "multi-select":   '<path stroke-linecap="round" stroke-linejoin="round" d="M8 9l4-4 4 4m0 6l-4 4-4-4" />',
  radio:            '<path stroke-linecap="round" stroke-linejoin="round" d="M8 9l4-4 4 4m0 6l-4 4-4-4" />',
  checkbox:         '<path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />',
  switch:           '<path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />',
  number:           '<path stroke-linecap="round" stroke-linejoin="round" d="M7 20l4-16m2 16l4-16M6 9h14M4 15h14" />',
  currency:         '<path stroke-linecap="round" stroke-linejoin="round" d="M7 20l4-16m2 16l4-16M6 9h14M4 15h14" />',
  range:            '<path stroke-linecap="round" stroke-linejoin="round" d="M7 20l4-16m2 16l4-16M6 9h14M4 15h14" />',
  rating:           '<path stroke-linecap="round" stroke-linejoin="round" d="M7 20l4-16m2 16l4-16M6 9h14M4 15h14" />',
  date:             '<path stroke-linecap="round" stroke-linejoin="round" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />',
  time:             '<path stroke-linecap="round" stroke-linejoin="round" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />',
  "datetime-local": '<path stroke-linecap="round" stroke-linejoin="round" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />',
  month:            '<path stroke-linecap="round" stroke-linejoin="round" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />',
  week:             '<path stroke-linecap="round" stroke-linejoin="round" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />',
  email:            '<path stroke-linecap="round" stroke-linejoin="round" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />',
  tel:              '<path stroke-linecap="round" stroke-linejoin="round" d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z" />',
  url:              '<path stroke-linecap="round" stroke-linejoin="round" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />',
  "rich-text":      '<path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 10h16M4 14h10" />',
  signature:        '<path stroke-linecap="round" stroke-linejoin="round" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z" />',
  file:             '<path stroke-linecap="round" stroke-linejoin="round" d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z" />',
  image:            '<path stroke-linecap="round" stroke-linejoin="round" d="M2.25 15.75l5.159-5.159a2.25 2.25 0 013.182 0l5.159 5.159m-1.5-1.5l1.409-1.409a2.25 2.25 0 013.182 0l2.909 2.909M3.75 21h16.5A2.25 2.25 0 0022.5 18.75V5.25A2.25 2.25 0 0020.25 3H3.75A2.25 2.25 0 001.5 5.25v13.5A2.25 2.25 0 003.75 21z" />',
  color:            '<path stroke-linecap="round" stroke-linejoin="round" d="M7 21a4 4 0 01-4-4V5a2 2 0 012-2h4a2 2 0 012 2v12a4 4 0 01-4 4zm0 0h12a2 2 0 002-2v-4a2 2 0 00-2-2h-2.343M11 7.343l1.657-1.657a2 2 0 012.828 0l2.829 2.829a2 2 0 010 2.828l-8.486 8.485M7 17h.01" />'
}

const TYPE_TO_DEFAULT_HTML = {
  String: 'text', Integer: 'number', Float: 'number', Boolean: 'checkbox',
  Array: 'select', Date: 'date', DateTime: 'datetime-local', Time: 'time'
}

const HTML_TYPE_COLORS = {
  text: ['text-slate-500', 'bg-slate-100/80'], textarea: ['text-slate-500', 'bg-slate-100/80'],
  search: ['text-slate-500', 'bg-slate-100/80'], password: ['text-slate-500', 'bg-slate-100/80'],
  hidden: ['text-slate-500', 'bg-slate-100/80'], 'rich-text': ['text-slate-500', 'bg-slate-100/80'],
  signature: ['text-slate-500', 'bg-slate-100/80'],
  select: ['text-violet-500', 'bg-violet-100/80'], 'multi-select': ['text-violet-500', 'bg-violet-100/80'],
  radio: ['text-violet-500', 'bg-violet-100/80'], checkbox: ['text-violet-500', 'bg-violet-100/80'],
  switch: ['text-violet-500', 'bg-violet-100/80'],
  number: ['text-blue-500', 'bg-blue-100/80'], currency: ['text-blue-500', 'bg-blue-100/80'],
  range: ['text-blue-500', 'bg-blue-100/80'], rating: ['text-blue-500', 'bg-blue-100/80'],
  date: ['text-amber-600', 'bg-amber-100/80'], time: ['text-amber-600', 'bg-amber-100/80'],
  'datetime-local': ['text-amber-600', 'bg-amber-100/80'], month: ['text-amber-600', 'bg-amber-100/80'],
  week: ['text-amber-600', 'bg-amber-100/80'],
  email: ['text-emerald-500', 'bg-emerald-100/80'], tel: ['text-emerald-500', 'bg-emerald-100/80'],
  url: ['text-emerald-500', 'bg-emerald-100/80'],
  file: ['text-rose-500', 'bg-rose-100/80'], image: ['text-rose-500', 'bg-rose-100/80'],
  color: ['text-rose-500', 'bg-rose-100/80']
}

function htmlTypeIconSvg(htmlType, rawType) {
  const effective = htmlType || TYPE_TO_DEFAULT_HTML[rawType] || TYPE_TO_DEFAULT_HTML[rawType?.split('::')?.pop()] || 'text'
  const iconPath = HTML_TYPE_ICONS[effective] || HTML_TYPE_ICONS.text
  const colors = HTML_TYPE_COLORS[effective] || ['text-gray-400', 'bg-gray-100']
  return `<div class="w-5 h-5 rounded flex items-center justify-center flex-shrink-0 ${colors[1]}"><svg class="w-3 h-3 ${colors[0]}" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">${iconPath}</svg></div>`
}

export class TabManager extends BaseManager {
  static TAB_ACTIVE_CLASSES = ["bg-white", "text-gray-900", "shadow-sm"]
  static TAB_INACTIVE_CLASSES = ["text-gray-500"]

  _showPanel(panel) {
    panel.classList.remove("hidden")
  }

  _hidePanel(panel) {
    panel.classList.add("hidden")
  }

  switchTab(event) {
    const clickedButton = event.currentTarget
    const targetTab = clickedButton.dataset.tab
    const isCurrentlyActive = clickedButton.classList.contains("bg-white")

    if (isCurrentlyActive) {
      this._deactivateButton(clickedButton)
      clickedButton.setAttribute("aria-selected", "false")

      this.c.tabPanelTargets.forEach(panel => {
        if (panel.dataset.tabPanel === targetTab) {
          this._hidePanel(panel)
        }
      })
    } else {
      this.c.tabButtonTargets.forEach(button => {
        this._deactivateButton(button)
        button.setAttribute("aria-selected", "false")
      })

      this.c.tabPanelTargets.forEach(panel => {
        this._hidePanel(panel)
      })

      this._activateButton(clickedButton)
      clickedButton.setAttribute("aria-selected", "true")

      this.c.tabPanelTargets.forEach(panel => {
        if (panel.dataset.tabPanel === targetTab) {
          this._showPanel(panel)
        }
      })
    }
  }

  closeAllTabPanels() {
    this.c.tabButtonTargets.forEach(button => {
      this._deactivateButton(button)
      button.setAttribute("aria-selected", "false")
    })
    this.c.tabPanelTargets.forEach(panel => {
      this._hidePanel(panel)
    })
  }

  // Show/hide list vs editor layer within a drawer panel
  showDrawerEditor(panelKey) {
    const listEl = this.c.element.querySelector(`[data-drawer-list="${panelKey}"]`)
    const editorEl = this.c.element.querySelector(`[data-drawer-editor="${panelKey}"]`)
    if (listEl) listEl.classList.add("hidden")
    if (editorEl) editorEl.classList.remove("hidden")
  }

  showDrawerList(panelKey) {
    const listEl = this.c.element.querySelector(`[data-drawer-list="${panelKey}"]`)
    const editorEl = this.c.element.querySelector(`[data-drawer-editor="${panelKey}"]`)
    if (editorEl) {
      editorEl.classList.add("hidden")
      editorEl.innerHTML = ""
    }
    if (listEl) listEl.classList.remove("hidden")
  }

  _activateButton(button) {
    button.classList.remove(...TabManager.TAB_INACTIVE_CLASSES)
    button.classList.add(...TabManager.TAB_ACTIVE_CLASSES)
  }

  _deactivateButton(button) {
    button.classList.remove(...TabManager.TAB_ACTIVE_CLASSES)
    button.classList.add(...TabManager.TAB_INACTIVE_CLASSES)
  }

  searchComponents(event) {
    const query = event.target.value.toLowerCase().trim()

    this.c.element.querySelectorAll(".entity-field-item").forEach(item => {
      const label = (item.dataset.fieldLabel || item.dataset.propertyName || "").toLowerCase()
      const type = (item.dataset.fieldType || item.dataset.propertyType || "").toLowerCase()
      const matches = label.includes(query) || type.includes(query) || query === ""
      item.classList.toggle("hidden", !matches)
    })
  }

  // Equivalent of `el.querySelector(":scope > div:last-child")` (that selector
  // throws/mis-parses in happy-dom): the last element child, iff it is a <div>.
  _lastDivChild(el) {
    const last = el.lastElementChild
    return last && last.tagName === "DIV" ? last : null
  }

  toggleCategory(event) {
    const button = event.currentTarget
    const categoryDiv = button.closest("[data-searchable-category]")
    if (!categoryDiv) return

    const content = categoryDiv.querySelector('[data-page-builder-target="entityFieldsCategory"]') ||
                    button.nextElementSibling
    const chevron = button.querySelector("[data-chevron]")

    if (content) {
      const isHidden = content.classList.contains("hidden")
      content.classList.toggle("hidden", !isHidden)

      if (chevron) {
        chevron.classList.toggle("rotate-180", isHidden)
      }

      // Also fold/expand all child subsections
      categoryDiv.querySelectorAll("[data-searchable-section]").forEach(section => {
        const sectionContent = this._lastDivChild(section)
        const sectionChevron = section.querySelector("[data-chevron]")

        if (sectionContent) {
          sectionContent.classList.toggle("hidden", !isHidden)
        }
        if (sectionChevron) {
          sectionChevron.classList.toggle("rotate-180", isHidden)
        }
      })
    }
  }

  toggleSubsection(event) {
    const button = event.currentTarget
    const section = button.closest("[data-searchable-section]")
    if (!section) return

    const content = this._lastDivChild(section)
    const chevron = button.querySelector("[data-chevron]")

    if (content) {
      const isHidden = content.classList.contains("hidden")
      content.classList.toggle("hidden", !isHidden)

      if (chevron) {
        chevron.classList.toggle("rotate-180", isHidden)
      }
    }
  }

  filterSidebar(event) {
    const searchTerm = event.target.value.toLowerCase().trim()

    if (!this.c.hasSidebarContentTarget) return

    const categories = this.c.sidebarContentTarget.querySelectorAll("[data-searchable-category]")
    const sections = this.c.sidebarContentTarget.querySelectorAll("[data-searchable-section]")
    const items = this.c.sidebarContentTarget.querySelectorAll("[data-searchable-item]")

    if (!searchTerm) {
      categories.forEach(cat => {
        cat.classList.remove("hidden")
        const content = cat.querySelector('[data-page-builder-target="entityFieldsCategory"]') ||
                        this._lastDivChild(cat)
        if (content) content.classList.remove("hidden")
        const chevron = cat.querySelector("button [data-chevron]")
        if (chevron) chevron.classList.add("rotate-180")
      })
      sections.forEach(section => section.classList.remove("hidden"))
      items.forEach(item => item.classList.remove("hidden"))
      return
    }

    sections.forEach(section => section.classList.add("hidden"))

    const matchingSections = new Set()
    const matchingCategories = new Set()
    items.forEach(item => {
      const searchText = item.dataset.searchText || ""
      const matches = searchText.includes(searchTerm)

      if (matches) {
        item.classList.remove("hidden")
        const section = item.closest("[data-searchable-section]")
        if (section) matchingSections.add(section)
        const category = item.closest("[data-searchable-category]")
        if (category) matchingCategories.add(category)
      } else {
        item.classList.add("hidden")
      }
    })

    // Expand matching sections
    matchingSections.forEach(section => {
      section.classList.remove("hidden")
      const content = this._lastDivChild(section)
      if (content) {
        content.classList.remove("hidden")
        const chevron = section.querySelector("[data-chevron]")
        if (chevron) chevron.classList.add("rotate-180")
      }
    })

    // Expand parent categories that have matches
    categories.forEach(cat => {
      if (matchingCategories.has(cat)) {
        cat.classList.remove("hidden")
        const content = cat.querySelector('[data-page-builder-target="entityFieldsCategory"]') ||
                        this._lastDivChild(cat)
        if (content) content.classList.remove("hidden")
        const chevron = cat.querySelector("button [data-chevron]")
        if (chevron) chevron.classList.add("rotate-180")
      } else {
        cat.classList.add("hidden")
      }
    })
  }

  selectEntity(event) {
    const button = event.currentTarget
    const entityId = button.dataset.entityId
    const entityName = button.dataset.entityName
    const properties = JSON.parse(button.dataset.entityProperties || "[]")

    this.c.metadata.entity_id = parseInt(entityId)
    this.c.metadata.entity_name = entityName
    this.c.entityIdValue = parseInt(entityId)

    if (this.c.hasEntityNameTarget) {
      this.c.entityNameTarget.textContent = entityName
    }

    this.renderEntityFields(properties)

    const dropdown = button.closest('[data-controller="dropdown"]')
    if (dropdown) {
      dropdown.querySelector('[data-dropdown-target="menu"]')?.classList.add("hidden")
    }

    this.c.saveManager.markDirty()
  }

  renderEntityFields(properties) {
    if (!this.c.hasEntityFieldsListTarget) return

    if (properties.length === 0) {
      this.c.entityFieldsListTarget.innerHTML = `
        <div class="px-4 py-8 text-center">
          <div class="w-10 h-10 mx-auto mb-2.5 rounded-full bg-gray-100 flex items-center justify-center">
            <svg class="w-5 h-5 text-gray-300" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
              <path stroke-linecap="round" stroke-linejoin="round" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4" />
            </svg>
          </div>
          <p class="text-xs font-medium text-gray-500 mb-0.5">${this.escapeHtml(this.c.noFieldsLabelValue)}</p>
          <p class="text-[11px] text-gray-400">${this.escapeHtml(this.c.noPropertiesFoundLabelValue)}</p>
        </div>
      `
    } else {
      this.c.entityFieldsListTarget.innerHTML = properties.map(prop => `
        <div class="entity-field-item flex items-center gap-2 px-1.5 py-[5px] rounded-md cursor-grab hover:bg-gray-50 active:bg-gray-100 transition-all duration-150 group"
             data-action="pointerdown->page-builder#dragPointerDown dblclick->page-builder#addField"
             data-drag-kind="new"
             data-field-type="entity"
             data-property-slug="${prop.name_slug}"
             data-property-name="${prop.name}"
             data-property-type="${prop.type}"
             data-property-html-type="${prop.html_type || ''}"
             data-source="entity"
             data-source-section="${this.c.metadata?.entity_name || ''}">
          <svg class="w-3 h-3 flex-shrink-0 text-transparent group-hover:text-gray-300 transition-colors duration-150" fill="currentColor" viewBox="0 0 24 24">
            <circle cx="8" cy="6" r="2"/><circle cx="16" cy="6" r="2"/><circle cx="8" cy="12" r="2"/><circle cx="16" cy="12" r="2"/><circle cx="8" cy="18" r="2"/><circle cx="16" cy="18" r="2"/>
          </svg>
          ${htmlTypeIconSvg(prop.html_type, prop.type)}
          <span class="text-[11px] leading-tight text-gray-600 group-hover:text-gray-900 truncate flex-1 transition-colors duration-150">${prop.name}</span>
        </div>
      `).join("")
    }

    if (this.c.hasEntityFieldCountTarget) {
      this.c.entityFieldCountTarget.textContent = properties.length
    }

    this.c.fieldManager.updateSidebarFieldStates()
  }

  onEntityChange(event) {
    const entityId = event.target.value

    if (entityId) {
      this.c.metadata.entity_id = parseInt(entityId, 10)
      this.c.entityIdValue = parseInt(entityId, 10)
    } else {
      delete this.c.metadata.entity_id
      this.c.entityIdValue = null
    }

    this.c.saveManager.markDirty()
  }
}
