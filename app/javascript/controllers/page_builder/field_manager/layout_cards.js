import { LAYOUT_ICONS } from "controllers/page_builder/field_manager"

// Spacer-height badge words — English source of truth for the
// spacerHeightLabels i18n Value (see page_builder_controller.js).
export const SPACER_HEIGHT_LABELS = { sm: "Small", md: "Medium", lg: "Large", xl: "Extra Large" }

// List-style badge words — English source of truth for the listStyleLabels
// i18n Value (see page_builder_controller.js).
export const LIST_STYLE_LABELS = { bullet: "Bullet", numbered: "Numbered", none: "Plain" }

// Column-layout badge words — English source of truth for the
// columnLayoutBadgeLabels i18n Value (see page_builder_controller.js).
export const COLUMN_LAYOUT_BADGE_LABELS = {
  "50-50": "2 Equal", "33-33-33": "3 Equal", "66-33": "2:1", "33-66": "1:2", "25-25-25-25": "4 Equal"
}

/**
 * LayoutCardsMixin provides all layout card HTML generation methods.
 * Apply to a class using Object.assign(YourClass.prototype, LayoutCardsMixin)
 */
export const LayoutCardsMixin = {
  createLayoutCardHtml(field) {
    const fieldType = field.field_type || "section"
    switch (fieldType) {
      case "section":
        return this.createSectionCardHtml(field)
      case "divider":
        return this.createDividerCardHtml(field)
      case "heading":
        return this.createHeadingCardHtml(field)
      case "paragraph":
        return this.createParagraphCardHtml(field)
      case "spacer":
        return this.createSpacerCardHtml(field)
      case "alert":
        return this.createAlertCardHtml(field)
      case "image":
        return this.createImageCardHtml(field)
      case "callout":
        return this.createCalloutCardHtml(field)
      case "quote":
        return this.createQuoteCardHtml(field)
      case "button":
        return this.createButtonCardHtml(field)
      case "video":
        return this.createVideoCardHtml(field)
      case "list":
        return this.createListCardHtml(field)
      case "code_block":
        return this.createCodeBlockCardHtml(field)
      case "card":
        return this.createCardCardHtml(field)
      case "progress_bar":
        return this.createProgressBarCardHtml(field)
      case "columns":
        return this.createColumnsCardHtml(field)
      default:
        return this.createSectionCardHtml(field)
    }
  },

  createSectionCardHtml(field) {
    const icon = this.getFieldIcon("layout", "section")
    return `
      <div class="bg-violet-50 border border-violet-200 rounded-lg px-2 py-1.5 hover:border-violet-300">
        <div class="flex items-center justify-between mb-0.5">
          <div class="flex items-center gap-1.5">
            <div class="w-5 h-5 rounded bg-violet-100 flex items-center justify-center flex-shrink-0">${icon}</div>
            <span class="text-[10px] font-semibold text-violet-600 uppercase tracking-wider">${this.c.componentCatalogLabelsValue.section}</span>
          </div>
          ${this.cardActionButtons(field)}
        </div>
        <div class="text-xs font-semibold text-gray-800" data-action="dblclick->page-builder#startInlineEdit" data-inline-edit-property="label">${this.escapeHtml(field.label || "Section Title")}</div>
        ${field.content ? `<div class="text-[11px] text-gray-500 mt-0.5">${this.escapeHtml(field.content)}</div>` : ""}
        <div class="mt-1 border-b-2 border-violet-200"></div>
      </div>
    `
  },

  createDividerCardHtml(field) {
    return `
      <div class="py-0.5 px-2 hover:bg-gray-50 rounded-lg border border-transparent hover:border-gray-200">
        <div class="flex items-center justify-between">
          <div class="flex-1 flex items-center gap-2">
            <hr class="flex-1 border-t-2 border-gray-300">
          </div>
          ${this.cardActionButtons(field)}
        </div>
      </div>
    `
  },

  createHeadingCardHtml(field) {
    const level = field.heading_level || "h3"
    const sizeClasses = { h2: "text-base", h3: "text-sm", h4: "text-xs" }
    const sizeClass = sizeClasses[level] || "text-sm"
    return `
      <div class="bg-white border border-gray-200 rounded-lg px-2 py-1.5 hover:border-gray-300">
        <div class="flex items-center justify-between mb-0.5">
          <span class="text-[10px] font-semibold text-gray-400 uppercase tracking-wider">${level.toUpperCase()} ${this.c.componentCatalogLabelsValue.heading}</span>
          ${this.cardActionButtons(field)}
        </div>
        <div class="${sizeClass} font-bold text-gray-900" data-action="dblclick->page-builder#startInlineEdit" data-inline-edit-property="label">${this.escapeHtml(field.content || field.label || "Heading Text")}</div>
      </div>
    `
  },

  createParagraphCardHtml(field) {
    return `
      <div class="bg-white border border-gray-200 rounded-lg px-2 py-1.5 hover:border-gray-300">
        <div class="flex items-center justify-between mb-0.5">
          <span class="text-[10px] font-semibold text-gray-400 uppercase tracking-wider">${this.c.componentCatalogLabelsValue.paragraph}</span>
          ${this.cardActionButtons(field)}
        </div>
        <div class="text-xs text-gray-600 leading-relaxed" data-action="dblclick->page-builder#startInlineEdit" data-inline-edit-property="content">${this.escapeHtml(field.content || "Enter your text here...")}</div>
      </div>
    `
  },

  createSpacerCardHtml(field) {
    const heightLabels = this.c.spacerHeightLabelsValue
    const heightLabel = heightLabels[field.spacer_height] || heightLabels.md
    const heightClasses = { sm: "h-2", md: "h-3", lg: "h-5", xl: "h-8" }
    const heightClass = heightClasses[field.spacer_height] || "h-3"
    return `
      <div class="bg-white border border-gray-200 rounded-lg px-2 py-1.5 hover:border-gray-300">
        <div class="flex items-center justify-between mb-0.5">
          <span class="text-[10px] font-semibold text-gray-400 uppercase tracking-wider">${this.c.componentCatalogLabelsValue.spacer} (${heightLabel})</span>
          ${this.cardActionButtons(field)}
        </div>
        <div class="${heightClass} bg-gray-100 rounded border border-dashed border-gray-300 flex items-center justify-center">
          <svg class="w-3.5 h-3.5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M8 7l4-4m0 0l4 4m-4-4v18" />
          </svg>
        </div>
      </div>
    `
  },

  createAlertCardHtml(field) {
    const variant = field.alert_variant || "info"
    const variantStyles = {
      info:    { bg: "bg-blue-50", border: "border-blue-200", text: "text-blue-800" },
      warning: { bg: "bg-yellow-50", border: "border-yellow-200", text: "text-yellow-800" },
      success: { bg: "bg-green-50", border: "border-green-200", text: "text-green-800" },
      danger:  { bg: "bg-red-50", border: "border-red-200", text: "text-red-800" }
    }
    const style = variantStyles[variant] || variantStyles.info
    return `
      <div class="rounded-lg px-2 py-1.5 border ${style.bg} ${style.border} hover:opacity-90">
        <div class="flex items-center justify-between mb-0.5">
          <span class="text-[10px] font-semibold text-gray-400 uppercase tracking-wider">${this.c.componentCatalogLabelsValue.alert} (${variant})</span>
          ${this.cardActionButtons(field)}
        </div>
        <div class="text-xs ${style.text}" data-action="dblclick->page-builder#startInlineEdit" data-inline-edit-property="content">${this.escapeHtml(field.content || "Important notice")}</div>
      </div>
    `
  },

  createImageCardHtml(field) {
    const hasUrl = field.image_url && field.image_url.trim() !== ""
    const imageContent = hasUrl
      ? `<img src="${this.escapeHtml(field.image_url)}" alt="${this.escapeHtml(field.alt_text || "")}" class="max-h-12 rounded border border-gray-200 mx-auto">`
      : `<div class="h-8 bg-gray-100 rounded border border-dashed border-gray-300 flex items-center justify-center">
          <svg class="w-4 h-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
            <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 15.75l5.159-5.159a2.25 2.25 0 013.182 0l5.159 5.159m-1.5-1.5l1.409-1.409a2.25 2.25 0 013.182 0l2.909 2.909M3.75 21h16.5A2.25 2.25 0 0022.5 18.75V5.25A2.25 2.25 0 0020.25 3H3.75A2.25 2.25 0 001.5 5.25v13.5A2.25 2.25 0 003.75 21z" />
          </svg>
        </div>`
    return `
      <div class="bg-white border border-gray-200 rounded-lg px-2 py-1.5 hover:border-gray-300">
        <div class="flex items-center justify-between mb-0.5">
          <span class="text-[10px] font-semibold text-gray-400 uppercase tracking-wider">${this.c.componentCatalogLabelsValue.image}</span>
          ${this.cardActionButtons(field)}
        </div>
        <div class="text-center">${imageContent}</div>
      </div>
    `
  },

  createCalloutCardHtml(field) {
    return `
      <div class="border-l-4 border-indigo-400 bg-indigo-50 rounded-r-lg px-2 py-1.5 hover:bg-indigo-100">
        <div class="flex items-center justify-between mb-0.5">
          <span class="text-[10px] font-semibold text-gray-400 uppercase tracking-wider">${this.c.componentCatalogLabelsValue.callout}</span>
          ${this.cardActionButtons(field)}
        </div>
        <div class="text-xs text-indigo-900" data-action="dblclick->page-builder#startInlineEdit" data-inline-edit-property="content">${this.escapeHtml(field.content || "Highlighted information")}</div>
      </div>
    `
  },

  createQuoteCardHtml(field) {
    return `
      <div class="border-l-4 border-gray-300 bg-white rounded-r-lg px-2 py-1.5 hover:border-gray-400">
        <div class="flex items-center justify-between mb-0.5">
          <span class="text-[10px] font-semibold text-gray-400 uppercase tracking-wider">${this.c.componentCatalogLabelsValue.quote}</span>
          ${this.cardActionButtons(field)}
        </div>
        <div class="text-xs text-gray-600 italic">${this.escapeHtml(field.content || "Enter your quote here...")}</div>
        ${field.attribution ? `<div class="text-[11px] text-gray-400 mt-0.5">&mdash; ${this.escapeHtml(field.attribution)}</div>` : ""}
      </div>
    `
  },

  createButtonCardHtml(field) {
    const variant = field.button_variant || "primary"
    const size = field.button_size || "md"
    const variantStyles = {
      primary:   "bg-indigo-600 text-white",
      secondary: "bg-white text-gray-700 border border-gray-300",
      outline:   "bg-transparent text-indigo-600 border border-indigo-600"
    }
    const sizeStyles = { sm: "px-2 py-0.5 text-[11px]", md: "px-3 py-1 text-xs", lg: "px-4 py-1.5 text-sm" }
    const alignClass = { left: "text-left", center: "text-center", right: "text-right" }
    return `
      <div class="bg-white border border-gray-200 rounded-lg px-2 py-1.5 hover:border-gray-300">
        <div class="flex items-center justify-between mb-0.5">
          <span class="text-[10px] font-semibold text-gray-400 uppercase tracking-wider">${this.c.componentCatalogLabelsValue.button} (${variant}/${size})</span>
          ${this.cardActionButtons(field)}
        </div>
        <div class="${alignClass[field.alignment] || "text-left"}">
          <span class="inline-block rounded-lg font-medium ${variantStyles[variant] || variantStyles.primary} ${sizeStyles[size] || sizeStyles.md}" data-action="dblclick->page-builder#startInlineEdit" data-inline-edit-property="label">${this.escapeHtml(field.content || field.label || "Click Me")}</span>
        </div>
      </div>
    `
  },

  createVideoCardHtml(field) {
    const hasUrl = field.video_url && field.video_url.trim() !== ""
    const videoContent = hasUrl
      ? `<div class="h-8 bg-gray-800 rounded flex items-center justify-center">
          <svg class="w-5 h-5 text-white opacity-80" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
            <path stroke-linecap="round" stroke-linejoin="round" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            <path stroke-linecap="round" stroke-linejoin="round" d="M15.91 11.672a.375.375 0 010 .656l-5.603 3.113a.375.375 0 01-.557-.328V8.887c0-.286.307-.466.557-.327l5.603 3.112z" />
          </svg>
        </div>
        <div class="text-[11px] text-gray-400 mt-0.5 truncate">${this.escapeHtml(field.video_url)}</div>`
      : `<div class="h-8 bg-gray-100 rounded border border-dashed border-gray-300 flex items-center justify-center">
          <svg class="w-4 h-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
            <path stroke-linecap="round" stroke-linejoin="round" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            <path stroke-linecap="round" stroke-linejoin="round" d="M15.91 11.672a.375.375 0 010 .656l-5.603 3.113a.375.375 0 01-.557-.328V8.887c0-.286.307-.466.557-.327l5.603 3.112z" />
          </svg>
        </div>`
    return `
      <div class="bg-white border border-gray-200 rounded-lg px-2 py-1.5 hover:border-gray-300">
        <div class="flex items-center justify-between mb-0.5">
          <span class="text-[10px] font-semibold text-gray-400 uppercase tracking-wider">${this.c.componentCatalogLabelsValue.video}</span>
          ${this.cardActionButtons(field)}
        </div>
        ${videoContent}
      </div>
    `
  },

  createListCardHtml(field) {
    const style = field.list_style || "bullet"
    const styleLabels = this.c.listStyleLabelsValue
    const items = (field.content || "").split("\n").filter(i => i.trim()).slice(0, 3)
    const listItems = items.map(item => `<li class="text-xs text-gray-600">${this.escapeHtml(item.trim())}</li>`).join("")
    const listClasses = style === "numbered" ? "list-decimal pl-4 space-y-0.5" : style === "bullet" ? "list-disc pl-4 space-y-0.5" : "space-y-0.5"
    const tag = style === "numbered" ? "ol" : "ul"
    return `
      <div class="bg-white border border-gray-200 rounded-lg px-2 py-1.5 hover:border-gray-300">
        <div class="flex items-center justify-between mb-0.5">
          <span class="text-[10px] font-semibold text-gray-400 uppercase tracking-wider">${this.c.componentCatalogLabelsValue.list} (${styleLabels[style] || styleLabels.bullet})</span>
          ${this.cardActionButtons(field)}
        </div>
        <${tag} class="${listClasses}">${listItems}</${tag}>
      </div>
    `
  },

  createCodeBlockCardHtml(field) {
    const lang = field.code_language || ""
    return `
      <div class="bg-gray-800 rounded-lg px-2 py-1.5 hover:bg-gray-750">
        <div class="flex items-center justify-between mb-0.5">
          <span class="text-[10px] font-semibold text-gray-400 uppercase tracking-wider">${this.c.codeBadgeLabelValue}${lang ? ` (${this.escapeHtml(lang)})` : ""}</span>
          ${this.cardActionButtons(field)}
        </div>
        <pre class="text-[11px] text-gray-200 font-mono overflow-hidden max-h-8 leading-tight">${this.escapeHtml(field.content || "// Your code here")}</pre>
      </div>
    `
  },

  createCardCardHtml(field) {
    return `
      <div class="bg-white border border-gray-200 rounded-lg px-2 py-1.5 hover:border-gray-300">
        <div class="flex items-center justify-between mb-0.5">
          <span class="text-[10px] font-semibold text-gray-400 uppercase tracking-wider">${this.c.componentCatalogLabelsValue.card}</span>
          ${this.cardActionButtons(field)}
        </div>
        <div class="border border-gray-200 rounded-lg px-2 py-1.5 bg-gray-50">
          <div class="text-xs font-semibold text-gray-800">${this.escapeHtml(field.label || "Card Title")}</div>
          ${field.content ? `<div class="text-[11px] text-gray-500 mt-0.5">${this.escapeHtml(field.content)}</div>` : ""}
        </div>
      </div>
    `
  },

  createProgressBarCardHtml(field) {
    const value = Math.min(100, Math.max(0, parseInt(field.progress_value) || 0))
    const colorMap = { indigo: "bg-indigo-600", green: "bg-green-600", blue: "bg-blue-600", red: "bg-red-600" }
    const barColor = colorMap[field.progress_color] || colorMap.indigo
    const progressLabel = this.c.componentCatalogLabelsValue.progress_bar
    return `
      <div class="bg-white border border-gray-200 rounded-lg px-2 py-1.5 hover:border-gray-300">
        <div class="flex items-center justify-between mb-0.5">
          <span class="text-[10px] font-semibold text-gray-400 uppercase tracking-wider">${progressLabel}</span>
          ${this.cardActionButtons(field)}
        </div>
        <div class="flex items-center justify-between text-[11px] text-gray-600 mb-0.5">
          <span>${this.escapeHtml(field.label || progressLabel)}</span>
          <span>${value}%</span>
        </div>
        <div class="w-full bg-gray-200 rounded-full h-2">
          <div class="${barColor} h-2 rounded-full" style="width: ${value}%"></div>
        </div>
      </div>
    `
  },

  createColumnsCardHtml(field) {
    const layout = field.column_layout || "50-50"
    const columns = field.columns || []
    const layoutLabels = this.c.columnLayoutBadgeLabelsValue
    const gridClasses = {
      "50-50": "grid-cols-2",
      "33-33-33": "grid-cols-3",
      "25-25-25-25": "grid-cols-4",
      "66-33": "grid-cols-3",
      "33-66": "grid-cols-3"
    }
    const colSpanMap = {
      "66-33": [2, 1],
      "33-66": [1, 2]
    }

    const gridClass = gridClasses[layout] || "grid-cols-2"
    const colSpans = colSpanMap[layout]

    const columnHtml = columns.map((col, idx) => {
      const childFields = col.fields || []
      const spanClass = colSpans ? `col-span-${colSpans[idx]}` : ""
      const childrenHtml = childFields.length > 0
        ? childFields.map(f => `
            <div class="text-xs text-gray-600 bg-white rounded border border-gray-200 px-1.5 py-1 truncate"
                 data-field-id="${f.id}">
              ${this.escapeHtml(f.label || f.field_type)}
            </div>
          `).join("")
        : `<div class="text-[11px] text-gray-400 italic text-center py-0.5">${this.c.dropFieldsHereLabelValue}</div>`

      return `
        <div class="min-h-[32px] border-2 border-dashed border-gray-300 rounded-lg p-1 space-y-0.5 hover:border-indigo-300 hover:bg-indigo-50/20 transition-colors ${spanClass}"
             data-column-index="${idx}"
             data-parent-field-id="${field.id}">
          ${childrenHtml}
        </div>
      `
    }).join("")

    return `
      <div class="bg-violet-50 border border-violet-200 rounded-lg px-2 py-1.5 hover:border-violet-300">
        <div class="flex items-center justify-between mb-0.5">
          <div class="flex items-center gap-1.5">
            <div class="w-5 h-5 rounded bg-violet-100 flex items-center justify-center flex-shrink-0">
              <svg class="w-3.5 h-3.5 text-violet-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                ${LAYOUT_ICONS.columns}
              </svg>
            </div>
            <span class="text-[10px] font-semibold text-violet-600 uppercase tracking-wider">${this.c.componentCatalogLabelsValue.columns} (${layoutLabels[layout] || layout})</span>
          </div>
          ${this.cardActionButtons(field)}
        </div>
        <div class="grid ${gridClass} gap-1.5">
          ${columnHtml}
        </div>
      </div>
    `
  },

  cardActionButtons(field) {
    return `<div class="flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity">
      <button type="button" class="field-duplicate-btn p-0.5 text-gray-400 hover:text-indigo-500 transition-colors" title="${this.c.actionDuplicateTitleValue}"
              data-action="click->page-builder#duplicateFieldFromCard" data-field-id="${field.id}">
        <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
        </svg>
      </button>
      <button type="button" class="field-remove-btn p-0.5 text-gray-400 hover:text-red-500 transition-colors" title="${this.c.actionDeleteTitleValue}"
              data-action="click->page-builder#removeFieldFromCard" data-field-id="${field.id}">
        <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
        </svg>
      </button>
      <button type="button" class="field-drag-handle p-0.5 text-gray-400 hover:text-gray-600 cursor-grab" title="${this.c.dragToReorderTitleValue}">
        <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 20 20">
          <path d="M7 2a2 2 0 1 0 0 4 2 2 0 0 0 0-4zm6 0a2 2 0 1 0 0 4 2 2 0 0 0 0-4zM7 8a2 2 0 1 0 0 4 2 2 0 0 0 0-4zm6 0a2 2 0 1 0 0 4 2 2 0 0 0 0-4zM7 14a2 2 0 1 0 0 4 2 2 0 0 0 0-4zm6 0a2 2 0 1 0 0 4 2 2 0 0 0 0-4z"/>
        </svg>
      </button>
    </div>`
  }
}
