import { BaseManager } from "controllers/page_builder/base_manager"
import { TypeSettingsMixin } from "controllers/page_builder/property_manager/type_settings"
import { FormBuilderMixin } from "controllers/page_builder/property_manager/form_builder"
import { BreadcrumbMixin } from "controllers/page_builder/property_manager/breadcrumb"
import { WidthBreakpointMixin } from "controllers/page_builder/property_manager/width_breakpoint"
import { ThemeMixin } from "controllers/page_builder/property_manager/theme"

export const OPTIONS_FIELD_TYPES = ["select", "multi-select", "radio", "checkbox", "switch"]

export const HTML_TYPE_DISPLAY_NAMES = {
  text: "Input Text", textarea: "Text Area", search: "Search",
  password: "Password", hidden: "Hidden",
  select: "Dropdown", "multi-select": "Multi Select",
  radio: "Radio", checkbox: "Checkbox", switch: "Toggle Switch",
  number: "Number", currency: "Currency", range: "Range Slider", rating: "Rating",
  date: "Date", time: "Time", "datetime-local": "Date & Time", month: "Month", week: "Week",
  email: "Email", tel: "Phone", url: "URL",
  "rich-text": "Rich Text", signature: "Signature",
  file: "File Upload", image: "Image Upload", color: "Color Picker"
}

export const TYPE_SETTINGS_MAP = {
  text:             ["fieldMaxLength", "fieldMinLength", "fieldPattern", "fieldAutocomplete"],
  textarea:         ["fieldRows", "fieldMaxLength", "fieldResize"],
  search:           [],
  password:         ["fieldShowToggle", "fieldMinLength"],
  hidden:           [],
  select:           ["fieldAllowBlank", "fieldSearchable"],
  "multi-select":   ["fieldMinMaxSelections", "fieldSearchable"],
  radio:            ["fieldInlineLayout"],
  checkbox:         ["fieldInlineLayout"],
  switch:           ["fieldOnOffLabel"],
  number:           ["fieldMinMaxValue", "fieldStep"],
  currency:         ["fieldCurrencySymbol", "fieldDecimalPlaces", "fieldMinMaxValue"],
  range:            ["fieldMinMaxValue", "fieldStep", "fieldShowValue"],
  rating:           ["fieldMaxRating", "fieldAllowHalf"],
  date:             ["fieldMinMaxConstraint"],
  time:             ["fieldMinMaxConstraint", "fieldTimeStep"],
  "datetime-local": ["fieldMinMaxConstraint"],
  month:            ["fieldMinMaxConstraint"],
  week:             ["fieldMinMaxConstraint"],
  email:            ["fieldAllowMultiple"],
  tel:              ["fieldPhonePattern"],
  url:              [],
  "rich-text":      ["fieldToolbar", "fieldMaxLength"],
  signature:        ["fieldCanvasHeight", "fieldPenColor", "fieldPenWidth"],
  file:             ["fieldAcceptTypes", "fieldMaxFileSize", "fieldAllowMultiple"],
  image:            ["fieldAcceptTypes", "fieldMaxFileSize"],
  color:            ["fieldColorFormat"]
}

export const DATE_TIME_INPUT_TYPES = {
  date: "date",
  time: "time",
  "datetime-local": "datetime-local",
  month: "month",
  week: "week"
}

// Dynamic "Settings" section heading per layout type — English source of
// truth for the layoutSettingsLabels i18n Value (see page_builder_controller.js).
export const SETTINGS_SECTION_LABELS = {
  heading: "Heading Settings", paragraph: "Paragraph Settings",
  section: "Section Settings", divider: "Divider Settings",
  spacer: "Spacer Settings", alert: "Alert Settings",
  image: "Image Settings", button: "Button Settings",
  video: "Video Settings", list: "List Settings",
  code_block: "Code Block Settings", card: "Card Settings",
  progress_bar: "Progress Bar Settings", columns: "Column Settings",
  callout: "Callout Settings", quote: "Quote Settings"
}

// Human-readable condition operator labels for the advanced-tab rule summary —
// English source of truth for the operatorLabels i18n Value.
export const OPERATOR_LABELS = {
  equals: "equals", not_equals: "does not equal", contains: "contains",
  not_contains: "does not contain", greater_than: ">", less_than: "<",
  is_empty: "is empty", is_not_empty: "is not empty"
}
export class PropertyManager extends BaseManager {
  showFloatingPanel(fieldId) {
    const field = this.c.currentPageFields.find(f => f.id === fieldId)
    if (!field) return

    this.c.selectedFieldValue = fieldId
    this.c.selectedFieldId = fieldId
    this.c.floatingPanelVisibleValue = true

    // Remove multi-select overlay, restore property panel
    this._removeMultiSelectOverlay()
    if (this.c.hasPropertyPanelTarget) {
      this.c.propertyPanelTarget.style.display = ""
    }

    this.populatePropertyPanel(field)
    this.syncToolbarWidth(field)

    if (this.c.hasFloatingPanelTarget) {
      this.c.floatingPanelTarget.classList.remove("hidden")
    }
  }

  hideFloatingPanel() {
    this.c.floatingPanelVisibleValue = false
    this.c.selectedFieldValue = null
    this.resetToolbarWidth()
    this._removeMultiSelectOverlay()

    if (this.c.hasPropertyPanelTarget) {
      this.c.propertyPanelTarget.style.display = ""
    }

    if (this.c.hasFloatingPanelTarget) {
      this.c.floatingPanelTarget.classList.add("hidden")
    }
  }

  isFloatingPanelVisible() {
    if (!this.c.hasFloatingPanelTarget) return false
    return !this.c.floatingPanelTarget.classList.contains("hidden")
  }

  showMultiSelectToolbar(count) {
    if (!this.c.hasFloatingPanelTarget) return

    this.c.floatingPanelVisibleValue = true
    this.resetToolbarWidth()

    // Hide property panel, create dynamic overlay
    if (this.c.hasPropertyPanelTarget) {
      this.c.propertyPanelTarget.style.display = "none"
    }

    this._removeMultiSelectOverlay()
    const overlay = document.createElement("div")
    overlay.className = "relative h-full flex flex-col bg-white"
    overlay.setAttribute("data-multi-select-overlay", "")
    overlay.innerHTML = `
      <div class="p-4 space-y-3">
        <div class="flex items-center gap-2">
          <span class="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
            ${this.escapeHtml(this.c.fieldsSelectedLabelValue.replace("{count}", count))}
          </span>
        </div>

        <div class="space-y-2">
          <button type="button"
                  data-action="click->page-builder#openMoveToPageModal"
                  class="w-full flex items-center gap-2 px-3 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors">
            <svg class="w-4 h-4 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M7 16V4m0 0L3 8m4-4l4 4m6 0v12m0 0l4-4m-4 4l-4-4" />
            </svg>
            ${this.escapeHtml(this.c.moveToPageEllipsisLabelValue)}
          </button>

          <button type="button"
                  data-action="click->page-builder#deleteField"
                  class="w-full flex items-center gap-2 px-3 py-2 text-sm font-medium text-red-700 bg-white border border-red-200 rounded-lg hover:bg-red-50 transition-colors">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
            </svg>
            ${this.escapeHtml(this.c.deleteSelectedLabelValue)}
          </button>
        </div>

        <button type="button"
                data-action="click->page-builder#deselectField"
                class="text-xs text-gray-500 hover:text-gray-700 underline">
          ${this.escapeHtml(this.c.deselectAllLabelValue)}
        </button>
      </div>
    `

    this.c.floatingPanelTarget.appendChild(overlay)
    this.c.floatingPanelTarget.classList.remove("hidden")
  }

  _removeMultiSelectOverlay() {
    if (!this.c.hasFloatingPanelTarget) return
    const overlay = this.c.floatingPanelTarget.querySelector("[data-multi-select-overlay]")
    if (overlay) overlay.remove()
  }

  populatePropertyPanel(field) {
    this._activeBreakpoint = "desktop"
    const isLayout = field.property_type === "layout"
    const fieldType = field.field_type || ""
    const isColumns = isLayout && fieldType === "columns"
    const isGroup = field.type === "field_group"

    // Tab visibility based on field category
    if (this.c.hasPropertyTabsTarget) {
      const tabBar = this.c.propertyTabsTarget
      tabBar.querySelectorAll("[data-tab]").forEach(btn => {
        const tab = btn.dataset.tab
        const _section = btn.dataset.fieldSection
        let show = false

        if (isGroup) {
          show = (tab === "content" || tab === "style")
        } else if (isColumns) {
          show = (tab === "structure" || tab === "style")
        } else if (isLayout) {
          show = (tab === "content" || tab === "style")
        } else {
          // data fields
          show = (tab === "content" || tab === "layout" || tab === "validation" || tab === "advanced")
        }

        btn.classList.toggle("hidden", !show)
      })

      // Activate default tab
      const defaultTab = isColumns ? "structure" : "content"
      tabBar.querySelectorAll("[data-tab]").forEach(btn => {
        btn.classList.remove("border-indigo-500", "text-indigo-600")
        btn.classList.add("border-transparent", "text-gray-500")
        if (btn.dataset.tab === defaultTab) {
          btn.classList.remove("border-transparent", "text-gray-500")
          btn.classList.add("border-indigo-500", "text-indigo-600")
        }
      })

      // Show/hide tab content panels
      const panel = this.c.floatingPanelTarget
      panel.querySelectorAll("[data-property-tab-content]").forEach(el => {
        el.classList.toggle("hidden", el.dataset.propertyTabContent !== defaultTab)
      })
    }

    // Panel header — field name
    if (this.c.hasFieldNameTarget) {
      this.c.fieldNameTarget.textContent = field.label || field.property_slug || this.c.untitledFieldLabelValue
      this.c.fieldNameTarget.title = field.label || field.property_slug || ""
    }

    // Panel header — type label (use html_type with friendly display name)
    if (this.c.hasFieldTypeLabelTarget) {
      if (isGroup) {
        this.c.fieldTypeLabelTarget.textContent = this.c.fieldGroupLabelValue
      } else {
        const htmlType = field.html_type || fieldType
        const label = isLayout
          ? this.formatLabel(fieldType || "layout")
          : (this.c.htmlTypeDisplayNamesValue[htmlType] || this.formatLabel(htmlType))
        this.c.fieldTypeLabelTarget.textContent = label
      }
    }

    // Panel icon
    if (this.c.hasFieldIconTarget) {
      if (isLayout) {
        this.c.fieldIconTarget.className = "w-7 h-7 rounded-md bg-violet-100 flex items-center justify-center mr-2 flex-shrink-0"
        this.c.fieldIconTarget.innerHTML = this.c.fieldManager.getFieldIcon("layout", fieldType)
      } else {
        this.c.fieldIconTarget.className = "w-7 h-7 rounded-md bg-indigo-100 flex items-center justify-center mr-2 flex-shrink-0"
        this.c.fieldIconTarget.innerHTML = this.c.fieldManager.getFieldIcon(field.property_type, fieldType)
      }
    }

    // Dynamic section label
    if (this.c.hasGeneralSectionLabelTarget) {
      if (isGroup) {
        this.c.generalSectionLabelTarget.textContent = this.c.fieldGroupSettingsLabelValue
      } else if (isLayout) {
        this.c.generalSectionLabelTarget.textContent = this.c.layoutSettingsLabelsValue[fieldType] || this.c.layoutSettingsFallbackLabelValue
      } else {
        this.c.generalSectionLabelTarget.textContent = this.c.fieldPropertiesLabelValue
      }
    }

    // General fields
    if (this.c.hasFieldLabelTarget) {
      this.c.fieldLabelTarget.value = field.label || ""
    }
    if (this.c.hasFieldPlaceholderTarget) {
      this.c.fieldPlaceholderTarget.value = field.placeholder || ""
      this.c.fieldPlaceholderTarget.closest("div")?.classList.toggle("hidden", isLayout || isGroup)
    }
    if (this.c.hasFieldHelpTextTarget) {
      this.c.fieldHelpTextTarget.value = field.help_text || ""
      const hideHelpText = isGroup || (isLayout && ["divider", "spacer", "image", "video", "progress_bar", "columns"].includes(fieldType))
      this.c.fieldHelpTextTarget.closest("div")?.classList.toggle("hidden", hideHelpText)
    }
    if (this.c.hasFieldRequiredTarget) {
      this.c.fieldRequiredTarget.checked = field.required || false
      this.c.fieldRequiredTarget.closest("div")?.classList.toggle("hidden", isGroup || (isLayout && fieldType === "columns"))
    }
    if (this.c.hasFieldDefaultValueTarget) {
      this.c.fieldDefaultValueTarget.value = field.default_value || ""
      this.c.fieldDefaultValueTarget.closest("div")?.classList.toggle("hidden", isLayout || isGroup)
    }

    // Layout-specific fields
    if (this.c.hasFieldContentTarget) {
      const showContent = isLayout && ["heading", "paragraph", "section", "alert", "callout", "quote", "list", "code_block", "card", "button"].includes(fieldType)
      this.c.fieldContentTarget.value = field.content || ""
      this.c.fieldContentTarget.closest("div")?.classList.toggle("hidden", !showContent)
    }
    if (this.c.hasHeadingLevelTarget) {
      const showLevel = isLayout && fieldType === "heading"
      this.c.headingLevelTarget.value = field.heading_level || "h3"
      this.c.headingLevelTarget.closest("div")?.classList.toggle("hidden", !showLevel)
    }
    if (this.c.hasSpacerHeightTarget) {
      const showSpacerHeight = isLayout && fieldType === "spacer"
      this.c.spacerHeightTarget.value = field.spacer_height || "md"
      this.c.spacerHeightTarget.closest("div")?.classList.toggle("hidden", !showSpacerHeight)
    }
    if (this.c.hasAlertVariantTarget) {
      const showAlertVariant = isLayout && fieldType === "alert"
      this.c.alertVariantTarget.value = field.alert_variant || "info"
      this.c.alertVariantTarget.closest("div")?.classList.toggle("hidden", !showAlertVariant)
    }
    if (this.c.hasImageUrlAltGroupTarget) {
      const showImage = isLayout && fieldType === "image"
      this.c.imageUrlAltGroupTarget.classList.toggle("hidden", !showImage)
    }
    if (this.c.hasImageUrlTarget) {
      this.c.imageUrlTarget.value = field.image_url || ""
    }
    if (this.c.hasAltTextTarget) {
      this.c.altTextTarget.value = field.alt_text || ""
    }
    if (this.c.hasAttributionTarget) {
      const show = isLayout && fieldType === "quote"
      this.c.attributionTarget.value = field.attribution || ""
      this.c.attributionTarget.closest("div")?.classList.toggle("hidden", !show)
    }
    if (this.c.hasButtonUrlTarget) {
      const show = isLayout && fieldType === "button"
      this.c.buttonUrlTarget.value = field.button_url || "#"
      this.c.buttonUrlTarget.closest("div")?.classList.toggle("hidden", !show)
    }
    if (this.c.hasButtonVariantSizeGroupTarget) {
      const show = isLayout && fieldType === "button"
      this.c.buttonVariantSizeGroupTarget.classList.toggle("hidden", !show)
    }
    if (this.c.hasButtonVariantTarget) {
      this.c.buttonVariantTarget.value = field.button_variant || "primary"
    }
    if (this.c.hasButtonSizeTarget) {
      this.c.buttonSizeTarget.value = field.button_size || "md"
    }
    if (this.c.hasAlignmentTarget) {
      const show = isLayout && ["button", "video", "heading", "paragraph", "image"].includes(fieldType)
      this.c.alignmentTarget.value = field.alignment || "left"
      this.c.alignmentTarget.closest("div")?.classList.toggle("hidden", !show)
    }
    if (this.c.hasVideoUrlTarget) {
      const show = isLayout && fieldType === "video"
      this.c.videoUrlTarget.value = field.video_url || ""
      this.c.videoUrlTarget.closest("div")?.classList.toggle("hidden", !show)
    }
    if (this.c.hasListStyleTarget) {
      const show = isLayout && fieldType === "list"
      this.c.listStyleTarget.value = field.list_style || "bullet"
      this.c.listStyleTarget.closest("div")?.classList.toggle("hidden", !show)
    }
    if (this.c.hasCodeLanguageTarget) {
      const show = isLayout && fieldType === "code_block"
      this.c.codeLanguageTarget.value = field.code_language || ""
      this.c.codeLanguageTarget.closest("div")?.classList.toggle("hidden", !show)
    }
    if (this.c.hasProgressValueColorGroupTarget) {
      const show = isLayout && fieldType === "progress_bar"
      this.c.progressValueColorGroupTarget.classList.toggle("hidden", !show)
    }
    if (this.c.hasProgressValueTarget) {
      this.c.progressValueTarget.value = field.progress_value ?? 0
    }
    if (this.c.hasProgressColorTarget) {
      this.c.progressColorTarget.value = field.progress_color || "indigo"
    }

    // Column layout selector
    if (this.c.hasColumnLayoutTarget) {
      const showColumnLayout = isLayout && fieldType === "columns"
      this.c.columnLayoutTarget.closest("div")?.classList.toggle("hidden", !showColumnLayout)
      if (showColumnLayout) {
        this.c.columnLayoutTarget.value = field.column_layout || "50-50"
      }
    }

    // Show/hide sections based on layout vs data field
    this.toggleLayoutSections(field)

    // Show/hide Type Settings based on field type
    this.populateTypeSettings(field)

    // Show/hide options editor based on field type
    this.toggleOptionsEditor(field)

    // Render options if applicable
    if (OPTIONS_FIELD_TYPES.includes(fieldType) || OPTIONS_FIELD_TYPES.includes(field.property_type)) {
      this.renderOptionsEditor(field)
    }

    // Render conditions UI
    this.renderConditionsUI(field)

    // Populate advanced tab for data fields
    if (!isLayout) {
      this._populateAdvancedTab(field)
    }

    // Render breadcrumb navigation
    this._renderBreadcrumb(field)
  }

  switchPropertyTab(event) {
    const tabKey = event.currentTarget.dataset.tab
    if (!tabKey) return

    const tabBar = event.currentTarget.closest("[data-page-builder-target='propertyTabs']")
    if (tabBar) {
      tabBar.querySelectorAll("[data-tab]").forEach(btn => {
        btn.classList.remove("border-indigo-500", "text-indigo-600")
        btn.classList.add("border-transparent", "text-gray-500")
      })
      event.currentTarget.classList.remove("border-transparent", "text-gray-500")
      event.currentTarget.classList.add("border-indigo-500", "text-indigo-600")
    }

    const panel = this.c.floatingPanelTarget
    panel.querySelectorAll("[data-property-tab-content]").forEach(el => {
      el.classList.toggle("hidden", el.dataset.propertyTabContent !== tabKey)
    })
  }

  _populateAdvancedTab(field) {
    // Wire the "Add logic" button to prefill with the current field id
    const addLogicBtn = this.c.floatingPanelTarget.querySelector("[data-prefill-target-field]")
    if (addLogicBtn) addLogicBtn.dataset.prefillTargetField = field.id

    const rulesContainer = this.c.floatingPanelTarget.querySelector("[data-advanced-rules-summary]")
    if (!rulesContainer) return

    const rules = this.c.configuration.rules || []
    const summaries = []

    rules.forEach(rule => {
      if (!rule.enabled) return
      const isTarget = rule.actions?.some(a => a.field_id === field.id)
      if (!isTarget) return

      const conditionParts = (rule.conditions || []).flatMap(group => {
        return (group.items || []).map(item => {
          const sourceField = this.c.allFields.find(f => f.id === item.field_id)
          const fieldLabel = sourceField?.label || item.field_id
          const operator = this._operatorLabel(item.operator)
          const value = item.value || '""'
          return `[${fieldLabel}] ${operator} [${value}]`
        })
      })

      if (conditionParts.length > 0) {
        const actionType = rule.actions?.find(a => a.field_id === field.id)?.type || "show"
        const verb = actionType === "hide" ? this.c.ruleSummaryHideVerbValue : this.c.ruleSummaryShowVerbValue
        summaries.push(this.c.ruleSummaryFormatValue.replace("{verb}", verb).replace("{conditions}", conditionParts.join(" and ")))
      }
    })

    if (summaries.length === 0) {
      rulesContainer.innerHTML = `<p class="text-xs text-gray-400 italic">${this.escapeHtml(this.c.noConditionalRulesLabelValue)}</p>`
    } else {
      rulesContainer.innerHTML = summaries.map(s =>
        `<p class="text-xs text-gray-600 mb-1">${s}</p>`
      ).join("") +
      `<button type="button" class="text-xs text-indigo-600 hover:text-indigo-800 font-medium mt-1" data-action="click->page-builder#openRulesForField" data-field-id="${field.id}">${this.escapeHtml(this.c.editRulesLabelValue)}</button>`
    }
  }

  _operatorLabel(op) {
    return this.c.operatorLabelsValue[op] || op
  }

  toggleLayoutSections(field) {
    const isLayout = field.property_type === "layout"

    // Hide Validation section for layout components
    const validationSection = this.c.element.querySelector("[data-property-section='validation']")
    if (validationSection) {
      validationSection.classList.toggle("hidden", isLayout)
    }

    // Hide Conditional Logic section for structural layout types without meaningful content
    const conditionsSection = this.c.element.querySelector("[data-property-section='conditions']")
    if (conditionsSection) {
      const hideConditions = isLayout && ["divider", "spacer", "image", "video", "progress_bar"].includes(field.field_type)
      conditionsSection.classList.toggle("hidden", hideConditions)
    }
  }

  updateFieldProperty(event) {
    const property = event.target.dataset.property
    let value
    if (event.target.type === "checkbox") {
      value = event.target.checked
    } else if (event.target.type === "number") {
      // Coerce numeric inputs so validation values round-trip as numbers, not
      // strings (a blank input clears the property rather than storing "").
      value = event.target.value === "" ? null : Number(event.target.value)
    } else {
      value = event.target.value
    }

    const fieldId = this.c.selectedFieldValue || this.c.selectedFieldId
    if (!fieldId || !property) return

    const field = this.c.currentPageFields.find(f => f.id === fieldId)
    if (!field) return

    // Debounced undo: save state on first change, then debounce subsequent ones
    if (!this._undoTimer) {
      this.c.undoRedoManager.saveState()
    } else {
      clearTimeout(this._undoTimer)
    }
    this._undoTimer = setTimeout(() => { this._undoTimer = null }, 500)

    field[property] = value
    this.c.fieldManager.renderFieldCard(field)
    this.c.saveManager.markDirty()

    // Keep header field name in sync when label changes
    if (property === "label" && this.c.hasFieldNameTarget) {
      this.c.fieldNameTarget.textContent = value || field.property_slug || this.c.untitledFieldLabelValue
      this.c.fieldNameTarget.title = value || field.property_slug || ""
    }
  }

  updateFieldSlug(event) {
    const fieldId = this.c.selectedFieldValue || this.c.selectedFieldId
    if (!fieldId) return

    const field = this.c.currentPageFields.find(f => f.id === fieldId)
    if (!field) return

    const newSlug = this.generateSlug(event.target.value)
    if (!newSlug) return

    // Check for uniqueness
    const existingSlugs = new Set(this.c.allFields.filter(f => f.id !== fieldId).map(f => f.property_slug))
    if (existingSlugs.has(newSlug)) return

    this.c.undoRedoManager.saveState()
    field.property_slug = newSlug
    event.target.value = newSlug
    this.c.fieldManager.renderFieldCard(field)
    this.c.fieldManager.updateSidebarFieldStates()
    this.c.saveManager.markDirty()
  }

  toggleSection(event) {
    const button = event.currentTarget
    const section = button.closest(".border-b")
    const content = section?.querySelector('[data-page-builder-target="sectionContent"]')
    const chevron = [...button.children].find(el => el.tagName.toLowerCase() === "svg")

    if (content) {
      content.classList.toggle("hidden")
      chevron?.classList.toggle("rotate-180")
    }
  }

  updateFormSettings(event) {
    const property = event.target.dataset.property
    const value = event.target.type === "checkbox" ? event.target.checked : event.target.value

    if (!property) return

    this.c.undoRedoManager.saveState()

    this.c.configuration.form_settings = this.c.configuration.form_settings || {}
    this.c.configuration.form_settings[property] = value

    if (property === "submit_button_text") {
      this.c.pageManager.updateFormFooter()
    }

    this.c.saveManager.markDirty()
  }

  // --- Linked pages -------------------------------------------------------
  updateSubmissionModes() {
    const modes = Array.from(this.c.element.querySelectorAll("[data-submission-mode]"))
      .filter((box) => box.checked)
      .map((box) => box.value)
    this._writeFormSetting("modes", modes)
  }

  updatePageInputs() {
    const inputs = Array.from(this.c.element.querySelectorAll("[data-page-input]"))
      .filter((box) => box.checked)
      .map((box) => ({ field: box.value, entity_id: Number(box.dataset.entityId) }))
    this._writeFormSetting("inputs", inputs)
  }

  _writeFormSetting(key, value) {
    this.c.undoRedoManager.saveState()
    this.c.configuration.form_settings = this.c.configuration.form_settings || {}
    this.c.configuration.form_settings[key] = value
    this.c.saveManager.markDirty()
  }

  updateWizardSettings(event) {
    const property = event.target.dataset.property
    const value = event.target.type === "checkbox" ? event.target.checked : event.target.value

    if (!property) return

    this.c.undoRedoManager.saveState()

    this.c.configuration.wizard_settings = this.c.configuration.wizard_settings || {}
    this.c.configuration.wizard_settings[property] = value

    this.c.saveManager.markDirty()
  }

  showFormSettings() {
    this.c.element.querySelectorAll("[data-field-section]").forEach(el => {
      el.classList.add("hidden")
    })

    const formSettingsSection = this.c.element.querySelector("[data-form-settings]")
    if (formSettingsSection) {
      formSettingsSection.classList.remove("hidden")
    }

    if (this.c.hasFieldTypeLabelTarget) {
      this.c.fieldTypeLabelTarget.textContent = this.c.formSettingsLabelValue
    }
    if (this.c.hasFloatingPanelTarget) {
      this.c.floatingPanelTarget.classList.remove("hidden")
      this.c.floatingPanelTarget.classList.add("flex", "flex-col")
    }
  }

  // Column layout management
  // =========================================================================

  updateColumnLayout(event) {
    const newLayout = event.target.value
    if (!newLayout) return

    const fieldId = this.c.selectedFieldValue || this.c.selectedFieldId
    if (!fieldId) return

    const field = this.c.currentPageFields.find(f => f.id === fieldId)
    if (!field || field.field_type !== "columns") return

    this.c.undoRedoManager.saveState()

    const layoutColumnCounts = {
      "50-50": 2, "33-33-33": 3, "66-33": 2, "33-66": 2, "25-25-25-25": 4
    }
    const targetCount = layoutColumnCounts[newLayout] || 2

    field.column_layout = newLayout

    // Adjust columns array to match new count
    while (field.columns.length < targetCount) {
      field.columns.push({ fields: [] })
    }
    // If reducing columns, merge overflow fields into last column
    if (field.columns.length > targetCount) {
      const overflow = field.columns.splice(targetCount)
      const lastCol = field.columns[targetCount - 1]
      overflow.forEach(col => {
        lastCol.fields.push(...(col.fields || []))
      })
    }

    this.c.fieldManager.renderFields()
    this.c.fieldManager.selectFieldById(fieldId)
    this.c.saveManager.markDirty()
  }
}

Object.assign(PropertyManager.prototype, TypeSettingsMixin)
Object.assign(PropertyManager.prototype, FormBuilderMixin)
Object.assign(PropertyManager.prototype, BreadcrumbMixin)
Object.assign(PropertyManager.prototype, WidthBreakpointMixin)
Object.assign(PropertyManager.prototype, ThemeMixin)
