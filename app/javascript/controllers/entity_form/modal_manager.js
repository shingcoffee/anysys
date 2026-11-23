import { BaseManager, CSS } from "controllers/entity_form/base_manager"
import { resolveValidatorLabel } from "constants/validator_labels"
import { CONFIG_TYPE_MAP } from "controllers/entity_form/type_manager"

export class ModalManager extends BaseManager {
  openModal(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.c.hasModalTarget) return
    this.c.attributeModalContext = "entity"
    this.c.inclusionManuallyRemoved = false
    this.c.modalTarget.classList.remove(CSS.hidden)
    document.body.style.overflow = CSS.hidden
    this.c.optionsSourceMode = "manual"
    this.c.constantsManager.updateOptionsSourceUI()
    if (this.c.referenceManager) this.c.referenceManager.reset()
    this.resetModalSectionNav()
    this.focusModalNameField()
    if (this.c.computedManager) this.c.computedManager.updateModeUI()
  }

  openModalForAssociationAttribute(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }
    if (!this.c.hasModalTarget) return
    this.c.attributeModalContext = "association"
    this.c.editingAssociationAttributeIndex = null
    if (this.c.hasModalTitleTarget) this.c.modalTitleTarget.textContent = this.c.addAssociationAttributeLabelValue
    if (this.c.hasModalSubmitBtnTarget) this.c.modalSubmitBtnTarget.textContent = this.c.addAttributeLabelValue
    this.c.modalTarget.classList.remove(CSS.hidden)
    document.body.style.overflow = CSS.hidden
    this.c.optionsSourceMode = "manual"
    this.c.constantsManager.updateOptionsSourceUI()
    if (this.c.referenceManager) this.c.referenceManager.reset()
    this.resetModalSectionNav()
    this.focusModalNameField()
    if (this.c.computedManager) this.c.computedManager.updateModeUI()
  }

  closeModal(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }
    if (!this.c.hasModalTarget) return
    if (this.c.modalTarget.classList.contains(CSS.hidden)) return
    this.c.modalTarget.classList.add(CSS.hidden)
    document.body.style.overflow = ""
    this.resetModalFields()
    this.c.attributeModalContext = "entity"
    this.c.editingAssociationAttributeIndex = null
    if (this.c.hasModalTitleTarget) this.c.modalTitleTarget.textContent = this.c.addAttributeLabelValue
    if (this.c.hasModalSubmitBtnTarget) this.c.modalSubmitBtnTarget.textContent = this.c.addAttributeLabelValue
  }

  focusModalNameField() {
    if (this.c.hasModalNameTarget) setTimeout(() => this.c.modalNameTarget.focus(), 100)
  }

  resetModalSectionNav() {
    if (!this.c.hasModalTarget) return
    this.c.modalTarget.querySelector("[data-tabs-target='tab'][data-tabs-id='definition']")?.click()
  }

  resetModalFields() {
    if (this.c.hasModalNameTarget) this.c.modalNameTarget.value = ""
    if (this.c.hasModalNameSlugTarget) this.c.modalNameSlugTarget.value = ""
    if (this.c.hasModalDisplayLabelTarget) {
      this.c.modalDisplayLabelTarget.value = ""
      delete this.c.modalDisplayLabelTarget.dataset.manuallyEdited
    }
    this.resetModalVisibility(true)
    this.resetModalEditable(true)
    this.resetModalValidatorApply(true)
    this.syncValidatorApplyWithVisibility()
    if (this.c.hasModalHtmlTypeTarget) this.c.modalHtmlTypeTarget.selectedIndex = 0
    if (this.c.hasModalDescriptionTarget) this.c.modalDescriptionTarget.value = ""
    if (this.c.hasModalValidatorSelectTarget) this.c.modalValidatorSelectTarget.selectedIndex = 0
    if (this.c.hasValidatorsContainerTarget) this.c.validatorsContainerTarget.innerHTML = ""
    this.c.validatorManager.hideValidatorConfigSection()
    if (this.c.hasOptionsContainerTarget) this.c.optionsContainerTarget.innerHTML = ""
    this.c.optionIndex = 0
    this.c.optionsSourceMode = "manual"
    if (this.c.referenceManager) this.c.referenceManager.reset()
    if (this.c.hasConstantSelectTarget) this.c.constantSelectTarget.selectedIndex = 0
    this.c.constantsManager.hideConstantPreview()
    if (this.c.hasConfigAcceptTarget) this.c.configAcceptTarget.value = ""
    if (this.c.hasConfigMultipleTarget) this.c.configMultipleTarget.checked = false
    this.applyOwner(false)
    this.c.typeManager.hideConfigSection()
    this.c.editingRow = null
    if (this.c.hasModalTitleTarget) this.c.modalTitleTarget.textContent = this.c.addAttributeLabelValue
    if (this.c.hasModalSubmitBtnTarget) this.c.modalSubmitBtnTarget.textContent = this.c.addAttributeLabelValue
    if (this.c.computedManager) this.c.computedManager.reset()
  }

  prefillModalWithAttribute({ name, name_slug, display_label, html_type, description, validators, visibility, validator_apply, editable, config, type, owner }) {
    if (this.c.hasModalNameTarget) this.c.modalNameTarget.value = name || ""
    if (this.c.hasModalNameSlugTarget) this.c.modalNameSlugTarget.value = name_slug || ""
    if (this.c.hasModalDisplayLabelTarget) {
      this.c.modalDisplayLabelTarget.value = display_label || name || ""
      this.c.modalDisplayLabelTarget.dataset.manuallyEdited = "true"
    }
    this.applyVisibility(visibility)
    this.applyEditable(editable)
    this.applyValidatorApply(validator_apply)
    this.syncValidatorApplyWithVisibility()
    if (this.c.hasModalHtmlTypeTarget) this.c.modalHtmlTypeTarget.value = html_type || "text"
    if (this.c.hasModalDescriptionTarget) this.c.modalDescriptionTarget.value = description || ""

    if (this.c.hasValidatorsContainerTarget) {
      this.c.validatorsContainerTarget.innerHTML = ""
      if (validators?.length) {
        validators.forEach(validator => {
          if (typeof validator === 'string') {
            this.c.validatorManager.appendValidatorBadge(validator, resolveValidatorLabel(validator, this.c.validatorLabelsValue))
          } else if (validator.type) {
            const label = validator.config
              ? this.c.validatorManager.buildValidatorLabelWithConfig(validator.type, validator.config)
              : resolveValidatorLabel(validator.type, this.c.validatorLabelsValue)
            this.c.validatorManager.appendValidatorBadge(validator.type, label, validator)
          }
        })
      }
    }

    this.c.typeManager.hideConfigSection()
    if (this.c.hasOptionsContainerTarget) this.c.optionsContainerTarget.innerHTML = ""
    this.c.optionIndex = 0
    if (this.c.hasConfigAcceptTarget) this.c.configAcceptTarget.value = ""
    if (this.c.hasConfigMultipleTarget) this.c.configMultipleTarget.checked = false

    if (config) {
      const configType = CONFIG_TYPE_MAP[html_type]
      if (configType) {
        if (this.c.hasOptionsSectionTarget) this.c.optionsSectionTarget.classList.remove(CSS.hidden)
        this.c.typeManager.hideAllConfigContainers()
        const targetName = `has${this.capitalize(configType)}ConfigTarget`
        if (this.c[targetName]) this.c[`${configType}ConfigTarget`].classList.remove(CSS.hidden)

        if (configType === "selection" && config.options_source === "entity_entries") {
          this.c.referenceManager.applyConfig(config)
        } else if (configType === "selection" && config.options?.length) {
          if (config.source === "constant" && config.constant_id) {
            this.c.optionsSourceMode = "constant"
            this.c.constantsManager.updateOptionsSourceUI()
            if (this.c.hasConstantSelectTarget) {
              this.c.constantSelectTarget.value = config.constant_id
              const event = new Event("change")
              this.c.constantSelectTarget.dispatchEvent(event)
            }
          } else {
            this.c.optionsSourceMode = "manual"
            this.c.constantsManager.updateOptionsSourceUI()
            config.options.forEach(opt => {
              const html = this.c.templateBuilder.buildOptionRowHtml(this.c.optionIndex)
              this.c.optionsContainerTarget.insertAdjacentHTML("beforeend", html)
              const newRow = this.c.optionsContainerTarget.lastElementChild
              const labelEl = newRow.querySelector("[data-option-label]")
              const valueEl = newRow.querySelector("[data-option-value]")
              const defaultEl = newRow.querySelector("[data-option-default]")
              if (labelEl) labelEl.value = opt.label || ""
              if (valueEl) valueEl.value = opt.value || ""
              if (defaultEl) defaultEl.checked = opt.default || false
              this.c.optionIndex++
            })
          }
        } else if (configType === "file") {
          if (this.c.hasConfigAcceptTarget) this.c.configAcceptTarget.value = config.accept || ""
          if (this.c.hasConfigMultipleTarget) this.c.configMultipleTarget.checked = config.multiple || false
        }
      }
    }

    if (type === "Computed" && this.c.computedManager) {
      this.c.computedManager.selectComputedMode()
      this.c.computedManager.applyComputedConfig(config)
    } else if (this.c.computedManager) {
      this.c.computedManager.selectInputMode()
    }

    this.applyOwner(owner)
  }

  applyOwner(owner) {
    if (this.c.hasModalOwnerTarget) this.c.modalOwnerTarget.checked = owner === true
  }

  resetModalVisibility(checked) {
    if (this.c.hasModalVisibilityAdminTarget) this.c.modalVisibilityAdminTarget.checked = checked
    if (this.c.hasModalVisibilityMemberTarget) this.c.modalVisibilityMemberTarget.checked = checked
    if (this.c.hasModalVisibilityPublicTarget) this.c.modalVisibilityPublicTarget.checked = checked
  }

  resetModalEditable(checked) {
    this._audienceTargets().forEach(({ edit }) => {
      if (!edit) return
      edit.checked = checked
      edit.disabled = false
    })
  }

  resetModalValidatorApply(checked) {
    if (this.c.hasModalValidatorApplyAdminTarget) this.c.modalValidatorApplyAdminTarget.checked = checked
    if (this.c.hasModalValidatorApplyMemberTarget) this.c.modalValidatorApplyMemberTarget.checked = checked
    if (this.c.hasModalValidatorApplyPublicTarget) this.c.modalValidatorApplyPublicTarget.checked = checked
  }

  applyVisibility(visibility) {
    const v = visibility && typeof visibility === "object"
      ? visibility
      : { admin: true, member: true, public: true }
    if (this.c.hasModalVisibilityAdminTarget) this.c.modalVisibilityAdminTarget.checked = v.admin !== false
    if (this.c.hasModalVisibilityMemberTarget) this.c.modalVisibilityMemberTarget.checked = v.member !== false
    if (this.c.hasModalVisibilityPublicTarget) this.c.modalVisibilityPublicTarget.checked = v.public !== false
  }

  applyEditable(editable) {
    const e = editable && typeof editable === "object"
      ? editable
      : { admin: true, member: true, public: true }
    const keys = ["admin", "member", "public"]
    this._audienceTargets().forEach(({ edit }, i) => {
      if (edit) edit.checked = e[keys[i]] !== false
    })
  }

  applyValidatorApply(validatorApply) {
    const v = validatorApply && typeof validatorApply === "object"
      ? validatorApply
      : { admin: true, member: true, public: true }
    if (this.c.hasModalValidatorApplyAdminTarget) this.c.modalValidatorApplyAdminTarget.checked = v.admin !== false
    if (this.c.hasModalValidatorApplyMemberTarget) this.c.modalValidatorApplyMemberTarget.checked = v.member !== false
    if (this.c.hasModalValidatorApplyPublicTarget) this.c.modalValidatorApplyPublicTarget.checked = v.public !== false
  }

  _audienceTargets() {
    return ["Admin", "Member", "Public"].map((suffix) => ({
      vis: this.hasTarget(`modalVisibility${suffix}`) ? this.c[`modalVisibility${suffix}Target`] : null,
      edit: this.hasTarget(`modalEditable${suffix}`) ? this.c[`modalEditable${suffix}Target`] : null,
      apply: this.hasTarget(`modalValidatorApply${suffix}`) ? this.c[`modalValidatorApply${suffix}Target`] : null
    }))
  }

  syncValidatorApplyWithVisibility() {
    this._audienceTargets().forEach(({ vis, edit, apply }) => this._syncAudienceAccess(vis, edit, apply))
  }

  _syncAudienceAccess(visEl, editEl, applyEl) {
    if (visEl && editEl) {
      if (!visEl.checked) {
        editEl.checked = false
        editEl.disabled = true
      } else {
        editEl.disabled = false
      }
    }
    if (!applyEl) return
    const visOn = !visEl || visEl.checked
    const editOn = !editEl || editEl.checked
    if (!visOn || !editOn) {
      applyEl.checked = false
      applyEl.disabled = true
    } else {
      applyEl.disabled = false
    }
  }

  visibilityAudienceChanged(event) {
    const target = event?.target
    if (target?.checked) {
      this._audienceTargets().forEach(({ vis, edit, apply }) => {
        if (vis && target === vis) {
          if (edit) edit.checked = true
          if (apply) apply.checked = true
        } else if (edit && target === edit) {
          if (apply) apply.checked = true
        }
      })
    }
    this.syncValidatorApplyWithVisibility()
  }

  // View Modal
  viewAttribute(event) {
    event.preventDefault()
    event.stopPropagation()
    const row = event.target.closest("[data-attribute-item]")
    if (!row) return
    const attribute = this.c.schemaManager.extractAttributeFromRow(row)
    if (!attribute) return
    if (this.c.hasViewModalContentTarget) {
      this.c.viewModalContentTarget.innerHTML = this.c.templateBuilder.buildAttributeViewHtml(attribute)
    }
    if (this.c.hasViewModalTitleTarget) {
      this.c.viewModalTitleTarget.textContent = attribute.name || ""
    }
    if (this.c.hasViewModalSubtitleTarget) {
      const subtitle = attribute.display_label && attribute.display_label !== attribute.name
        ? attribute.display_label
        : (attribute.name_slug || "")
      this.c.viewModalSubtitleTarget.textContent = subtitle
    }
    if (this.c.hasViewModalTarget) {
      this.c.viewModalTarget.classList.remove(CSS.hidden)
      document.body.style.overflow = CSS.hidden
    }
  }

  closeViewModal(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }
    if (this.c.hasViewModalTarget) {
      this.c.viewModalTarget.classList.add(CSS.hidden)
      document.body.style.overflow = ""
    }
    if (this.c.hasViewModalContentTarget) this.c.viewModalContentTarget.innerHTML = ""
    if (this.c.hasViewModalTitleTarget) this.c.viewModalTitleTarget.textContent = ""
    if (this.c.hasViewModalSubtitleTarget) this.c.viewModalSubtitleTarget.textContent = ""
  }
}
