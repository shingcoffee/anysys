// Shared test scaffolding for the page_builder manager classes.
//
// The managers are plain classes (NOT Stimulus controllers): each is
// constructed with a host controller object and reaches into it via `this.c`.
// So we can unit-test them directly by handing them a stub controller — no
// mounting needed. `makeCtrl()` builds that stub with sensible defaults and
// vi.fn() spies for every sibling manager; individual tests override the bits
// they exercise.
import { vi } from "vitest"

// Mirrors the English `default:` values declared on page_builder_controller.js's
// `static values` block (the i18n seam: production overrides these via
// data-page-builder-<name>-value="<%= t(...) %>", tests get the same English
// text a real Stimulus-mounted controller would fall back to). Keep in sync
// with app/javascript/controllers/page_builder_controller.js.
export const I18N_VALUE_DEFAULTS = {
  // FieldManager
  untitledFieldLabelValue: "Untitled",
  fieldGroupLabelValue: "Field Group",
  ariaLayoutComponentLabelValue: "layout component",
  ariaFieldLabelValue: "field",
  dropHereLabelValue: "Drop here",
  ungroupLabelValue: "Ungroup",
  saveAsTemplateLabelValue: "Save as Template",
  templateNamePromptLabelValue: "Template name:",
  templateSavedMsgValue: "Template saved!",
  templateSaveFailedMsgValue: "Failed to save template",
  dragGhostFieldFallbackLabelValue: "Field",

  // PropertyManager
  htmlTypeDisplayNamesValue: {
    text: "Input Text", textarea: "Text Area", search: "Search",
    password: "Password", hidden: "Hidden",
    select: "Dropdown", "multi-select": "Multi Select",
    radio: "Radio", checkbox: "Checkbox", switch: "Toggle Switch",
    number: "Number", currency: "Currency", range: "Range Slider", rating: "Rating",
    date: "Date", time: "Time", "datetime-local": "Date & Time", month: "Month", week: "Week",
    email: "Email", tel: "Phone", url: "URL",
    "rich-text": "Rich Text", signature: "Signature",
    file: "File Upload", image: "Image Upload", color: "Color Picker",
  },
  fieldsSelectedLabelValue: "{count} fields selected",
  moveToPageEllipsisLabelValue: "Move to Page...",
  deleteSelectedLabelValue: "Delete Selected",
  deselectAllLabelValue: "Deselect all",
  fieldGroupSettingsLabelValue: "Field Group Settings",
  layoutSettingsLabelsValue: {
    heading: "Heading Settings", paragraph: "Paragraph Settings",
    section: "Section Settings", divider: "Divider Settings",
    spacer: "Spacer Settings", alert: "Alert Settings",
    image: "Image Settings", button: "Button Settings",
    video: "Video Settings", list: "List Settings",
    code_block: "Code Block Settings", card: "Card Settings",
    progress_bar: "Progress Bar Settings", columns: "Column Settings",
    callout: "Callout Settings", quote: "Quote Settings",
  },
  layoutSettingsFallbackLabelValue: "Layout Settings",
  fieldPropertiesLabelValue: "Field Properties",
  formSettingsLabelValue: "Form Settings",
  noConditionalRulesLabelValue: "No conditional rules",
  ruleSummaryShowVerbValue: "Show",
  ruleSummaryHideVerbValue: "Hide",
  ruleSummaryFormatValue: "{verb} this field when {conditions}",
  editRulesLabelValue: "Edit Rules",
  operatorLabelsValue: {
    equals: "equals", not_equals: "does not equal", contains: "contains",
    not_contains: "does not contain", greater_than: ">", less_than: "<",
    is_empty: "is empty", is_not_empty: "is not empty",
  },

  // Breadcrumb
  breadcrumbPageFallbackValue: "Page 1",
  breadcrumbColumnsLabelValue: "Columns",
  breadcrumbColumnNumberFormatValue: "Column {number}",
  breadcrumbSectionLabelValue: "Section",

  // TabManager
  noFieldsLabelValue: "No Fields",
  noPropertiesFoundLabelValue: "No properties found for this entity",

  // CommandPaletteManager
  noResultsFoundLabelValue: "No results found",
  untitledTemplateLabelValue: "Untitled Template",

  // PageManager
  deletePageConfirmSingularValue: 'Delete "{name}" and its {count} field?',
  deletePageConfirmPluralValue: 'Delete "{name}" and its {count} fields?',
  deletePageConfirmNoFieldsValue: 'Delete "{name}"?',
  deletePageFallbackNameValue: "this page",
  renamePageTitleValue: "Rename page",
  deletePageTitleValue: "Delete page",
  addNewPageTitleValue: "Add new page",
  cancelLabelValue: "Cancel",
  previousStepLabelValue: "← Previous",
  nextStepLabelValue: "Next →",
  stepOfFormatValue: "Step {current} of {total}",
  defaultSubmitButtonTextValue: "Submit",

  // SaveManager
  saveLabelValue: "Save",
  saveDirtyLabelValue: "Save*",
  savingLabelValue: "Saving...",
  savedLabelValue: "Saved",
  saveErrorGenericMessageValue: "Couldn't save the page. Please try again.",
  saveConflictLabelValue: "Conflict",
  saveConflictConfirmMsgValue: "This page was updated in another tab since you started editing. Reload to see the latest version? (Your unsaved changes will be lost.)",

  // SelectionManager
  bulkDeleteConfirmSingularValue: "Delete {count} field?",
  bulkDeleteConfirmPluralValue: "Delete {count} fields?",
  moveToPageModalTitleValue: "Move to Page",
  moveFieldsPromptSingularValue: "Move {count} field to another page",
  moveFieldsPromptPluralValue: "Move {count} fields to another page",
  currentPageTagValue: "(current)",
  orCreateNewPageLabelValue: "Or create a new page",
  newPageNamePlaceholderValue: "New page name...",
  moveFieldsButtonLabelValue: "Move Fields",

  // ZoomManager
  searchOfFormatValue: "{matches} of {total}",
  searchFieldsPlaceholderValue: "Search fields...",

  // CalculationsManager
  calcModalTitleEditValue: "Edit Calculation",
  calcModalTitleNewValue: "New Calculation",
  calcSelectTargetFormulaMsgValue: "Please select a target field and enter a formula",
  deleteCalculationConfirmValue: "Delete this calculation?",
  calcConfiguredSingularValue: "{count} calculation configured",
  calcConfiguredPluralValue: "{count} calculations configured",
  addCalculationLabelValue: "Add Calculation",
  noCalculatedFieldsLabelValue: "No calculated fields",
  noCalculatedFieldsHintValue: "Add formulas to automatically compute field values from other fields.",
  searchCalculationsPlaceholderValue: "Search calculations…",

  // RulesManager
  ruleModalTitleEditValue: "Edit Rule",
  ruleModalTitleNewValue: "New Rule",
  deleteRuleConfirmValue: "Delete this rule?",
  unnamedRuleFallbackValue: "Unnamed rule",
  rulesConfiguredSingularValue: "{count} rule configured",
  rulesConfiguredPluralValue: "{count} rules configured",
  addRuleLabelValue: "Add Rule",
  searchRulesPlaceholderValue: "Search rules…",
  noRulesDefinedLabelValue: "No rules defined",
  noRulesDefinedHintValue: "Add conditional rules to show or hide fields dynamically based on user input.",
  ruleWhenFormatValue: "When {field} {operator}",
  ruleActionArrowFormatValue: "→ {action} {field}",
  ruleEnableTitleValue: "Enable",
  ruleDisableTitleValue: "Disable",

  // Shared action titles (CalculationsManager + RulesManager panel rows)
  actionEditTitleValue: "Edit",
  actionDeleteTitleValue: "Delete",
  actionDuplicateTitleValue: "Duplicate",

  // InserterManager
  componentCatalogLabelsValue: {
    section: "Section", card: "Card", columns: "Columns", divider: "Divider", spacer: "Spacer",
    heading: "Heading", paragraph: "Paragraph", list: "List", quote: "Quote", code_block: "Code Block",
    image: "Image", video: "Video", button: "Button", alert: "Alert", callout: "Callout", progress_bar: "Progress",
  },
  componentCatalogCategoryLabelsValue: {
    Structure: "Structure", Content: "Content", "Media & Actions": "Media & Actions", Feedback: "Feedback",
  },

  // CommandPaletteManager
  fieldCommandLabelsValue: {
    text: "Text Input", email: "Email", select: "Select", number: "Number", date: "Date", file: "File Upload",
    textarea: "Textarea", checkbox: "Checkbox", radio: "Radio", switch: "Switch", currency: "Currency",
    rating: "Rating", password: "Password", tel: "Phone", url: "URL", "rich-text": "Rich Text", signature: "Signature",
  },
  layoutCommandLabelsValue: {
    section: "Section", heading: "Heading", paragraph: "Paragraph", divider: "Divider", spacer: "Spacer",
    columns: "Columns", card: "Card", alert: "Alert", button: "Button", image: "Image", video: "Video",
    list: "List", code_block: "Code Block", progress_bar: "Progress Bar", quote: "Quote", callout: "Callout",
  },
  actionCommandLabelsValue: {
    duplicate: "Duplicate Field", delete: "Delete Field", copy: "Copy Field", paste: "Paste Field",
    undo: "Undo", redo: "Redo", preview: "Preview Form", save: "Save Form",
  },
  commandCategoryLabelsValue: { Fields: "Fields", Layout: "Layout", Actions: "Actions", Templates: "Templates" },

  // ContextMenuManager
  editLabelActionTitleValue: "Edit Label",
  copyActionTitleValue: "Copy",
  cutActionTitleValue: "Cut",
  pasteActionTitleValue: "Paste",
  pasteAfterActionTitleValue: "Paste After",
  addFieldActionTitleValue: "Add Field",
  selectAllActionTitleValue: "Select All",
  widthMenuTitleValue: "Width",
  widthFullLabelValue: "Full",
  widthHalfLabelValue: "Half",

  // LayoutCardsMixin
  layoutDefaultLabelsValue: {},
  layoutDefaultContentsValue: {},
  resizeSnapLabelsValue: {},
  templateFieldFallbackLabelValue: "Template Field",
  spacerHeightLabelsValue: { sm: "Small", md: "Medium", lg: "Large", xl: "Extra Large" },
  listStyleLabelsValue: { bullet: "Bullet", numbered: "Numbered", none: "Plain" },
  columnLayoutBadgeLabelsValue: {
    "50-50": "2 Equal", "33-33-33": "3 Equal", "66-33": "2:1", "33-66": "1:2", "25-25-25-25": "4 Equal",
  },
  codeBadgeLabelValue: "Code",
  dropFieldsHereLabelValue: "Drop fields here",
  dragToReorderTitleValue: "Drag to reorder",

  // FormBuilderMixin
  conditionIfLabelValue: "If",
  conditionSelectFieldOptionValue: "Select field...",
  conditionOperatorLabelsValue: {
    equals: "Equals", not_equals: "Not equals", contains: "Contains", not_contains: "Not contains",
    greater_than: "Greater than", less_than: "Less than", is_empty: "Is empty", is_not_empty: "Is not empty",
  },
  valuePlaceholderValue: "Value",
  labelPlaceholderValue: "Label",
  conditionAndLabelValue: "AND",
  conditionOrLabelValue: "OR",
  newOptionLabelFormatValue: "Option {number}",

  // FieldPreviewsMixin
  hiddenFieldPreviewLabelValue: "Hidden field",
  enterFieldPlaceholderFormatValue: "Enter {label}",
  selectFieldPlaceholderFormatValue: "Select {label}",
  switchEnabledPreviewLabelValue: "Enabled",
  dropFileUploadLabelValue: "Drop file or click to upload",
  clickUploadImageLabelValue: "Click to upload image",
  signHerePreviewLabelValue: "Sign here",

  // FieldManager / FieldCrudMixin
  duplicateSuffixFormatValue: "{name} (Copy)",
  autoSectionFallbackLabelValue: "Fields",
}

// Flatten top-level fields + nested column/group children (mirrors the real
// controller's `allFields` getter).
function flatten(fields) {
  const out = []
  for (const f of fields) {
    out.push(f)
    if (f.field_type === "columns" && Array.isArray(f.columns)) {
      f.columns.forEach((col) => (col.fields || []).forEach((x) => out.push(x)))
    }
    if (f.type === "field_group" && Array.isArray(f.fields)) {
      f.fields.forEach((x) => out.push(x))
    }
  }
  return out
}

export function makeCtrl(overrides = {}) {
  const configuration = overrides.configuration || {
    calculations: [],
    rules: [],
    pages: [],
    theme: {},
  }
  const currentPage = overrides.currentPage || { id: "p1", fields: [] }

  const ctrl = {
    ...I18N_VALUE_DEFAULTS,
    customerIdValue: "123",
    idValue: "1",
    configuration,
    currentPage,
    fields: currentPage.fields,
    selectedFieldId: null,
    editingCalculationIdValue: "",
    currentEditingCalculation: null,
    viewportValue: "desktop",
    layoutTemplateValue: {},
    metadata: {},
    activePageValue: currentPage.id,
    element: overrides.element || document.body,
    reorderingFieldIds: null,

    // Direct controller-level helper (some managers call this.c.saveState()).
    saveState: vi.fn(),

    get currentPageFields() {
      return this.currentPage.fields
    },
    get allFields() {
      return flatten(this.currentPage.fields)
    },

    selectionManager: {
      getSelectedFields: vi.fn(() => []),
      getSelectedFieldIds: vi.fn(() => []),
      deselectAll: vi.fn(),
      addToSelection: vi.fn(),
      updateVisuals: vi.fn(),
      selectField: vi.fn(),
      selectFields: vi.fn(),
      isSelected: vi.fn(() => false),
      selectAll: vi.fn(),
      isEmpty: true,
    },

    fieldManager: {
      renderFields: vi.fn(),
      selectFieldById: vi.fn(),
      createField: vi.fn(),
      findFieldById: vi.fn(),
      removeFieldFromAnyColumn: vi.fn(),
      deleteField: vi.fn(),
      ungroupFields: vi.fn(),
      saveFieldAsTemplate: vi.fn(),
      addFieldAtIndex: vi.fn(),
      getUsedPropertySlugs: vi.fn(() => new Set()),
      _sectionIdForDrag: vi.fn(() => null),
    },

    saveManager: { markDirty: vi.fn(), preview: vi.fn(), save: vi.fn() },
    undoRedoManager: {
      saveState: vi.fn(),
      saveHistory: vi.fn(),
      undo: vi.fn(),
      redo: vi.fn(),
    },
    clipboardManager: {
      clipboard: [],
      copy: vi.fn(),
      cut: vi.fn(),
      paste: vi.fn(),
      duplicateSelected: vi.fn(),
    },
    commandPaletteManager: { open: vi.fn() },
    propertyManager: { hideFloatingPanel: vi.fn() },
    pageManager: {
      updateFormFooter: vi.fn(),
      renderPageTabs: vi.fn(),
      pruneReferencesToDeletedFields: vi.fn(),
    },
    tabManager: {
      closeAllTabPanels: vi.fn(),
      showDrawerEditor: vi.fn(),
      showDrawerList: vi.fn(),
    },
    dragDropManager: {
      captureCardRects: vi.fn(() => new Map()),
      flipFromRects: vi.fn(),
      _sidebarData: vi.fn(),
    },
    dragEngine: { _lastDropPoint: null },
    dragVisuals: {
      showGhost: vi.fn(),
      markSource: vi.fn(),
      moveGhost: vi.fn(),
      showIndicator: vi.fn(),
      highlightContainer: vi.fn(),
      hideGhost: vi.fn(),
      hideIndicator: vi.fn(),
      clearSource: vi.fn(),
    },
    dropResolver: { resolve: vi.fn(), buildSnapshot: vi.fn() },
    dropMutations: { apply: vi.fn() },
  }

  // Apply overrides last so tests can replace any data prop or manager wholesale.
  for (const [k, v] of Object.entries(overrides)) {
    if (k === "configuration" || k === "currentPage") continue
    ctrl[k] = v
  }
  return ctrl
}

// A field factory with the shape the managers expect.
export function field(attrs = {}) {
  return {
    id: attrs.id || `f_${Math.random().toString(36).slice(2, 8)}`,
    field_type: attrs.field_type || attrs.type || "text",
    property_type: attrs.property_type || "string",
    property_slug: attrs.property_slug ?? "slug",
    label: attrs.label || "Field",
    width: attrs.width || "full",
    order: attrs.order ?? 0,
    ...attrs,
  }
}
