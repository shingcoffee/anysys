import { BaseManager } from "controllers/page_builder/base_manager"
import { LayoutCardsMixin } from "controllers/page_builder/field_manager/layout_cards"
import { FieldPreviewsMixin } from "controllers/page_builder/field_manager/field_previews"
import { FieldCrudMixin } from "controllers/page_builder/field_manager/field_crud"
import { DragReorderMixin } from "controllers/page_builder/field_manager/drag_reorder"
import { DependencyOverlayMixin } from "controllers/page_builder/field_manager/dependency_overlay"

const WIDTH_COLS = { full: 12, three_quarters: 9, two_thirds: 8, half: 6, third: 4, quarter: 3 }
const WIDTH_CLASSES = { full: "col-span-12", three_quarters: "col-span-9", two_thirds: "col-span-8", half: "col-span-6", third: "col-span-4", quarter: "col-span-3" }

const FIELD_TYPE_MAPPING = {
  // Text types
  text: "string",
  textarea: "text",
  search: "string",
  password: "string",
  hidden: "string",
  // Selection types
  select: "select",
  "multi-select": "select",
  radio: "string",
  checkbox: "boolean",
  switch: "boolean",
  toggle: "boolean",
  // Numeric types
  number: "number",
  currency: "number",
  range: "number",
  rating: "number",
  // Date & Time types
  date: "date",
  time: "datetime",
  "datetime-local": "datetime",
  month: "date",
  week: "date",
  // Contact types
  email: "email",
  tel: "string",
  url: "string",
  // Rich content types
  "rich-text": "text",
  signature: "string",
  // Media & File types
  file: "string",
  image: "string",
  color: "string",
  // Entity
  entity: "string",
  // Layout types
  section: "layout",
  divider: "layout",
  heading: "layout",
  paragraph: "layout",
  spacer: "layout",
  alert: "layout",
  callout: "layout",
  quote: "layout",
  button: "layout",
  video: "layout",
  list: "layout",
  code_block: "layout",
  card: "layout",
  progress_bar: "layout",
  columns: "layout",
}

const FIELD_ICONS = {
  string: '<path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 10h16M4 14h16M4 18h16" />',
  text: '<path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 10h16M4 14h10" />',
  email: '<path stroke-linecap="round" stroke-linejoin="round" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />',
  number: '<path stroke-linecap="round" stroke-linejoin="round" d="M7 20l4-16m2 16l4-16M6 9h14M4 15h14" />',
  integer: '<path stroke-linecap="round" stroke-linejoin="round" d="M7 20l4-16m2 16l4-16M6 9h14M4 15h14" />',
  float: '<path stroke-linecap="round" stroke-linejoin="round" d="M7 20l4-16m2 16l4-16M6 9h14M4 15h14" />',
  boolean: '<path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />',
  date: '<path stroke-linecap="round" stroke-linejoin="round" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />',
  datetime: '<path stroke-linecap="round" stroke-linejoin="round" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />',
  select: '<path stroke-linecap="round" stroke-linejoin="round" d="M8 9l4-4 4 4m0 6l-4 4-4-4" />',
  layout: '<path stroke-linecap="round" stroke-linejoin="round" d="M4 5a1 1 0 011-1h14a1 1 0 011 1v2a1 1 0 01-1 1H5a1 1 0 01-1-1V5z" />'
}

// HTML-type-specific icons (used when html_type gives more info than property_type)
const HTML_TYPE_ICONS = {
  tel: '<path stroke-linecap="round" stroke-linejoin="round" d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z" />',
  url: '<path stroke-linecap="round" stroke-linejoin="round" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />',
  currency: '<path stroke-linecap="round" stroke-linejoin="round" d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />',
  range: '<path stroke-linecap="round" stroke-linejoin="round" d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z" />',
  rating: '<path stroke-linecap="round" stroke-linejoin="round" d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z" />',
  color: '<path stroke-linecap="round" stroke-linejoin="round" d="M7 21a4 4 0 01-4-4V5a2 2 0 012-2h4a2 2 0 012 2v12a4 4 0 01-4 4zm0 0h12a2 2 0 002-2v-4a2 2 0 00-2-2h-2.343M11 7.343l1.657-1.657a2 2 0 012.828 0l2.829 2.829a2 2 0 010 2.828l-8.486 8.485M7 17h.01" />',
  signature: '<path stroke-linecap="round" stroke-linejoin="round" d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L6.832 19.82a4.5 4.5 0 01-1.897 1.13l-2.685.8.8-2.685a4.5 4.5 0 011.13-1.897L16.863 4.487zm0 0L19.5 7.125" />',
  file: '<path stroke-linecap="round" stroke-linejoin="round" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12" />',
  image: '<path stroke-linecap="round" stroke-linejoin="round" d="M2.25 15.75l5.159-5.159a2.25 2.25 0 013.182 0l5.159 5.159m-1.5-1.5l1.409-1.409a2.25 2.25 0 013.182 0l2.909 2.909M3.75 21h16.5A2.25 2.25 0 0022.5 18.75V5.25A2.25 2.25 0 0020.25 3H3.75A2.25 2.25 0 001.5 5.25v13.5A2.25 2.25 0 003.75 21z" />',
  switch: '<path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />',
  password: '<path stroke-linecap="round" stroke-linejoin="round" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />',
  search: '<path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />',
  "rich-text": '<path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 10h16M4 14h10" />',
}

const LAYOUT_ICONS = {
  section: '<path stroke-linecap="round" stroke-linejoin="round" d="M4 5a1 1 0 011-1h14a1 1 0 011 1v2a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM4 13a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H5a1 1 0 01-1-1v-6zM16 13a1 1 0 011-1h2a1 1 0 011 1v6a1 1 0 01-1 1h-2a1 1 0 01-1-1v-6z" />',
  divider: '<path stroke-linecap="round" stroke-linejoin="round" d="M20 12H4" />',
  heading: '<path stroke-linecap="round" stroke-linejoin="round" d="M7 4v16M17 4v16M7 12h10" />',
  paragraph: '<path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 12h16M4 18h7" />',
  spacer: '<path stroke-linecap="round" stroke-linejoin="round" d="M8 7l4-4m0 0l4 4m-4-4v18" />',
  alert: '<path stroke-linecap="round" stroke-linejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />',
  image: '<path stroke-linecap="round" stroke-linejoin="round" d="M2.25 15.75l5.159-5.159a2.25 2.25 0 013.182 0l5.159 5.159m-1.5-1.5l1.409-1.409a2.25 2.25 0 013.182 0l2.909 2.909M3.75 21h16.5A2.25 2.25 0 0022.5 18.75V5.25A2.25 2.25 0 0020.25 3H3.75A2.25 2.25 0 001.5 5.25v13.5A2.25 2.25 0 003.75 21z" />',
  callout: '<path stroke-linecap="round" stroke-linejoin="round" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />',
  quote: '<path stroke-linecap="round" stroke-linejoin="round" d="M3 6v12M9 8h12M9 12h10M9 16h8" />',
  button: '<path stroke-linecap="round" stroke-linejoin="round" d="M15.042 21.672L13.684 16.6m0 0l-2.51 2.225.569-9.47 5.227 7.917-3.286-.672zM12 2.25V4.5m5.834.166l-1.591 1.591M20.25 10.5H18M7.757 14.743l-1.59 1.59M6 10.5H3.75m4.007-4.243l-1.59-1.59" />',
  video: '<path stroke-linecap="round" stroke-linejoin="round" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" /><path stroke-linecap="round" stroke-linejoin="round" d="M15.91 11.672a.375.375 0 010 .656l-5.603 3.113a.375.375 0 01-.557-.328V8.887c0-.286.307-.466.557-.327l5.603 3.112z" />',
  list: '<path stroke-linecap="round" stroke-linejoin="round" d="M8.25 6.75h12M8.25 12h12m-12 5.25h12M3.75 6.75h.007v.008H3.75V6.75zm.375 0a.375.375 0 11-.75 0 .375.375 0 01.75 0zM3.75 12h.007v.008H3.75V12zm.375 0a.375.375 0 11-.75 0 .375.375 0 01.75 0zm-.375 5.25h.007v.008H3.75v-.008zm.375 0a.375.375 0 11-.75 0 .375.375 0 01.75 0z" />',
  code_block: '<path stroke-linecap="round" stroke-linejoin="round" d="M17.25 6.75L22.5 12l-5.25 5.25m-10.5 0L1.5 12l5.25-5.25m7.5-3l-4.5 16.5" />',
  card: '<path stroke-linecap="round" stroke-linejoin="round" d="M2.25 8.25h19.5M2.25 9h19.5m-16.5 5.25h6m-6 2.25h3m-3.75 3h15a2.25 2.25 0 002.25-2.25V6.75A2.25 2.25 0 0019.5 4.5h-15a2.25 2.25 0 00-2.25 2.25v10.5A2.25 2.25 0 004.5 19.5z" />',
  progress_bar: '<path stroke-linecap="round" stroke-linejoin="round" d="M3 13.125C3 12.504 3.504 12 4.125 12h2.25c.621 0 1.125.504 1.125 1.125v6.75C7.5 20.496 6.996 21 6.375 21h-2.25A1.125 1.125 0 013 19.875v-6.75zM9.75 8.625c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125v11.25c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 01-1.125-1.125V8.625zM16.5 4.125c0-.621.504-1.125 1.125-1.125h2.25C20.496 3 21 3.504 21 4.125v15.75c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 01-1.125-1.125V4.125z" />',
  columns: '<path stroke-linecap="round" stroke-linejoin="round" d="M9 4.5v15m6-15v15M4.5 4.5h15a1.5 1.5 0 011.5 1.5v12a1.5 1.5 0 01-1.5 1.5h-15A1.5 1.5 0 013 18V6a1.5 1.5 0 011.5-1.5z" />'
}

const LAYOUT_DEFAULTS = {
  section: { label: "Section Title", content: "" },
  divider: { label: "Divider", content: "" },
  heading: { label: "Heading", content: "Heading Text", heading_level: "h3" },
  paragraph: { label: "Paragraph", content: "Enter your text here..." },
  spacer: { label: "Spacer", content: "", spacer_height: "md" },
  alert: { label: "Alert", content: "Important notice", alert_variant: "info" },
  image: { label: "Image", content: "", image_url: "", alt_text: "" },
  callout: { label: "Callout", content: "Highlighted information" },
  quote: { label: "Quote", content: "Enter your quote here...", attribution: "" },
  button: { label: "Button", content: "Click Me", button_url: "#", button_variant: "primary", button_size: "md", alignment: "left" },
  video: { label: "Video", content: "", video_url: "", alignment: "center" },
  list: { label: "List", content: "Item 1\nItem 2\nItem 3", list_style: "bullet" },
  code_block: { label: "Code Block", content: "// Your code here", code_language: "" },
  card: { label: "Card Title", content: "Card description goes here." },
  progress_bar: { label: "Progress", content: "", progress_value: 50, progress_color: "indigo" },
  columns: { label: "Columns", content: "", column_layout: "50-50", columns: [{ fields: [] }, { fields: [] }] }
}

export { FIELD_TYPE_MAPPING, FIELD_ICONS, LAYOUT_ICONS, LAYOUT_DEFAULTS, WIDTH_CLASSES }

export class FieldManager extends BaseManager {

  // Layout elements that always occupy a full row and force breaks
  static FULL_ROW_TYPES = new Set(["section", "divider", "heading", "paragraph", "spacer", "alert", "callout", "quote", "columns", "card", "list", "code_block", "progress_bar", "video", "image", "button", "field_group"])

  // Returns the effective render width for a field, applying layout template rules when active.
  // Non-destructive: does not modify the stored field.width.
  _effectiveWidth(field) {
    if (field.property_type === "layout") return field.width || "full"

    const viewport = this.c.viewportValue || "desktop"

    if (viewport !== "desktop" && field.responsive_widths) {
      const override = field.responsive_widths[viewport]
      if (override) return override
      if (viewport === "mobile" && field.responsive_widths.tablet) {
        return field.responsive_widths.tablet
      }
    }

    // A width the user set explicitly (toolbar, context menu, bulk bar, resize)
    // must win over the layout template's per-type default — otherwise width
    // changes silently do nothing on template-based pages.
    const layout = this.c.layoutTemplateValue
    if (field.width_explicit || !layout || Object.keys(layout).length === 0) return field.width || "full"
    return layout.field_width_rules?.[field.html_type] || layout.default_width || field.width || "full"
  }

  _getBreakpointBadge(field) {
    if (!field.responsive_widths) return ""
    const badges = []
    if (field.responsive_widths.tablet) badges.push("T")
    if (field.responsive_widths.mobile) badges.push("M")
    if (badges.length === 0) return ""
    return `<span class="text-[9px] font-bold text-indigo-500 bg-indigo-50 rounded px-0.5">${badges.join("")}</span>`
  }

  groupFieldsIntoRows(fields) {
    const rows = []
    let currentRow = { fields: [], usedCols: 0 }

    for (const field of fields) {
      // Field groups always get their own row
      if (field.type === "field_group") {
        if (currentRow.fields.length > 0) {
          rows.push(currentRow)
          currentRow = { fields: [], usedCols: 0 }
        }
        rows.push({ fields: [field], usedCols: 12, isGroupRow: true })
        continue
      }

      const isLayout = field.property_type === "layout"
      const isFullRowLayout = isLayout && FieldManager.FULL_ROW_TYPES.has(field.field_type)

      // Full-width layout elements always get their own row
      if (isFullRowLayout) {
        if (currentRow.fields.length > 0) {
          rows.push(currentRow)
          currentRow = { fields: [], usedCols: 0 }
        }
        rows.push({ fields: [field], usedCols: 12, isLayoutRow: true, layoutType: field.field_type })
        continue
      }

      const effectiveWidth = this._effectiveWidth(field)
      const cols = WIDTH_COLS[effectiveWidth] || 12
      if (currentRow.usedCols + cols > 12 && currentRow.fields.length > 0) {
        rows.push(currentRow)
        currentRow = { fields: [], usedCols: 0 }
      }
      currentRow.fields.push(field)
      currentRow.usedCols += cols
    }

    if (currentRow.fields.length > 0) rows.push(currentRow)
    return rows
  }

  // ---------------------------------------------------------------------------
  // Automatic section dividers
  //
  // Sections are flat markers in the field list (not nested containers), so we
  // keep a divider line between consecutive sections: one immediately before
  // every section header except the first, and never after the last section.
  // Auto-managed dividers carry `auto_section_divider: true` so user-added
  // dividers are left untouched. Because this runs on every render, adding,
  // deleting, or moving a section keeps the dividers correct without each
  // operation having to manage them itself.
  // ---------------------------------------------------------------------------
  _isSectionField(f) {
    return f && f.property_type === "layout" && f.field_type === "section"
  }

  _isAutoSectionDivider(f) {
    return f && f.property_type === "layout" && f.field_type === "divider" && f.auto_section_divider === true
  }

  _isDivider(f) {
    return f && f.property_type === "layout" && f.field_type === "divider"
  }

  _makeAutoSectionDivider() {
    const divider = this.createField({ type: "divider", label: "" })
    divider.auto_section_divider = true
    return divider
  }

  normalizeSectionDividers() {
    const fields = this.c.currentPageFields
    if (!Array.isArray(fields) || fields.length === 0) return
    if (this._sectionDividersValid(fields)) return // already correct — keep ids stable (idempotent)

    // 1) Drop existing auto dividers. 2) Drop any run of dividers sitting
    //    immediately before a NON-FIRST section header — that slot is a section
    //    separator we own. This self-heals data where an auto divider lost its
    //    `auto_section_divider` flag on a save round-trip (it would otherwise be
    //    kept as a user divider AND get a fresh auto one stacked beside it).
    const base = fields.filter(f => !this._isAutoSectionDivider(f))
    const firstSectionIdx = base.findIndex(f => this._isSectionField(f))

    const cleaned = []
    for (let i = 0; i < base.length; i++) {
      if (this._isDivider(base[i])) {
        let j = i
        while (j < base.length && this._isDivider(base[j])) j++
        if (j < base.length && this._isSectionField(base[j]) && j > firstSectionIdx) {
          i = j - 1 // skip the whole divider run before this section header
          continue
        }
      }
      cleaned.push(base[i])
    }

    const sectionCount = cleaned.filter(f => this._isSectionField(f)).length
    let rebuilt
    if (sectionCount <= 1) {
      rebuilt = cleaned
    } else {
      rebuilt = []
      let seenSections = 0
      for (const f of cleaned) {
        if (this._isSectionField(f)) {
          seenSections++
          if (seenSections > 1) rebuilt.push(this._makeAutoSectionDivider())
        }
        rebuilt.push(f)
      }
    }

    rebuilt.forEach((f, i) => { f.order = i })
    this.c.currentPage.fields = rebuilt
  }

  // True when exactly one auto-divider (and no other divider) sits immediately
  // before every section header except the first, with no auto-divider elsewhere.
  _sectionDividersValid(fields) {
    let seenSections = 0
    for (let i = 0; i < fields.length; i++) {
      if (this._isSectionField(fields[i])) {
        seenSections++
        if (seenSections > 1) {
          if (!this._isAutoSectionDivider(fields[i - 1])) return false // missing/ wrong separator
          if (this._isDivider(fields[i - 2])) return false             // a second divider stacked before it
        }
      }
    }
    // Every auto-divider must sit immediately before a section header.
    for (let i = 0; i < fields.length; i++) {
      if (this._isAutoSectionDivider(fields[i]) && !this._isSectionField(fields[i + 1])) return false
    }
    return true
  }

  renderFields() {
    if (!this.c.hasFieldsContainerTarget) return

    this.normalizeSectionDividers()
    this.c.fields = this.c.currentPageFields

    if (this.c.hasEmptyStateTarget) {
      this.c.emptyStateTarget.classList.toggle("hidden", this.c.fields.length > 0)
    }

    this.c.fieldsContainerTarget.querySelectorAll(".field-card, .inserter-row, .row-drop-zone, .section-group, .field-group").forEach(el => el.remove())

    const fields = this.c.fields
    const rows = this.groupFieldsIntoRows(fields)

    // Group rows into visual sections for better layout
    const sectionGroups = this._groupRowsIntoSections(rows)

    sectionGroups.forEach((group) => {
      if (group.type === "section") {
        this._renderSectionGroup(group)
      } else {
        group.rows.forEach(row => this._renderRow(row))
      }
    })

    // Final inserter after last row
    if (fields.length > 0) {
      this.c.fieldsContainerTarget.appendChild(this._createInserterRow(fields.length))
    }

    this.updateSidebarFieldStates()
    this.c.pageManager.updateFormFooter()
  }

  // Organize rows into visual section groups for rendering
  _groupRowsIntoSections(rows) {
    const groups = []
    let currentGroup = { type: "standalone", rows: [] }

    for (const row of rows) {
      const isSectionHeader = row.isLayoutRow && row.layoutType === "section"
      const isDivider = row.isLayoutRow && row.layoutType === "divider"

      if (isSectionHeader) {
        // Flush previous group
        if (currentGroup.rows.length > 0) {
          groups.push(currentGroup)
        }
        // Start a new section group
        currentGroup = { type: "section", sectionField: row.fields[0], rows: [] }
      } else if (isDivider && currentGroup.type === "section") {
        // Dividers inside sections end the section group
        if (currentGroup.rows.length > 0 || currentGroup.sectionField) {
          groups.push(currentGroup)
        }
        // Push divider as standalone
        groups.push({ type: "standalone", rows: [row] })
        currentGroup = { type: "standalone", rows: [] }
      } else {
        currentGroup.rows.push(row)
      }
    }

    if (currentGroup.rows.length > 0 || currentGroup.sectionField) {
      groups.push(currentGroup)
    }

    return groups
  }

  // Organize fields by source group order:
  // 1. Entity fields (base model + own + nested) with their section header
  // 2. Associated entity fields, each group with its own section header
  // Fields without source metadata are treated as entity fields.
  // Within each group, original relative order is preserved.
  _organizeFieldsBySource(fields) {
    // Separate fields into source groups while preserving relative order
    const entityFields = []     // source === "entity" or no source
    const associatedGroups = {} // keyed by source_section
    const associatedOrder = []  // track insertion order of associated sections
    const standaloneLayouts = [] // layout elements without source (manually added)

    // First pass: categorize
    for (const field of fields) {
      const source = field.source
      const section = field.source_section

      if (source === "bridge" && section) {
        if (!associatedGroups[section]) {
          associatedGroups[section] = []
          associatedOrder.push(section)
        }
        associatedGroups[section].push(field)
      } else if (source === "entity" || field.property_type !== "layout" || (field.field_type === "section" && !source)) {
        // Entity-sourced fields, data fields without source, or section headers without source
        entityFields.push(field)
      } else {
        // Standalone layout elements (dividers, spacers, headings added manually)
        standaloneLayouts.push(field)
      }
    }

    // Ensure entity group has a section header
    const entityName = this.c.metadata?.entity_name || null
    this._ensureSectionHeader(entityFields, "entity", entityName)

    // Ensure each associated group has a section header
    for (const sectionName of associatedOrder) {
      this._ensureSectionHeader(associatedGroups[sectionName], "bridge", sectionName)
    }

    // Assemble final order: entity fields -> associated groups -> standalone layouts
    const result = [...entityFields]
    for (const sectionName of associatedOrder) {
      result.push(...associatedGroups[sectionName])
    }
    result.push(...standaloneLayouts)

    return result
  }

  // Ensures a source group has a section header at the beginning.
  // If no section header exists, one is auto-generated.
  _ensureSectionHeader(groupFields, source, sectionName = null) {
    if (groupFields.length === 0) return

    const hasSectionHeader = groupFields.some(f => f.field_type === "section" && f.property_type === "layout")
    if (hasSectionHeader) {
      // Move the section header to the front of the group if not already there
      const headerIdx = groupFields.findIndex(f => f.field_type === "section" && f.property_type === "layout")
      if (headerIdx > 0) {
        const [header] = groupFields.splice(headerIdx, 1)
        groupFields.unshift(header)
      }
      return
    }

    // Auto-generate a section header
    const label = sectionName || this.c.autoSectionFallbackLabelValue
    const header = {
      id: `section_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      field_type: "section",
      property_slug: label.toLowerCase().replace(/\s+/g, '_'),
      property_type: "layout",
      label: source === "entity" ? `${label} Fields` : label,
      placeholder: "",
      help_text: "",
      required: false,
      width: "full",
      order: 0,
      source: source,
      source_section: sectionName
    }
    groupFields.unshift(header)
  }

  _renderSectionGroup(group) {
    const container = this.c.fieldsContainerTarget

    // Section wrapper — spans full grid width
    const wrapper = document.createElement("div")
    wrapper.className = "section-group col-span-12 rounded-xl border border-gray-100 bg-gradient-to-b from-gray-50/80 to-white mb-1"

    // Section header
    const sectionField = group.sectionField
    wrapper.dataset.sectionId = sectionField.id
    const inserter = this._createInserterRow(sectionField.order)
    container.appendChild(inserter)

    const headerCard = this.createFieldCard(sectionField)
    // Override default section card styling for section-group headers
    headerCard.className = `field-card layout-card group cursor-pointer transition-all col-span-12 ${sectionField.id === this.c.selectedFieldId ? "selected ring-2 ring-indigo-500 ring-offset-1" : ""}`
    // Double-clicking the header selects the whole section (header + all child fields).
    headerCard.dataset.action = `${headerCard.dataset.action} dblclick->page-builder#selectSection`
    wrapper.appendChild(headerCard)

    // Render child rows inside the section wrapper with inner grid
    if (group.rows.length > 0) {
      const innerGrid = document.createElement("div")
      innerGrid.className = "grid grid-cols-12 gap-2 px-3 pb-3 pt-1"

      group.rows.forEach(row => {
        // Inserter inside section
        const rowInserter = this._createInserterRow(row.fields[0].order)
        innerGrid.appendChild(rowInserter)

        row.fields.forEach(field => {
          const card = this.createFieldCard(field)
          innerGrid.appendChild(card)
        })

        if (row.usedCols < 12 && !row.isLayoutRow) {
          const remainingCols = 12 - row.usedCols
          innerGrid.appendChild(this._createRowDropZone(row, remainingCols))
        }
      })

      wrapper.appendChild(innerGrid)
    }

    container.appendChild(wrapper)
  }

  _renderRow(row) {
    const container = this.c.fieldsContainerTarget

    // If the row contains a field_group, render it directly
    if (row.isGroupRow) {
      const group = row.fields[0]
      container.appendChild(this._createInserterRow(group.order || 0))
      const groupEl = this._renderFieldGroup(group)
      container.appendChild(groupEl)
      return
    }

    // Inserter before each row group
    container.appendChild(this._createInserterRow(row.fields[0].order))

    // Render each field in the row
    row.fields.forEach(field => {
      const card = this.createFieldCard(field)
      container.appendChild(card)
    })

    // If row has remaining space, add a row drop zone
    if (row.usedCols < 12 && !row.isLayoutRow) {
      const remainingCols = 12 - row.usedCols
      container.appendChild(this._createRowDropZone(row, remainingCols))
    }
  }

  _createInserterRow(index) {
    const row = document.createElement("div")
    row.className = "inserter-row col-span-12 group/inserter flex items-center justify-center py-0.5"
    row.innerHTML = `
      <button type="button"
              class="opacity-0 group-hover/inserter:opacity-100 focus:opacity-100 inline-flex items-center gap-1 px-3 py-1 rounded-full text-xs font-medium text-gray-400 hover:text-indigo-600 hover:bg-indigo-50 border border-transparent hover:border-indigo-200 transition-all"
              data-insert-index="${index}"
              data-action="click->page-builder#openInserterPopover">
        <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
        </svg>
      </button>
    `
    return row
  }

  _createRowDropZone(row, remainingCols) {
    const colSpanClass = { 4: "col-span-4", 6: "col-span-6", 8: "col-span-8" }[remainingCols] || `col-span-${remainingCols}`
    const zone = document.createElement("div")
    zone.className = `row-drop-zone ${colSpanClass} min-h-[3rem] border-2 border-dashed border-transparent rounded-lg transition-all flex items-center justify-center`
    zone.dataset.rowInsertIndex = String(row.fields[row.fields.length - 1].order + 1)
    zone.dataset.remainingCols = String(remainingCols)
    // Drop handling is owned by the pointer-events DragEngine via geometry; this
    // zone is now just the visual "remaining space" hint.

    zone.innerHTML = `
      <span class="text-xs text-gray-300 opacity-0 transition-opacity pointer-events-none" data-zone-hint>
        ${this.escapeHtml(this.c.dropHereLabelValue)}
      </span>
    `
    return zone
  }

  createFieldCard(field) {
    const div = document.createElement("div")
    const isSelected = field.id === this.c.selectedFieldId
    const isLayout = field.property_type === "layout"

    div.dataset.fieldId = field.id
    div.dataset.width = field.width || "full"
    div.dataset.dragKind = "move"
    div.setAttribute("role", "listitem")
    div.setAttribute("aria-selected", isSelected)
    div.setAttribute("aria-label", `${field.label || this.c.untitledFieldLabelValue} ${isLayout ? this.c.ariaLayoutComponentLabelValue : this.c.ariaFieldLabelValue}`)

    div.dataset.action = [
      "click->page-builder#selectField",
      "pointerdown->page-builder#dragPointerDown",
      "contextmenu->page-builder#openFieldContextMenu"
    ].join(" ")

    const colSpanClass = WIDTH_CLASSES[this._effectiveWidth(field)] || "col-span-12"
    if (isLayout) {
      div.className = `field-card layout-card group cursor-pointer transition-all relative ${isSelected ? "selected ring-2 ring-indigo-500 ring-offset-1" : ""} ${colSpanClass}`
      div.innerHTML = this.createLayoutCardHtml(field)
    } else {
      div.className = `field-card group bg-white rounded-lg border border-gray-200 p-2 cursor-pointer hover:border-gray-300 transition-all relative ${isSelected ? "selected ring-2 ring-indigo-500 ring-offset-1" : ""} ${colSpanClass}`
      div.innerHTML = this.createDataFieldCardHtml(field) +
        '<div class="absolute inset-0 rounded-lg opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none border-2 border-transparent group-hover:border-indigo-200/50"></div>'
    }

    // Append resize handle when a single data field is selected (not layout)
    if (isSelected && !isLayout) {
      const handle = document.createElement("div")
      handle.className = "resize-handle absolute right-0 top-1/2 -translate-y-1/2 translate-x-1/2 w-1.5 h-8 bg-gray-300 rounded-full cursor-col-resize hover:bg-indigo-400 transition-all z-20"
      handle.dataset.action = "mousedown->page-builder#startResize"
      div.appendChild(handle)
    }

    return div
  }

  createDataFieldCardHtml(field) {
    const iconStyle = this._fieldIconStyle(field)
    const icon = this.getFieldIcon(field.property_type, field.field_type, iconStyle.text, field.html_type)
    const theme = this.c.configuration.theme || {}

    return `
      <div class="flex items-center justify-between mb-1">
        <div class="flex items-center flex-1 min-w-0 gap-1.5">
          <div class="w-5 h-5 rounded ${iconStyle.bg} flex items-center justify-center flex-shrink-0">
            ${icon}
          </div>
          <div class="flex items-center gap-1 min-w-0">
            <span class="text-xs font-medium text-gray-900 truncate" data-action="dblclick->page-builder#startInlineEdit" data-inline-edit-property="label">${this.escapeHtml(field.label || this.c.untitledFieldLabelValue)}</span>
            ${field.required ? '<span class="text-red-500 text-[10px]">*</span>' : ""}
            ${this._getBreakpointBadge(field)}
            <svg class="w-3 h-3 text-gray-300 opacity-0 group-hover:opacity-50 transition-opacity inline-block ml-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"/></svg>
          </div>
          ${this._getDependencyBadgeHtml(field)}
        </div>
        ${this.cardActionButtons(field)}
      </div>
      ${this.getFieldPreviewHtml(field, theme)}
      ${field.help_text ? `<p class="mt-0.5 text-[11px] text-gray-400 truncate">${this.escapeHtml(field.help_text)}</p>` : ""}
    `
  }

  getFieldIcon(type, fieldType, colorClass = null, htmlType = null) {
    if (type === "layout" && fieldType && LAYOUT_ICONS[fieldType]) {
      const path = LAYOUT_ICONS[fieldType]
      return `<svg class="w-3.5 h-3.5 text-violet-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">${path}</svg>`
    }
    // Prefer html_type-specific icon, then property_type fallback
    const path = (htmlType && HTML_TYPE_ICONS[htmlType]) || FIELD_ICONS[type] || FIELD_ICONS.string
    const cls = colorClass || "text-gray-500"
    return `<svg class="w-3.5 h-3.5 ${cls}" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">${path}</svg>`
  }

  // Selection
  selectField(event) {
    const card = event.currentTarget
    const fieldId = card.dataset.fieldId

    if (event.target.closest(".field-drag-handle")) return
    if (event.target.closest(".field-remove-btn")) return
    if (event.target.closest(".field-duplicate-btn")) return

    this.c.selectionManager.selectField(fieldId, {
      shift: event.shiftKey,
      meta: event.ctrlKey || event.metaKey
    })
  }

  // Double-click a section header → select the header and every field inside the section.
  selectSection(event) {
    // Defer to inline editing when the double-click lands on the editable title text.
    if (event.target.closest("[data-inline-edit-property]")) return

    const wrapper = event.currentTarget.closest(".section-group")
    if (!wrapper) return

    const fieldIds = Array.from(wrapper.querySelectorAll(".field-card"))
      .map(card => card.dataset.fieldId)
      .filter(Boolean)
    if (fieldIds.length === 0) return

    this.c.selectionManager.selectFields(fieldIds)
  }

  selectFieldById(fieldId, opts = {}) {
    this.c.selectionManager.selectField(fieldId, { shift: false, meta: false, ...opts })
  }

  deselectField() {
    this.c.selectionManager.deselectAll()
  }

  updateField(_event) {
    if (!this.c.selectedFieldId) return

    const field = this.c.fields.find(f => f.id === this.c.selectedFieldId)
    if (!field) return

    const form = this.c.propertyFormTarget
    const formData = new FormData(form)

    this.c.undoRedoManager.saveState()

    field.label = formData.get("label") || field.label
    field.placeholder = formData.get("placeholder") || ""
    field.help_text = formData.get("help_text") || ""
    field.required = formData.get("required") === "on"
    field.width = formData.get("width") || field.width || "full"

    if (field.property_type === "layout") {
      field.content = formData.get("content") || ""
      if (field.field_type === "heading") {
        field.heading_level = formData.get("heading_level") || "h3"
      }
      if (field.field_type === "spacer") {
        field.spacer_height = formData.get("spacer_height") || "md"
      }
      if (field.field_type === "alert") {
        field.alert_variant = formData.get("alert_variant") || "info"
      }
      if (field.field_type === "image") {
        field.image_url = formData.get("image_url") || ""
        field.alt_text = formData.get("alt_text") || ""
      }
      if (field.field_type === "quote") {
        field.attribution = formData.get("attribution") || ""
      }
      if (field.field_type === "button") {
        field.button_url = formData.get("button_url") || "#"
        field.button_variant = formData.get("button_variant") || "primary"
        field.button_size = formData.get("button_size") || "md"
        field.alignment = formData.get("alignment") || "left"
      }
      if (field.field_type === "video") {
        field.video_url = formData.get("video_url") || ""
        field.alignment = formData.get("alignment") || "center"
      }
      if (field.field_type === "list") {
        field.list_style = formData.get("list_style") || "bullet"
      }
      if (field.field_type === "code_block") {
        field.code_language = formData.get("code_language") || ""
      }
      if (field.field_type === "progress_bar") {
        field.progress_value = parseInt(formData.get("progress_value")) || 0
        field.progress_color = formData.get("progress_color") || "indigo"
      }
    }

    this.renderFields()
    this.selectFieldById(this.c.selectedFieldId)
  }

  _renderFieldGroup(group) {
    const colSpanClass = WIDTH_CLASSES[group.width || "full"] || "col-span-12"
    const borderClass = { dashed: "border-dashed border-gray-300", solid: "border-solid border-gray-300", subtle: "border-solid border-gray-200", none: "border-transparent" }[group.style?.border || "dashed"]
    const bgClass = { light_gray: "bg-gray-50", light_blue: "bg-blue-50/30", none: "bg-transparent" }[group.style?.background || "none"]

    const groupDiv = document.createElement("div")
    groupDiv.className = `field-group group border-2 ${borderClass} ${bgClass} rounded-lg p-2 space-y-1 cursor-pointer ${colSpanClass}`
    groupDiv.dataset.groupId = group.id
    groupDiv.dataset.fieldId = group.id
    groupDiv.dataset.action = "click->page-builder#selectField contextmenu->page-builder#openFieldContextMenu"

    const isSelected = this.c.selectionManager?.isSelected(group.id)
    if (isSelected) groupDiv.classList.add("selected", "ring-2", "ring-indigo-500", "ring-offset-1")

    groupDiv.innerHTML = `
      <div class="flex items-center justify-between mb-1">
        <span class="text-xs font-semibold text-gray-600 truncate"
              data-action="dblclick->page-builder#startInlineEdit"
              data-inline-edit-property="label">${this.escapeHtml(group.label || this.c.fieldGroupLabelValue)}</span>
        <div class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
          <button type="button" class="text-[10px] text-gray-400 hover:text-indigo-500 px-1"
                  data-action="click->page-builder#ungroupFields" data-group-id="${group.id}">${this.escapeHtml(this.c.ungroupLabelValue)}</button>
          <button type="button" class="text-[10px] text-gray-400 hover:text-indigo-500 px-1"
                  data-action="click->page-builder#saveFieldAsTemplate" data-field-id="${group.id}">${this.escapeHtml(this.c.saveAsTemplateLabelValue)}</button>
        </div>
      </div>
    `

    const nestedGrid = document.createElement("div")
    nestedGrid.className = "grid grid-cols-12 gap-1"
    nestedGrid.dataset.groupFieldsContainer = group.id

    ;(group.fields || []).forEach(field => {
      const card = this.createFieldCard(field)
      nestedGrid.appendChild(card)
    })

    groupDiv.appendChild(nestedGrid)
    return groupDiv
  }

  // Sidebar state management
  getUsedPropertySlugs() {
    return new Set(this.c.allFields.map(f => f.property_slug).filter(Boolean))
  }

  updateSidebarFieldStates() {
    const usedSlugs = this.getUsedPropertySlugs()
    const disabledClasses = ["opacity-40", "cursor-not-allowed", "pointer-events-none"]

    let totalAvailable = 0
    this.c.element.querySelectorAll(".entity-field-item").forEach(item => {
      const slug = item.dataset.propertySlug
      if (usedSlugs.has(slug)) {
        item.draggable = false
        item.classList.add(...disabledClasses)
        item.classList.remove("cursor-grab")
      } else {
        item.draggable = true
        item.classList.remove(...disabledClasses)
        item.classList.add("cursor-grab")
        totalAvailable++
      }
    })

    // Update sidebar field count badge
    if (this.c.hasEntityFieldCountTarget) {
      const total = this.c.element.querySelectorAll(".entity-field-item").length
      this.c.entityFieldCountTarget.textContent = totalAvailable < total ? `${totalAvailable}/${total}` : total
    }

    // Update "Add" / "Remove" button states per section
    this.c.element.querySelectorAll("[data-searchable-section]").forEach(section => {
      const items = section.querySelectorAll(".entity-field-item")
      const slugs = Array.from(items).map(item => item.dataset.propertySlug).filter(Boolean)
      const allUsed = slugs.every(slug => usedSlugs.has(slug))
      const noneUsed = slugs.every(slug => !usedSlugs.has(slug))

      const addBtn = section.querySelector("[data-add-all-section]")
      if (addBtn) {
        addBtn.disabled = allUsed
        addBtn.classList.toggle("opacity-40", allUsed)
        addBtn.classList.toggle("cursor-not-allowed", allUsed)
      }

      const removeBtn = section.querySelector("[data-remove-all-section]")
      if (removeBtn) {
        removeBtn.disabled = noneUsed
        removeBtn.classList.toggle("opacity-40", noneUsed)
        removeBtn.classList.toggle("cursor-not-allowed", noneUsed)
      }
    })
  }

  renderFieldCard(field) {
    const existingCard = this.c.element.querySelector(`[data-field-id="${field.id}"]`)
    if (!existingCard) return

    const newCard = this.createFieldCard(field)
    existingCard.replaceWith(newCard)

    // Re-apply selection visuals after replacing card
    if (this.c.selectionManager) {
      this.c.selectionManager.updateVisuals()
    }
  }

}

Object.assign(FieldManager.prototype, LayoutCardsMixin)
Object.assign(FieldManager.prototype, FieldPreviewsMixin)
Object.assign(FieldManager.prototype, FieldCrudMixin)
Object.assign(FieldManager.prototype, DragReorderMixin)
Object.assign(FieldManager.prototype, DependencyOverlayMixin)
