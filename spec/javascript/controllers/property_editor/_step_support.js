// Shared fakes for StepManager + its mixins (drag_drop, action_picker,
// config_fields). NOT a test file (no *.test.js suffix).
import { StepManager } from "controllers/property_editor/step_manager"

// English defaults mirroring the Stimulus `static values` on
// PropertyEditorController — see property_editor_controller.js and
// _support.js's PROPERTY_EDITOR_I18N_DEFAULTS for the rationale.
const STEP_I18N_DEFAULTS = {
  stepConfigSetCountFormatValue: "{count} set",
  softTypeHintTitleValue: "Expected a number or a ctx expression",
  tabStepsLabelValue: "Step",

  // step_manager.js#_stepItemLabels() -> templates/step.js
  stepDragToReorderTitleValue: "Drag to reorder",
  stepChangeButtonLabelValue: "Change",
  stepChangeActionTitleValue: "Change action",
  stepRemoveButtonLabelValue: "Remove",
  stepRemoveButtonTitleValue: "Remove step",
  stepErrorBadgeLabelValue: "Error",
  stepParamsPrefixLabelValue: "Params:",

  // step_manager.js#_stepFieldLabels() -> templates/fields.js
  stepMoreOptionsLabelValue: "More options",
  insertVariableTitleValue: "Insert variable",
  noVariablesAvailableValue: "No variables available",
  usedInThisElementLabelValue: "Used in this element",
  noMatchingVariablesLabelValue: "No matching variables",
  selectColumnPlaceholderValue: "Select column…",
  otherGroupLabelValue: "Other",
  enterManuallyLabelValue: "enter manually…",
  switchToDropdownTitleValue: "Switch to dropdown",
  columnNamePlaceholderValue: "column name",
  kvKeyPlaceholderValue: "Key",
  kvValuePlaceholderValue: "Value",
  kvRemoveRowTitleValue: "Remove row",
  addLabelValue: "Add",
  joinAndLabelValue: "AND",
  joinOrLabelValue: "OR",
  addRowLabelValue: "Add row",
  removeRowTitleValue: "Remove",

  // step_manager/action_picker.js#buildStepPickerHTML
  stepPickerSearchPlaceholderValue: "Search actions…",
  stepPickerNoMatchLabelValue: "No matching actions",
  stepPickerAlreadyUsedLabelValue: "(already used)",
  stepPickerAllCategoriesLabelValue: "All",
  stepPickerCategoriesLabelValue: "Filter by category",
  stepPickerRecentLabelValue: "Recently used",
  stepRetryNotIdempotentHintValue: "Retry is available only for idempotent requests (safe methods or an idempotency key).",
  stepTimeoutGivesUpFormatValue: "Gives up after {seconds} s",
}

export function makeStepController(over = {}) {
  const form = over.formTarget || document.createElement("form")
  return {
    canvas: "canvas" in over ? over.canvas : { entityAttributes: [], findStepById: () => null },
    currentElement:
      "currentElement" in over ? over.currentElement : { id: "p1", type: "process", properties: {} },
    formTarget: form,
    formFieldsTarget: form,
    hasFormTarget: true,
    disclosureState: over.disclosureState || new Map(),
    stepIoManager: over.stepIoManager || null,
    application: over.application || { getControllerForElementAndIdentifier: () => null },
    ...STEP_I18N_DEFAULTS,
    ...over.controllerOverrides,
  }
}

export function makeStepManager(over = {}) {
  const controller = over.controller || makeStepController(over)
  return { mgr: new StepManager(controller), controller }
}
