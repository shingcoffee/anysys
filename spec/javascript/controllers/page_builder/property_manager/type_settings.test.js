import { describe, it, expect, vi } from "vitest"
import { PropertyManager } from "controllers/page_builder/property_manager"
import { makeCtrl, field } from "../../../support/page_builder.js"

function tsCtrl() {
  const ctrl = makeCtrl()
  ctrl.element = document.createElement("div")
  return ctrl
}
const newPM = () => {
  const ctrl = tsCtrl()
  return { pm: new PropertyManager(ctrl), ctrl }
}

// Build a type-settings section holding a div per named setting.
function withSection(ctrl, names) {
  const section = document.createElement("div")
  names.forEach((n) => {
    const div = document.createElement("div")
    div.setAttribute("data-type-setting", n)
    section.appendChild(div)
  })
  ctrl.hasTypeSettingsSectionTarget = true
  ctrl.typeSettingsSectionTarget = section
  return section
}
const shown = (section, name) =>
  !section.querySelector(`[data-type-setting="${name}"]`).classList.contains("hidden")

describe("TypeSettingsMixin.populateTypeSettings", () => {
  it("shows only the settings mapped to the field type", () => {
    const { pm, ctrl } = newPM()
    const section = withSection(ctrl, ["fieldMaxLength", "fieldMinLength", "fieldPattern", "fieldAutocomplete", "fieldRows"])
    pm.populateTypeSettings(field({ id: "f1", field_type: "text", property_type: "string" }))
    expect(ctrl.typeSettingsSectionTarget.classList.contains("hidden")).toBe(false)
    expect(shown(section, "fieldMaxLength")).toBe(true)
    expect(shown(section, "fieldPattern")).toBe(true)
    expect(shown(section, "fieldRows")).toBe(false) // belongs to textarea, not text
  })

  it("hides the whole section for a layout field", () => {
    const { pm, ctrl } = newPM()
    withSection(ctrl, ["fieldMaxLength"])
    pm.populateTypeSettings({ id: "f1", property_type: "layout", field_type: "heading" })
    expect(ctrl.typeSettingsSectionTarget.classList.contains("hidden")).toBe(true)
  })

  it("hides the section for a type with no settings (e.g. search)", () => {
    const { pm, ctrl } = newPM()
    withSection(ctrl, ["fieldMaxLength"])
    pm.populateTypeSettings(field({ id: "f1", field_type: "search", property_type: "string" }))
    expect(ctrl.typeSettingsSectionTarget.classList.contains("hidden")).toBe(true)
  })

  it("populates value + checkbox targets from the field", () => {
    const { pm, ctrl } = newPM()
    withSection(ctrl, ["fieldMaxLength", "fieldMinLength", "fieldPattern", "fieldAutocomplete"])
    ctrl.hasFieldMaxLengthTarget = true
    ctrl.fieldMaxLengthTarget = document.createElement("input")
    ctrl.hasFieldShowToggleTarget = true
    ctrl.fieldShowToggleTarget = Object.assign(document.createElement("input"), { type: "checkbox" })
    pm.populateTypeSettings(field({ id: "f1", field_type: "text", property_type: "string", max_length: 25, show_toggle: true }))
    expect(ctrl.fieldMaxLengthTarget.value).toBe("25")
  })

  it("sets the input type + value on date/time constraint targets", () => {
    const { pm, ctrl } = newPM()
    withSection(ctrl, ["fieldMinMaxConstraint"])
    ctrl.hasFieldMinConstraintTarget = true
    ctrl.fieldMinConstraintTarget = document.createElement("input")
    ctrl.hasFieldMaxConstraintTarget = true
    ctrl.fieldMaxConstraintTarget = document.createElement("input")
    pm.populateTypeSettings(field({ id: "f1", field_type: "date", property_type: "date", min_constraint: "2026-01-01" }))
    expect(ctrl.fieldMinConstraintTarget.type).toBe("date")
    expect(ctrl.fieldMinConstraintTarget.value).toBe("2026-01-01")
  })

  it("returns early when there is no type-settings section target", () => {
    const { pm } = newPM()
    expect(() => pm.populateTypeSettings(field({ id: "f1", field_type: "text" }))).not.toThrow()
  })

  it("clears the min-constraint value when the field has none", () => {
    const { pm, ctrl } = newPM()
    withSection(ctrl, ["fieldMinMaxConstraint"])
    ctrl.hasFieldMinConstraintTarget = true
    ctrl.fieldMinConstraintTarget = document.createElement("input")
    pm.populateTypeSettings(field({ id: "f1", field_type: "date", property_type: "date" }))
    expect(ctrl.fieldMinConstraintTarget.value).toBe("")
  })

  it("populates rich-text toolbar checkboxes matching field properties", () => {
    const { pm, ctrl } = newPM()
    withSection(ctrl, ["fieldToolbar", "fieldMaxLength"])
    ctrl.hasFieldToolbarTarget = true
    ctrl.fieldToolbarTarget = document.createElement("div")
    const bold = Object.assign(document.createElement("input"), { type: "checkbox" })
    bold.dataset.property = "toolbar_bold"
    const noProp = Object.assign(document.createElement("input"), { type: "checkbox" })
    const unset = Object.assign(document.createElement("input"), { type: "checkbox" })
    unset.dataset.property = "toolbar_unset" // absent from field → left untouched
    ctrl.fieldToolbarTarget.append(bold, noProp, unset)
    pm.populateTypeSettings(field({ id: "f1", field_type: "rich-text", property_type: "string", toolbar_bold: true }))
    expect(bold.checked).toBe(true)
    expect(unset.checked).toBe(false)
  })

  it("skips the rich-text toolbar block without a toolbar target", () => {
    const { pm, ctrl } = newPM()
    withSection(ctrl, ["fieldMaxLength"])
    pm.populateTypeSettings(field({ id: "f1", field_type: "rich-text", property_type: "string" }))
    expect(ctrl.hasFieldToolbarTarget).toBeFalsy()
  })
})

describe("TypeSettingsMixin._populateTypeSettingValue / _populateTypeSettingCheckbox", () => {
  it("writes a value when the corresponding target exists", () => {
    const { pm, ctrl } = newPM()
    ctrl.hasFieldRowsTarget = true
    ctrl.fieldRowsTarget = document.createElement("input")
    pm._populateTypeSettingValue("fieldRows", 4)
    expect(ctrl.fieldRowsTarget.value).toBe("4")
    pm._populateTypeSettingValue("fieldRows", null)
    expect(ctrl.fieldRowsTarget.value).toBe("") // null coerces to empty
  })

  it("skips silently when the target is absent", () => {
    const { pm } = newPM()
    expect(() => pm._populateTypeSettingValue("fieldRows", 4)).not.toThrow()
  })

  it("writes checkbox state", () => {
    const { pm, ctrl } = newPM()
    ctrl.hasFieldAllowHalfTarget = true
    ctrl.fieldAllowHalfTarget = Object.assign(document.createElement("input"), { type: "checkbox" })
    pm._populateTypeSettingCheckbox("fieldAllowHalf", true)
    expect(ctrl.fieldAllowHalfTarget.checked).toBe(true)
    pm._populateTypeSettingCheckbox("fieldAllowHalf", undefined)
    expect(ctrl.fieldAllowHalfTarget.checked).toBe(false)
  })
})

describe("TypeSettingsMixin.toggleOptionsEditor", () => {
  function withOptionsSection(ctrl) {
    const el = document.createElement("div")
    el.setAttribute("data-field-types", "")
    ctrl.element.appendChild(el)
    return el
  }

  it("shows the options editor for a choice field type", () => {
    const { pm, ctrl } = newPM()
    const el = withOptionsSection(ctrl)
    el.classList.add("hidden")
    pm.toggleOptionsEditor(field({ id: "f1", field_type: "select", property_type: "string" }))
    expect(el.classList.contains("hidden")).toBe(false)
  })

  it("hides the options editor for a non-choice field type", () => {
    const { pm, ctrl } = newPM()
    const el = withOptionsSection(ctrl)
    pm.toggleOptionsEditor(field({ id: "f1", field_type: "text", property_type: "string" }))
    expect(el.classList.contains("hidden")).toBe(true)
  })

  it("shows the options editor when only property_type is a choice type", () => {
    const { pm, ctrl } = newPM()
    const el = withOptionsSection(ctrl)
    el.classList.add("hidden")
    pm.toggleOptionsEditor(field({ id: "f1", field_type: "custom_widget", property_type: "checkbox" }))
    expect(el.classList.contains("hidden")).toBe(false)
  })

  it("is a no-op when there is no options section", () => {
    const { pm } = newPM()
    expect(() => pm.toggleOptionsEditor(field({ id: "f1", field_type: "select" }))).not.toThrow()
  })

  it("defaults field_type to '' when the field has none", () => {
    const { pm, ctrl } = newPM()
    const el = withOptionsSection(ctrl)
    el.classList.add("hidden")
    pm.toggleOptionsEditor({ id: "f1", property_type: "string" }) // no field_type at all
    expect(el.classList.contains("hidden")).toBe(true)
  })
})
