import { Controller } from "@hotwired/stimulus"
import { UndoRedoManager } from "controllers/page_builder/undo_redo_manager"
import { ViewportManager } from "controllers/page_builder/viewport_manager"
import { TabManager } from "controllers/page_builder/tab_manager"
import { DragDropManager } from "controllers/page_builder/drag_drop_manager"
import { FieldManager } from "controllers/page_builder/field_manager"
import { PageManager } from "controllers/page_builder/page_manager"
import { PropertyManager, HTML_TYPE_DISPLAY_NAMES, SETTINGS_SECTION_LABELS, OPERATOR_LABELS } from "controllers/page_builder/property_manager"
import { CONDITION_OPERATOR_LABELS } from "controllers/page_builder/property_manager/form_builder"
import { SaveManager } from "controllers/page_builder/save_manager"
import { KeyboardManager } from "controllers/page_builder/keyboard_manager"
import { SelectionManager } from "controllers/page_builder/selection_manager"
import { InserterManager, COMPONENT_CATALOG } from "controllers/page_builder/inserter_manager"
import { RulesManager } from "controllers/page_builder/rules_manager"
import { CalculationsManager } from "controllers/page_builder/calculations_manager"
import { InlineEditManager } from "controllers/page_builder/inline_edit_manager"
import { ClipboardManager } from "controllers/page_builder/clipboard_manager"
import { ResizeManager } from "controllers/page_builder/resize_manager"
import { CommandPaletteManager, FIELD_COMMANDS, LAYOUT_COMMANDS, ACTION_COMMANDS } from "controllers/page_builder/command_palette_manager"
import { SPACER_HEIGHT_LABELS, LIST_STYLE_LABELS, COLUMN_LAYOUT_BADGE_LABELS } from "controllers/page_builder/field_manager/layout_cards"
import { ZoomManager } from "controllers/page_builder/zoom_manager"
import { DragEngine } from "controllers/page_builder/drag_engine"
import { DragVisuals } from "controllers/page_builder/drag_visuals"
import { DropResolver } from "controllers/page_builder/drop_resolver"
import { DropMutations } from "controllers/page_builder/drop_mutations"
import { ContextMenuManager } from "controllers/page_builder/context_menu_manager"

/**
 * PageBuilderController
 *
 * Thin orchestrator that delegates to specialized managers.
 * All Stimulus targets and values remain on the controller.
 * Action methods delegate to the appropriate manager.
 */
export default class extends Controller {
  static targets = [
    // Toolbar
    "entityName", "viewportBtn", "viewportSize", "undoBtn", "redoBtn", "saveBtn", "saveText",
    "settingsSaveError", "settingsSaveErrorMessage", "previewForm", "previewConfigInput",
    // Tabs
    "tabButton", "tabPanel",
    // Sidebars
    "leftSidebar", "componentSearch", "componentLibrary", "searchInput", "sidebarContent",
    "categoryChevron", "categoryContent",
    // Entity fields
    "entityFieldsCategory", "entityFieldCount", "entityFieldsList",
    // Canvas
    "canvasArea", "canvasFrame", "dropZone", "fieldsContainer", "emptyState",
    "dragPreview", "dropIndicator", "formFooter",
    // Quick-add & Inserter
    "quickAddToolbar", "toolbarWidthGroup", "toolbarWidthBtn",
    "inserterPopover", "inserterPopoverSearch", "inserterPopoverContent",
    // Property sidebar
    "floatingPanel", "propertyPanel", "propertyForm",
    "propertyTabs", "propertyTabContent",
    "fieldIcon", "fieldName", "fieldTypeLabel", "generalSectionLabel",
    "buttonVariantSizeGroup", "progressValueColorGroup", "imageUrlAltGroup",
    "fieldLabel", "fieldPlaceholder", "fieldHelpText", "fieldWidth", "fieldRequired", "fieldDefaultValue",
    "fieldContent", "headingLevel", "spacerHeight", "alertVariant", "imageUrl", "altText",
    "attribution", "buttonUrl", "buttonVariant", "buttonSize", "alignment", "videoUrl",
    "listStyle", "codeLanguage", "progressValue", "progressColor",
    "validationOptions", "sectionContent",
    // Column layout
    "columnLayout",
    // Theme panel
    "themePanel",
    // Modal
    "shortcutsModal",
    // Multi-page
    "pageTabs", "conditionsContainer",
    // Options editor
    "optionsList", "optionsEditor",
    // Rules and calculations
    "rulesPanel", "rulesList", "calculationsPanel", "calculationsList",
    "ruleEditorModal", "formulaEditorModal", "moveToPageModal",
    "ruleNameInput", "conditionsLogic", "conditionGroups", "ruleActions",
    "calculationTargetField", "formulaInput",
    "calculationEditorTemplate", "ruleEditorTemplate",
    // Floating Action Bar (multi-select)
    "floatingActionBar", "selectionCount",
    // Breakpoint selector
    "breakpointSelector", "resetBreakpoint",
    // Type Settings section
    "typeSettingsSection",
    // Text properties
    "fieldMaxLength", "fieldMinLength", "fieldPattern", "fieldAutocomplete",
    // Textarea properties
    "fieldRows", "fieldResize",
    // Password properties
    "fieldShowToggle",
    // Selection properties
    "fieldAllowBlank", "fieldSearchable", "fieldInlineLayout",
    "fieldMinSelections", "fieldMaxSelections",
    // Switch properties
    "fieldOnLabel", "fieldOffLabel",
    // Numeric properties
    "fieldMinValue", "fieldMaxValue", "fieldStep", "fieldShowValue",
    // Currency properties
    "fieldCurrencySymbol", "fieldDecimalPlaces",
    // Rating properties
    "fieldMaxRating", "fieldAllowHalf",
    // Date/time constraint properties
    "fieldMinConstraint", "fieldMaxConstraint", "fieldTimeStep",
    // Contact properties
    "fieldAllowMultiple", "fieldPhonePattern",
    // Rich text properties
    "fieldToolbar",
    // Signature properties
    "fieldCanvasHeight", "fieldPenColor", "fieldPenWidth",
    // File properties
    "fieldAcceptTypes", "fieldMaxFileSize",
    // Color properties
    "fieldColorFormat",
    // Context Menu
    "contextMenu", "contextMenuContent",
    // Command Palette
    "commandPalette", "commandPaletteInput", "commandPaletteResults",
    // Zoom & Navigation
    "zoomLevel", "miniMap", "miniMapCanvas", "searchCount",
    // Breadcrumb
    "breadcrumbBar", "breadcrumbContent",
  ]

  static values = {
    id: Number,
    customerId: Number,
    configuration: String,
    entityId: Number,
    updatedAt: String,
    viewport: { type: String, default: "desktop" },
    activePage: { type: String, default: "page_1" },
    floatingPanelVisible: { type: Boolean, default: false },
    selectedField: String,
    editingRuleId: String,
    editingCalculationId: String,
    layoutTemplate: { type: Object, default: {} },

    // ── i18n seam: English defaults keep JS specs green without any
    // data-*-value attribute; the page editor view (_editor.html.erb) supplies
    // translated strings via data-page-builder-<name>-value="<%= t(...) %>". ──

    // FieldManager
    untitledFieldLabel: { type: String, default: "Untitled" },
    fieldGroupLabel: { type: String, default: "Field Group" },
    ariaLayoutComponentLabel: { type: String, default: "layout component" },
    ariaFieldLabel: { type: String, default: "field" },
    dropHereLabel: { type: String, default: "Drop here" },
    ungroupLabel: { type: String, default: "Ungroup" },
    saveAsTemplateLabel: { type: String, default: "Save as Template" },
    templateNamePromptLabel: { type: String, default: "Template name:" },
    templateSavedMsg: { type: String, default: "Template saved!" },
    templateSaveFailedMsg: { type: String, default: "Failed to save template" },
    dragGhostFieldFallbackLabel: { type: String, default: "Field" },

    // PropertyManager
    htmlTypeDisplayNames: { type: Object, default: { ...HTML_TYPE_DISPLAY_NAMES } },
    fieldsSelectedLabel: { type: String, default: "{count} fields selected" },
    moveToPageEllipsisLabel: { type: String, default: "Move to Page..." },
    deleteSelectedLabel: { type: String, default: "Delete Selected" },
    deselectAllLabel: { type: String, default: "Deselect all" },
    fieldGroupSettingsLabel: { type: String, default: "Field Group Settings" },
    layoutSettingsLabels: { type: Object, default: { ...SETTINGS_SECTION_LABELS } },
    layoutSettingsFallbackLabel: { type: String, default: "Layout Settings" },
    fieldPropertiesLabel: { type: String, default: "Field Properties" },
    formSettingsLabel: { type: String, default: "Form Settings" },
    noConditionalRulesLabel: { type: String, default: "No conditional rules" },
    ruleSummaryShowVerb: { type: String, default: "Show" },
    ruleSummaryHideVerb: { type: String, default: "Hide" },
    ruleSummaryFormat: { type: String, default: "{verb} this field when {conditions}" },
    editRulesLabel: { type: String, default: "Edit Rules" },
    operatorLabels: { type: Object, default: { ...OPERATOR_LABELS } },

    // Breadcrumb
    breadcrumbPageFallback: { type: String, default: "Page 1" },
    breadcrumbColumnsLabel: { type: String, default: "Columns" },
    breadcrumbColumnNumberFormat: { type: String, default: "Column {number}" },
    breadcrumbSectionLabel: { type: String, default: "Section" },

    // TabManager
    noFieldsLabel: { type: String, default: "No Fields" },
    noPropertiesFoundLabel: { type: String, default: "No properties found for this entity" },

    // CommandPaletteManager
    noResultsFoundLabel: { type: String, default: "No results found" },
    untitledTemplateLabel: { type: String, default: "Untitled Template" },

    // PageManager
    deletePageConfirmSingular: { type: String, default: 'Delete "{name}" and its {count} field?' },
    deletePageConfirmPlural: { type: String, default: 'Delete "{name}" and its {count} fields?' },
    deletePageConfirmNoFields: { type: String, default: 'Delete "{name}"?' },
    deletePageFallbackName: { type: String, default: "this page" },
    renamePageTitle: { type: String, default: "Rename page" },
    deletePageTitle: { type: String, default: "Delete page" },
    addNewPageTitle: { type: String, default: "Add new page" },
    cancelLabel: { type: String, default: "Cancel" },
    previousStepLabel: { type: String, default: "← Previous" },
    nextStepLabel: { type: String, default: "Next →" },
    stepOfFormat: { type: String, default: "Step {current} of {total}" },
    defaultSubmitButtonText: { type: String, default: "Submit" },

    // SaveManager
    saveLabel: { type: String, default: "Save" },
    saveDirtyLabel: { type: String, default: "Save*" },
    savingLabel: { type: String, default: "Saving..." },
    savedLabel: { type: String, default: "Saved" },
    saveErrorGenericMessage: { type: String, default: "Couldn't save the page. Please try again." },
    saveConflictLabel: { type: String, default: "Conflict" },
    saveConflictConfirmMsg: {
      type: String,
      default: "This page was updated in another tab since you started editing. Reload to see the latest version? (Your unsaved changes will be lost.)"
    },

    // SelectionManager
    bulkDeleteConfirmSingular: { type: String, default: "Delete {count} field?" },
    bulkDeleteConfirmPlural: { type: String, default: "Delete {count} fields?" },
    moveToPageModalTitle: { type: String, default: "Move to Page" },
    moveFieldsPromptSingular: { type: String, default: "Move {count} field to another page" },
    moveFieldsPromptPlural: { type: String, default: "Move {count} fields to another page" },
    currentPageTag: { type: String, default: "(current)" },
    orCreateNewPageLabel: { type: String, default: "Or create a new page" },
    newPageNamePlaceholder: { type: String, default: "New page name..." },
    moveFieldsButtonLabel: { type: String, default: "Move Fields" },

    // ZoomManager
    searchOfFormat: { type: String, default: "{matches} of {total}" },
    searchFieldsPlaceholder: { type: String, default: "Search fields..." },

    // CalculationsManager
    calcModalTitleEdit: { type: String, default: "Edit Calculation" },
    calcModalTitleNew: { type: String, default: "New Calculation" },
    calcSelectTargetFormulaMsg: { type: String, default: "Please select a target field and enter a formula" },
    deleteCalculationConfirm: { type: String, default: "Delete this calculation?" },
    calcConfiguredSingular: { type: String, default: "{count} calculation configured" },
    calcConfiguredPlural: { type: String, default: "{count} calculations configured" },
    addCalculationLabel: { type: String, default: "Add Calculation" },
    noCalculatedFieldsLabel: { type: String, default: "No calculated fields" },
    noCalculatedFieldsHint: { type: String, default: "Add formulas to automatically compute field values from other fields." },
    searchCalculationsPlaceholder: { type: String, default: "Search calculations…" },

    // RulesManager
    ruleModalTitleEdit: { type: String, default: "Edit Rule" },
    ruleModalTitleNew: { type: String, default: "New Rule" },
    deleteRuleConfirm: { type: String, default: "Delete this rule?" },
    unnamedRuleFallback: { type: String, default: "Unnamed rule" },
    rulesConfiguredSingular: { type: String, default: "{count} rule configured" },
    rulesConfiguredPlural: { type: String, default: "{count} rules configured" },
    addRuleLabel: { type: String, default: "Add Rule" },
    searchRulesPlaceholder: { type: String, default: "Search rules…" },
    noRulesDefinedLabel: { type: String, default: "No rules defined" },
    noRulesDefinedHint: { type: String, default: "Add conditional rules to show or hide fields dynamically based on user input." },
    ruleWhenFormat: { type: String, default: "When {field} {operator}" },
    ruleActionArrowFormat: { type: String, default: "→ {action} {field}" },
    ruleEnableTitle: { type: String, default: "Enable" },
    ruleDisableTitle: { type: String, default: "Disable" },

    // Shared action titles (used by both CalculationsManager and RulesManager
    // panel rows)
    actionEditTitle: { type: String, default: "Edit" },
    actionDeleteTitle: { type: String, default: "Delete" },
    actionDuplicateTitle: { type: String, default: "Duplicate" },

    // InserterManager — component-palette catalog labels
    componentCatalogLabels: {
      type: Object,
      default: COMPONENT_CATALOG.reduce((acc, group) => {
        group.items.forEach(item => { acc[item.type] = item.label })
        return acc
      }, {})
    },
    componentCatalogCategoryLabels: {
      type: Object,
      default: COMPONENT_CATALOG.reduce((acc, group) => {
        acc[group.category] = group.category
        return acc
      }, {})
    },

    // CommandPaletteManager — command-list labels
    fieldCommandLabels: {
      type: Object,
      default: FIELD_COMMANDS.reduce((acc, cmd) => { acc[cmd.type] = cmd.label; return acc }, {})
    },
    layoutCommandLabels: {
      type: Object,
      default: LAYOUT_COMMANDS.reduce((acc, cmd) => { acc[cmd.type] = cmd.label; return acc }, {})
    },
    actionCommandLabels: {
      type: Object,
      default: ACTION_COMMANDS.reduce((acc, cmd) => { acc[cmd.action] = cmd.label; return acc }, {})
    },
    commandCategoryLabels: {
      type: Object,
      default: { Fields: "Fields", Layout: "Layout", Actions: "Actions", Templates: "Templates" }
    },

    // ContextMenuManager
    editLabelActionTitle: { type: String, default: "Edit Label" },
    copyActionTitle: { type: String, default: "Copy" },
    cutActionTitle: { type: String, default: "Cut" },
    pasteActionTitle: { type: String, default: "Paste" },
    pasteAfterActionTitle: { type: String, default: "Paste After" },
    addFieldActionTitle: { type: String, default: "Add Field" },
    selectAllActionTitle: { type: String, default: "Select All" },
    widthMenuTitle: { type: String, default: "Width" },
    widthFullLabel: { type: String, default: "Full" },
    widthHalfLabel: { type: String, default: "Half" },

    // Field-insert defaults (field_manager/field_crud.js) — server-provided
    // translations; empty default falls back to the English LAYOUT_DEFAULTS.
    layoutDefaultLabels: { type: Object, default: {} },
    layoutDefaultContents: { type: Object, default: {} },
    // Resize tooltip snap labels (resize_manager.js), keyed by snap name.
    resizeSnapLabels: { type: Object, default: {} },
    // CommandPaletteManager template-field fallback label.
    templateFieldFallbackLabel: { type: String, default: "Template Field" },

    // LayoutCardsMixin (field_manager/layout_cards.js)
    spacerHeightLabels: { type: Object, default: { ...SPACER_HEIGHT_LABELS } },
    listStyleLabels: { type: Object, default: { ...LIST_STYLE_LABELS } },
    columnLayoutBadgeLabels: { type: Object, default: { ...COLUMN_LAYOUT_BADGE_LABELS } },
    codeBadgeLabel: { type: String, default: "Code" },
    dropFieldsHereLabel: { type: String, default: "Drop fields here" },
    dragToReorderTitle: { type: String, default: "Drag to reorder" },

    // FormBuilderMixin (property_manager/form_builder.js)
    conditionIfLabel: { type: String, default: "If" },
    conditionSelectFieldOption: { type: String, default: "Select field..." },
    conditionOperatorLabels: { type: Object, default: { ...CONDITION_OPERATOR_LABELS } },
    valuePlaceholder: { type: String, default: "Value" },
    labelPlaceholder: { type: String, default: "Label" },
    conditionAndLabel: { type: String, default: "AND" },
    conditionOrLabel: { type: String, default: "OR" },
    newOptionLabelFormat: { type: String, default: "Option {number}" },

    // FieldPreviewsMixin (field_manager/field_previews.js)
    hiddenFieldPreviewLabel: { type: String, default: "Hidden field" },
    enterFieldPlaceholderFormat: { type: String, default: "Enter {label}" },
    selectFieldPlaceholderFormat: { type: String, default: "Select {label}" },
    switchEnabledPreviewLabel: { type: String, default: "Enabled" },
    dropFileUploadLabel: { type: String, default: "Drop file or click to upload" },
    clickUploadImageLabel: { type: String, default: "Click to upload image" },
    signHerePreviewLabel: { type: String, default: "Sign here" },

    // FieldManager / FieldCrudMixin
    duplicateSuffixFormat: { type: String, default: "{name} (Copy)" },
    autoSectionFallbackLabel: { type: String, default: "Fields" }
  }

  // =========================================================================
  // Lifecycle
  // =========================================================================

  connect() {
    // Initialize managers — each wrapped independently so one failure does not
    // abort all subsequent managers (graceful degradation).
    const initManager = (name, factory) => {
      try {
        return factory()
      } catch (e) {
        console.error(`Failed to init ${name}`, e)
        return null
      }
    }

    this.undoRedoManager      = initManager("UndoRedoManager",      () => new UndoRedoManager(this))
    this.viewportManager      = initManager("ViewportManager",      () => new ViewportManager(this))
    this.tabManager           = initManager("TabManager",           () => new TabManager(this))
    this.dragDropManager      = initManager("DragDropManager",      () => new DragDropManager(this))
    this.fieldManager         = initManager("FieldManager",         () => new FieldManager(this))
    this.pageManager          = initManager("PageManager",          () => new PageManager(this))
    this.propertyManager      = initManager("PropertyManager",      () => new PropertyManager(this))
    this.saveManager          = initManager("SaveManager",          () => new SaveManager(this))
    this.keyboardManager      = initManager("KeyboardManager",      () => new KeyboardManager(this))
    this.selectionManager     = initManager("SelectionManager",     () => {
      const sm = new SelectionManager(this)
      sm.initialize()
      return sm
    })
    this.inserterManager      = initManager("InserterManager",      () => new InserterManager(this))
    this.rulesManager         = initManager("RulesManager",         () => new RulesManager(this))
    this.calculationsManager  = initManager("CalculationsManager",  () => new CalculationsManager(this))
    this.inlineEditManager    = initManager("InlineEditManager",    () => new InlineEditManager(this))
    this.clipboardManager     = initManager("ClipboardManager",     () => new ClipboardManager(this))
    this.resizeManager        = initManager("ResizeManager",        () => new ResizeManager(this))
    this.commandPaletteManager = initManager("CommandPaletteManager", () => new CommandPaletteManager(this))
    this.zoomManager          = initManager("ZoomManager",          () => new ZoomManager(this))
    this.contextMenuManager   = initManager("ContextMenuManager",   () => new ContextMenuManager(this))
    // Pointer-events drag-and-drop engine (replaces native HTML5 DnD on canvas).
    this.dragVisuals          = initManager("DragVisuals",          () => new DragVisuals(this))
    this.dropResolver         = initManager("DropResolver",         () => new DropResolver(this))
    this.dropMutations        = initManager("DropMutations",        () => new DropMutations(this))
    this.dragEngine           = initManager("DragEngine",           () => new DragEngine(this))

    this._beforeUnload = (e) => {
      if (this.isDirty) { e.preventDefault(); e.returnValue = "" }
    }
    window.addEventListener("beforeunload", this._beforeUnload)

    this._onKeydown = (e) => this.closeModalsOnEscape(e)
    document.addEventListener("keydown", this._onKeydown)

    this.initializeState()
    this.keyboardManager.bindKeyboardShortcuts()
    this.keyboardManager.bindClickOutside()
    this.pageManager.renderPageTabs()
    this.fieldManager.renderFields()
    this.pageManager.updateFormFooter()
    this.viewportManager.updateViewportUI()
  }

  disconnect() {
    this.fieldManager?.cleanup?.()
    this.keyboardManager.unbindKeyboardShortcuts()
    this.keyboardManager.unbindClickOutside()
    this.selectionManager.cleanupRubberBand()
    window.removeEventListener("beforeunload", this._beforeUnload)
    if (this._onKeydown) document.removeEventListener("keydown", this._onKeydown)
  }

  // =========================================================================
  // State Initialization
  // =========================================================================

  initializeState() {
    try {
      this.configuration = JSON.parse(this.configurationValue || '{"pages":[],"metadata":{}}')
    } catch (_e) {
      this.configuration = { pages: [], metadata: {} }
    }

    if (!this.configuration.pages || this.configuration.pages.length === 0) {
      this.configuration.pages = [{
        id: "page_1",
        name: "Page 1",
        order: 1,
        fields: []
      }]
    }

    this.configuration.theme = this.configuration.theme || {
      primary_color: "indigo",
      font_family: "sans",
      border_radius: "lg",
      input_style: "outline",
      form_background: "white"
    }

    this.fields = this.currentPageFields
    this.metadata = this.configuration.metadata || {}
    this.selectedFieldId = null
    this.isDirty = false
    this.isSaving = false
    this.lastSavedAt = this.hasUpdatedAtValue ? this.updatedAtValue : null

    this.undoStack = []
    this.redoStack = []
    this.maxHistorySize = 50

    this.draggedElement = null
    this.draggedData = null

    if (!this.activePageValue || !this.configuration.pages.find(p => p.id === this.activePageValue)) {
      this.activePageValue = this.configuration.pages[0]?.id || "page_1"
    }
  }

  // =========================================================================
  // Getters
  // =========================================================================

  get currentPage() {
    return this.configuration.pages.find(p => p.id === this.activePageValue) ||
           this.configuration.pages[0]
  }

  get currentPageFields() {
    return this.currentPage?.fields || []
  }

  get allFields() {
    const fields = this.configuration.pages?.flatMap(p => p.fields || []) || []
    return fields.flatMap(f => {
      if (f.field_type === "columns") return [f, ...(f.columns || []).flatMap(c => c.fields || [])]
      if (f.type === "field_group") return [f, ...(f.fields || [])]
      return [f]
    })
  }

  get allPages() {
    return this.configuration.pages || []
  }

  // =========================================================================
  // Delegated Actions -> UndoRedoManager
  // =========================================================================

  undo() { this.undoRedoManager.undo() }
  redo() { this.undoRedoManager.redo() }
  saveState() { this.undoRedoManager.saveState() }
  saveHistory() { this.undoRedoManager.saveHistory() }

  // =========================================================================
  // Delegated Actions -> ViewportManager
  // =========================================================================

  setViewport(event) { this.viewportManager.setViewport(event) }

  // =========================================================================
  // Delegated Actions -> TabManager
  // =========================================================================

  switchTab(event) { this.tabManager.switchTab(event) }
  closeAllTabPanels() { this.tabManager.closeAllTabPanels() }
  searchComponents(event) { this.tabManager.searchComponents(event) }

  // Modal dismiss handlers
  onModalBackdropClick(event) {
    if (event.target === event.currentTarget) {
      this.tabManager.closeAllTabPanels()
    }
  }

  stopModalClose(event) {
    event.stopPropagation()
  }

  closeModalsOnEscape(event) {
    if (event.key !== "Escape") return
    const anyOpen = this.tabPanelTargets.some(p => !p.classList.contains("hidden"))
    if (anyOpen) this.tabManager.closeAllTabPanels()
  }
  toggleCategory(event) { this.tabManager.toggleCategory(event) }
  toggleSubsection(event) { this.tabManager.toggleSubsection(event) }
  filterSidebar(event) { this.tabManager.filterSidebar(event) }
  selectEntity(event) { this.tabManager.selectEntity(event) }
  onEntityChange(event) { this.tabManager.onEntityChange(event) }

  // =========================================================================
  // Delegated Actions -> DragDropManager
  // =========================================================================

  // Single entry point for the pointer-events drag engine (canvas cards,
  // section headers, and sidebar field items all bind pointerdown to this).
  dragPointerDown(event) { this.dragEngine.pointerDown(event) }

  // =========================================================================
  // Delegated Actions -> FieldManager
  // =========================================================================

  addField(event) { this.fieldManager.addField(event) }
  addAllFieldsFromSection(event) { this.fieldManager.addAllFieldsFromSection(event) }
  removeAllFieldsFromSection(event) { this.fieldManager.removeAllFieldsFromSection(event) }
  selectField(event) { this.fieldManager.selectField(event) }
  selectSection(event) { this.fieldManager.selectSection(event) }
  deselectField() { this.fieldManager.deselectField() }
  updateField(event) { this.fieldManager.updateField(event) }
  duplicateField() { this.fieldManager.duplicateField() }
  deleteField() { this.fieldManager.deleteField() }
  duplicateSelectedField() { this.fieldManager.duplicateSelectedField() }
  deleteSelectedField() { this.fieldManager.deleteSelectedField() }
  removeFieldFromCard(event) { this.fieldManager.removeFieldFromCard(event) }
  duplicateFieldFromCard(event) { this.fieldManager.duplicateFieldFromCard(event) }
  ungroupFields(event) { this.fieldManager.ungroupFields(event) }
  saveFieldAsTemplate(event) { this.fieldManager.saveFieldAsTemplate(event) }
  showDependencyLines(event) { this.fieldManager.showDependencyLines(event) }

  // =========================================================================
  // Delegated Actions -> PageManager
  // =========================================================================

  addPage() { this.pageManager.addPage() }
  switchPage(event) { this.pageManager.switchPage(event) }
  deletePage(event) { this.pageManager.deletePage(event) }
  renamePage(event) { this.pageManager.renamePage(event) }
  pageTabDragStart(event) { this.pageManager.pageTabDragStart(event) }
  pageTabDragEnd(event) { this.pageManager.pageTabDragEnd(event) }
  pageTabDragOver(event) { this.pageManager.pageTabDragOver(event) }
  pageTabDrop(event) { this.pageManager.pageTabDrop(event) }

  // =========================================================================
  // Delegated Actions -> PropertyManager
  // =========================================================================

  updateFieldProperty(event) { this.propertyManager.updateFieldProperty(event) }
  updateFieldSlug(event) { this.propertyManager.updateFieldSlug(event) }
  toggleSection(event) { this.propertyManager.toggleSection(event) }
  addCondition() { this.propertyManager.addCondition() }
  updateCondition(event) { this.propertyManager.updateCondition(event) }
  removeCondition(event) { this.propertyManager.removeCondition(event) }
  addOption(event) { this.propertyManager.addOption(event) }
  removeOption(event) { this.propertyManager.removeOption(event) }
  updateOption(event) { this.propertyManager.updateOption(event) }
  updateFormSettings(event) { this.propertyManager.updateFormSettings(event) }
  updateSubmissionModes() { this.propertyManager.updateSubmissionModes() }
  updatePageInputs() { this.propertyManager.updatePageInputs() }
  updateWizardSettings(event) { this.propertyManager.updateWizardSettings(event) }
  showFormSettings() { this.propertyManager.showFormSettings() }
  updateTheme(event) { this.propertyManager.updateTheme(event) }
  applyThemePreset(event) { this.propertyManager.applyThemePreset(event) }
  updateColumnLayout(event) { this.propertyManager.updateColumnLayout(event) }
  setFieldWidth(event) { this.propertyManager.setFieldWidth(event) }
  switchBreakpoint(event) { this.propertyManager.switchBreakpoint(event) }
  resetBreakpointWidth(event) { this.propertyManager.resetBreakpointWidth(event) }
  switchPropertyTab(event) { this.propertyManager.switchPropertyTab(event) }
  breadcrumbNavigate(event) { this.propertyManager.breadcrumbNavigate(event) }
  breadcrumbHighlight(event) { this.propertyManager.breadcrumbHighlight(event) }
  breadcrumbUnhighlight(event) { this.propertyManager.breadcrumbUnhighlight(event) }
  openRulesForField(_event) { this.tabManager.switchTab({ currentTarget: this.tabButtonTargets.find(t => t.dataset.tab === "rules") }) }

  // =========================================================================
  // Delegated Actions -> InserterManager
  // =========================================================================

  openInserterPopover(event) { this.inserterManager.openPopover(event) }
  closeInserterPopover() { this.inserterManager.closePopover() }
  filterInserterPopover(event) { this.inserterManager.filterPopover(event) }
  insertFromPopover(event) { this.inserterManager.insertFromPopover(event) }
  insertFromToolbar(event) { this.inserterManager.insertFromToolbar(event) }
  openFullCatalog(event) { this.inserterManager.openFullCatalog(event) }

  // =========================================================================
  // Delegated Actions -> SelectionManager
  // =========================================================================

  selectAllFields() { this.selectionManager.selectAll() }
  openMoveToPageModal() { this.selectionManager.openMoveToPageModal() }
  closeMoveToPageModal() { this.selectionManager.closeMoveToPageModal() }
  closeMoveToPageModalOnBackdrop(event) { this.selectionManager.closeMoveToPageModalOnBackdrop(event) }
  confirmMoveToPage() { this.selectionManager.confirmMoveToPage() }
  canvasMouseDown(event) { this.selectionManager.startRubberBand(event) }
  canvasMouseMove(event) { this.selectionManager.updateRubberBand(event) }
  canvasMouseUp(event) { this.selectionManager.endRubberBand(event) }
  bulkSetWidth(event) { this.selectionManager.bulkSetWidth(event) }
  bulkDuplicate() { this.clipboardManager.duplicateSelected() }
  bulkDelete() { this.selectionManager.bulkDelete() }
  groupIntoSection() { this.selectionManager.groupIntoSection() }

  // =========================================================================
  // Delegated Actions -> SaveManager
  // =========================================================================

  save() { this.saveManager.save() }
  preview() { this.saveManager.preview() }
  dismissSettingsError() { this.saveManager.hideModalError() }

  // =========================================================================
  // Delegated Actions -> KeyboardManager
  // =========================================================================

  showShortcuts() { this.keyboardManager.showShortcuts() }
  hideShortcuts() { this.keyboardManager.hideShortcuts() }

  // =========================================================================
  // Delegated Actions -> RulesManager
  // =========================================================================

  openRuleEditor(event) { this.rulesManager.openRuleEditor(event) }
  closeRuleEditor() { this.rulesManager.closeRuleEditor() }
  closeRuleEditorOnBackdrop(event) { this.rulesManager.closeRuleEditorOnBackdrop(event) }
  editRule(event) { this.rulesManager.editRule(event) }
  saveRule() { this.rulesManager.saveRule() }
  deleteRule(event) { this.rulesManager.deleteRule(event) }
  toggleRule(event) { this.rulesManager.toggleRule(event) }
  duplicateRule(event) { this.rulesManager.duplicateRule(event) }
  addConditionGroup() { this.rulesManager.addConditionGroup() }
  removeConditionGroup(event) { this.rulesManager.removeConditionGroup(event) }
  addConditionItem(event) { this.rulesManager.addConditionItem(event) }
  removeConditionItem(event) { this.rulesManager.removeConditionItem(event) }
  addAction() { this.rulesManager.addAction() }
  removeAction(event) { this.rulesManager.removeAction(event) }
  onActionTypeChange(event) { this.rulesManager.onActionTypeChange(event) }

  // =========================================================================
  // Delegated Actions -> CalculationsManager
  // =========================================================================

  openFormulaEditor(event) { this.calculationsManager.openFormulaEditor(event) }
  closeFormulaEditor() { this.calculationsManager.closeFormulaEditor() }
  closeFormulaEditorOnBackdrop(event) { this.calculationsManager.closeFormulaEditorOnBackdrop(event) }
  editCalculation(event) { this.calculationsManager.editCalculation(event) }
  saveCalculation() { this.calculationsManager.saveCalculation() }
  deleteCalculation(event) { this.calculationsManager.deleteCalculation(event) }
  insertFieldReference(event) { this.calculationsManager.insertFieldReference(event) }
  insertFunction(event) { this.calculationsManager.insertFunction(event) }

  // =========================================================================
  // Delegated Actions -> InlineEditManager
  // =========================================================================

  startInlineEdit(event) { this.inlineEditManager.startEdit(event) }

  // =========================================================================
  // Delegated Actions -> ClipboardManager
  // =========================================================================

  copyField() { this.clipboardManager.copy() }
  cutField() { this.clipboardManager.cut() }
  pasteField() { this.clipboardManager.paste() }

  // =========================================================================
  // Delegated Actions -> ResizeManager
  // =========================================================================

  startResize(event) { this.resizeManager.startResize(event) }

  // =========================================================================
  // Delegated Actions -> CommandPaletteManager
  // =========================================================================

  openCommandPalette() { this.commandPaletteManager.open() }
  closeCommandPalette() { this.commandPaletteManager.close() }
  filterCommandPalette(event) { this.commandPaletteManager.filter(event) }
  commandPaletteKeydown(event) { this.commandPaletteManager.handleKeydown(event) }
  executeCommandPaletteResult(event) { this.commandPaletteManager.executeFromClick(event) }
  stopPropagation(event) { event.stopPropagation() }

  // =========================================================================
  // Delegated Actions -> ZoomManager
  // =========================================================================

  zoomIn() { this.zoomManager.zoomIn() }
  zoomOut() { this.zoomManager.zoomOut() }
  zoomReset() { this.zoomManager.zoomReset() }
  toggleMiniMap() { this.zoomManager.toggleMiniMap() }
  openCanvasSearch() { this.zoomManager.openSearch() }
  closeCanvasSearch() { this.zoomManager.closeSearch() }
  filterCanvasSearch(event) { this.zoomManager.filterSearch(event) }
  canvasSearchKeydown(event) { this.zoomManager.searchKeydown(event) }

  // =========================================================================
  // Delegated Actions -> ContextMenuManager
  // =========================================================================

  openFieldContextMenu(event) { this.contextMenuManager.openForField(event) }
  openCanvasContextMenu(event) { this.contextMenuManager.openForCanvas(event) }
  closeContextMenu() { this.contextMenuManager.close() }

  // =========================================================================
  // Panel search filter
  // Used by rules and calculations panels to filter visible list items.
  // The input must carry:
  //   data-action="input->page-builder#filterPanel"
  //   data-filter-panel="<panel-data-attribute>"   e.g. "rules-panel" or "calculations-panel"
  //   data-filter-items="<item-data-attribute>"     e.g. "rule-id" or "calculation-id"
  // =========================================================================

  filterPanel(event) {
    const input = event.currentTarget
    const query = input.value.toLowerCase()
    const panelAttr = input.dataset.filterPanel
    const itemAttr = input.dataset.filterItems
    if (!panelAttr || !itemAttr) return

    const panel = input.closest(`[data-${panelAttr}]`)
    if (!panel) return

    panel.querySelectorAll(`[data-${itemAttr}]`).forEach(el => {
      el.classList.toggle("hidden", query.length > 0 && !el.textContent.toLowerCase().includes(query))
    })
  }
}
