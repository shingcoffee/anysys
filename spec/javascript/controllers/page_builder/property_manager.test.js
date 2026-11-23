import { describe, it, expect, beforeEach, vi } from "vitest"
import {
  PropertyManager, OPTIONS_FIELD_TYPES, HTML_TYPE_DISPLAY_NAMES,
  TYPE_SETTINGS_MAP, DATE_TIME_INPUT_TYPES,
} from "controllers/page_builder/property_manager"
import { makeCtrl, field } from "../../support/page_builder.js"

function pmCtrl(fields = [], overrides = {}) {
  const ctrl = makeCtrl({ currentPage: { id: "p1", name: "Page 1", fields }, ...overrides })
  ctrl.element = document.createElement("div")
  ctrl.selectedFieldId = null
  ctrl.selectedFieldValue = null
  ctrl.fieldManager.renderFieldCard = vi.fn()
  ctrl.fieldManager.updateSidebarFieldStates = vi.fn()
  ctrl.fieldManager.getFieldIcon = vi.fn(() => "<svg></svg>")
  ctrl.pageManager.updateFormFooter = vi.fn()
  return ctrl
}

function newPM(fields = [], overrides = {}) {
  const ctrl = pmCtrl(fields, overrides)
  return { pm: new PropertyManager(ctrl), ctrl }
}

describe("PropertyManager — exported constants", () => {
  it("OPTIONS_FIELD_TYPES lists the choice-style field types", () => {
    expect(OPTIONS_FIELD_TYPES).toEqual(["select", "multi-select", "radio", "checkbox", "switch"])
  })
  it("HTML_TYPE_DISPLAY_NAMES maps html types to friendly labels", () => {
    expect(HTML_TYPE_DISPLAY_NAMES.text).toBe("Input Text")
    expect(HTML_TYPE_DISPLAY_NAMES["multi-select"]).toBe("Multi Select")
  })
  it("TYPE_SETTINGS_MAP + DATE_TIME_INPUT_TYPES expose per-type config", () => {
    expect(TYPE_SETTINGS_MAP.currency).toContain("fieldCurrencySymbol")
    expect(TYPE_SETTINGS_MAP.search).toEqual([])
    expect(DATE_TIME_INPUT_TYPES["datetime-local"]).toBe("datetime-local")
  })
})

describe("PropertyManager.updateFormSettings", () => {
  it("writes a key into form_settings", () => {
    const { pm, ctrl } = newPM()
    pm.updateFormSettings({ target: { dataset: { property: "title" }, value: "Contact", type: "text" } })
    expect(ctrl.configuration.form_settings.title).toBe("Contact")
    expect(ctrl.undoRedoManager.saveState).toHaveBeenCalled()
    expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
  })

  it("keeps the other form settings when writing one", () => {
    const { pm, ctrl } = newPM([], { configuration: { form_settings: { modes: ["create"] } } })
    pm.updateFormSettings({ target: { dataset: { property: "success_message" }, value: "Thanks!", type: "text" } })
    expect(ctrl.configuration.form_settings).toEqual({ modes: ["create"], success_message: "Thanks!" })
  })

  it("uses checkbox state for checkbox inputs", () => {
    const { pm, ctrl } = newPM()
    pm.updateFormSettings({ target: { dataset: { property: "captcha" }, type: "checkbox", checked: true } })
    expect(ctrl.configuration.form_settings.captcha).toBe(true)
  })

  it("refreshes the footer when the submit button text changes", () => {
    const { pm, ctrl } = newPM()
    pm.updateFormSettings({ target: { dataset: { property: "submit_button_text" }, value: "Go", type: "text" } })
    expect(ctrl.pageManager.updateFormFooter).toHaveBeenCalled()
  })

  it("ignores an event with no property", () => {
    const { pm, ctrl } = newPM()
    pm.updateFormSettings({ target: { dataset: {}, value: "x", type: "text" } })
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })
})

describe("PropertyManager — linked pages", () => {
  it("stores the checked submission modes", () => {
    const { pm, ctrl } = newPM()
    ctrl.element.insertAdjacentHTML("beforeend", `<input type="checkbox" data-submission-mode value="create" checked><input type="checkbox" data-submission-mode value="update">`)
    pm.updateSubmissionModes()
    expect(ctrl.configuration.form_settings.modes).toEqual(["create"])
    expect(ctrl.undoRedoManager.saveState).toHaveBeenCalled()
    expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
  })

  it("stores the checked reference fields as locked inputs", () => {
    const { pm, ctrl } = newPM()
    ctrl.element.insertAdjacentHTML("beforeend", `<input type="checkbox" data-page-input value="student" data-entity-id="7" checked><input type="checkbox" data-page-input value="course" data-entity-id="8">`)
    pm.updatePageInputs()
    expect(ctrl.configuration.form_settings.inputs).toEqual([{ field: "student", entity_id: 7 }])
  })
})

describe("PropertyManager.toggleLayoutSections", () => {
  function withSections(ctrl) {
    const validation = document.createElement("div")
    validation.setAttribute("data-property-section", "validation")
    const conditions = document.createElement("div")
    conditions.setAttribute("data-property-section", "conditions")
    ctrl.element.append(validation, conditions)
    return { validation, conditions }
  }

  it("hides the validation section and (for structural layout types) the conditions section", () => {
    const { pm, ctrl } = newPM()
    const { validation, conditions } = withSections(ctrl)
    pm.toggleLayoutSections({ id: "f1", property_type: "layout", field_type: "spacer" })
    expect(validation.classList.contains("hidden")).toBe(true)
    expect(conditions.classList.contains("hidden")).toBe(true)
  })

  it("keeps the conditions section visible for a layout type with meaningful content (e.g. heading)", () => {
    const { pm, ctrl } = newPM()
    const { validation, conditions } = withSections(ctrl)
    pm.toggleLayoutSections({ id: "f1", property_type: "layout", field_type: "heading" })
    expect(validation.classList.contains("hidden")).toBe(true)
    expect(conditions.classList.contains("hidden")).toBe(false)
  })

  it("shows both sections for a data field", () => {
    const { pm, ctrl } = newPM()
    const { validation, conditions } = withSections(ctrl)
    pm.toggleLayoutSections({ id: "f1", property_type: "string", field_type: "text" })
    expect(validation.classList.contains("hidden")).toBe(false)
    expect(conditions.classList.contains("hidden")).toBe(false)
  })

  it("tolerates missing section elements", () => {
    const { pm } = newPM()
    expect(() => pm.toggleLayoutSections({ id: "f1", property_type: "string", field_type: "text" })).not.toThrow()
  })
})

describe("PropertyManager.updateFieldProperty", () => {
  function evt(dataset, extra) {
    return { target: { dataset, ...extra } }
  }

  it("coerces checkbox, number, and text values", () => {
    const f = field({ id: "f1" })
    const { pm, ctrl } = newPM([f])
    ctrl.selectedFieldValue = "f1"

    pm.updateFieldProperty(evt({ property: "required" }, { type: "checkbox", checked: true }))
    expect(f.required).toBe(true)

    pm.updateFieldProperty(evt({ property: "max_length" }, { type: "number", value: "42" }))
    expect(f.max_length).toBe(42)

    pm.updateFieldProperty(evt({ property: "max_length" }, { type: "number", value: "" }))
    expect(f.max_length).toBeNull()

    pm.updateFieldProperty(evt({ property: "label" }, { type: "text", value: "Hello" }))
    expect(f.label).toBe("Hello")
  })

  it("debounces undo — saveState fires once across rapid edits", () => {
    const f = field({ id: "f1" })
    const { pm, ctrl } = newPM([f])
    ctrl.selectedFieldValue = "f1"
    pm.updateFieldProperty(evt({ property: "label" }, { type: "text", value: "A" }))
    pm.updateFieldProperty(evt({ property: "label" }, { type: "text", value: "AB" }))
    expect(ctrl.undoRedoManager.saveState).toHaveBeenCalledTimes(1)
  })

  it("syncs the header field-name target when the label changes", () => {
    const f = field({ id: "f1", property_slug: "slug" })
    const { pm, ctrl } = newPM([f])
    ctrl.selectedFieldValue = "f1"
    ctrl.hasFieldNameTarget = true
    ctrl.fieldNameTarget = document.createElement("span")
    pm.updateFieldProperty(evt({ property: "label" }, { type: "text", value: "Renamed" }))
    expect(ctrl.fieldNameTarget.textContent).toBe("Renamed")
  })

  it("is a no-op when no field is selected or property is missing", () => {
    const { pm, ctrl } = newPM([field({ id: "f1" })])
    pm.updateFieldProperty(evt({ property: "label" }, { type: "text", value: "x" }))
    expect(ctrl.saveManager.markDirty).not.toHaveBeenCalled()
  })

  it("is a no-op when the selected field id has no matching field", () => {
    const { pm, ctrl } = newPM([field({ id: "f1" })])
    ctrl.selectedFieldValue = "missing"
    pm.updateFieldProperty(evt({ property: "label" }, { type: "text", value: "x" }))
    expect(ctrl.saveManager.markDirty).not.toHaveBeenCalled()
  })

  it("falls back to property_slug / empty string for the header name when the label is cleared", () => {
    const f = field({ id: "f1", property_slug: "my_slug" })
    const { pm, ctrl } = newPM([f])
    ctrl.selectedFieldValue = "f1"
    ctrl.hasFieldNameTarget = true
    ctrl.fieldNameTarget = document.createElement("span")
    pm.updateFieldProperty(evt({ property: "label" }, { type: "text", value: "" }))
    expect(ctrl.fieldNameTarget.textContent).toBe("my_slug")

    const f2 = field({ id: "f2", property_slug: "" })
    ctrl.currentPage.fields.push(f2)
    ctrl.selectedFieldValue = "f2"
    pm.updateFieldProperty(evt({ property: "label" }, { type: "text", value: "" }))
    expect(ctrl.fieldNameTarget.textContent).toBe("Untitled")
    expect(ctrl.fieldNameTarget.title).toBe("")
  })

  it("does not touch the header name target when a non-label property changes", () => {
    const f = field({ id: "f1" })
    const { pm, ctrl } = newPM([f])
    ctrl.selectedFieldValue = "f1"
    ctrl.hasFieldNameTarget = true
    ctrl.fieldNameTarget = document.createElement("span")
    ctrl.fieldNameTarget.textContent = "Unchanged"
    pm.updateFieldProperty(evt({ property: "help_text" }, { type: "text", value: "x" }))
    expect(ctrl.fieldNameTarget.textContent).toBe("Unchanged")
  })
})

describe("PropertyManager.updateFieldSlug", () => {
  it("normalizes and applies a unique slug", () => {
    const f = field({ id: "f1", property_slug: "old" })
    const { pm, ctrl } = newPM([f, field({ id: "f2", property_slug: "taken" })])
    ctrl.selectedFieldValue = "f1"
    const target = { value: "New Slug!" }
    pm.updateFieldSlug({ target })
    expect(f.property_slug).toBe("new_slug")
    expect(target.value).toBe("new_slug")
    expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
  })

  it("rejects a slug that collides with another field", () => {
    const f = field({ id: "f1", property_slug: "old" })
    const { pm, ctrl } = newPM([f, field({ id: "f2", property_slug: "taken" })])
    ctrl.selectedFieldValue = "f1"
    pm.updateFieldSlug({ target: { value: "taken" } })
    expect(f.property_slug).toBe("old")
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("ignores when no field is selected at all", () => {
    const f = field({ id: "f1", property_slug: "old" })
    const { pm } = newPM([f])
    // selectedFieldValue/selectedFieldId both unset → early return on fieldId
    pm.updateFieldSlug({ target: { value: "New" } })
    expect(f.property_slug).toBe("old")
  })

  it("ignores when the selected field id has no matching field", () => {
    const f = field({ id: "f1", property_slug: "old" })
    const { pm, ctrl } = newPM([f])
    ctrl.selectedFieldValue = "missing"
    pm.updateFieldSlug({ target: { value: "New" } })
    expect(f.property_slug).toBe("old")
  })

  it("ignores an empty normalized slug", () => {
    const f = field({ id: "f1", property_slug: "old" })
    const { pm, ctrl } = newPM([f])
    ctrl.selectedFieldValue = "f1"
    pm.updateFieldSlug({ target: { value: "!!!" } })
    expect(f.property_slug).toBe("old")
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })
})

describe("PropertyManager._operatorLabel", () => {
  it("maps known operators and passes unknowns through", () => {
    const { pm } = newPM()
    expect(pm._operatorLabel("equals")).toBe("equals")
    expect(pm._operatorLabel("greater_than")).toBe(">")
    expect(pm._operatorLabel("is_empty")).toBe("is empty")
    expect(pm._operatorLabel("weird")).toBe("weird")
  })
})

describe("PropertyManager.updateColumnLayout", () => {
  function columnsField(id, layout, cols) {
    return { id, field_type: "columns", column_layout: layout, columns: cols }
  }

  it("grows the columns array to match a wider layout", () => {
    const f = columnsField("c1", "50-50", [{ fields: [] }, { fields: [] }])
    const { pm, ctrl } = newPM([f])
    ctrl.selectedFieldValue = "c1"
    pm.updateColumnLayout({ target: { value: "33-33-33" } })
    expect(f.columns).toHaveLength(3)
    expect(f.column_layout).toBe("33-33-33")
    expect(ctrl.fieldManager.renderFields).toHaveBeenCalled()
  })

  it("shrinks and merges overflow fields into the last remaining column", () => {
    const f = columnsField("c1", "25-25-25-25", [
      { fields: [field({ id: "a" })] }, { fields: [field({ id: "b" })] },
      { fields: [field({ id: "c" })] }, { fields: [field({ id: "d" })] },
    ])
    const { pm, ctrl } = newPM([f])
    ctrl.selectedFieldValue = "c1"
    pm.updateColumnLayout({ target: { value: "50-50" } })
    expect(f.columns).toHaveLength(2)
    // c + d merged into the 2nd (last) column, after b
    expect(f.columns[1].fields.map((x) => x.id)).toEqual(["b", "c", "d"])
  })

  it("ignores non-columns fields and blank layout", () => {
    const f = field({ id: "f1" })
    const { pm, ctrl } = newPM([f])
    ctrl.selectedFieldValue = "f1"
    pm.updateColumnLayout({ target: { value: "50-50" } })
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("ignores a blank layout value", () => {
    const f = columnsField("c1", "50-50", [{ fields: [] }, { fields: [] }])
    const { pm, ctrl } = newPM([f])
    ctrl.selectedFieldValue = "c1"
    pm.updateColumnLayout({ target: { value: "" } })
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("ignores when there is no selected field", () => {
    const { pm, ctrl } = newPM([columnsField("c1", "50-50", [{ fields: [] }, { fields: [] }])])
    pm.updateColumnLayout({ target: { value: "50-50" } })
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("defaults to 2 columns for an unrecognized layout key", () => {
    const f = columnsField("c1", "50-50", [{ fields: [] }])
    const { pm, ctrl } = newPM([f])
    ctrl.selectedFieldValue = "c1"
    pm.updateColumnLayout({ target: { value: "custom-layout" } })
    expect(f.columns).toHaveLength(2)
  })

  it("treats an overflow column with no fields array as empty when merging", () => {
    const f = columnsField("c1", "25-25-25-25", [
      { fields: [field({ id: "a" })] }, { fields: [field({ id: "b" })] },
      {}, // no `fields` key at all
    ])
    const { pm, ctrl } = newPM([f])
    ctrl.selectedFieldValue = "c1"
    pm.updateColumnLayout({ target: { value: "66-33" } })
    expect(f.columns).toHaveLength(2)
    expect(f.columns[1].fields.map((x) => x.id)).toEqual(["b"])
  })
})

describe("PropertyManager.updateWizardSettings", () => {
  it("stores wizard settings and marks dirty", () => {
    const { pm, ctrl } = newPM()
    pm.updateWizardSettings({ target: { dataset: { property: "show_progress" }, type: "checkbox", checked: true } })
    expect(ctrl.configuration.wizard_settings.show_progress).toBe(true)
    expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
  })

  it("updateWizardSettings stores the raw value for a non-checkbox input", () => {
    const { pm, ctrl } = newPM()
    pm.updateWizardSettings({ target: { dataset: { property: "steps_label" }, type: "text", value: "Steps" } })
    expect(ctrl.configuration.wizard_settings.steps_label).toBe("Steps")
  })

  it("updateWizardSettings is a no-op with no property", () => {
    const { pm, ctrl } = newPM()
    pm.updateWizardSettings({ target: { dataset: {}, type: "text", value: "x" } })
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })
})

describe("PropertyManager — floating panel + multi-select overlay", () => {
  function withPanel(ctrl) {
    ctrl.hasFloatingPanelTarget = true
    ctrl.floatingPanelTarget = document.createElement("div")
    ctrl.floatingPanelTarget.classList.add("hidden")
    ctrl.hasPropertyPanelTarget = true
    ctrl.propertyPanelTarget = document.createElement("div")
  }

  it("showFloatingPanel selects the field, populates the panel, syncs width, and reveals the panel", () => {
    const f = field({ id: "f1", label: "Email" })
    const { pm, ctrl } = newPM([f])
    withPanel(ctrl)
    ctrl.hasToolbarWidthGroupTarget = false
    // leave an overlay behind from a prior multi-select to prove it's removed
    const overlay = document.createElement("div")
    overlay.setAttribute("data-multi-select-overlay", "")
    ctrl.floatingPanelTarget.appendChild(overlay)

    pm.showFloatingPanel("f1")
    expect(ctrl.selectedFieldValue).toBe("f1")
    expect(ctrl.selectedFieldId).toBe("f1")
    expect(ctrl.floatingPanelVisibleValue).toBe(true)
    expect(ctrl.floatingPanelTarget.querySelector("[data-multi-select-overlay]")).toBeNull()
    expect(ctrl.propertyPanelTarget.style.display).toBe("")
    expect(ctrl.floatingPanelTarget.classList.contains("hidden")).toBe(false)
  })

  it("showFloatingPanel is a no-op when the field id has no match", () => {
    const { pm, ctrl } = newPM([field({ id: "f1" })])
    pm.showFloatingPanel("missing")
    expect(ctrl.selectedFieldValue).toBeNull()
  })

  it("showFloatingPanel tolerates missing property-panel / floating-panel 'has' flags", () => {
    // hasPropertyPanelTarget / hasFloatingPanelTarget both false → those two
    // guarded blocks are skipped, but populatePropertyPanel still runs.
    const { pm, ctrl } = newPM([field({ id: "f1" })])
    ctrl.floatingPanelTarget = document.createElement("div") // read unconditionally by _populateAdvancedTab
    expect(() => pm.showFloatingPanel("f1")).not.toThrow()
    expect(ctrl.selectedFieldId).toBe("f1")
  })

  it("showMultiSelectToolbar injects an overlay, hides the property panel, and reveals the floating panel", () => {
    const { pm, ctrl } = newPM()
    withPanel(ctrl)
    ctrl.hasToolbarWidthGroupTarget = false
    pm.showMultiSelectToolbar(3)
    expect(ctrl.floatingPanelTarget.querySelector("[data-multi-select-overlay]")).toBeTruthy()
    expect(ctrl.floatingPanelTarget.innerHTML).toContain("3 fields selected")
    expect(ctrl.propertyPanelTarget.style.display).toBe("none")
    expect(ctrl.floatingPanelTarget.classList.contains("hidden")).toBe(false)
  })

  it("isFloatingPanelVisible reflects the hidden class", () => {
    const { pm, ctrl } = newPM()
    withPanel(ctrl)
    expect(pm.isFloatingPanelVisible()).toBe(false)
    ctrl.floatingPanelTarget.classList.remove("hidden")
    expect(pm.isFloatingPanelVisible()).toBe(true)
  })

  it("isFloatingPanelVisible returns false without a floating-panel target", () => {
    const { pm } = newPM() // makeCtrl leaves hasFloatingPanelTarget falsy
    expect(pm.isFloatingPanelVisible()).toBe(false)
  })

  it("showMultiSelectToolbar is a no-op without a floating-panel target", () => {
    const { pm, ctrl } = newPM()
    expect(() => pm.showMultiSelectToolbar(2)).not.toThrow()
    expect(ctrl.floatingPanelVisibleValue).toBeUndefined()
  })

  it("hideFloatingPanel hides the panel, removes the overlay, and clears the scalar", () => {
    const { pm, ctrl } = newPM()
    withPanel(ctrl)
    ctrl.hasToolbarWidthGroupTarget = false
    pm.showMultiSelectToolbar(2)
    pm.hideFloatingPanel()
    expect(ctrl.floatingPanelVisibleValue).toBe(false)
    expect(ctrl.selectedFieldValue).toBeNull()
    expect(ctrl.floatingPanelTarget.querySelector("[data-multi-select-overlay]")).toBeNull()
    expect(ctrl.floatingPanelTarget.classList.contains("hidden")).toBe(true)
  })
})

describe("PropertyManager.toggleSection", () => {
  // The chevron is the button's direct-child <svg> (looked up via child
  // iteration, happy-dom-safe); rotation is asserted in the svg-child test below.
  it("toggles the collapsible section content open/closed", () => {
    const { pm } = newPM()
    const section = document.createElement("div")
    section.className = "border-b"
    const content = document.createElement("div")
    content.setAttribute("data-page-builder-target", "sectionContent")
    section.appendChild(content)
    const button = document.createElement("button")
    section.appendChild(button)

    pm.toggleSection({ currentTarget: button })
    expect(content.classList.contains("hidden")).toBe(true)
    pm.toggleSection({ currentTarget: button })
    expect(content.classList.contains("hidden")).toBe(false)
  })

  it("rotates the button's direct-child svg chevron", () => {
    const { pm } = newPM()
    const section = document.createElement("div")
    section.className = "border-b"
    const content = document.createElement("div")
    content.setAttribute("data-page-builder-target", "sectionContent")
    section.appendChild(content)
    const button = document.createElement("button")
    const chevron = document.createElementNS("http://www.w3.org/2000/svg", "svg")
    button.appendChild(chevron)
    section.appendChild(button)

    pm.toggleSection({ currentTarget: button })
    expect(chevron.classList.contains("rotate-180")).toBe(true)
  })

  it("is a no-op when the button is not inside a bordered section", () => {
    const { pm } = newPM()
    const button = document.createElement("button")
    expect(() => pm.toggleSection({ currentTarget: button })).not.toThrow()
  })
})

describe("PropertyManager.switchPropertyTab", () => {
  it("activates the clicked tab and shows the matching content panel", () => {
    const { pm, ctrl } = newPM()
    const panel = document.createElement("div")
    const tabBar = document.createElement("div")
    tabBar.setAttribute("data-page-builder-target", "propertyTabs")
    const btnContent = document.createElement("button"); btnContent.dataset.tab = "content"
    const btnStyle = document.createElement("button"); btnStyle.dataset.tab = "style"
    tabBar.append(btnContent, btnStyle)
    const cContent = document.createElement("div"); cContent.dataset.propertyTabContent = "content"
    const cStyle = document.createElement("div"); cStyle.dataset.propertyTabContent = "style"
    panel.append(tabBar, cContent, cStyle)
    ctrl.floatingPanelTarget = panel

    pm.switchPropertyTab({ currentTarget: btnStyle })
    expect(btnStyle.classList.contains("border-indigo-500")).toBe(true)
    expect(btnContent.classList.contains("text-gray-500")).toBe(true)
    expect(cStyle.classList.contains("hidden")).toBe(false)
    expect(cContent.classList.contains("hidden")).toBe(true)
  })

  it("ignores a tab button with no data-tab", () => {
    const { pm } = newPM()
    expect(() => pm.switchPropertyTab({ currentTarget: { dataset: {} } })).not.toThrow()
  })
})

describe("PropertyManager.populatePropertyPanel — tab visibility", () => {
  function panelDom() {
    const panel = document.createElement("div")
    const tabBar = document.createElement("div")
    tabBar.setAttribute("data-page-builder-target", "propertyTabs")
    const tabs = ["content", "structure", "layout", "validation", "advanced", "style"]
    tabs.forEach((t) => {
      const b = document.createElement("button"); b.dataset.tab = t; tabBar.appendChild(b)
      const c = document.createElement("div"); c.dataset.propertyTabContent = t; panel.appendChild(c)
    })
    panel.appendChild(tabBar)
    return panel
  }

  function setup(f) {
    const { pm, ctrl } = newPM([f])
    const panel = panelDom()
    ctrl.hasPropertyTabsTarget = true
    ctrl.propertyTabsTarget = panel.querySelector("[data-page-builder-target='propertyTabs']")
    ctrl.floatingPanelTarget = panel
    return { pm, ctrl, panel }
  }
  const visibleTabs = (panel) =>
    [...panel.querySelectorAll("[data-tab]")].filter((b) => !b.classList.contains("hidden")).map((b) => b.dataset.tab)

  it("shows data-field tabs for a normal field and defaults to content", () => {
    const { pm, panel } = setup(field({ id: "f1", property_type: "string", field_type: "text", html_type: "text" }))
    pm.populatePropertyPanel(panel.__field = { id: "f1", property_type: "string", field_type: "text", html_type: "text" })
    expect(visibleTabs(panel).sort()).toEqual(["advanced", "content", "layout", "validation"])
  })

  it("shows structure+style and defaults to structure for a columns layout", () => {
    const f = { id: "f1", property_type: "layout", field_type: "columns" }
    const { pm, panel } = setup(f)
    pm.populatePropertyPanel(f)
    expect(visibleTabs(panel).sort()).toEqual(["structure", "style"])
    const structureBtn = panel.querySelector("[data-tab='structure']")
    expect(structureBtn.classList.contains("border-indigo-500")).toBe(true)
  })

  it("shows content+style for a field group", () => {
    const f = { id: "f1", type: "field_group", label: "Grp" }
    const { pm, panel } = setup(f)
    pm.populatePropertyPanel(f)
    expect(visibleTabs(panel).sort()).toEqual(["content", "style"])
  })

  it("shows content+style for a non-columns layout field (isLayout, not columns/group)", () => {
    const f = { id: "f1", property_type: "layout", field_type: "section" }
    const { pm, panel } = setup(f)
    pm.populatePropertyPanel(f)
    expect(visibleTabs(panel).sort()).toEqual(["content", "style"])
  })
})

describe("PropertyManager.showFormSettings", () => {
  it("hides field sections, reveals form settings, and relabels/reveals the floating panel", () => {
    const { pm, ctrl } = newPM()
    const fieldSection = document.createElement("div")
    fieldSection.setAttribute("data-field-section", "")
    const formSettingsSection = document.createElement("div")
    formSettingsSection.setAttribute("data-form-settings", "")
    formSettingsSection.classList.add("hidden")
    ctrl.element.append(fieldSection, formSettingsSection)
    ctrl.hasFieldTypeLabelTarget = true
    ctrl.fieldTypeLabelTarget = document.createElement("span")
    ctrl.hasFloatingPanelTarget = true
    ctrl.floatingPanelTarget = document.createElement("div")
    ctrl.floatingPanelTarget.classList.add("hidden")

    pm.showFormSettings()
    expect(fieldSection.classList.contains("hidden")).toBe(true)
    expect(formSettingsSection.classList.contains("hidden")).toBe(false)
    expect(ctrl.fieldTypeLabelTarget.textContent).toBe("Form Settings")
    expect(ctrl.floatingPanelTarget.classList.contains("hidden")).toBe(false)
    expect(ctrl.floatingPanelTarget.classList.contains("flex")).toBe(true)
  })

  it("tolerates missing form-settings section and targets", () => {
    const { pm } = newPM()
    expect(() => pm.showFormSettings()).not.toThrow()
  })
})

describe("PropertyManager.populatePropertyPanel — full field/target population", () => {
  // Wire every optional target the panel body reads, each value input wrapped
  // in a `<div>` so `.closest("div")` (used to hide/show its row) resolves.
  function withAllFieldTargets(ctrl) {
    const wrap = (el) => { const div = document.createElement("div"); div.appendChild(el); ctrl.element.appendChild(div); return el }
    const bare = (el) => { ctrl.element.appendChild(el); return el }

    ctrl.hasFieldNameTarget = true; ctrl.fieldNameTarget = bare(document.createElement("span"))
    ctrl.hasFieldTypeLabelTarget = true; ctrl.fieldTypeLabelTarget = bare(document.createElement("span"))
    ctrl.hasFieldIconTarget = true; ctrl.fieldIconTarget = bare(document.createElement("div"))
    ctrl.hasGeneralSectionLabelTarget = true; ctrl.generalSectionLabelTarget = bare(document.createElement("span"))
    ctrl.hasFieldLabelTarget = true; ctrl.fieldLabelTarget = wrap(document.createElement("input"))
    ctrl.hasFieldPlaceholderTarget = true; ctrl.fieldPlaceholderTarget = wrap(document.createElement("input"))
    ctrl.hasFieldHelpTextTarget = true; ctrl.fieldHelpTextTarget = wrap(document.createElement("input"))
    ctrl.hasFieldRequiredTarget = true; ctrl.fieldRequiredTarget = wrap(Object.assign(document.createElement("input"), { type: "checkbox" }))
    ctrl.hasFieldDefaultValueTarget = true; ctrl.fieldDefaultValueTarget = wrap(document.createElement("input"))
    ctrl.hasFieldContentTarget = true; ctrl.fieldContentTarget = wrap(document.createElement("textarea"))
    ctrl.hasHeadingLevelTarget = true; ctrl.headingLevelTarget = wrap(document.createElement("input") /* stand-in for <select> — happy-dom rejects .value writes without a matching <option> */)
    ctrl.hasSpacerHeightTarget = true; ctrl.spacerHeightTarget = wrap(document.createElement("input") /* stand-in for <select> — happy-dom rejects .value writes without a matching <option> */)
    ctrl.hasAlertVariantTarget = true; ctrl.alertVariantTarget = wrap(document.createElement("input") /* stand-in for <select> — happy-dom rejects .value writes without a matching <option> */)
    ctrl.hasImageUrlAltGroupTarget = true; ctrl.imageUrlAltGroupTarget = bare(document.createElement("div"))
    ctrl.hasImageUrlTarget = true; ctrl.imageUrlTarget = bare(document.createElement("input"))
    ctrl.hasAltTextTarget = true; ctrl.altTextTarget = bare(document.createElement("input"))
    ctrl.hasAttributionTarget = true; ctrl.attributionTarget = wrap(document.createElement("input"))
    ctrl.hasButtonUrlTarget = true; ctrl.buttonUrlTarget = wrap(document.createElement("input"))
    ctrl.hasButtonVariantSizeGroupTarget = true; ctrl.buttonVariantSizeGroupTarget = bare(document.createElement("div"))
    ctrl.hasButtonVariantTarget = true; ctrl.buttonVariantTarget = bare(document.createElement("input") /* stand-in for <select> — happy-dom rejects .value writes without a matching <option> */)
    ctrl.hasButtonSizeTarget = true; ctrl.buttonSizeTarget = bare(document.createElement("input") /* stand-in for <select> — happy-dom rejects .value writes without a matching <option> */)
    ctrl.hasAlignmentTarget = true; ctrl.alignmentTarget = wrap(document.createElement("input") /* stand-in for <select> — happy-dom rejects .value writes without a matching <option> */)
    ctrl.hasVideoUrlTarget = true; ctrl.videoUrlTarget = wrap(document.createElement("input"))
    ctrl.hasListStyleTarget = true; ctrl.listStyleTarget = wrap(document.createElement("input") /* stand-in for <select> — happy-dom rejects .value writes without a matching <option> */)
    ctrl.hasCodeLanguageTarget = true; ctrl.codeLanguageTarget = wrap(document.createElement("input"))
    ctrl.hasProgressValueColorGroupTarget = true; ctrl.progressValueColorGroupTarget = bare(document.createElement("div"))
    ctrl.hasProgressValueTarget = true; ctrl.progressValueTarget = bare(document.createElement("input"))
    ctrl.hasProgressColorTarget = true; ctrl.progressColorTarget = bare(document.createElement("input") /* stand-in for <select> — happy-dom rejects .value writes without a matching <option> */)
    ctrl.hasColumnLayoutTarget = true; ctrl.columnLayoutTarget = wrap(document.createElement("input") /* stand-in for <select> — happy-dom rejects .value writes without a matching <option> */)
  }

  it("populates every layout-specific target (values + show/hide) for a 'button' layout field", () => {
    const f = {
      id: "f1", property_type: "layout", field_type: "button", label: "Click me",
      content: "Go", button_url: "/x", button_variant: "secondary", button_size: "lg", alignment: "center",
    }
    const { pm, ctrl } = newPM([f])
    withAllFieldTargets(ctrl)
    pm.populatePropertyPanel(f)

    expect(ctrl.fieldNameTarget.textContent).toBe("Click me")
    expect(ctrl.fieldTypeLabelTarget.textContent).toBe("Button")
    expect(ctrl.fieldIconTarget.className).toContain("bg-violet-100")
    expect(ctrl.generalSectionLabelTarget.textContent).toBe("Button Settings")
    expect(ctrl.fieldPlaceholderTarget.closest("div").classList.contains("hidden")).toBe(true) // layout → hidden
    expect(ctrl.fieldContentTarget.closest("div").classList.contains("hidden")).toBe(false) // button shows content
    expect(ctrl.fieldContentTarget.value).toBe("Go")
    expect(ctrl.headingLevelTarget.closest("div").classList.contains("hidden")).toBe(true) // not a heading
    expect(ctrl.buttonUrlTarget.closest("div").classList.contains("hidden")).toBe(false)
    expect(ctrl.buttonUrlTarget.value).toBe("/x")
    expect(ctrl.buttonVariantSizeGroupTarget.classList.contains("hidden")).toBe(false)
    expect(ctrl.buttonVariantTarget.value).toBe("secondary")
    expect(ctrl.buttonSizeTarget.value).toBe("lg")
    expect(ctrl.alignmentTarget.closest("div").classList.contains("hidden")).toBe(false)
    expect(ctrl.alignmentTarget.value).toBe("center")
    expect(ctrl.videoUrlTarget.closest("div").classList.contains("hidden")).toBe(true)
    expect(ctrl.columnLayoutTarget.closest("div").classList.contains("hidden")).toBe(true)
  })

  it.each([
    ["heading", { heading_level: "h1" }, "headingLevelTarget", "h1"],
    ["spacer", { spacer_height: "lg" }, "spacerHeightTarget", "lg"],
    ["alert", { alert_variant: "warning" }, "alertVariantTarget", "warning"],
    ["video", { video_url: "https://x" }, "videoUrlTarget", "https://x"],
    ["list", { list_style: "numbered" }, "listStyleTarget", "numbered"],
    ["code_block", { code_language: "ruby" }, "codeLanguageTarget", "ruby"],
    ["quote", { attribution: "— Me" }, "attributionTarget", "— Me"],
  ])("shows and populates the %s-specific target", (fieldType, attrs, targetName, expected) => {
    const f = { id: "f1", property_type: "layout", field_type: fieldType, ...attrs }
    const { pm, ctrl } = newPM([f])
    withAllFieldTargets(ctrl)
    pm.populatePropertyPanel(f)
    expect(ctrl[targetName].closest("div").classList.contains("hidden")).toBe(false)
    expect(ctrl[targetName].value).toBe(expected)
  })

  it("shows the image target group and progress-bar target group, and populates progress value/color", () => {
    const f = {
      id: "f1", property_type: "layout", field_type: "image",
      image_url: "https://img", alt_text: "Alt",
    }
    const { pm, ctrl } = newPM([f])
    withAllFieldTargets(ctrl)
    pm.populatePropertyPanel(f)
    expect(ctrl.imageUrlAltGroupTarget.classList.contains("hidden")).toBe(false)
    expect(ctrl.imageUrlTarget.value).toBe("https://img")
    expect(ctrl.altTextTarget.value).toBe("Alt")

    const bar = { id: "f2", property_type: "layout", field_type: "progress_bar", progress_value: 42, progress_color: "rose" }
    pm.populatePropertyPanel(bar)
    expect(ctrl.progressValueColorGroupTarget.classList.contains("hidden")).toBe(false)
    expect(ctrl.progressValueTarget.value).toBe("42")
    expect(ctrl.progressColorTarget.value).toBe("rose")
  })

  it("defaults the column-layout to '50-50' when a columns field has none set (`|| \"50-50\"`)", () => {
    const f = { id: "f1", property_type: "layout", field_type: "columns" }
    const { pm, ctrl } = newPM([f])
    withAllFieldTargets(ctrl)
    pm.populatePropertyPanel(f)
    expect(ctrl.columnLayoutTarget.value).toBe("50-50")
  })

  it("labels a layout field with no field_type as 'Layout' (`fieldType || \"layout\"`)", () => {
    const f = { id: "f1", property_type: "layout", field_type: "" }
    const { pm, ctrl } = newPM([f])
    withAllFieldTargets(ctrl)
    pm.populatePropertyPanel(f)
    expect(ctrl.fieldTypeLabelTarget.textContent).toBe("Layout")
  })

  it("labels a data field with an unmapped html_type via formatLabel (`HTML_TYPE_DISPLAY_NAMES[...] || formatLabel`)", () => {
    const f = { id: "f1", property_type: "string", field_type: "text", html_type: "weird_type" }
    const { pm, ctrl } = newPM([f])
    withAllFieldTargets(ctrl)
    ctrl.floatingPanelTarget = document.createElement("div") // data field → _populateAdvancedTab reads it
    pm.populatePropertyPanel(f)
    expect(ctrl.fieldTypeLabelTarget.textContent).toBe("Weird type")
  })

  it("shows the column-layout target and applies the field's column_layout for a columns field", () => {
    const f = { id: "f1", property_type: "layout", field_type: "columns", column_layout: "33-66" }
    const { pm, ctrl } = newPM([f])
    withAllFieldTargets(ctrl)
    pm.populatePropertyPanel(f)
    expect(ctrl.columnLayoutTarget.closest("div").classList.contains("hidden")).toBe(false)
    expect(ctrl.columnLayoutTarget.value).toBe("33-66")
    // required + help-text rows are hidden for a columns layout
    expect(ctrl.fieldRequiredTarget.closest("div").classList.contains("hidden")).toBe(true)
    expect(ctrl.fieldHelpTextTarget.closest("div").classList.contains("hidden")).toBe(true)
  })

  it("falls back to 'Layout Settings' for an unmapped layout field_type and uses formatLabel for the type label", () => {
    const f = { id: "f1", property_type: "layout", field_type: "custom_widget" }
    const { pm, ctrl } = newPM([f])
    withAllFieldTargets(ctrl)
    pm.populatePropertyPanel(f)
    expect(ctrl.generalSectionLabelTarget.textContent).toBe("Layout Settings")
    expect(ctrl.fieldTypeLabelTarget.textContent).toBe("Custom widget")
  })

  it("labels a field group and skips the advanced tab", () => {
    const f = { id: "f1", type: "field_group", label: "" }
    const { pm, ctrl } = newPM([f])
    withAllFieldTargets(ctrl)
    ctrl.floatingPanelTarget = document.createElement("div") // read unconditionally by _populateAdvancedTab
    pm.populatePropertyPanel(f)
    expect(ctrl.fieldTypeLabelTarget.textContent).toBe("Field Group")
    expect(ctrl.fieldIconTarget.className).toContain("bg-indigo-100")
    expect(ctrl.generalSectionLabelTarget.textContent).toBe("Field Group Settings")
    expect(ctrl.fieldNameTarget.textContent).toBe("Untitled") // no label, no property_slug
    expect(ctrl.fieldRequiredTarget.closest("div").classList.contains("hidden")).toBe(true)
    expect(ctrl.fieldDefaultValueTarget.closest("div").classList.contains("hidden")).toBe(true)
  })

  it("populates a plain data field: general fields visible, HTML_TYPE_DISPLAY_NAMES label, and renders options + advanced tab", () => {
    const f = field({ id: "f1", field_type: "select", property_type: "string", html_type: "select", label: "Pick one", options: [{ label: "A", value: "a" }] })
    const { pm, ctrl } = newPM([f])
    withAllFieldTargets(ctrl)
    ctrl.hasOptionsListTarget = true
    ctrl.optionsListTarget = document.createElement("div")
    ctrl.floatingPanelTarget = document.createElement("div") // read unconditionally by _populateAdvancedTab
    pm.populatePropertyPanel(f)
    expect(ctrl.fieldTypeLabelTarget.textContent).toBe("Dropdown")
    expect(ctrl.generalSectionLabelTarget.textContent).toBe("Field Properties")
    expect(ctrl.fieldPlaceholderTarget.closest("div").classList.contains("hidden")).toBe(false)
    expect(ctrl.fieldRequiredTarget.closest("div").classList.contains("hidden")).toBe(false)
    expect(ctrl.optionsListTarget.children.length).toBeGreaterThan(0) // OPTIONS_FIELD_TYPES → rendered
  })
})

describe("PropertyManager._populateAdvancedTab", () => {
  it("summarizes enabled rules targeting the field", () => {
    const rules = [{
      enabled: true,
      actions: [{ field_id: "f1", type: "hide" }],
      conditions: [{ items: [{ field_id: "f2", operator: "equals", value: "yes" }] }],
    }]
    const f2 = field({ id: "f2", label: "Trigger" })
    const { pm, ctrl } = newPM([field({ id: "f1" }), f2], { configuration: { rules, pages: [], calculations: [] } })
    const panel = document.createElement("div")
    panel.innerHTML = '<div data-advanced-rules-summary></div>'
    ctrl.floatingPanelTarget = panel
    pm._populateAdvancedTab({ id: "f1" })
    const summary = panel.querySelector("[data-advanced-rules-summary]").innerHTML
    expect(summary).toContain("Hide this field when [Trigger] equals [yes]")
  })

  it("renders a 'no rules' placeholder when nothing targets the field", () => {
    const { pm, ctrl } = newPM([field({ id: "f1" })])
    const panel = document.createElement("div")
    panel.innerHTML = '<div data-advanced-rules-summary></div>'
    ctrl.floatingPanelTarget = panel
    pm._populateAdvancedTab({ id: "f1" })
    expect(panel.querySelector("[data-advanced-rules-summary]").textContent).toContain("No conditional rules")
  })

  it("prefills the add-logic button with the field id when present", () => {
    const { pm, ctrl } = newPM([field({ id: "f1" })])
    const panel = document.createElement("div")
    panel.innerHTML = '<button data-prefill-target-field></button><div data-advanced-rules-summary></div>'
    ctrl.floatingPanelTarget = panel
    pm._populateAdvancedTab({ id: "f1" })
    expect(panel.querySelector("[data-prefill-target-field]").dataset.prefillTargetField).toBe("f1")
  })

  it("is a no-op without a rules-summary container (even if the add-logic button exists)", () => {
    const { pm, ctrl } = newPM([field({ id: "f1" })])
    const panel = document.createElement("div")
    panel.innerHTML = '<button data-prefill-target-field></button>'
    ctrl.floatingPanelTarget = panel
    expect(() => pm._populateAdvancedTab({ id: "f1" })).not.toThrow()
  })

  it("skips disabled rules and rules that don't target the field, and defaults verb to 'Show' with a fallback label/value", () => {
    const rules = [
      { enabled: false, actions: [{ field_id: "f1", type: "hide" }], conditions: [{ items: [{ field_id: "f2", operator: "equals", value: "x" }] }] },
      { enabled: true, actions: [{ field_id: "other" }], conditions: [{ items: [{ field_id: "f2", operator: "equals", value: "x" }] }] },
      { enabled: true, actions: [{ field_id: "f1" }], conditions: [{ items: [{ field_id: "missing_field", operator: "contains", value: "" }] }] },
    ]
    const { pm, ctrl } = newPM([field({ id: "f1" })], { configuration: { rules, pages: [], calculations: [] } })
    const panel = document.createElement("div")
    panel.innerHTML = '<div data-advanced-rules-summary></div>'
    ctrl.floatingPanelTarget = panel
    pm._populateAdvancedTab({ id: "f1" })
    const summary = panel.querySelector("[data-advanced-rules-summary]").innerHTML
    // 3rd rule: no action.type → defaults verb to "Show"; source field not found → falls back
    // to the raw field_id; blank condition value → falls back to the literal `""`.
    expect(summary).toContain('Show this field when [missing_field] contains [""]')
    expect(summary).toContain("Edit Rules")
  })

  it("omits a rule from the summary when it targets the field but has no condition items", () => {
    const rules = [{ enabled: true, actions: [{ field_id: "f1", type: "show" }], conditions: [] }]
    const { pm, ctrl } = newPM([field({ id: "f1" })], { configuration: { rules, pages: [], calculations: [] } })
    const panel = document.createElement("div")
    panel.innerHTML = '<div data-advanced-rules-summary></div>'
    ctrl.floatingPanelTarget = panel
    pm._populateAdvancedTab({ id: "f1" })
    expect(panel.querySelector("[data-advanced-rules-summary]").textContent).toContain("No conditional rules")
  })

  it("defaults a rule's missing conditions/items to [] (the `|| []` fallbacks)", () => {
    const rules = [
      { enabled: true, actions: [{ field_id: "f1", type: "show" }] }, // no `conditions` key
      { enabled: true, actions: [{ field_id: "f1", type: "show" }], conditions: [{}] }, // group with no `items`
    ]
    const { pm, ctrl } = newPM([field({ id: "f1" })], { configuration: { rules, pages: [], calculations: [] } })
    const panel = document.createElement("div")
    panel.innerHTML = '<div data-advanced-rules-summary></div>'
    ctrl.floatingPanelTarget = panel
    pm._populateAdvancedTab({ id: "f1" })
    // both rules produce zero condition parts → no summary
    expect(panel.querySelector("[data-advanced-rules-summary]").textContent).toContain("No conditional rules")
  })

  it("defaults an empty rules configuration to []", () => {
    const { pm, ctrl } = newPM([field({ id: "f1" })], { configuration: { pages: [], calculations: [] } })
    const panel = document.createElement("div")
    panel.innerHTML = '<div data-advanced-rules-summary></div>'
    ctrl.floatingPanelTarget = panel
    expect(() => pm._populateAdvancedTab({ id: "f1" })).not.toThrow()
  })
})
