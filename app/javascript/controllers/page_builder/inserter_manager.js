import { BaseManager } from "controllers/page_builder/base_manager"

const COMPONENT_CATALOG = [
  {
    category: "Structure",
    color: "violet",
    items: [
      { type: "section", label: "Section", icon: "M4 5a1 1 0 011-1h14a1 1 0 011 1v2a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM4 13a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H5a1 1 0 01-1-1v-6zM16 13a1 1 0 011-1h2a1 1 0 011 1v6a1 1 0 01-1 1h-2a1 1 0 01-1-1v-6z" },
      { type: "card", label: "Card", icon: "M2.25 8.25h19.5M2.25 9h19.5m-16.5 5.25h6m-6 2.25h3m-3.75 3h15a2.25 2.25 0 002.25-2.25V6.75A2.25 2.25 0 0019.5 4.5h-15a2.25 2.25 0 00-2.25 2.25v10.5A2.25 2.25 0 004.5 19.5z" },
      { type: "columns", label: "Columns", icon: "M9 4.5v15m6-15v15M4.5 4.5h15a1.5 1.5 0 011.5 1.5v12a1.5 1.5 0 01-1.5 1.5h-15A1.5 1.5 0 013 18V6a1.5 1.5 0 011.5-1.5z" },
      { type: "divider", label: "Divider", icon: "M20 12H4" },
      { type: "spacer", label: "Spacer", icon: "M8 7l4-4m0 0l4 4m-4-4v18" }
    ]
  },
  {
    category: "Content",
    color: "emerald",
    items: [
      { type: "heading", label: "Heading", icon: "M7 4v16M17 4v16M7 12h10" },
      { type: "paragraph", label: "Paragraph", icon: "M4 6h16M4 12h16M4 18h7" },
      { type: "list", label: "List", icon: "M8.25 6.75h12M8.25 12h12m-12 5.25h12M3.75 6.75h.007v.008H3.75V6.75zm.375 0a.375.375 0 11-.75 0 .375.375 0 01.75 0zM3.75 12h.007v.008H3.75V12zm.375 0a.375.375 0 11-.75 0 .375.375 0 01.75 0zm-.375 5.25h.007v.008H3.75v-.008zm.375 0a.375.375 0 11-.75 0 .375.375 0 01.75 0z" },
      { type: "quote", label: "Quote", icon: "M3 6v12M9 8h12M9 12h10M9 16h8" },
      { type: "code_block", label: "Code Block", icon: "M17.25 6.75L22.5 12l-5.25 5.25m-10.5 0L1.5 12l5.25-5.25m7.5-3l-4.5 16.5" }
    ]
  },
  {
    category: "Media & Actions",
    color: "amber",
    items: [
      { type: "image", label: "Image", icon: "M2.25 15.75l5.159-5.159a2.25 2.25 0 013.182 0l5.159 5.159m-1.5-1.5l1.409-1.409a2.25 2.25 0 013.182 0l2.909 2.909M3.75 21h16.5A2.25 2.25 0 0022.5 18.75V5.25A2.25 2.25 0 0020.25 3H3.75A2.25 2.25 0 001.5 5.25v13.5A2.25 2.25 0 003.75 21z" },
      { type: "video", label: "Video", icon: "M21 12a9 9 0 11-18 0 9 9 0 0118 0zM15.91 11.672a.375.375 0 010 .656l-5.603 3.113a.375.375 0 01-.557-.328V8.887c0-.286.307-.466.557-.327l5.603 3.112z" },
      { type: "button", label: "Button", icon: "M15.042 21.672L13.684 16.6m0 0l-2.51 2.225.569-9.47 5.227 7.917-3.286-.672zM12 2.25V4.5m5.834.166l-1.591 1.591M20.25 10.5H18M7.757 14.743l-1.59 1.59M6 10.5H3.75m4.007-4.243l-1.59-1.59" }
    ]
  },
  {
    category: "Feedback",
    color: "rose",
    items: [
      { type: "alert", label: "Alert", icon: "M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" },
      { type: "callout", label: "Callout", icon: "M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" },
      { type: "progress_bar", label: "Progress", icon: "M3 13.125C3 12.504 3.504 12 4.125 12h2.25c.621 0 1.125.504 1.125 1.125v6.75C7.5 20.496 6.996 21 6.375 21h-2.25A1.125 1.125 0 013 19.875v-6.75zM9.75 8.625c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125v11.25c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 01-1.125-1.125V8.625zM16.5 4.125c0-.621.504-1.125 1.125-1.125h2.25C20.496 3 21 3.504 21 4.125v15.75c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 01-1.125-1.125V4.125z" }
    ]
  }
]

const COLOR_MAP = {
  indigo:  { bg: "bg-indigo-50", hover: "hover:bg-indigo-100", border: "border-indigo-200", text: "text-indigo-600", icon: "text-indigo-500", heading: "text-indigo-600" },
  violet:  { bg: "bg-violet-50", hover: "hover:bg-violet-100", border: "border-violet-200", text: "text-violet-600", icon: "text-violet-500", heading: "text-violet-600" },
  emerald: { bg: "bg-emerald-50", hover: "hover:bg-emerald-100", border: "border-emerald-200", text: "text-emerald-600", icon: "text-emerald-500", heading: "text-emerald-600" },
  amber:   { bg: "bg-amber-50", hover: "hover:bg-amber-100", border: "border-amber-200", text: "text-amber-600", icon: "text-amber-500", heading: "text-amber-600" },
  rose:    { bg: "bg-rose-50", hover: "hover:bg-rose-100", border: "border-rose-200", text: "text-rose-600", icon: "text-rose-500", heading: "text-rose-600" }
}

export { COMPONENT_CATALOG }

export class InserterManager extends BaseManager {
  openPopover(event) {
    event.stopPropagation()
    const button = event.currentTarget
    const index = parseInt(button.dataset.insertIndex, 10)

    this._currentInsertIndex = isNaN(index) ? this.c.fields.length : index
    this._showPopover(button)
  }

  openFullCatalog(event) {
    event.stopPropagation()
    const button = event.currentTarget
    this._currentInsertIndex = this.c.selectedFieldId
      ? this.c.fields.findIndex(f => f.id === this.c.selectedFieldId) + 1
      : this.c.fields.length

    this._showPopover(button)
  }

  closePopover() {
    if (!this.c.hasInserterPopoverTarget) return
    this.c.inserterPopoverTarget.classList.add("hidden")
    this._currentInsertIndex = null
  }

  isPopoverOpen() {
    return this.c.hasInserterPopoverTarget && !this.c.inserterPopoverTarget.classList.contains("hidden")
  }

  filterPopover(event) {
    const query = event.target.value.toLowerCase().trim()
    if (!this.c.hasInserterPopoverContentTarget) return

    const items = this.c.inserterPopoverContentTarget.querySelectorAll("[data-component-type]")
    const categories = this.c.inserterPopoverContentTarget.querySelectorAll("[data-catalog-category]")

    items.forEach(item => {
      const label = (item.dataset.componentLabel || "").toLowerCase()
      const type = (item.dataset.componentType || "").toLowerCase()
      item.classList.toggle("hidden", query !== "" && !label.includes(query) && !type.includes(query))
    })

    categories.forEach(cat => {
      const visibleItems = cat.querySelectorAll("[data-component-type]:not(.hidden)")
      cat.classList.toggle("hidden", visibleItems.length === 0)
    })
  }

  insertFromPopover(event) {
    event.stopPropagation()
    const el = event.currentTarget
    const type = el.dataset.componentType
    const label = el.dataset.componentLabel
    if (!type) return

    const fieldData = {
      type,
      label,
      propertySlug: "",
      propertyType: this._isLayoutType(type) ? "layout" : undefined
    }

    const index = this._currentInsertIndex ?? this.c.fields.length
    this.c.fieldManager.addFieldAtIndex(fieldData, index)
    this.closePopover()
  }

  insertFromToolbar(event) {
    event.stopPropagation()
    const el = event.currentTarget
    const type = el.dataset.componentType
    const label = el.dataset.componentLabel
    if (!type) return

    const fieldData = {
      type,
      label,
      propertySlug: "",
      propertyType: this._isLayoutType(type) ? "layout" : undefined
    }

    const index = this.c.selectedFieldId
      ? this.c.fields.findIndex(f => f.id === this.c.selectedFieldId) + 1
      : this.c.fields.length

    this.c.fieldManager.addFieldAtIndex(fieldData, index)
  }

  // --- Private helpers ---

  _showPopover(anchorElement) {
    if (!this.c.hasInserterPopoverTarget) return

    this.c.inserterPopoverContentTarget.innerHTML = this._buildCatalogHtml()
    this.c.inserterPopoverTarget.classList.remove("hidden")

    // Position near anchor
    const rect = anchorElement.getBoundingClientRect()
    const popover = this.c.inserterPopoverTarget
    const popoverRect = popover.getBoundingClientRect()

    let top = rect.bottom + 8
    let left = rect.left + (rect.width / 2) - (popoverRect.width / 2)

    // Keep within viewport
    if (left < 8) left = 8
    if (left + popoverRect.width > window.innerWidth - 8) {
      left = window.innerWidth - popoverRect.width - 8
    }
    if (top + popoverRect.height > window.innerHeight - 8) {
      top = rect.top - popoverRect.height - 8
    }

    popover.style.top = `${top}px`
    popover.style.left = `${left}px`

    // Focus search
    if (this.c.hasInserterPopoverSearchTarget) {
      this.c.inserterPopoverSearchTarget.value = ""
      setTimeout(() => this.c.inserterPopoverSearchTarget.focus(), 50)
    }
  }

  // Translated display label for a catalog item — falls back to the item's
  // English default (COMPONENT_CATALOG) when the type isn't in the i18n map.
  _itemLabel(item) {
    return this.c.componentCatalogLabelsValue[item.type] || item.label
  }

  // Translated display label for a catalog category heading — falls back to
  // the raw category key (also the English default) when untranslated.
  _categoryLabel(category) {
    return this.c.componentCatalogCategoryLabelsValue[category] || category
  }

  _buildCatalogHtml() {
    return COMPONENT_CATALOG.map(group => {
      const colors = COLOR_MAP[group.color] || COLOR_MAP.indigo
      const categoryLabel = this._categoryLabel(group.category)
      const items = group.items.map(item => {
        const label = this._itemLabel(item)
        return `
        <button type="button"
                class="flex flex-col items-center gap-1.5 p-2.5 rounded-lg border border-transparent ${colors.bg} ${colors.hover} hover:${colors.border} transition-all cursor-pointer group/item"
                data-component-type="${item.type}"
                data-component-label="${label}"
                data-action="click->page-builder#insertFromPopover">
          <svg class="w-5 h-5 ${colors.icon}" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="${item.icon}" />
          </svg>
          <span class="text-[11px] font-medium text-gray-700 group-hover/item:${colors.text} leading-tight text-center">${label}</span>
        </button>
      `
      }).join("")

      return `
        <div data-catalog-category="${group.category}">
          <div class="px-1 py-1.5">
            <span class="text-[10px] font-bold ${colors.heading} uppercase tracking-wider">${categoryLabel}</span>
          </div>
          <div class="grid grid-cols-4 gap-1.5 mb-3">
            ${items}
          </div>
        </div>
      `
    }).join("")
  }

  _isLayoutType(type) {
    const layoutTypes = new Set([
      "section", "divider", "heading", "paragraph", "spacer",
      "alert", "image", "callout", "quote", "button", "video",
      "list", "code_block", "card", "progress_bar", "columns"
    ])
    return layoutTypes.has(type)
  }
}
