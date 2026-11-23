import { VALIDATOR_LABELS } from "constants/validator_labels"

// Shared helper for testing entity_form manager classes.
//
// The managers are NOT Stimulus controllers — each is a plain class constructed
// with a `controller` object and reads Stimulus-style targets/values off it
// (`this.c.fooTarget`, `this.c.hasFooTarget`, `this.c.fooValue`). Rather than
// booting a real Stimulus Application, we synthesize a lightweight fake
// controller from a chunk of HTML: every element carrying
// `data-entity-form-target="name"` becomes `nameTarget` / `nameTargets`, and a
// matching `hasNameTarget` getter. Values and collaborator managers are attached
// directly. This keeps each manager under test with real DOM structure while
// letting us stub collaborators where a unit boundary is wanted.

const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1)

// Mirrors the English `default:` values declared on entity_form_controller.js's
// `static values` block (the i18n seam: production overrides these via
// data-entity-form-<name>-value="<%= t(...) %>", tests get the same English
// text a real Stimulus-mounted controller would fall back to). Keep in sync
// with app/javascript/controllers/entity_form_controller.js.
export const I18N_VALUE_DEFAULTS = {
  // AssociationManager
  addAssociationLabelValue: "Add Association",
  editAssociationLabelValue: "Edit Association",
  updateAssociationLabelValue: "Update Association",
  editAssociationAttributeLabelValue: "Edit Association Attribute",
  updateAttributeLabelValue: "Update Attribute",
  selectTargetEntityMsgValue: "Please select a target entity",
  selectDisplayFieldMsgValue: "Please select a display field",

  // ValidatorManager
  allowedValuesLabelValue: "Allowed Values",
  forbiddenValuesLabelValue: "Forbidden Values",
  configurationValueLabelValue: "Configuration Value",
  validatorConfigLabelsValue: {
    greater_than_or_equal_to: "Minimum Value (>=)",
    less_than_or_equal_to: "Maximum Value (<=)",
    equal_to: "Required Value (==)",
    not_equal_to: "Forbidden Value (!=)",
    greater_than: "Minimum Value (>)",
    less_than: "Maximum Value (<)",
    length_minimum: "Minimum Length",
    length_maximum: "Maximum Length",
  },
  validatorLabelsValue: { ...VALIDATOR_LABELS },
  enterValueMsgValue: "Please enter a value",
  enterMinMaxMsgValue: "Please enter both minimum and maximum values",
  minLessThanMaxMsgValue: "Minimum value must be less than maximum value",
  enterPatternMsgValue: "Please enter a regex pattern",
  invalidPatternMsgValue: "Invalid regex pattern",
  enterAtLeastOneValueMsgValue: "Please enter at least one value",

  // GroupManager
  newGroupLabelValue: "New Group",
  createGroupLabelValue: "Create Group",
  editGroupLabelValue: "Edit Group",
  saveGroupLabelValue: "Save Group",
  groupNameRequiredMsgValue: "Group name is required",
  groupNameUniqueMsgValue: "Group name must be unique",

  // AttributeManager
  nameRequiredMsgValue: "Name is required",
  displayLabelRequiredMsgValue: "Display Label is required",
  duplicateNameMsgValue: "An attribute with this name already exists",
  duplicateSlugMsgValue: "This name conflicts with an existing attribute.",
  fieldReservedMsgValue: "Field name '{name}' is reserved. It already exists in {model} model.",
  editAttributeLabelValue: "Edit Attribute",
  saveChangesLabelValue: "Save Changes",

  // ModalManager
  addAssociationAttributeLabelValue: "Add Association Attribute",
  addAttributeLabelValue: "Add Attribute",

  // ConstantsManager
  constantOptionCountLabelValue: "{name} ({count} options)",
  optionCountSingularLabelValue: "{count} option",
  optionCountPluralLabelValue: "{count} options",

  // TemplateBuilder — attribute table, badges, view/association modals
  nameLabelValue: "Name",
  displayLabelHeaderValue: "Display Label",
  htmlTypeHeaderValue: "HTML Type",
  validatorsHeaderValue: "Validators",
  visibilityHeaderValue: "Visibility",
  actionsHeaderValue: "Actions",
  dragTitleValue: "Drag",
  viewAttributeTitleValue: "View attribute",
  copyAttributeTitleValue: "Copy attribute",
  editAttributeTitleValue: "Edit attribute",
  removeAttributeTitleValue: "Remove attribute",
  groupUngroupedLabelValue: "Ungrouped",
  groupEmptyBadgeLabelValue: "Empty",
  groupActionsTitleValue: "Group actions",
  attributeCountSingularValue: "{count} attribute",
  attributeCountPluralValue: "{count} attributes",
  adminLabelValue: "Admin",
  memberLabelValue: "Member",
  publicLabelValue: "Public",
  visibleLabelValue: "Visible",
  applyValidatorsLabelValue: "Apply validators",
  editableLabelValue: "Can edit",
  optionDefaultLabelValue: "Default",
  optionLabelPlaceholderValue: "Label (displayed to user)",
  optionValuePlaceholderValue: "Value (stored in database)",
  removeOptionTitleValue: "Remove option",
  removeValidatorTitleValue: "Remove",
  noneLabelValue: "None",
  groupHeaderValue: "Group",
  configurationHeaderValue: "Configuration",
  descriptionHeaderValue: "Description",
  identitySectionHeaderValue: "Identity",
  audienceSectionHeaderValue: "Audience",
  validationSectionHeaderValue: "Validation",
  detailsSectionHeaderValue: "Details",
  noDescriptionProvidedLabelValue: "No description provided.",
  configLabelHeaderValue: "Label",
  configValueHeaderValue: "Value",
  configAcceptLabelValue: "Accept: ",
  configMultipleLabelValue: "Multiple: ",
  yesLabelValue: "Yes",
  noLabelValue: "No",
  assocWillBeCreatedLabelValue: "Will be created on save",
  assocMoreFormatValue: "+{count} more",
  editAssociationTitleValue: "Edit association",
  removeAssociationTitleValue: "Remove association",
  targetEntityHeaderValue: "Target Entity",
  displayColumnHeaderValue: "Display",
  bridgeEntityHeaderValue: "Bridge Entity",
  additionalAttributesHeaderValue: "Additional Attributes",
  groupMenuNewGroupLabelValue: "+ New group…",
  groupMenuEditLabelValue: "Edit…",
  groupMenuDeleteLabelValue: "Delete",

  // TypeManager
  htmlTypeLabelsValue: {
    text: "Text Input", textarea: "Textarea", search: "Search",
    password: "Password", hidden: "Hidden",
    select: "Dropdown", radio: "Radio", checkbox: "Checkbox",
    number: "Number", range: "Range",
    date: "Date", time: "Time", "datetime-local": "DateTime",
    month: "Month", week: "Week",
    email: "Email", tel: "Phone", url: "URL",
    file: "File", image: "Image", color: "Color",
  },
  htmlTypeNaLabelValue: "N/A",

  // ComputedManager
  computedOptionsValue: [],
  computedIncompleteMsgValue: "Please complete the computed field configuration",
  computedTypeBadgeValue: "Computed",
  computedRelationPlaceholderValue: "Select a relation",
  computedAttributePlaceholderValue: "Select an attribute",
  computedRelationFormatValue: "{related} ({bridge})",
  computedEmptyHintValue: "No related associations",
  computedFilterNoneValue: "No filter",
}

// Build a fake controller. `html` is wrapped in a `data-controller="entity-form"`
// root (which becomes controller.element). Target getters resolve live against
// the current DOM subtree, so dynamically-inserted targets are picked up too.
export function buildController(html = "", { values = {} } = {}) {
  document.body.innerHTML = `<div data-controller="entity-form">${html}</div>`
  const element = document.body.firstElementChild
  const controller = { element }

  Object.assign(controller, I18N_VALUE_DEFAULTS, values)

  // Discover every distinct target name currently present so we can define
  // getters. Getters re-query on each access to stay live.
  const names = new Set()
  const scan = () =>
    element.querySelectorAll("[data-entity-form-target]").forEach((el) => {
      el.getAttribute("data-entity-form-target").split(/\s+/).forEach((n) => n && names.add(n))
    })
  scan()

  const define = (name) => {
    if (Object.getOwnPropertyDescriptor(controller, `${name}Target`)) return
    const all = () => Array.from(element.querySelectorAll(`[data-entity-form-target~="${name}"]`))
    Object.defineProperty(controller, `${name}Target`, { configurable: true, get: () => all()[0] })
    Object.defineProperty(controller, `${name}Targets`, { configurable: true, get: () => all() })
    Object.defineProperty(controller, `has${cap(name)}Target`, { configurable: true, get: () => all().length > 0 })
  }
  names.forEach(define)

  // Allow tests to register target names that will appear after dynamic inserts.
  controller.__defineTarget = define

  return { controller, element }
}

// A no-arg fake DOM event with the guards the managers call (preventDefault,
// stopPropagation) plus optional target/currentTarget and a dataTransfer stub.
export function fakeEvent(overrides = {}) {
  return {
    preventDefault: () => {},
    stopPropagation: () => {},
    ...overrides,
  }
}

// dataTransfer stub for HTML5 drag events (happy-dom has no native DataTransfer).
export function fakeDataTransfer() {
  const store = {}
  return {
    effectAllowed: null,
    dropEffect: null,
    setData: (type, val) => { store[type] = val },
    getData: (type) => store[type] || "",
  }
}
