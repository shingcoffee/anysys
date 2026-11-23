import { OPTIONS_FIELD_TYPES, TYPE_SETTINGS_MAP, DATE_TIME_INPUT_TYPES } from "controllers/page_builder/property_manager"

/**
 * TypeSettingsMixin provides type-specific settings population and toggle logic.
 * Apply to a class using Object.assign(YourClass.prototype, TypeSettingsMixin)
 */
export const TypeSettingsMixin = {
  populateTypeSettings(field) {
    const isLayout = field.property_type === "layout"
    const fieldType = field.field_type || ""
    const settings = TYPE_SETTINGS_MAP[fieldType]

    // Hide entire section if layout or no type settings defined
    if (this.c.hasTypeSettingsSectionTarget) {
      const showSection = !isLayout && settings && settings.length > 0
      this.c.typeSettingsSectionTarget.classList.toggle("hidden", !showSection)
      if (!showSection) return
    } else {
      return
    }

    // Hide ALL type-setting divs first
    this.c.typeSettingsSectionTarget.querySelectorAll("[data-type-setting]").forEach(div => {
      div.classList.add("hidden")
    })

    // Show only the relevant ones for this field type
    settings.forEach(targetName => {
      const div = this.c.typeSettingsSectionTarget.querySelector(`[data-type-setting="${targetName}"]`)
      if (div) div.classList.remove("hidden")
    })

    // Populate values from field object
    this._populateTypeSettingValue("fieldMaxLength", field.max_length)
    this._populateTypeSettingValue("fieldMinLength", field.min_length)
    this._populateTypeSettingValue("fieldPattern", field.pattern)
    this._populateTypeSettingValue("fieldAutocomplete", field.autocomplete)
    this._populateTypeSettingValue("fieldRows", field.rows)
    this._populateTypeSettingValue("fieldResize", field.resize)
    this._populateTypeSettingCheckbox("fieldShowToggle", field.show_toggle)
    this._populateTypeSettingCheckbox("fieldAllowBlank", field.allow_blank)
    this._populateTypeSettingCheckbox("fieldSearchable", field.searchable)
    this._populateTypeSettingCheckbox("fieldInlineLayout", field.inline_layout)
    this._populateTypeSettingValue("fieldMinSelections", field.min_selections)
    this._populateTypeSettingValue("fieldMaxSelections", field.max_selections)
    this._populateTypeSettingValue("fieldOnLabel", field.on_label)
    this._populateTypeSettingValue("fieldOffLabel", field.off_label)
    this._populateTypeSettingValue("fieldMinValue", field.min_value)
    this._populateTypeSettingValue("fieldMaxValue", field.max_value)
    this._populateTypeSettingValue("fieldStep", field.step)
    this._populateTypeSettingCheckbox("fieldShowValue", field.show_value)
    this._populateTypeSettingValue("fieldCurrencySymbol", field.currency_symbol)
    this._populateTypeSettingValue("fieldDecimalPlaces", field.decimal_places)
    this._populateTypeSettingValue("fieldMaxRating", field.max_rating)
    this._populateTypeSettingCheckbox("fieldAllowHalf", field.allow_half)
    this._populateTypeSettingValue("fieldTimeStep", field.time_step)
    this._populateTypeSettingCheckbox("fieldAllowMultiple", field.allow_multiple)
    this._populateTypeSettingValue("fieldPhonePattern", field.phone_pattern)
    this._populateTypeSettingValue("fieldCanvasHeight", field.canvas_height)
    this._populateTypeSettingValue("fieldPenColor", field.pen_color || "#000000")
    this._populateTypeSettingValue("fieldPenWidth", field.pen_width)
    this._populateTypeSettingValue("fieldAcceptTypes", field.accept_types)
    this._populateTypeSettingValue("fieldMaxFileSize", field.max_file_size)
    this._populateTypeSettingValue("fieldColorFormat", field.color_format)

    // For date/time fields, dynamically set input type on min/max constraint fields
    const inputType = DATE_TIME_INPUT_TYPES[fieldType]
    if (inputType) {
      if (this.c.hasFieldMinConstraintTarget) {
        this.c.fieldMinConstraintTarget.type = inputType
        this.c.fieldMinConstraintTarget.value = field.min_constraint || ""
      }
      if (this.c.hasFieldMaxConstraintTarget) {
        this.c.fieldMaxConstraintTarget.type = inputType
        this.c.fieldMaxConstraintTarget.value = field.max_constraint || ""
      }
    }

    // For rich-text toolbar, populate checkbox states
    if (fieldType === "rich-text" && this.c.hasFieldToolbarTarget) {
      const toolbarChecks = this.c.fieldToolbarTarget.querySelectorAll("input[type='checkbox']")
      toolbarChecks.forEach(cb => {
        const prop = cb.dataset.property
        if (prop && field[prop] !== undefined) {
          cb.checked = field[prop]
        }
      })
    }
  },

  _populateTypeSettingValue(targetName, value) {
    const hasTarget = `has${targetName.charAt(0).toUpperCase()}${targetName.slice(1)}Target`
    const target = `${targetName.charAt(0).toLowerCase()}${targetName.slice(1)}Target`
    if (this.c[hasTarget]) {
      this.c[target].value = value ?? ""
    }
  },

  _populateTypeSettingCheckbox(targetName, value) {
    const hasTarget = `has${targetName.charAt(0).toUpperCase()}${targetName.slice(1)}Target`
    const target = `${targetName.charAt(0).toLowerCase()}${targetName.slice(1)}Target`
    if (this.c[hasTarget]) {
      this.c[target].checked = value || false
    }
  },

  toggleOptionsEditor(field) {
    const optionsSection = this.c.element.querySelector("[data-field-types]")
    if (!optionsSection) return

    const fieldType = field.field_type || ""
    if (OPTIONS_FIELD_TYPES.includes(fieldType) || OPTIONS_FIELD_TYPES.includes(field.property_type)) {
      optionsSection.classList.remove("hidden")
    } else {
      optionsSection.classList.add("hidden")
    }
  }
}
