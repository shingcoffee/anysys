import { describe, it, expect, vi } from "vitest"
import { PropertyManager } from "controllers/page_builder/property_manager"
import { makeCtrl, field } from "../../../support/page_builder.js"

function fbCtrl(fields = []) {
  const ctrl = makeCtrl({ currentPage: { id: "p1", fields } })
  ctrl.selectedFieldId = null
  ctrl.selectedFieldValue = null
  return ctrl
}
function newPM(fields = []) {
  const ctrl = fbCtrl(fields)
  return { pm: new PropertyManager(ctrl), ctrl }
}
function withOptionsList(ctrl) {
  ctrl.hasOptionsListTarget = true
  ctrl.optionsListTarget = document.createElement("div")
}
function withConditions(ctrl) {
  ctrl.hasConditionsContainerTarget = true
  ctrl.conditionsContainerTarget = document.createElement("div")
}

describe("FormBuilderMixin — options CRUD", () => {
  it("addOption appends a numbered option and re-renders", () => {
    const f = field({ id: "f1" })
    const { pm, ctrl } = newPM([f])
    withOptionsList(ctrl)
    pm.addOption({ currentTarget: { dataset: { fieldId: "f1" } } })
    expect(f.options).toEqual([{ label: "Option 1", value: "option_1" }])
    expect(ctrl.undoRedoManager.saveState).toHaveBeenCalled()
    expect(ctrl.optionsListTarget.innerHTML).toContain("option_1")
  })

  it("addOption falls back to the selected field id", () => {
    const f = field({ id: "f1" })
    const { pm, ctrl } = newPM([f])
    withOptionsList(ctrl)
    ctrl.selectedFieldId = "f1"
    pm.addOption({ currentTarget: { dataset: {} } })
    expect(f.options).toHaveLength(1)
  })

  it("addOption is a no-op with no resolvable field id or no matching field", () => {
    const { pm, ctrl } = newPM([field({ id: "f1" })])
    pm.addOption({ currentTarget: { dataset: {} } }) // no fieldId, no selectedFieldId
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
    pm.addOption({ currentTarget: { dataset: { fieldId: "missing" } } }) // fieldId set, field not found
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("removeOption splices by index", () => {
    const f = field({ id: "f1", options: [{ label: "A", value: "a" }, { label: "B", value: "b" }] })
    const { pm, ctrl } = newPM([f])
    withOptionsList(ctrl)
    pm.removeOption({ currentTarget: { dataset: { fieldId: "f1", optionIndex: "0" } } })
    expect(f.options).toEqual([{ label: "B", value: "b" }])
  })

  it("removeOption is a no-op when the field or its options are missing", () => {
    const { pm, ctrl } = newPM([field({ id: "f1" })]) // no options array
    pm.removeOption({ currentTarget: { dataset: { fieldId: "f1", optionIndex: "0" } } })
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
    pm.removeOption({ currentTarget: { dataset: { fieldId: "missing", optionIndex: "0" } } })
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("updateOption mutates the target option property", () => {
    const f = field({ id: "f1", options: [{ label: "A", value: "a" }] })
    const { pm, ctrl } = newPM([f])
    pm.updateOption({ target: { dataset: { fieldId: "f1", optionIndex: "0", property: "label" }, value: "Alpha" } })
    expect(f.options[0].label).toBe("Alpha")
    expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
  })

  it("updateOption is a no-op when the field, its options, or the target index is missing", () => {
    const { pm, ctrl } = newPM([field({ id: "f1" })]) // no options
    pm.updateOption({ target: { dataset: { fieldId: "f1", optionIndex: "0", property: "label" }, value: "x" } })
    expect(ctrl.saveManager.markDirty).not.toHaveBeenCalled()

    const f2 = field({ id: "f2", options: [{ label: "A", value: "a" }] })
    const { pm: pm2, ctrl: ctrl2 } = newPM([f2])
    pm2.updateOption({ target: { dataset: { fieldId: "f2", optionIndex: "5", property: "label" }, value: "x" } }) // index out of range
    expect(ctrl2.saveManager.markDirty).not.toHaveBeenCalled()
  })

  it("renderOptionsEditor emits a row per option with escaped-attribute values", () => {
    const f = field({ id: "f1", options: [{ label: "One", value: "1" }, { label: "Two", value: "2" }] })
    const { pm, ctrl } = newPM([f])
    withOptionsList(ctrl)
    pm.renderOptionsEditor(f)
    // one row div per option (its inputs/buttons also carry data-option-index)
    expect(ctrl.optionsListTarget.children).toHaveLength(2)
    expect(ctrl.optionsListTarget.innerHTML).toContain('value="One"')
  })

  it("renderOptionsEditor defaults missing options/label/value to empty", () => {
    const f = field({ id: "f1" }) // no options array at all
    const { pm, ctrl } = newPM([f])
    withOptionsList(ctrl)
    pm.renderOptionsEditor(f)
    expect(ctrl.optionsListTarget.children).toHaveLength(0)

    const f2 = field({ id: "f2", options: [{}] }) // option with no label/value
    pm.renderOptionsEditor(f2)
    const inputs = ctrl.optionsListTarget.querySelectorAll("input")
    expect(inputs[0].value).toBe("") // label falls back to ""
    expect(inputs[1].value).toBe("") // value falls back to ""
  })

  it("renderOptionsEditor is a no-op without the options-list target", () => {
    const { pm } = newPM([field({ id: "f1" })])
    expect(() => pm.renderOptionsEditor(field({ id: "f1", options: [] }))).not.toThrow()
  })
})

describe("FormBuilderMixin — conditions", () => {
  it("addCondition seeds a default condition and renders", () => {
    const f = field({ id: "f1" })
    const { pm, ctrl } = newPM([f])
    ctrl.selectedFieldValue = "f1"
    withConditions(ctrl)
    pm.addCondition()
    expect(f.conditions).toEqual([{ field_id: "", operator: "equals", value: "", logic: "and" }])
    expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
  })

  it("addCondition is a no-op with no selected field", () => {
    const { pm, ctrl } = newPM([field({ id: "f1" })])
    pm.addCondition()
    expect(ctrl.saveManager.markDirty).not.toHaveBeenCalled()
  })

  it("addCondition is a no-op when the selected field id has no match", () => {
    const { pm, ctrl } = newPM([field({ id: "f1" })])
    ctrl.selectedFieldValue = "missing"
    pm.addCondition()
    expect(ctrl.saveManager.markDirty).not.toHaveBeenCalled()
  })

  it("updateCondition writes the property and clears value when operator becomes is_empty", () => {
    const f = field({ id: "f1", conditions: [{ field_id: "x", operator: "equals", value: "keep", logic: "and" }] })
    const { pm } = newPM([f])
    const valueInput = document.createElement("input")
    valueInput.setAttribute("data-property", "value")
    valueInput.value = "keep"
    const item = document.createElement("div")
    item.className = "condition-item"
    item.appendChild(valueInput)
    // Use an input (accepts any .value) to stand in for the operator <select> —
    // a real happy-dom <select> coerces .value to "" without a matching <option>.
    const target = document.createElement("input")
    target.dataset.fieldId = "f1"
    target.dataset.conditionIndex = "0"
    target.dataset.property = "operator"
    target.value = "is_empty"
    item.appendChild(target)

    pm.updateCondition({ target })
    expect(f.conditions[0].operator).toBe("is_empty")
    expect(f.conditions[0].value).toBe("")
    expect(valueInput.classList.contains("hidden")).toBe(true)
  })

  it("updateCondition reveals the value input again for an operator that needs a value", () => {
    const f = field({ id: "f1", conditions: [{ field_id: "x", operator: "is_empty", value: "", logic: "and" }] })
    const { pm } = newPM([f])
    const valueInput = document.createElement("input")
    valueInput.setAttribute("data-property", "value")
    valueInput.classList.add("hidden")
    const item = document.createElement("div")
    item.className = "condition-item"
    item.appendChild(valueInput)
    const target = document.createElement("input")
    Object.assign(target.dataset, { fieldId: "f1", conditionIndex: "0", property: "operator" })
    target.value = "contains"
    item.appendChild(target)

    pm.updateCondition({ target })
    expect(f.conditions[0].operator).toBe("contains")
    expect(valueInput.classList.contains("hidden")).toBe(false)
  })

  it("updateCondition does not touch the value input when the changed property isn't operator", () => {
    const f = field({ id: "f1", conditions: [{ field_id: "x", operator: "equals", value: "old", logic: "and" }] })
    const { pm, ctrl } = newPM([f])
    const target = document.createElement("input")
    Object.assign(target.dataset, { fieldId: "f1", conditionIndex: "0", property: "value" })
    target.value = "new"
    pm.updateCondition({ target })
    expect(f.conditions[0].value).toBe("new")
    expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
  })

  it("updateCondition tolerates an operator change with no surrounding .condition-item / matching value input", () => {
    const f = field({ id: "f1", conditions: [{ field_id: "x", operator: "equals", value: "v", logic: "and" }] })
    const { pm } = newPM([f])
    const target = document.createElement("input") // not attached to any .condition-item
    Object.assign(target.dataset, { fieldId: "f1", conditionIndex: "0", property: "operator" })
    target.value = "is_empty"
    expect(() => pm.updateCondition({ target })).not.toThrow()
    expect(f.conditions[0].operator).toBe("is_empty")
  })

  it("updateCondition is a no-op when the field, its conditions, or the index is missing", () => {
    const { pm, ctrl } = newPM([field({ id: "f1" })]) // no conditions
    pm.updateCondition({ target: { dataset: { fieldId: "f1", conditionIndex: "0", property: "value" }, value: "x" } })
    expect(ctrl.saveManager.markDirty).not.toHaveBeenCalled()

    const f2 = field({ id: "f2", conditions: [{ field_id: "x", operator: "equals", value: "", logic: "and" }] })
    const { pm: pm2, ctrl: ctrl2 } = newPM([f2])
    pm2.updateCondition({ target: { dataset: { fieldId: "f2", conditionIndex: "5", property: "value" }, value: "x" } })
    expect(ctrl2.saveManager.markDirty).not.toHaveBeenCalled()
  })

  it("removeCondition splices and re-renders", () => {
    const f = field({ id: "f1", conditions: [{ field_id: "x", operator: "equals", value: "", logic: "and" }] })
    const { pm, ctrl } = newPM([f])
    withConditions(ctrl)
    const evt = { stopPropagation: vi.fn(), target: { dataset: { fieldId: "f1", conditionIndex: "0" } }, currentTarget: { dataset: {} } }
    pm.removeCondition(evt)
    expect(f.conditions).toHaveLength(0)
    expect(evt.stopPropagation).toHaveBeenCalled()
  })

  it("removeCondition falls back to currentTarget's dataset when the click lands on the SVG icon", () => {
    const f = field({ id: "f1", conditions: [{ field_id: "x", operator: "equals", value: "", logic: "and" }] })
    const { pm, ctrl } = newPM([f])
    withConditions(ctrl)
    const evt = {
      stopPropagation: vi.fn(),
      target: { dataset: {} }, // e.g. the inner <svg>, no data attrs of its own
      currentTarget: { dataset: { fieldId: "f1", conditionIndex: "0" } },
    }
    pm.removeCondition(evt)
    expect(f.conditions).toHaveLength(0)
  })

  it("removeCondition is a no-op when the field or its conditions are missing", () => {
    const { pm, ctrl } = newPM([field({ id: "f1" })]) // no conditions
    const evt = { stopPropagation: vi.fn(), target: { dataset: { fieldId: "f1", conditionIndex: "0" } }, currentTarget: { dataset: {} } }
    pm.removeCondition(evt)
    expect(ctrl.saveManager.markDirty).not.toHaveBeenCalled()
  })

  it("renderConditionsUI clears the container when there are no conditions", () => {
    const f = field({ id: "f1" })
    const { pm, ctrl } = newPM([f])
    withConditions(ctrl)
    ctrl.conditionsContainerTarget.innerHTML = "stale"
    pm.renderConditionsUI(f)
    expect(ctrl.conditionsContainerTarget.innerHTML).toBe("")
  })

  it("renderConditionsUI builds a condition row with other-field options and marks selected", () => {
    const f = field({ id: "f1", conditions: [{ field_id: "f2", operator: "contains", value: "hi", logic: "and" }] })
    const other = field({ id: "f2", label: "Other" })
    const { pm, ctrl } = newPM([f, other])
    withConditions(ctrl)
    pm.renderConditionsUI(f)
    const html = ctrl.conditionsContainerTarget.innerHTML
    expect(html).toContain("condition-item")
    expect(html).toContain('value="f2" selected') // preselected other field
    expect(html).toContain('value="contains" selected') // preselected operator
    // first condition shows "If", not the logic joiner
    expect(html).toMatch(/>\s*If\s*</)
  })

  it("renderConditionsUI falls back to property_slug when an other-field has no label", () => {
    const f = field({ id: "f1", conditions: [{ field_id: "", operator: "equals", value: "", logic: "and" }] })
    const other = field({ id: "f2", label: "", property_slug: "other_slug" })
    const { pm, ctrl } = newPM([f, other])
    withConditions(ctrl)
    pm.renderConditionsUI(f)
    expect(ctrl.conditionsContainerTarget.innerHTML).toContain("other_slug")
  })

  it("renders every operator's selected state, hides the value input for is_empty/is_not_empty, and shows the AND/OR logic select for non-first conditions", () => {
    const conditions = [
      { field_id: "", operator: "not_equals", value: "a", logic: "and" },
      { field_id: "", operator: "not_contains", value: "b", logic: "or" },
      { field_id: "", operator: "greater_than", value: "c", logic: "and" },
      { field_id: "", operator: "less_than", value: "d", logic: "or" },
      { field_id: "", operator: "is_empty", value: "", logic: "and" },
      { field_id: "", operator: "is_not_empty", value: "", logic: "or" },
    ]
    const f = field({ id: "f1", conditions })
    const other = field({ id: "f2", label: "Other" }) // non-matching field option (selected ternary's false branch)
    const { pm, ctrl } = newPM([f, other])
    withConditions(ctrl)
    pm.renderConditionsUI(f)
    const html = ctrl.conditionsContainerTarget.innerHTML
    expect(html).toContain('value="f2"') // present but not selected, since no condition targets it
    expect(html).not.toMatch(/value="f2" selected/)
    expect(html).toContain('value="not_equals" selected')
    expect(html).toContain('value="not_contains" selected')
    expect(html).toContain('value="greater_than" selected')
    expect(html).toContain('value="less_than" selected')
    expect(html).toContain('value="is_empty" selected')
    expect(html).toContain('value="is_not_empty" selected')
    expect(html).toContain('OR')
    expect(html).toContain('AND')

    // is_empty condition's value input carries the "hidden" class
    const items = ctrl.conditionsContainerTarget.querySelectorAll(".condition-item")
    const isEmptyItem = items[4]
    const valueInput = isEmptyItem.querySelector("[data-property='value']")
    expect(valueInput.classList.contains("hidden")).toBe(true)

    // non-first conditions render the logic select; the first does not
    expect(items[0].querySelector("[data-property='logic']")).toBeNull()
    expect(items[1].querySelector("[data-property='logic']")).not.toBeNull()
  })
})
