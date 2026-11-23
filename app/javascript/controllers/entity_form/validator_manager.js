import { BaseManager, CSS } from "controllers/entity_form/base_manager"
import { resolveValidatorLabel } from "constants/validator_labels"

const VALIDATOR_CONFIG_TYPES = {
  "greater_than_or_equal_to": "single_value",
  "less_than_or_equal_to": "single_value",
  "equal_to": "single_value",
  "not_equal_to": "single_value",
  "greater_than": "single_value",
  "less_than": "single_value",
  "length_minimum": "single_value",
  "length_maximum": "single_value",
  "length_in_range": "range",
  "format_custom": "pattern",
  "inclusion": "list",
  "exclusion": "list"
}

const VALIDATOR_CONFIG_LABELS = {
  "greater_than_or_equal_to": "Minimum Value (>=)",
  "less_than_or_equal_to": "Maximum Value (<=)",
  "equal_to": "Required Value (==)",
  "not_equal_to": "Forbidden Value (!=)",
  "greater_than": "Minimum Value (>)",
  "less_than": "Maximum Value (<)",
  "length_minimum": "Minimum Length",
  "length_maximum": "Maximum Length"
}

export { VALIDATOR_CONFIG_TYPES, VALIDATOR_CONFIG_LABELS }

export class ValidatorManager extends BaseManager {
  validatorSelectChanged(event) {
    this.hideValidatorConfigSection()
    this.resetValidatorConfigFields()
    const value = event.target.value
    if (!value) return
    const configType = VALIDATOR_CONFIG_TYPES[value]
    if (configType) { this.showValidatorConfigPreview(value, configType) }
  }

  addValidator(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.c.hasModalValidatorSelectTarget || !this.c.hasValidatorsContainerTarget) return
    const select = this.c.modalValidatorSelectTarget
    const value = select.value
    const label = select.options[select.selectedIndex]?.text
    if (!value) return
    if (this.isValidatorAlreadyAdded(value)) { this.highlightExistingValidator(value); return }
    const configType = VALIDATOR_CONFIG_TYPES[value]
    if (configType) { this.showValidatorConfig(value, configType) }
    else { this.appendValidatorBadge(value, label); select.selectedIndex = 0 }
  }

  showValidatorConfigPreview(validatorType, configType) {
    this.c.pendingValidator = { type: validatorType }
    this.hideAllValidatorConfigs()
    if (this.c.hasValidatorConfigSectionTarget) this.c.validatorConfigSectionTarget.classList.remove(CSS.hidden)
    this._showConfigByType(configType, validatorType)
    this.resetValidatorConfigFields()
  }

  showValidatorConfig(validatorType, configType) {
    this.c.pendingValidator = { type: validatorType }
    this.hideAllValidatorConfigs()
    if (this.c.hasValidatorConfigSectionTarget) this.c.validatorConfigSectionTarget.classList.remove(CSS.hidden)
    this._showConfigByType(configType, validatorType)
    this.focusConfigInput(configType)
  }

  _showConfigByType(configType, validatorType) {
    switch (configType) {
      case "single_value": this.showSingleValueConfig(validatorType); break
      case "range": this.showRangeConfig(); break
      case "pattern": this.showPatternConfig(); break
      case "list": this.showListConfig(validatorType); break
    }
  }

  showSingleValueConfig(validatorType) {
    if (this.c.hasValidatorSingleValueConfigTarget) this.c.validatorSingleValueConfigTarget.classList.remove(CSS.hidden)
    if (this.c.hasValidatorConfigLabelTarget) {
      this.c.validatorConfigLabelTarget.textContent = this.c.validatorConfigLabelsValue[validatorType] || this.c.configurationValueLabelValue
    }
    if (this.c.hasValidatorConfigValueTarget) this.c.validatorConfigValueTarget.focus()
  }

  showRangeConfig() {
    if (this.c.hasValidatorRangeConfigTarget) this.c.validatorRangeConfigTarget.classList.remove(CSS.hidden)
    if (this.c.hasValidatorConfigMinValueTarget) this.c.validatorConfigMinValueTarget.focus()
  }

  showPatternConfig() {
    if (this.c.hasValidatorPatternConfigTarget) this.c.validatorPatternConfigTarget.classList.remove(CSS.hidden)
    if (this.c.hasValidatorConfigPatternTarget) this.c.validatorConfigPatternTarget.focus()
  }

  showListConfig(validatorType) {
    if (this.c.hasValidatorListConfigTarget) this.c.validatorListConfigTarget.classList.remove(CSS.hidden)
    if (this.c.hasValidatorListLabelTarget) {
      this.c.validatorListLabelTarget.textContent = validatorType === "inclusion" ? this.c.allowedValuesLabelValue : this.c.forbiddenValuesLabelValue
    }
    if (this.c.hasValidatorConfigListTarget) this.c.validatorConfigListTarget.focus()
  }

  hideAllValidatorConfigs() {
    const targets = ["validatorSingleValueConfig", "validatorRangeConfig", "validatorPatternConfig", "validatorListConfig"]
    targets.forEach(name => {
      const hasName = `has${this.capitalize(name)}Target`
      if (this.c[hasName]) this.c[`${name}Target`].classList.add(CSS.hidden)
    })
  }

  hideValidatorConfigSection() {
    if (this.c.hasValidatorConfigSectionTarget) this.c.validatorConfigSectionTarget.classList.add(CSS.hidden)
    this.hideAllValidatorConfigs()
    this.resetValidatorConfigFields()
    this.c.pendingValidator = null
  }

  addValidatorWithConfig(event) {
    event?.preventDefault()
    event?.stopPropagation()
    let validatorType = null
    if (this.c.pendingValidator) { validatorType = this.c.pendingValidator.type }
    else if (this.c.hasModalValidatorSelectTarget) { validatorType = this.c.modalValidatorSelectTarget.value }
    if (!validatorType) return
    if (this.isValidatorAlreadyAdded(validatorType)) { this.highlightExistingValidator(validatorType); return }

    const configType = VALIDATOR_CONFIG_TYPES[validatorType]
    let config = null

    switch (configType) {
      case "single_value": {
        const value = this.getTargetValue("validatorConfigValue")
        if (!value) { this.showValidatorConfigError(this.c.enterValueMsgValue); return }
        config = { value: parseFloat(value) }
        break
      }
      case "range": {
        const minValue = this.getTargetValue("validatorConfigMinValue")
        const maxValue = this.getTargetValue("validatorConfigMaxValue")
        if (!minValue || !maxValue) { this.showValidatorConfigError(this.c.enterMinMaxMsgValue); return }
        const min = parseInt(minValue), max = parseInt(maxValue)
        if (min >= max) { this.showValidatorConfigError(this.c.minLessThanMaxMsgValue); return }
        config = { min, max }
        break
      }
      case "pattern": {
        const pattern = this.getTargetValue("validatorConfigPattern")
        if (!pattern) { this.showValidatorConfigError(this.c.enterPatternMsgValue); return }
        try { new RegExp(pattern); config = { pattern } }
        catch (_e) { this.showValidatorConfigError(this.c.invalidPatternMsgValue); return }
        break
      }
      case "list": {
        const listText = this.getTargetValue("validatorConfigList")
        if (!listText) { this.showValidatorConfigError(this.c.enterAtLeastOneValueMsgValue); return }
        const values = listText.split('\n').map(v => v.trim()).filter(v => v.length > 0)
        if (values.length === 0) { this.showValidatorConfigError(this.c.enterAtLeastOneValueMsgValue); return }
        config = { values }
        break
      }
    }

    const validator = { type: validatorType, config }
    const label = this.buildValidatorLabelWithConfig(validatorType, config)
    this.appendValidatorBadge(validatorType, label, validator)
    this.hideValidatorConfigSection()
    if (this.c.hasModalValidatorSelectTarget) this.c.modalValidatorSelectTarget.selectedIndex = 0
    this.c.pendingValidator = null
  }

  buildValidatorLabelWithConfig(validatorType, config) {
    const baseLabel = resolveValidatorLabel(validatorType, this.c.validatorLabelsValue)
    switch (VALIDATOR_CONFIG_TYPES[validatorType]) {
      case "single_value": return `${baseLabel} ${config.value}`
      case "range": return `${baseLabel} (${config.min}-${config.max})`
      case "pattern": return `${baseLabel}: ${config.pattern}`
      case "list": {
        const preview = config.values.length > 2
          ? `${config.values.slice(0, 2).join(', ')}... (+${config.values.length - 2})`
          : config.values.join(', ')
        return `${baseLabel}: ${preview}`
      }
      default: return baseLabel
    }
  }

  showValidatorConfigError(message) { alert(message) }

  resetValidatorConfigFields() {
    const fields = ["validatorConfigValue", "validatorConfigMinValue", "validatorConfigMaxValue", "validatorConfigPattern", "validatorConfigList"]
    fields.forEach(name => {
      const hasName = `has${this.capitalize(name)}Target`
      if (this.c[hasName]) this.c[`${name}Target`].value = ""
    })
  }

  focusConfigInput(configType) {
    setTimeout(() => {
      const map = {
        "single_value": "validatorConfigValue",
        "range": "validatorConfigMinValue",
        "pattern": "validatorConfigPattern",
        "list": "validatorConfigList"
      }
      const target = map[configType]
      if (target && this.c[`has${this.capitalize(target)}Target`]) this.c[`${target}Target`].focus()
    }, 100)
  }

  cancelValidatorConfig(event) {
    event?.preventDefault()
    event?.stopPropagation()
    this.hideValidatorConfigSection()
    if (this.c.hasModalValidatorSelectTarget) this.c.modalValidatorSelectTarget.selectedIndex = 0
  }

  handleValidatorConfigKeydown(event) {
    switch (event.key) {
      case "Enter":
        if (event.target.tagName.toLowerCase() !== "textarea") {
          event.preventDefault()
          this.addValidatorWithConfig()
        }
        break
      case "Escape":
        event.preventDefault()
        this.cancelValidatorConfig()
        break
    }
  }

  removeValidator(event) {
    event.preventDefault()
    event.stopPropagation()
    const badge = event.target.closest("[data-validator-item]")
    if (badge) {
      if (badge.dataset.validatorValue === "inclusion") {
        this.c.inclusionManuallyRemoved = true
      }
      badge.remove()
    }
  }

  syncInclusionValidator() {
    if (this.c.inclusionManuallyRemoved) return

    const htmlType = this.c.hasModalHtmlTypeTarget ? this.c.modalHtmlTypeTarget.value : ""
    if (!["select", "multi-select", "radio", "checkbox"].includes(htmlType)) return

    let values = []
    if (this.c.optionsSourceMode === "constant") {
      const constantId = this.c.hasConstantSelectTarget ? this.c.constantSelectTarget.value : ""
      const constant = this.c.constants.find(c => String(c.id) === String(constantId))
      if (constant?.options) {
        values = constant.options.map(o => (typeof o === "string" ? o : o.value || o.label)).filter(v => v)
      }
    } else if (this.c.optionsSourceMode !== "entity_entries") {
      const options = this.c.typeManager.getSelectedOptions()
      values = options.map(o => o.value || o.label).filter(v => v)
    }

    // Remove existing inclusion badge (we'll re-add with updated values)
    const existing = this.c.hasValidatorsContainerTarget
      ? this.c.validatorsContainerTarget.querySelector('[data-validator-value="inclusion"]')
      : null
    if (existing) existing.remove()

    if (values.length === 0) return

    const config = { values }
    const validator = { type: "inclusion", config }
    const label = this.buildValidatorLabelWithConfig("inclusion", config)
    this.appendValidatorBadge("inclusion", label, validator)
  }

  isValidatorAlreadyAdded(value) {
    return !!this.c.validatorsContainerTarget.querySelector(`[data-validator-value="${value}"]`)
  }

  highlightExistingValidator(value) {
    const badge = this.c.validatorsContainerTarget.querySelector(`[data-validator-value="${value}"]`)
    if (!badge) return
    badge.classList.add(...CSS.highlightRing)
    setTimeout(() => badge.classList.remove(...CSS.highlightRing), 800)
  }

  appendValidatorBadge(value, label, validatorObject = null) {
    const validator = validatorObject || { type: value }
    if (validator && typeof validator === "object") delete validator.visibility
    const html = this.c.templateBuilder.buildValidatorBadgeHtml(value, label, validator)
    this.c.validatorsContainerTarget.insertAdjacentHTML("beforeend", html)
  }

  getSelectedValidators() {
    if (!this.c.hasValidatorsContainerTarget) return []
    return Array.from(
      this.c.validatorsContainerTarget.querySelectorAll("[data-validator-item]")
    ).map(item => {
      if (item.dataset.validatorObject) {
        try {
          const validator = JSON.parse(item.dataset.validatorObject)
          if (validator && typeof validator === "object") delete validator.visibility
          return validator
        }
        catch (_e) { return { type: item.dataset.validatorValue } }
      }
      return { type: item.dataset.validatorValue }
    }).filter(validator => validator?.type)
  }

  getSelectedOptions() {
    return this.c.typeManager.getSelectedOptions()
  }

  // ---------------------------------------------------------------------------
  // HTML-type-aware validator filtering
  // ---------------------------------------------------------------------------

  filterValidatorsByHtmlType(htmlType) {
    if (!this.c.hasModalValidatorSelectTarget) return

    const mapping = this.c.htmlTypeValidatorsValue || {}
    const allowed = mapping[htmlType] || null
    const select = this.c.modalValidatorSelectTarget

    // Show/hide individual options
    const options = select.querySelectorAll("option[data-validator-key]")
    options.forEach(opt => {
      const key = opt.dataset.validatorKey
      const visible = allowed ? allowed.includes(key) : true
      opt.hidden = !visible
      opt.disabled = !visible
    })

    // Show/hide optgroups when all their options are hidden
    select.querySelectorAll("optgroup").forEach(group => {
      const groupOptions = group.querySelectorAll("option[data-validator-key]")
      const anyVisible = Array.from(groupOptions).some(opt => !opt.hidden)
      group.hidden = !anyVisible
    })

    // Remove already-added validators that are no longer compatible
    if (allowed && this.c.hasValidatorsContainerTarget) {
      const badges = this.c.validatorsContainerTarget.querySelectorAll("[data-validator-item]")
      badges.forEach(badge => {
        const validatorKey = badge.dataset.validatorValue
        if (!allowed.includes(validatorKey)) badge.remove()
      })
    }

    // Reset selection to the first visible option
    const firstVisible = Array.from(options).find(opt => !opt.hidden)
    if (firstVisible) {
      select.value = firstVisible.value
    }

    // Hide config section since selection was reset
    this.hideValidatorConfigSection()
  }
}
