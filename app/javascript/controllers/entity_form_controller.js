import { Controller } from "@hotwired/stimulus"
import { TypeManager, HTML_TYPE_LABELS } from "controllers/entity_form/type_manager"
import { ValidatorManager, VALIDATOR_CONFIG_LABELS } from "controllers/entity_form/validator_manager"
import { TemplateBuilder } from "controllers/entity_form/template_builder"
import { SchemaManager } from "controllers/entity_form/schema_manager"
import { ModalManager } from "controllers/entity_form/modal_manager"
import { ConstantsManager } from "controllers/entity_form/constants_manager"
import { ReferenceManager } from "controllers/entity_form/reference_manager"
import { AttributeManager } from "controllers/entity_form/attribute_manager"
import { AssociationManager } from "controllers/entity_form/association_manager"
import { GroupManager } from "controllers/entity_form/group_manager"
import { DndManager   } from "controllers/entity_form/dnd_manager"
import { ComputedManager } from "controllers/entity_form/computed_manager"
import { CSS } from "controllers/entity_form/base_manager"
import { VALIDATOR_LABELS } from "constants/validator_labels"

// Palette used to color groups auto-created from a template's Section labels,
// so adjacent sections are visually distinct. Mirrors GroupManager's colors.
const TEMPLATE_GROUP_COLORS = ["slate", "indigo", "sky", "teal", "emerald", "amber", "rose", "violet"]

/**
 * EntityFormController
 *
 * Thin orchestrator that delegates to specialized managers.
 * All Stimulus targets and values remain on the controller.
 * Action methods delegate to the appropriate manager.
 */
export default class extends Controller {
  static targets = [
    "attributesContainer",
    "attributesTable",
    "emptyState",
    "propertySchema",
    "modal",
    "modalName",
    "modalNameSlug",
    "modalHtmlType",
    "modalDisplayLabel",
    "modalVisibilityAdmin",
    "modalVisibilityMember",
    "modalVisibilityPublic",
    "modalValidatorApplyAdmin",
    "modalValidatorApplyMember",
    "modalValidatorApplyPublic",
    "modalEditableAdmin",
    "modalEditableMember",
    "modalEditablePublic",
    "modalDescription",
    "modalValidatorSelect",
    "validatorsContainer",
    "validatorConfigSection",
    "validatorSingleValueConfig",
    "validatorRangeConfig",
    "validatorPatternConfig",
    "validatorListConfig",
    "validatorConfigLabel",
    "validatorConfigValue",
    "validatorConfigMinValue",
    "validatorConfigMaxValue",
    "validatorConfigPattern",
    "validatorConfigList",
    "validatorListLabel",
    "entityName",
    "entityDisplayLabel",
    "optionsSection",
    "optionsContainer",
    "selectionConfig",
    "fileConfig",
    "configAccept",
    "configMultiple",
    "viewModal",
    "viewModalContent",
    "viewModalTitle",
    "viewModalSubtitle",
    "modalTitle",
    "modalSubmitBtn",
    "manualOptionsBtn",
    "constantOptionsBtn",
    "manualOptionsSection",
    "constantOptionsSection",
    "constantSelect",
    "constantPreview",
    "constantPreviewList",
    "constantOptionsCount",
    "entityRecordsOptionsBtn",
    "entityRecordsOptionsSection",
    "referenceEntitySelect",
    "referenceLabelFieldSelect",
    "ownerSection",
    "modalOwner",
    "associationsContainer",
    "associationsTable",
    "associationsEmptyState",
    "associationsSchema",
    "associationModal",
    "associationModalTitle",
    "associationModalSubmitBtn",
    "associationTargetEntity",
    "associationAttributesContainer",
    "associationAttributesEmptyState",
    "associationAttributesTableWrapper",
    "associationDisplaySection",
    "associationDisplayField",
    "attributeGroupsInput",
    "groupingToolbar",
    "selectionCount",
    "moveToGroupMenu",
    "moveToGroupBtn",
    "groupEditModal",
    "groupEditName",
    "groupEditDescription",
    "groupEditIcon",
    "groupEditColor",
    "groupModalTitle",
    "groupModalSubmit",
    "overwriteModal",
    "overwriteCount",
    "modeInputBtn",
    "modeComputedBtn",
    "computedSection",
    "computedRelation",
    "computedAttribute",
    "computedFunction",
    "computedPrecision",
    "computedFilterAttribute",
    "computedFilterOp",
    "computedFilterValue",
    "htmlTypeField",
    "validatorsSection",
    "valueSourceSection"
  ]

  static values = {
    customerId: String,
    currentEntityId: String,
    reservedFieldNames: Array,
    personEntityIds: { type: Array, default: [] },
    htmlTypeValidators: { type: Object, default: {} },

    // ── i18n seam: English defaults keep JS specs green without any
    // data-*-value attribute; the entities views supply the translated
    // strings via data-entity-form-<name>-value="<%= t(...) %>". ──

    // AssociationManager
    addAssociationLabel: { type: String, default: "Add Association" },
    editAssociationLabel: { type: String, default: "Edit Association" },
    updateAssociationLabel: { type: String, default: "Update Association" },
    editAssociationAttributeLabel: { type: String, default: "Edit Association Attribute" },
    updateAttributeLabel: { type: String, default: "Update Attribute" },
    selectTargetEntityMsg: { type: String, default: "Please select a target entity" },
    selectDisplayFieldMsg: { type: String, default: "Please select a display field" },

    // ValidatorManager
    allowedValuesLabel: { type: String, default: "Allowed Values" },
    forbiddenValuesLabel: { type: String, default: "Forbidden Values" },
    configurationValueLabel: { type: String, default: "Configuration Value" },
    validatorConfigLabels: { type: Object, default: { ...VALIDATOR_CONFIG_LABELS } },
    validatorLabels: { type: Object, default: { ...VALIDATOR_LABELS } },
    enterValueMsg: { type: String, default: "Please enter a value" },
    enterMinMaxMsg: { type: String, default: "Please enter both minimum and maximum values" },
    minLessThanMaxMsg: { type: String, default: "Minimum value must be less than maximum value" },
    enterPatternMsg: { type: String, default: "Please enter a regex pattern" },
    invalidPatternMsg: { type: String, default: "Invalid regex pattern" },
    enterAtLeastOneValueMsg: { type: String, default: "Please enter at least one value" },

    // GroupManager
    newGroupLabel: { type: String, default: "New Group" },
    createGroupLabel: { type: String, default: "Create Group" },
    editGroupLabel: { type: String, default: "Edit Group" },
    saveGroupLabel: { type: String, default: "Save Group" },
    groupNameRequiredMsg: { type: String, default: "Group name is required" },
    groupNameUniqueMsg: { type: String, default: "Group name must be unique" },

    // AttributeManager
    nameRequiredMsg: { type: String, default: "Name is required" },
    displayLabelRequiredMsg: { type: String, default: "Display Label is required" },
    duplicateNameMsg: { type: String, default: "An attribute with this name already exists" },
    duplicateSlugMsg: { type: String, default: "This name conflicts with an existing attribute." },
    fieldReservedMsg: { type: String, default: "Field name '{name}' is reserved. It already exists in {model} model." },
    editAttributeLabel: { type: String, default: "Edit Attribute" },
    saveChangesLabel: { type: String, default: "Save Changes" },

    // ModalManager
    addAssociationAttributeLabel: { type: String, default: "Add Association Attribute" },
    addAttributeLabel: { type: String, default: "Add Attribute" },

    // ConstantsManager
    constantOptionCountLabel: { type: String, default: "{name} ({count} options)" },
    optionCountSingularLabel: { type: String, default: "{count} option" },
    optionCountPluralLabel: { type: String, default: "{count} options" },

    // TemplateBuilder — attribute table, badges, view/association modals
    nameLabel: { type: String, default: "Name" },
    displayLabelHeader: { type: String, default: "Display Label" },
    htmlTypeHeader: { type: String, default: "HTML Type" },
    validatorsHeader: { type: String, default: "Validators" },
    visibilityHeader: { type: String, default: "Visibility" },
    actionsHeader: { type: String, default: "Actions" },
    dragTitle: { type: String, default: "Drag" },
    viewAttributeTitle: { type: String, default: "View attribute" },
    copyAttributeTitle: { type: String, default: "Copy attribute" },
    editAttributeTitle: { type: String, default: "Edit attribute" },
    removeAttributeTitle: { type: String, default: "Remove attribute" },
    groupUngroupedLabel: { type: String, default: "Ungrouped" },
    groupEmptyBadgeLabel: { type: String, default: "Empty" },
    groupActionsTitle: { type: String, default: "Group actions" },
    attributeCountSingular: { type: String, default: "{count} attribute" },
    attributeCountPlural: { type: String, default: "{count} attributes" },
    adminLabel: { type: String, default: "Admin" },
    memberLabel: { type: String, default: "Member" },
    publicLabel: { type: String, default: "Public" },
    visibleLabel: { type: String, default: "Visible" },
    applyValidatorsLabel: { type: String, default: "Apply validators" },
    editableLabel: { type: String, default: "Can edit" },
    optionDefaultLabel: { type: String, default: "Default" },
    optionLabelPlaceholder: { type: String, default: "Label (displayed to user)" },
    optionValuePlaceholder: { type: String, default: "Value (stored in database)" },
    removeOptionTitle: { type: String, default: "Remove option" },
    removeValidatorTitle: { type: String, default: "Remove" },
    noneLabel: { type: String, default: "None" },
    groupHeader: { type: String, default: "Group" },
    configurationHeader: { type: String, default: "Configuration" },
    descriptionHeader: { type: String, default: "Description" },
    identitySectionHeader: { type: String, default: "Identity" },
    audienceSectionHeader: { type: String, default: "Audience" },
    validationSectionHeader: { type: String, default: "Validation" },
    detailsSectionHeader: { type: String, default: "Details" },
    noDescriptionProvidedLabel: { type: String, default: "No description provided." },
    configLabelHeader: { type: String, default: "Label" },
    configValueHeader: { type: String, default: "Value" },
    configAcceptLabel: { type: String, default: "Accept: " },
    configMultipleLabel: { type: String, default: "Multiple: " },
    yesLabel: { type: String, default: "Yes" },
    noLabel: { type: String, default: "No" },
    assocWillBeCreatedLabel: { type: String, default: "Will be created on save" },
    assocMoreFormat: { type: String, default: "+{count} more" },
    editAssociationTitle: { type: String, default: "Edit association" },
    removeAssociationTitle: { type: String, default: "Remove association" },
    targetEntityHeader: { type: String, default: "Target Entity" },
    displayColumnHeader: { type: String, default: "Display" },
    bridgeEntityHeader: { type: String, default: "Bridge Entity" },
    additionalAttributesHeader: { type: String, default: "Additional Attributes" },
    groupMenuNewGroupLabel: { type: String, default: "+ New group…" },
    groupMenuEditLabel: { type: String, default: "Edit…" },
    groupMenuDeleteLabel: { type: String, default: "Delete" },

    // TypeManager
    htmlTypeLabels: { type: Object, default: { ...HTML_TYPE_LABELS } },
    htmlTypeNaLabel: { type: String, default: "N/A" },

    // ComputedManager
    computedOptions: { type: Array, default: [] },
    computedIncompleteMsg: { type: String, default: "Please complete the computed field configuration" },
    computedTypeBadge: { type: String, default: "Computed" },
    computedRelationPlaceholder: { type: String, default: "Select a relation" },
    computedAttributePlaceholder: { type: String, default: "Select an attribute" },
    computedRelationFormat: { type: String, default: "{related} ({bridge})" },
    computedEmptyHint: { type: String, default: "No related associations" },
    computedFilterNone: { type: String, default: "No filter" }
  }

  // =========================================================================
  // Lifecycle
  // =========================================================================

  connect() {
    // Initialize managers
    this.typeManager = new TypeManager(this)
    this.validatorManager = new ValidatorManager(this)
    this.templateBuilder = new TemplateBuilder(this)
    this.schemaManager = new SchemaManager(this)
    this.modalManager = new ModalManager(this)
    this.constantsManager = new ConstantsManager(this)
    this.referenceManager = new ReferenceManager(this)
    this.attributeManager = new AttributeManager(this)
    this.associationManager = new AssociationManager(this)
    this.groupManager = new GroupManager(this)
    this.dndManager   = new DndManager(this)
    this.computedManager = new ComputedManager(this)

    // Controller state
    this.attributeMode = "input"
    this.attributeIndex = this.existingAttributeCount
    this.optionIndex = 0
    this.editingRow = null
    this.optionsSourceMode = "manual"
    this.constants = []
    this.referenceTargets = null
    this.inclusionManuallyRemoved = false
    this.attributeModalContext = "entity"
    this.currentAssociationAttributes = []
    this.editingAssociationIndex = null
    this.editingAssociationAttributeIndex = null
    this.isProcessingModal = false

    // Keyboard
    this._handleKeydown = this._handleKeydown.bind(this)
    document.addEventListener("keydown", this._handleKeydown)

    // Initial sync
    this.schemaManager.syncPropertySchema()
    this.schemaManager.syncAssociationsSchema()
    this.constantsManager.loadConstants()
    this.computedManager.updateModeUI()
  }

  disconnect() {
    document.removeEventListener("keydown", this._handleKeydown)
  }

  // =========================================================================
  // Getters
  // =========================================================================

  get existingAttributeCount() {
    if (!this.hasAttributesContainerTarget) return 0
    return this.attributesContainerTarget.querySelectorAll("[data-attribute-item]").length
  }

  get isModalOpen() {
    return this.hasModalTarget && !this.modalTarget.classList.contains(CSS.hidden)
  }

  // =========================================================================
  // Keyboard
  // =========================================================================

  _handleKeydown(event) {
    if (event.key === "Escape") {
      if (this.hasViewModalTarget && !this.viewModalTarget.classList.contains(CSS.hidden)) {
        this.modalManager.closeViewModal()
      } else if (this.isModalOpen) {
        this.modalManager.closeModal()
      }
    }
  }

  // =========================================================================
  // Slug Generation (kept on controller - used in data-action)
  // =========================================================================

  generateSlug(name, separator = "_") {
    if (!name) return ""
    return name.toString().trim().normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9\s\-_]/g, "")
      .replace(/[\s\-_]+/g, separator)
      .replace(new RegExp(`^${separator}|${separator}$`, "g"), "")
  }

  updateEntityDisplayLabel() {
    if (!this.hasEntityNameTarget || !this.hasEntityDisplayLabelTarget) return
    if (this.entityDisplayLabelTarget.dataset.manuallyEdited) return

    this.entityDisplayLabelTarget.value = this.entityNameTarget.value
  }

  updateAttributeNameSlug() {
    if (!this.hasModalNameTarget) return
    const nameValue = this.modalNameTarget.value
    if (this.hasModalNameSlugTarget) {
      this.modalNameSlugTarget.value = this.generateSlug(nameValue)
    }
    if (this.hasModalDisplayLabelTarget && !this.modalDisplayLabelTarget.dataset.manuallyEdited) {
      this.modalDisplayLabelTarget.value = nameValue
    }
  }

  markDisplayLabelEdited(event) {
    event.target.dataset.manuallyEdited = "true"
  }

  // The base-model <select> submits `entity[extended_model]` natively (single
  // value). On change we refresh the reserved base-model field names so they
  // can't be redefined in the property schema.
  async extendedModelChanged(event) {
    const modelName = event.target.value

    if (!modelName) {
      this.reservedFieldNamesValue = []
      return
    }
    try {
      const response = await fetch(
        `/${this.customerIdValue}/admin/maintenance/entities/base_model_fields?model=${encodeURIComponent(modelName)}`,
        { headers: { "Accept": "application/json" } }
      )
      if (!response.ok) {
        this.reservedFieldNamesValue = []
        return
      }
      const data = await response.json()
      this.reservedFieldNamesValue = [...new Set(data.fields || [])]
    } catch (_error) {
      /* silently ignore */
    }
  }

  // =========================================================================
  // Delegated Actions -> TypeManager
  // =========================================================================

  htmlTypeChanged() { this.typeManager.htmlTypeChanged() }

  // =========================================================================
  // Delegated Actions -> ValidatorManager
  // =========================================================================

  validatorSelectChanged(event) { this.validatorManager.validatorSelectChanged(event) }
  addValidator(event) { this.validatorManager.addValidator(event) }
  addValidatorWithConfig(event) { this.validatorManager.addValidatorWithConfig(event) }
  cancelValidatorConfig(event) { this.validatorManager.cancelValidatorConfig(event) }
  handleValidatorConfigKeydown(event) { this.validatorManager.handleValidatorConfigKeydown(event) }
  removeValidator(event) { this.validatorManager.removeValidator(event) }

  // =========================================================================
  // Delegated Actions -> ModalManager
  // =========================================================================

  openModal(event) { this.modalManager.openModal(event) }
  closeModal(event) { this.modalManager.closeModal(event) }
  visibilityAudienceChanged(event) { this.modalManager.visibilityAudienceChanged(event) }
  viewAttribute(event) { this.modalManager.viewAttribute(event) }
  closeViewModal(event) { this.modalManager.closeViewModal(event) }

  // =========================================================================
  // Delegated Actions -> AttributeManager
  // =========================================================================

  addAttributeFromModal(event) { this.attributeManager.addAttributeFromModal(event) }
  copyAttribute(event) { this.attributeManager.copyAttribute(event) }
  editAttribute(event) { this.attributeManager.editAttribute(event) }
  removeAttribute(event) { this.attributeManager.removeAttribute(event) }

  // =========================================================================
  // Delegated Actions -> GroupManager
  // =========================================================================

  toggleAttributeSelection(event)      { this.groupManager.toggleAttributeSelection(event) }
  clearAttributeSelection(event)       { this.groupManager.clearAttributeSelection(event) }
  openMoveToGroup(event)               { this.groupManager.openMoveToGroup(event) }
  chooseGroup(event)                   { this.groupManager.chooseGroup(event) }
  openNewGroupModal(event)             { this.groupManager.openNewGroupModal(event) }
  openGroupMenu(event)                 { this.groupManager.openGroupMenu(event) }
  editGroup(event)                     { this.groupManager.editGroup(event) }
  deleteGroup(event)                   { this.groupManager.deleteGroup(event) }
  selectGroupIcon(event)               { this.groupManager.selectGroupIcon(event) }
  selectGroupColor(event)              { this.groupManager.selectGroupColor(event) }
  saveGroupEdit(event)                 { this.groupManager.saveGroupEdit(event) }
  closeGroupEditModal(event)           { this.groupManager.closeGroupEditModal(event) }
  closeFloater(event)                  { this.groupManager.closeFloater(event) }
  stopPropagation(event)               { event.stopPropagation() }
  colorBarClassFor(color)              { return this.groupManager?.colorBarClassFor(color) || "bg-slate-500" }

  // =========================================================================
  // Delegated Actions -> DndManager
  // =========================================================================

  dragStartRow(event)        { this.dndManager.dragStartRow(event) }
  dragOverRow(event)         { this.dndManager.dragOverRow(event) }
  dropRow(event)             { this.dndManager.dropRow(event) }
  dragEndRow(event)          { this.dndManager.dragEndRow(event) }
  dragStartGroup(event)      { this.dndManager.dragStartGroup(event) }
  dragOverGroupHeader(event) { this.dndManager.dragOverGroupHeader(event) }
  dropGroup(event)           { this.dndManager.dropGroup(event) }

  // =========================================================================
  // Delegated Actions -> ConstantsManager
  // =========================================================================

  selectManualOptions(event) { this.constantsManager.selectManualOptions(event) }
  selectConstantOptions(event) { this.constantsManager.selectConstantOptions(event) }
  constantChanged(event) { this.constantsManager.constantChanged(event) }

  // =========================================================================
  // Delegated Actions -> ReferenceManager
  // =========================================================================

  selectEntityRecordsOptions(event) { this.referenceManager.selectEntityRecordsOptions(event) }
  referenceEntityChanged() { this.referenceManager.entityChanged() }

  // =========================================================================
  // Delegated Actions -> AssociationManager
  // =========================================================================

  openAssociationModal() { this.associationManager.openAssociationModal() }
  closeAssociationModal() { this.associationManager.closeAssociationModal() }
  saveAssociation() { this.associationManager.saveAssociation() }
  addAssociationAttribute(event) { this.associationManager.addAssociationAttribute(event) }
  editAssociationAttribute(event) { this.associationManager.editAssociationAttribute(event) }
  removeAssociationAttributeFromList(event) { this.associationManager.removeAssociationAttributeFromList(event) }
  editAssociation(event) { this.associationManager.editAssociation(event) }
  removeAssociation(event) { this.associationManager.removeAssociation(event) }
  associationTargetEntityChanged() { this.associationManager.onTargetEntityChanged() }

  // =========================================================================
  // Delegated Actions -> ComputedManager
  // =========================================================================

  selectInputMode(event) { this.computedManager.selectInputMode(event) }
  selectComputedMode(event) { this.computedManager.selectComputedMode(event) }
  computedRelationChanged() { this.computedManager.relationChanged() }
  computedFunctionChanged() { this.computedManager.functionChanged() }
  computedFilterChanged() { this.computedManager.filterChanged() }

  // =========================================================================
  // Delegated Actions -> SchemaManager
  // =========================================================================

  collectAttributes() { this.schemaManager.collectAttributes() }

  // =========================================================================
  // Template Selection -> Auto-populate attributes
  // =========================================================================

  async handleTemplateSelected(event) {
    const key = event.detail?.key
    if (!key) return

    // Count existing attribute rows. In edit mode, replacing them is destructive,
    // so confirm first.
    const existingCount = this.element.querySelectorAll("[data-attribute-item]").length
    if (existingCount > 0) {
      this._pendingTemplateKey = key
      if (this.hasOverwriteCountTarget) this.overwriteCountTarget.textContent = existingCount
      if (this.hasOverwriteModalTarget) {
        this.overwriteModalTarget.classList.remove("hidden")
        return
      }
    }

    await this._applyTemplate(key)
  }

  async confirmOverwrite() {
    if (this.hasOverwriteModalTarget) this.overwriteModalTarget.classList.add("hidden")
    const key = this._pendingTemplateKey
    this._pendingTemplateKey = null
    if (key) await this._applyTemplate(key)
  }

  cancelOverwrite() {
    if (this.hasOverwriteModalTarget) this.overwriteModalTarget.classList.add("hidden")
    this._pendingTemplateKey = null
    // The picker already committed the new key to entity[referenced_template] before
    // dispatching templateSelected. Since we are NOT applying the template, tell the
    // template-selector to roll that commit back so the stored reference stays aligned
    // with the (unchanged) attribute list.
    this.dispatch("overwriteCancelled")
  }

  async _applyTemplate(key) {
    try {
      const response = await fetch(
        `/${this.customerIdValue}/admin/maintenance/entities/template_fields?key=${encodeURIComponent(key)}`,
        { headers: { "Accept": "application/json" } }
      )
      if (!response.ok) return
      const data = await response.json()

      if (this.hasPropertySchemaTarget) {
        const refInput = this.element.querySelector("input[name='entity[referenced_template]']")
        if (refInput) refInput.value = JSON.stringify(data.template)
      }

      if (data.fields?.length > 0) {
        this.populateAttributesFromTemplate(data.fields, data.groups || [])
      }
    } catch (_error) {
      /* silently ignore fetch errors */
    }
  }

  handleTemplateCleared() {
    // Clear the referenced template value
    const refInput = this.element.querySelector("input[name='entity[referenced_template]']")
    if (refInput) refInput.value = ""

    // Clear all existing attributes
    this.clearAllAttributes()
  }

  populateAttributesFromTemplate(fields, groups = []) {
    // Wipe the entire attribute list section (rows AND existing groups) first.
    this.clearAllAttributes()

    // Turn each template Section into an attribute group, mapping the section's
    // key to the generated group id so fields can be assigned to it. Groups are
    // written before any rows are appended so regrouping slots them correctly.
    const keyToGroupId = {}
    const builtGroups = groups.map((group, index) => {
      const built = this.groupManager.buildGroup({
        name: group.label,
        color: TEMPLATE_GROUP_COLORS[index % TEMPLATE_GROUP_COLORS.length]
      })
      keyToGroupId[group.key] = built.id
      return built
    })
    this.schemaManager.writeAttributeGroups(builtGroups)

    // Add each field as an attribute, assigned to its section's group.
    fields.forEach(field => {
      this.attributeManager.hideEmptyState()
      this.schemaManager.appendAttribute({
        name: field.name,
        name_slug: field.name_slug,
        display_label: field.display_label || field.name,
        html_type: field.html_type,
        description: field.description || "",
        validators: field.validators || [],
        visibility: field.visibility || { admin: true, member: true, public: true },
        group_id: keyToGroupId[field.group_key] || null,
        config: null
      })
      this.attributeIndex++
    })

    this.schemaManager.syncPropertySchema()
  }

  clearAllAttributes() {
    if (!this.hasAttributesContainerTarget) return
    const table = this.attributesContainerTarget.querySelector("table")
    if (table) table.remove()
    if (this.hasEmptyStateTarget) this.emptyStateTarget.classList.remove("hidden")
    this.attributeIndex = 0
    // Wiping the list also clears any groups (template-derived or otherwise).
    this.schemaManager.writeAttributeGroups([])
    this.schemaManager.syncPropertySchema()
  }

  // =========================================================================
  // Option management (kept on controller - simple data-action targets)
  // =========================================================================

  addOption(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }
    if (!this.hasOptionsContainerTarget) return
    const html = this.templateBuilder.buildOptionRowHtml(this.optionIndex)
    this.optionsContainerTarget.insertAdjacentHTML("beforeend", html)
    this.optionIndex++
    const newRow = this.optionsContainerTarget.lastElementChild
    const labelInput = newRow.querySelector('input[data-option-label]')
    if (labelInput) labelInput.focus()
    this.validatorManager.syncInclusionValidator()
  }

  removeOption(event) {
    event.preventDefault()
    event.stopPropagation()
    const row = event.target.closest("[data-option-item]")
    if (row) row.remove()
    this.validatorManager.syncInclusionValidator()
  }

  updateOptionValue(event) {
    const labelInput = event.target
    const optionItem = labelInput.closest("[data-option-item]")
    if (!optionItem) return
    const valueInput = optionItem.querySelector("[data-option-value]")
    if (!valueInput) return
    if (!valueInput.dataset.manuallyEdited) valueInput.value = labelInput.value
    this.validatorManager.syncInclusionValidator()
  }

  markValueAsManuallyEdited(event) {
    event.target.dataset.manuallyEdited = "true"
  }
}
