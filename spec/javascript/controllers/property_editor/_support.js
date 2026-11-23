// Shared fakes for BranchManager, its canvas_operations mixin, and the
// BranchManager class itself.
// NOT a test file (no *.test.js suffix) so vitest won't execute it directly.
import { vi } from "vitest"
import { BranchManager } from "controllers/property_editor/branch_manager"

export function makeCanvas(over = {}) {
  const connections = over.connections || []
  const elements = over.elements || []
  return {
    elements,
    connections,
    entityAttributes: over.entityAttributes || [],
    elementLayer: document.createElement("div"),
    renderElement: vi.fn(),
    updateElementPosition: vi.fn(),
    updateConnections: vi.fn(),
    _hideConnectionHandles: vi.fn(),
    onBeforeChange: vi.fn(),
    onchange: vi.fn(),
    _getSubTreeElements: vi.fn(() => []),
    shiftElementAndSubTree: vi.fn(),
    createConnection: vi.fn((from, to, fromSide, toSide, opts = {}) => {
      const conn = { id: `c_${from.id}_${to.id}`, from: from.id, to: to.id, fromPort: fromSide, ...opts }
      connections.push(conn)
      return conn
    }),
    deleteConnection: vi.fn((id) => {
      const index = connections.findIndex((conn) => conn.id === id)
      if (index !== -1) connections.splice(index, 1)
    }),
    ...over.canvasOverrides,
  }
}

// English defaults mirroring the Stimulus `static values` on
// PropertyEditorController — see property_editor_controller.js. Bare-object
// fakes (this file, and other manager-specific *_support.js files) are not
// real Stimulus controllers, so they don't get Value defaults for free; we
// duplicate the English default text here (byte-identical) so specs assert
// against the same strings the real controller would resolve to when no
// data-*-value attribute is present.
export const PROPERTY_EDITOR_I18N_DEFAULTS = {
  joinAndLabelValue: "AND",
  joinOrLabelValue: "OR",
  noVariablesAvailableValue: "No variables available",
  usedInThisElementLabelValue: "Used in this element",
  noMatchingVariablesLabelValue: "No matching variables",
  editBranchTitleValue: "Edit Branch",
  saveChangesLabelValue: "Save Changes",
  addDecisionBranchTitleValue: "Add Decision Branch",
  addBranchLabelValue: "Add Branch",
  branchesEmptyStateFormatValue: 'No branches yet. Click "{addBranchLabel}" to create the first route.',
  couldNotLoadEntitiesLabelValue: "Could not load entities",
  softTypeHintTitleValue: "Expected a number or a ctx expression",
  tabGeneralLabelValue: "General",
  tabStepsLabelValue: "Step",
  tabBranchesLabelValue: "Branches",
  tabIoLabelValue: "I/O",
  tabAdvancedLabelValue: "Advanced",
  connectionDescriptionLabelValue: "Description",

  // Shared conditions control (field + record-count rows)
  conditionGroupLabelValue: "Group",
  conditionLabelValue: "Condition",
  removeGroupTitleValue: "Remove group",
  removeConditionTitleValue: "Remove condition",
  conditionFieldTypeLabelValue: "Field",
  conditionCountTypeLabelValue: "Count",
  conditionBlankOperatorLabelValue: "— (use value) —",
  selectOperatorPlaceholderValue: "Select operator...",
  leftOperandLabelValue: "Left operand",
  operatorLabelValue: "Operator",
  rightOperandLabelValue: "Right operand",
  enterValuePlaceholderValue: "Enter a value…",
  chooseFromListTitleValue: "Choose from list instead",
  chooseFromListLabelValue: "choose from list",
  branchOperatorLabelsValue: {
    contains: "contains",
    starts_with: "starts with",
    ends_with: "ends with",
    is_empty: "is empty",
    is_not_empty: "is not empty",
    is_true: "is true",
    is_false: "is false",
    matches_regex: "matches regex",
    in_range: "in range",
    is_type: "is type",
    is_nil: "is nil"
  },
  entityLabelValue: "Entity",
  selectEntityPlaceholderValue: "Select entity...",
  whereOptionalLabelValue: "Where (optional)",
  addFilterLabelValue: "Add Filter",
  countOperatorLabelValue: "Count Operator",
  countValueLabelValue: "Count Value",
  selectOperandPlaceholderValue: "Select operand...",
  signalsGroupLabelValue: "Signals",
  contextGroupLabelValue: "Context",
  entityFieldsGroupLabelValue: "Entity Fields",
  parentOutputsGroupLabelValue: "Parent Outputs",
  selectValuePlaceholderValue: "Select value...",
  commonGroupLabelValue: "Common",
  otherGroupLabelValue: "Other",
  customValueLabelValue: "Custom value...",
  legacyConditionTitleValue: "Legacy text condition",
  currentValueLabelValue: "Current value:",
  convertLegacyConditionLabelValue: "Convert to structured condition",
  noneOptionLabelValue: "None",
  addRowLabelValue: "Add row",
  removeRowTitleValue: "Remove",
  searchPlaceholderValue: "Search…",
  localeEnLabelValue: "English",
  localeZhCnLabelValue: "Chinese",
  referenceLoadingLabelValue: "Loading…",
  referenceEmptyLabelValue: "No matches",
  referenceErrorLabelValue: "Could not load options",
  referencePlaceholderValue: "Select…",
  selectFieldPlaceholderValue: "Select field...",
  enterManuallyLabelValue: "enter manually…",
  removeFilterTitleValue: "Remove filter",
  switchToDropdownTitleValue: "Switch to dropdown",
  schemaUnavailableLabelValue: "Schema unavailable — enter field names manually",
  columnNamePlaceholderValue: "column name",
  valuePlaceholderValue: "value",

  // templates/branch.js (threaded via BranchManager#_branchLabels)
  matchValueLabelValue: "Match Value",
  matchValueEmptyHintValue: "(empty = default / otherwise)",
  matchValuePlaceholderValue: "e.g. active",
  branchNameLabelValue: "Branch Name",
  branchNamePlaceholderValue: "e.g. Active",
  optionalHintValue: "(optional)",
  branchDescriptionPlaceholderValue: "Describe this branch...",
  cancelLabelValue: "Cancel",
  editBranchItemTitleValue: "Edit branch",
  removeBranchItemTitleValue: "Remove branch",
  branchDefaultBadgeLabelValue: "default &mdash; otherwise",
  otherwiseLabelValue: "Otherwise",
  yesMatchLabelValue: "Yes",
  noMatchLabelValue: "No",
  routeByClearedNoticeValue: "Match values were cleared.",
  undoLabelValue: "Undo",
  branchFallbackNameFormatValue: "Branch {index}",
}

export function makeController(over = {}) {
  const formFieldsTarget = over.formFieldsTarget || document.createElement("div")
  const formTarget = over.formTarget || document.createElement("form")
  return {
    canvas: "canvas" in over ? over.canvas : makeCanvas(),
    currentElement: "currentElement" in over ? over.currentElement : { id: "d", type: "decision", properties: {} },
    formFieldsTarget,
    formTarget,
    application: over.application || { getControllerForElementAndIdentifier: () => null },
    _syncChangesToCanvas: over._syncChangesToCanvas || vi.fn(),
    ...PROPERTY_EDITOR_I18N_DEFAULTS,
    ...over.controllerOverrides,
  }
}

export function makeBranchManager(over = {}) {
  const controller = over.controller || makeController(over)
  const mgr = new BranchManager(controller)
  return { mgr, controller }
}
