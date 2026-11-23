import { BaseManager, CSS } from "controllers/entity_form/base_manager"

export const ENTITY_ENTRIES = "entity_entries"
const REFERENCE_HTML_TYPES = ["select", "radio"]

// "Use Entity Records": a select or radio attribute whose choices are another
// entity's records. The saved config is { options_source, entity_id,
// label_field }. An entry stores the record id; the display field only labels
// the choices, so only attributes the server marks `labelable` are offered.
export class ReferenceManager extends BaseManager {
  async loadTargets() {
    if (!this.c.referenceTargets && this.c.hasCustomerIdValue) {
      try {
        const response = await fetch(`/${this.customerIdValue}/admin/maintenance/entities.json`, {
          headers: { Accept: "application/json" }
        })
        if (response.ok) this.c.referenceTargets = await response.json()
      } catch (_error) {
        // The selects keep their placeholders; the next open retries.
      }
      this.populateEntitySelect()
    }
    return this.c.referenceTargets || []
  }

  populateEntitySelect() {
    if (!this.c.hasReferenceEntitySelectTarget) return
    const select = this.c.referenceEntitySelectTarget
    while (select.options.length > 1) select.remove(1)
    ;(this.c.referenceTargets || []).forEach(entity => {
      const option = document.createElement("option")
      option.value = String(entity.id)
      option.textContent = entity.name
      select.appendChild(option)
    })
  }

  populateLabelFieldSelect(entity) {
    if (!this.c.hasReferenceLabelFieldSelectTarget) return
    const select = this.c.referenceLabelFieldSelectTarget
    while (select.options.length > 1) select.remove(1)
    const schema = entity?.property_schema || []
    schema.filter(attribute => attribute.labelable).forEach(attribute => {
      const option = document.createElement("option")
      option.value = attribute.name_slug
      option.textContent = attribute.name
      select.appendChild(option)
    })
  }

  selectedTarget() {
    const id = this.getTargetValue("referenceEntitySelect")
    return (this.c.referenceTargets || []).find(entity => String(entity.id) === id) || null
  }

  entityChanged() {
    this.populateLabelFieldSelect(this.selectedTarget())
    this.syncOwnerVisibility()
  }

  // The Owner switch is shown only for a person target on a regular
  // (non-bridge, non-person) entity.
  personEntityIds() {
    const value = this.c.personEntityIdsValue
    return Array.isArray(value) ? value.map(String) : []
  }

  ownerAvailable() {
    if (this.c.attributeModalContext === "association") return false
    if (this.c.optionsSourceMode !== ENTITY_ENTRIES) return false
    const id = this.getTargetValue("referenceEntitySelect")
    if (!id) return false
    return this.personEntityIds().includes(String(id))
  }

  syncOwnerVisibility({ reset = true } = {}) {
    if (!this.c.hasOwnerSectionTarget) return
    const show = this.ownerAvailable()
    this.c.ownerSectionTarget.classList.toggle(CSS.hidden, !show)
    if (reset && !show && this.c.hasModalOwnerTarget) this.c.modalOwnerTarget.checked = false
  }

  selectEntityRecordsOptions(event) {
    event.preventDefault()
    this.c.optionsSourceMode = ENTITY_ENTRIES
    this.c.constantsManager.updateOptionsSourceUI()
    this.c.validatorManager.syncInclusionValidator()
    this.syncOwnerVisibility()
    return this.loadTargets()
  }

  // Offered for select and radio only; any other type drops back to manual entry.
  syncAvailability(htmlType) {
    const available = REFERENCE_HTML_TYPES.includes(htmlType)
    if (this.c.hasEntityRecordsOptionsBtnTarget) {
      this.c.entityRecordsOptionsBtnTarget.classList.toggle(CSS.hidden, !available)
    }
    if (!available && this.c.optionsSourceMode === ENTITY_ENTRIES) {
      this.c.optionsSourceMode = "manual"
      this.c.constantsManager.updateOptionsSourceUI()
    }
    this.syncOwnerVisibility()
  }

  getConfig() {
    const entityId = this.getTargetValue("referenceEntitySelect")
    const labelField = this.getTargetValue("referenceLabelFieldSelect")
    if (!entityId || !labelField) return null
    return { options_source: ENTITY_ENTRIES, entity_id: entityId, label_field: labelField }
  }

  // The first missing choice as { target, message }, or null when complete.
  validate() {
    if (!this.getTargetValue("referenceEntitySelect")) {
      return { target: "referenceEntitySelect", message: this.c.selectTargetEntityMsgValue }
    }
    if (!this.getTargetValue("referenceLabelFieldSelect")) {
      return { target: "referenceLabelFieldSelect", message: this.c.selectDisplayFieldMsgValue }
    }
    return null
  }

  async applyConfig(config) {
    this.c.optionsSourceMode = ENTITY_ENTRIES
    this.c.constantsManager.updateOptionsSourceUI()
    await this.loadTargets()
    if (this.c.hasReferenceEntitySelectTarget) {
      this.c.referenceEntitySelectTarget.value = String(config.entity_id ?? "")
    }
    this.populateLabelFieldSelect(this.selectedTarget())
    if (this.c.hasReferenceLabelFieldSelectTarget) {
      this.c.referenceLabelFieldSelectTarget.value = config.label_field || ""
    }
    this.syncOwnerVisibility({ reset: false })
  }

  reset() {
    if (this.c.hasReferenceEntitySelectTarget) this.c.referenceEntitySelectTarget.selectedIndex = 0
    this.populateLabelFieldSelect(null)
    this.syncOwnerVisibility()
  }
}
