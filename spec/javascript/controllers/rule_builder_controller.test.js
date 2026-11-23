import { describe, it, expect, beforeEach, vi } from "vitest"
import Controller from "controllers/rule_builder_controller"
import { ConditionEvaluator } from "lib/condition_evaluator"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

const FIELDS = [
  { id: "age", label: "Age", type: "integer" },
  { id: "name", label: "Name", type: "string" },
  { id: "color", label: "Color", type: "select", options: [{ value: "r", label: "Red" }, "blue"] },
  { id: "active", label: "Active", type: "boolean" },
  { id: "born", label: "Born", type: "date" },
]
const PAGES = [{ id: "p1", name: "Page One" }, { id: "p2" }]

function buildHtml({ rule = null, fields = FIELDS, actionFields = null, pages = PAGES, ruleId = "rule-9", omit = [] } = {}) {
  const has = (name) => !omit.includes(name)
  return `
    <div data-controller="rule-builder"
         ${ruleId ? `data-rule-id="${ruleId}"` : ""}
         data-rule-builder-fields-value='${JSON.stringify(fields)}'
         ${actionFields ? `data-rule-builder-action-fields-value='${JSON.stringify(actionFields)}'` : ""}
         data-rule-builder-pages-value='${JSON.stringify(pages)}'
         ${rule ? `data-rule-builder-rule-value='${JSON.stringify(rule)}'` : ""}>
      ${has("ruleName") ? `<input data-rule-builder-target="ruleName">` : ""}
      <input type="checkbox" data-rule-builder-target="testToggle">
      <div data-rule-builder-target="testPanel" class="hidden"></div>
      ${has("sampleInputs") ? `<div data-rule-builder-target="sampleInputs"></div>` : ""}
      ${has("conditionsLogic") ? `<select data-rule-builder-target="conditionsLogic"><option value="all">all</option><option value="any">any</option></select>` : ""}
      ${has("conditionGroups") ? `<div data-rule-builder-target="conditionGroups"></div>` : ""}
      ${has("ruleActions") ? `<div data-rule-builder-target="ruleActions"></div>` : ""}
    </div>`
}

async function mount(opts = {}) {
  const { application, element } = await mountController("rule-builder", Controller, buildHtml(opts))
  await tick()
  const ctrl = controllerFor(application, element, "rule-builder")
  return { application, element, ctrl }
}

// happy-dom's Element#remove() throws "not a child of this node" for some
// elements created via innerHTML template strings (internal children-cache
// bug) — detach via the parentNode API instead, which works reliably.
function detach(el) {
  el.parentNode.removeChild(el)
}

describe("rule-builder — pure helpers", () => {
  let ctrl
  beforeEach(async () => { ({ ctrl } = await mount()) })

  it("normalizeType buckets raw types", () => {
    expect(ctrl.normalizeType("integer")).toBe("number")
    expect(ctrl.normalizeType("currency")).toBe("number")
    expect(ctrl.normalizeType("datetime")).toBe("date")
    expect(ctrl.normalizeType("multi-select")).toBe("select")
    expect(ctrl.normalizeType("radio")).toBe("radio")
    expect(ctrl.normalizeType("checkbox")).toBe("boolean")
    expect(ctrl.normalizeType("text")).toBe("default")
    expect(ctrl.normalizeType(null)).toBe("default")
  })

  it("parseValue coerces booleans and numbers, keeps strings", () => {
    expect(ctrl.parseValue("true")).toBe(true)
    expect(ctrl.parseValue("false")).toBe(false)
    expect(ctrl.parseValue("42")).toBe(42)
    expect(ctrl.parseValue("3.5")).toBe(3.5)
    expect(ctrl.parseValue("abc")).toBe("abc")
    expect(ctrl.parseValue("42abc")).toBe("42abc") // not a clean number
  })

  it("valueEditorKind maps operator+field type", () => {
    const num = FIELDS[0], sel = FIELDS[2], bool = FIELDS[3], date = FIELDS[4], str = FIELDS[1]
    expect(ctrl.valueEditorKind("is_empty", num)).toBe("none")
    expect(ctrl.valueEditorKind("between", num)).toBe("number_range")
    expect(ctrl.valueEditorKind("equals", num)).toBe("number")
    expect(ctrl.valueEditorKind("between", date)).toBe("date_range")
    expect(ctrl.valueEditorKind("equals", sel)).toBe("select")
    expect(ctrl.valueEditorKind("equals", bool)).toBe("boolean")
    expect(ctrl.valueEditorKind("contains", str)).toBe("text")
  })

  it("actionFields falls back to fields when actionFieldsValue is empty", () => {
    expect(ctrl.actionFields).toEqual(FIELDS)
  })
})

describe("rule-builder — condition group/item DOM building", () => {
  let element, ctrl
  beforeEach(async () => { ({ element, ctrl } = await mount()) })

  it("addConditionGroup appends a group with logic select + add-condition button", () => {
    ctrl.addConditionGroup()
    const group = element.querySelector('[data-condition-group="0"]')
    expect(group).toBeTruthy()
    expect(group.querySelector('[data-group-logic="0"]')).toBeTruthy()
  })

  it("addConditionItem builds field/operator/value controls populated from fieldsValue", () => {
    ctrl.addConditionGroup()
    ctrl.addConditionItem({ currentTarget: { dataset: { groupIndex: "0" } } })
    const item = element.querySelector('[data-condition-item="0-0"]')
    expect(item).toBeTruthy()
    const fieldSelect = item.querySelector('[data-condition-field="0-0"]')
    // blank + 5 fields
    expect(fieldSelect.querySelectorAll("option").length).toBe(FIELDS.length + 1)
  })

  it("onConditionFieldChange narrows operators and swaps the value editor for the type", () => {
    ctrl.addConditionGroup()
    ctrl.addConditionItem({ currentTarget: { dataset: { groupIndex: "0" } } })
    const fieldSelect = element.querySelector('[data-condition-field="0-0"]')
    fieldSelect.value = "age" // number
    ctrl.onConditionFieldChange({ currentTarget: fieldSelect })
    const opSelect = element.querySelector('[data-condition-operator="0-0"]')
    expect([...opSelect.options].map(o => o.value)).toContain("greater_than")
    // number field default op "equals" -> number input
    expect(element.querySelector('[data-condition-value="0-0"]').type).toBe("number")
  })

  it("onConditionOperatorChange -> between renders a min/max range editor", () => {
    ctrl.addConditionGroup()
    ctrl.addConditionItem({ currentTarget: { dataset: { groupIndex: "0" } } })
    const fieldSelect = element.querySelector('[data-condition-field="0-0"]')
    fieldSelect.value = "age"
    ctrl.onConditionFieldChange({ currentTarget: fieldSelect })
    const opSelect = element.querySelector('[data-condition-operator="0-0"]')
    opSelect.value = "between"
    ctrl.onConditionOperatorChange({ currentTarget: opSelect })
    expect(element.querySelector('[data-condition-value="0-0"]')).toBeTruthy()
    expect(element.querySelector('[data-condition-value-max="0-0"]')).toBeTruthy()
  })

  it("select field's default operator is_selected renders no value editor", () => {
    ctrl.addConditionGroup()
    ctrl.addConditionItem({ currentTarget: { dataset: { groupIndex: "0" } } })
    const fieldSelect = element.querySelector('[data-condition-field="0-0"]')
    fieldSelect.value = "color"
    ctrl.onConditionFieldChange({ currentTarget: fieldSelect })
    // select-type default op is "is_selected" (no value)
    expect(element.querySelector('[data-condition-value="0-0"]')).toBeNull()
  })

  it("select field with 'equals' renders a <select> value editor from the field options", () => {
    ctrl.addConditionGroup()
    ctrl.addConditionItem({ currentTarget: { dataset: { groupIndex: "0" } } })
    const fieldSelect = element.querySelector('[data-condition-field="0-0"]')
    fieldSelect.value = "color"
    ctrl.onConditionFieldChange({ currentTarget: fieldSelect })
    const opSelect = element.querySelector('[data-condition-operator="0-0"]')
    opSelect.value = "equals"
    ctrl.onConditionOperatorChange({ currentTarget: opSelect })
    const valueEl = element.querySelector('[data-condition-value="0-0"]')
    expect(valueEl.tagName).toBe("SELECT")
    // blank + Red + blue
    expect([...valueEl.options].map(o => o.value)).toEqual(["", "r", "blue"])
  })

  it("removeConditionItem / removeConditionGroup detach elements", () => {
    ctrl.addConditionGroup()
    ctrl.addConditionItem({ currentTarget: { dataset: { groupIndex: "0" } } })
    ctrl.removeConditionItem({ currentTarget: { dataset: { groupIndex: "0", itemIndex: "0" } } })
    expect(element.querySelector('[data-condition-item="0-0"]')).toBeNull()
    ctrl.removeConditionGroup({ currentTarget: { dataset: { groupIndex: "0" } } })
    expect(element.querySelector('[data-condition-group="0"]')).toBeNull()
  })
})

describe("rule-builder — action DOM building", () => {
  let element, ctrl
  beforeEach(async () => { ({ element, ctrl } = await mount()) })

  it("addAction appends an action row with field targets", () => {
    ctrl.addAction({ currentTarget: {} })
    const item = element.querySelector('[data-action-item="0"]')
    expect(item).toBeTruthy()
    expect(item.querySelector('[data-action-type="0"]')).toBeTruthy()
    expect(item.querySelector('[data-action-target="0"]')).toBeTruthy()
  })

  // NOTE: happy-dom doesn't refresh <select>.selectedOptions on a *repeated*
  // value write, so each of these drives a fresh action row where the FIRST
  // selection is reliable.
  it("onActionTypeChange with a page action populates the target with pages", () => {
    ctrl.addAction({ currentTarget: {} })
    const typeSelect = element.querySelector('[data-action-type="0"]')
    typeSelect.value = "skip_to_page" // target=page (first write — reliable)
    ctrl.onActionTypeChange({ currentTarget: typeSelect })
    const targetSelect = element.querySelector('[data-action-target="0"]')
    expect([...targetSelect.options].map(o => o.textContent)).toContain("Page One")
  })

  it("onActionTypeChange with a has-value action adds a value input", () => {
    ctrl.addAction({ currentTarget: {} })
    const typeSelect = element.querySelector('[data-action-type="0"]')
    typeSelect.value = "set_value" // hasValue=true (first write)
    ctrl.onActionTypeChange({ currentTarget: typeSelect })
    expect(element.querySelector('[data-action-value="0"]')).toBeTruthy()
  })

  it("onActionTypeChange removes an existing value input for a no-value action", () => {
    ctrl.addAction({ currentTarget: {} })
    const row = element.querySelector('[data-action-item="0"]')
    // Seed a value input, then select the default no-value action (show_field is
    // the first, already-selected option) and re-run — it should be removed.
    const seeded = document.createElement("input")
    seeded.dataset.actionValue = "0"
    row.appendChild(seeded)
    const typeSelect = element.querySelector('[data-action-type="0"]')
    ctrl.onActionTypeChange({ currentTarget: typeSelect })
    expect(element.querySelector('[data-action-value="0"]')).toBeNull()
  })
})

describe("rule-builder — serialization (getRule)", () => {
  let element, ctrl
  beforeEach(async () => { ({ element, ctrl } = await mount()) })

  it("collects conditions and actions into a rule object", () => {
    ctrl.conditionsLogicTarget.value = "any"
    ctrl.addConditionGroup()
    ctrl.addConditionItem({ currentTarget: { dataset: { groupIndex: "0" } } })
    element.querySelector('[data-condition-field="0-0"]').value = "age"
    element.querySelector('[data-condition-operator="0-0"]').value = "equals"
    element.querySelector('[data-condition-value="0-0"]').value = "30"

    ctrl.addAction({ currentTarget: {} })
    element.querySelector('[data-action-type="0"]').value = "show_field"
    element.querySelector('[data-action-target="0"]').value = "name"

    const rule = ctrl.getRule()
    expect(rule.id).toBe("rule-9")
    expect(rule.conditions).toEqual({
      logic: "any",
      groups: [{ logic: "all", items: [{ field_id: "age", operator: "equals", value: 30 }] }],
    })
    expect(rule.actions).toEqual([{ type: "show_field", target_id: "name" }])
  })

  it("collectConditions ignores items without a chosen field", () => {
    ctrl.addConditionGroup()
    ctrl.addConditionItem({ currentTarget: { dataset: { groupIndex: "0" } } })
    // leave field empty
    expect(ctrl.collectConditions().groups).toEqual([])
  })
})

describe("rule-builder — hydration & test mode", () => {
  it("hydrate() rebuilds name/conditions/actions from a saved rule on connect", async () => {
    const rule = {
      name: "My Rule",
      conditions: { logic: "any", groups: [{ logic: "all", items: [{ field_id: "age", operator: "greater_than", value: 18 }] }] },
      actions: [{ type: "show_field", target_id: "name" }],
    }
    const { ctrl } = await mount({ rule })
    expect(ctrl.ruleNameTarget.value).toBe("My Rule")
    const rebuilt = ctrl.getRule()
    expect(rebuilt.name).toBe("My Rule")
    expect(rebuilt.conditions.groups[0].items[0]).toMatchObject({ field_id: "age", operator: "greater_than" })
    expect(rebuilt.actions[0]).toMatchObject({ type: "show_field", target_id: "name" })
  })

  it("runTest marks actionResult badges as fires/skipped from the evaluator", async () => {
    const { element, ctrl } = await mount()
    ctrl.addConditionGroup()
    ctrl.addConditionItem({ currentTarget: { dataset: { groupIndex: "0" } } })
    element.querySelector('[data-condition-field="0-0"]').value = "age"
    element.querySelector('[data-condition-operator="0-0"]').value = "equals"
    element.querySelector('[data-condition-value="0-0"]').value = "30"
    ctrl.addAction({ currentTarget: {} })

    // No sample values -> age undefined != 30 -> skipped
    ctrl.runTest()
    let badge = element.querySelector('[data-rule-builder-target="actionResult"]')
    expect(badge.textContent).toContain("skipped")

    // Provide a matching sample value -> fires
    ctrl.buildSampleInputs()
    const sample = element.querySelector('[data-sample-field="age"]')
    sample.value = "30"
    ctrl.runTest()
    badge = element.querySelector('[data-rule-builder-target="actionResult"]')
    expect(badge.textContent).toContain("fires")
  })

  it("toggleTest reveals the panel and builds sample inputs when switched on", async () => {
    const { element, ctrl } = await mount()
    ctrl.addConditionGroup()
    ctrl.addConditionItem({ currentTarget: { dataset: { groupIndex: "0" } } })
    element.querySelector('[data-condition-field="0-0"]').value = "age"
    ctrl.testToggleTarget.checked = true
    ctrl.toggleTest()
    expect(ctrl.testPanelTarget.classList.contains("hidden")).toBe(false)
    expect(element.querySelector('[data-sample-field="age"]')).toBeTruthy()
  })

})

describe("rule-builder — escapeHtml", () => {
  let ctrl
  beforeEach(async () => { ({ ctrl } = await mount()) })

  it("escapes markup-significant characters and coerces null/undefined to empty string", () => {
    const escaped = ctrl.escapeHtml(`<b>tom & jerry</b>`)
    expect(escaped).not.toContain("<b>")
    expect(escaped).toContain("&lt;b&gt;")
    expect(escaped).toContain("&amp;")
    expect(ctrl.escapeHtml(null)).toBe("")
    expect(ctrl.escapeHtml(undefined)).toBe("")
    expect(ctrl.escapeHtml(42)).toBe("42")
  })
})

describe("rule-builder — runTest catch branch", () => {
  it("swallows a throwing ConditionEvaluator and marks actions as skipped", async () => {
    const { element, ctrl } = await mount()
    ctrl.addAction({ currentTarget: {} })
    const spy = vi.spyOn(ConditionEvaluator.prototype, "evaluate").mockImplementation(() => {
      throw new Error("boom")
    })
    ctrl.runTest()
    spy.mockRestore()
    const badge = element.querySelector('[data-rule-builder-target="actionResult"]')
    expect(badge.textContent).toContain("skipped")
  })
})

describe("rule-builder — actionFields value branch", () => {
  it("uses actionFieldsValue directly when it has entries", async () => {
    const customActionFields = [{ id: "x", label: "X" }]
    const { ctrl } = await mount({ actionFields: customActionFields })
    expect(ctrl.actionFields).toEqual(customActionFields)
  })
})

describe("rule-builder — connect() idempotency", () => {
  it("connect() early-returns once already hydrated (no double hydrate)", async () => {
    const rule = { name: "R", conditions: {}, actions: [] }
    const { ctrl } = await mount({ rule })
    const hydrateSpy = vi.spyOn(ctrl, "hydrate")
    ctrl.connect()
    expect(hydrateSpy).not.toHaveBeenCalled()
  })
})

describe("rule-builder — hydrate() falsy-field branches", () => {
  it("no-ops name/logic/groups/actions when the rule omits them entirely", async () => {
    // rule has one key (conditions) so hasRuleValue's Object.keys check passes,
    // but conditions itself is missing groups/logic and actions is absent —
    // exercises every `|| fallback` inside hydrate().
    const { ctrl } = await mount({ rule: { conditions: {} } })
    expect(ctrl.ruleNameTarget.value).toBe("")
    expect(ctrl.conditionsLogicTarget.value).toBe("all")
    expect(ctrl.conditionGroupsTarget.children.length).toBe(0)
    expect(ctrl.ruleActionsTarget.children.length).toBe(0)
  })

  it("hydrates a group with no items key and an item with an array value into min/max inputs", async () => {
    // "age" (number) is used rather than a date field: happy-dom rejects a
    // non-YYYY-MM-DD string written to <input type="date">.value (silently
    // resets to ""), so a numeric field is needed to observe the assignment.
    const rule = {
      conditions: {
        groups: [
          { items: [{ field_id: "age", operator: "between", value: [10, 20] }] },
          {}, // group with no items key at all -> exercises `(group.items || [])`
        ],
      },
    }
    const { element, ctrl } = await mount({ rule })
    const rebuilt = ctrl.getRule()
    expect(rebuilt.conditions.groups[0].items[0].value).toEqual([10, 20])
    expect(element.querySelector('[data-condition-value="0-0"]').value).toBe("10")
    expect(element.querySelector('[data-condition-value-max="0-0"]').value).toBe("20")
    // Second (item-less) group produced no condition items and thus is dropped by getRule.
    expect(rebuilt.conditions.groups.length).toBe(1)
  })

  it("hydrates an action with a value (set_value) and one without (set_required, value omitted)", async () => {
    const rule = {
      actions: [
        { type: "set_value", target_id: "name", value: "hello" },
        { type: "set_required", target_id: "age" },
      ],
    }
    const { element, ctrl } = await mount({ rule })
    const valueInputs = element.querySelectorAll('[data-action-value]')
    expect(valueInputs.length).toBe(2)
    expect(valueInputs[0].value).toBe("hello")
    expect(valueInputs[1].value).toBe("")
  })

  it("falls back to an empty string for null/undefined array-value entries when the min/max inputs exist", async () => {
    const rule = {
      conditions: {
        groups: [{ items: [{ field_id: "age", operator: "between", value: [null, undefined] }] }],
      },
    }
    const { element } = await mount({ rule })
    expect(element.querySelector('[data-condition-value="0-0"]').value).toBe("")
    expect(element.querySelector('[data-condition-value-max="0-0"]').value).toBe("")
  })

  it("silently skips assigning an array value when the item's kind has no value editor at all", async () => {
    // "color" (select) + "is_empty" -> valueEditorKind "none": no valEl/valMaxEl
    // are rendered, so hydrate's array-value branch has nothing to assign to.
    const rule = {
      conditions: {
        groups: [{ items: [{ field_id: "color", operator: "is_empty", value: [] }] }],
      },
    }
    const { element, ctrl } = await mount({ rule })
    expect(element.querySelector('[data-condition-value="0-0"]')).toBeNull()
    expect(element.querySelector('[data-condition-value-max="0-0"]')).toBeNull()
    expect(ctrl.getRule().conditions.groups[0].items[0].operator).toBe("is_empty")
  })
})

describe("rule-builder — buildSampleInputs edge branches", () => {
  it("returns immediately when there is no sampleInputs target", async () => {
    const { ctrl } = await mount({ omit: ["sampleInputs"] })
    expect(() => ctrl.buildSampleInputs()).not.toThrow()
    expect(ctrl.hasSampleInputsTarget).toBe(false)
  })

  it("tolerates a rule with no conditions object and groups with no items", async () => {
    const { element, ctrl } = await mount()
    const spy = vi.spyOn(ctrl, "getRule").mockReturnValue({ conditions: undefined, actions: [] })
    expect(() => ctrl.buildSampleInputs()).not.toThrow()
    expect(element.querySelector('[data-rule-builder-target="sampleInputs"]').children.length).toBe(0)

    spy.mockReturnValue({ conditions: { groups: [{}] }, actions: [] })
    expect(() => ctrl.buildSampleInputs()).not.toThrow()
    spy.mockRestore()
  })

  it("falls back to the raw field_id as the label when the field is unknown or labelless", async () => {
    const { element, ctrl } = await mount({ fields: [...FIELDS, { id: "bare" }] })
    const spy = vi.spyOn(ctrl, "getRule").mockReturnValue({
      conditions: { groups: [{ items: [{ field_id: "ghost" }, { field_id: "bare" }] }] },
      actions: [],
    })
    ctrl.buildSampleInputs()
    spy.mockRestore()
    expect(element.querySelector('[data-sample-field="ghost"]').closest("div").querySelector("label").textContent).toBe("ghost")
    expect(element.querySelector('[data-sample-field="bare"]').closest("div").querySelector("label").textContent).toBe("bare")
  })
})

describe("rule-builder — getRule() / collectConditions() / collectActions() edge branches", () => {
  it("falls back to a null id and an empty name when there's no rule-id attribute or ruleName target", async () => {
    const { ctrl } = await mount({ ruleId: null, omit: ["ruleName"] })
    const rule = ctrl.getRule()
    expect(rule.id).toBeUndefined()
    expect(rule.name).toBe("")
  })

  it("falls back to 'all' logic when there's no conditionsLogic target", async () => {
    const { element, ctrl } = await mount({ omit: ["conditionsLogic"] })
    ctrl.addConditionGroup()
    ctrl.addConditionItem({ currentTarget: { dataset: { groupIndex: "0" } } })
    element.querySelector('[data-condition-field="0-0"]').value = "age"
    expect(ctrl.collectConditions().logic).toBe("all")
  })

  it("falls back group logic to 'all' when the group has no logic select in the DOM", async () => {
    const { element, ctrl } = await mount()
    ctrl.addConditionGroup()
    // Remove the group logic <select> to force the optional-chaining fallback.
    detach(element.querySelector('[data-group-logic="0"]'))
    ctrl.addConditionItem({ currentTarget: { dataset: { groupIndex: "0" } } })
    element.querySelector('[data-condition-field="0-0"]').value = "age"
    const conditions = ctrl.collectConditions()
    expect(conditions.groups[0].logic).toBe("all")
  })

  it("falls back operator to 'equals' when the operator select is missing", async () => {
    const { element, ctrl } = await mount()
    ctrl.addConditionGroup()
    ctrl.addConditionItem({ currentTarget: { dataset: { groupIndex: "0" } } })
    element.querySelector('[data-condition-field="0-0"]').value = "age"
    detach(element.querySelector('[data-condition-operator="0-0"]'))
    const conditions = ctrl.collectConditions()
    expect(conditions.groups[0].items[0].operator).toBe("equals")
  })

  it("collectActions includes action.value only when a value input exists", async () => {
    const { element, ctrl } = await mount()
    ctrl.addAction({ currentTarget: {} })
    const typeSelect = element.querySelector('[data-action-type="0"]')
    typeSelect.value = "set_value"
    ctrl.onActionTypeChange({ currentTarget: typeSelect })
    element.querySelector('[data-action-target="0"]').value = "name"
    element.querySelector('[data-action-value="0"]').value = "hi"
    const actions = ctrl.collectActions()
    expect(actions[0]).toEqual({ type: "set_value", target_id: "name", value: "hi" })
  })
})

describe("rule-builder — onConditionFieldChange / onConditionOperatorChange edge branches", () => {
  it("onConditionFieldChange no-ops when the row for the field's key no longer exists", async () => {
    const { ctrl } = await mount()
    expect(() => ctrl.onConditionFieldChange({
      currentTarget: { dataset: { conditionField: "9-9" }, value: "age" },
    })).not.toThrow()
  })

  it("onConditionFieldChange skips rebuilding the operator list when it has no operator element", async () => {
    const { element, ctrl } = await mount()
    ctrl.addConditionGroup()
    ctrl.addConditionItem({ currentTarget: { dataset: { groupIndex: "0" } } })
    detach(element.querySelector('[data-condition-operator="0-0"]'))
    const fieldSelect = element.querySelector('[data-condition-field="0-0"]')
    fieldSelect.value = "age"
    expect(() => ctrl.onConditionFieldChange({ currentTarget: fieldSelect })).not.toThrow()
    expect(element.querySelector('[data-condition-operator="0-0"]')).toBeNull()
  })

  it("date field's default (non-between) operator renders a plain date input; between renders a date range", async () => {
    const { element, ctrl } = await mount()
    ctrl.addConditionGroup()
    ctrl.addConditionItem({ currentTarget: { dataset: { groupIndex: "0" } } })
    const fieldSelect = element.querySelector('[data-condition-field="0-0"]')
    fieldSelect.value = "born"
    ctrl.onConditionFieldChange({ currentTarget: fieldSelect })
    expect(element.querySelector('[data-condition-value="0-0"]').type).toBe("date")

    ctrl.onConditionOperatorChange({ currentTarget: { value: "between", dataset: { conditionOperator: "0-0" } } })
    expect(element.querySelector('[data-condition-value="0-0"]')).toBeTruthy()
    expect(element.querySelector('[data-condition-value-max="0-0"]')).toBeTruthy()
  })

  it("onConditionOperatorChange no-ops when the row for the key no longer exists", async () => {
    const { ctrl } = await mount()
    expect(() => ctrl.onConditionOperatorChange({
      currentTarget: { value: "equals", dataset: { conditionOperator: "9-9" } },
    })).not.toThrow()
  })

  it("a non-empty operator on a boolean field renders the boolean select (not the 'none' editor)", async () => {
    const { element, ctrl } = await mount()
    ctrl.addConditionGroup()
    ctrl.addConditionItem({ currentTarget: { dataset: { groupIndex: "0" } } })
    element.querySelector('[data-condition-field="0-0"]').value = "active"
    ctrl.onConditionOperatorChange({ currentTarget: { value: "equals", dataset: { conditionOperator: "0-0" } } })
    const valueEl = element.querySelector('[data-condition-value="0-0"]')
    expect(valueEl.tagName).toBe("SELECT")
    expect([...valueEl.options].map(o => o.value)).toEqual(["true", "false"])
  })

  it("select-kind field without an options array renders just the blank option", async () => {
    const { element, ctrl } = await mount({ fields: [...FIELDS, { id: "tags", label: "Tags", type: "multi-select" }] })
    ctrl.addConditionGroup()
    ctrl.addConditionItem({ currentTarget: { dataset: { groupIndex: "0" } } })
    element.querySelector('[data-condition-field="0-0"]').value = "tags"
    ctrl.onConditionOperatorChange({ currentTarget: { value: "equals", dataset: { conditionOperator: "0-0" } } })
    const valueEl = element.querySelector('[data-condition-value="0-0"]')
    expect(valueEl.tagName).toBe("SELECT")
    expect(valueEl.options.length).toBe(1)
  })
})

describe("rule-builder — replaceValueEditor() direct kind coverage", () => {
  it("appends (no insertBefore) when the row has no remove button", async () => {
    const { ctrl } = await mount()
    const rowEl = document.createElement("div")
    // No `[data-action*="removeConditionItem"]` present.
    expect(() => ctrl.replaceValueEditor(rowEl, "k", "text", null)).not.toThrow()
    expect(rowEl.querySelector('[data-condition-value="k"]')).toBeTruthy()
  })

  it("kind='select' with an option object lacking a label falls back to its value as the label", async () => {
    const { ctrl } = await mount()
    const rowEl = document.createElement("div")
    ctrl.replaceValueEditor(rowEl, "k", "select", { options: [{ value: "g" }] })
    const opt = rowEl.querySelector('[data-condition-value="k"]').querySelector('option[value="g"]')
    expect(opt.textContent).toBe("g")
  })

  it("kind='number' and kind='date' render the matching bare input type", async () => {
    const { ctrl } = await mount()
    const numRow = document.createElement("div")
    ctrl.replaceValueEditor(numRow, "k", "number", null)
    expect(numRow.querySelector('[data-condition-value="k"]').type).toBe("number")

    const dateRow = document.createElement("div")
    ctrl.replaceValueEditor(dateRow, "k", "date", null)
    expect(dateRow.querySelector('[data-condition-value="k"]').type).toBe("date")
  })

  it("kind='none' clears any existing editors and renders nothing new", async () => {
    const { ctrl } = await mount()
    const rowEl = document.createElement("div")
    const stale = document.createElement("input")
    stale.dataset.conditionValue = "k"
    rowEl.appendChild(stale)
    ctrl.replaceValueEditor(rowEl, "k", "none", null)
    expect(rowEl.querySelector('[data-condition-value="k"]')).toBeNull()
  })
})

describe("rule-builder — onActionTypeChange edge branches", () => {
  it("no-ops when the action row no longer exists", async () => {
    const { ctrl } = await mount()
    expect(() => ctrl.onActionTypeChange({
      currentTarget: { dataset: { actionType: "9" }, selectedOptions: [{}] },
    })).not.toThrow()
  })

  it("appends the value input (no insertBefore) when the row has no remove button", async () => {
    const { element, ctrl } = await mount()
    const row = document.createElement("div")
    row.dataset.actionItem = "9"
    const typeSel = document.createElement("select")
    typeSel.dataset.actionType = "9"
    const opt = document.createElement("option")
    opt.value = "set_value"
    opt.dataset.hasValue = "true"
    opt.dataset.target = "field"
    typeSel.appendChild(opt)
    typeSel.value = "set_value"
    row.appendChild(typeSel)
    element.querySelector('[data-rule-builder-target="ruleActions"]').appendChild(row)
    ctrl.onActionTypeChange({ currentTarget: typeSel })
    expect(row.querySelector('[data-action-value="9"]')).toBeTruthy()
  })

  it("falls back to the field id when an actionFields entry has no label", async () => {
    const { element, ctrl } = await mount({ actionFields: [{ id: "nolabel" }] })
    ctrl.addAction({ currentTarget: {} })
    const typeSelect = element.querySelector('[data-action-type="0"]')
    typeSelect.value = "show_field" // target=field (default branch)
    ctrl.onActionTypeChange({ currentTarget: typeSelect })
    const targetSelect = element.querySelector('[data-action-target="0"]')
    expect([...targetSelect.options].map(o => o.textContent)).toContain("nolabel")
  })
})

describe("rule-builder — group/item/action container-missing guards", () => {
  it("addConditionGroup no-ops without a conditionGroups target", async () => {
    const { ctrl } = await mount({ omit: ["conditionGroups"] })
    expect(ctrl.hasConditionGroupsTarget).toBe(false)
    expect(() => ctrl.addConditionGroup()).not.toThrow()
  })

  it("addConditionItem no-ops when the group's items container doesn't exist", async () => {
    const { ctrl } = await mount()
    expect(() => ctrl.addConditionItem({ currentTarget: { dataset: { groupIndex: "99" } } })).not.toThrow()
  })

  it("addAction no-ops without a ruleActions target", async () => {
    const { ctrl } = await mount({ omit: ["ruleActions"] })
    expect(ctrl.hasRuleActionsTarget).toBe(false)
    expect(() => ctrl.addAction({ currentTarget: {} })).not.toThrow()
  })

  it("addAction removes a stale empty-state placeholder before inserting a row", async () => {
    const { element, ctrl } = await mount()
    const placeholder = document.createElement("div")
    placeholder.className = "text-sm text-gray-500 text-center"
    placeholder.textContent = "No actions yet"
    ctrl.ruleActionsTarget.appendChild(placeholder)
    ctrl.addAction({ currentTarget: {} })
    expect(element.querySelector(".text-sm.text-gray-500.text-center")).toBeNull()
    expect(element.querySelector('[data-action-item="0"]')).toBeTruthy()
  })

  it("addConditionItem's field options record type + fall back to id when a field has neither type nor label", async () => {
    const { element, ctrl } = await mount({ fields: [{ id: "bare" }] })
    ctrl.addConditionGroup()
    ctrl.addConditionItem({ currentTarget: { dataset: { groupIndex: "0" } } })
    const opt = element.querySelector('[data-condition-field="0-0"]').querySelector('option[value="bare"]')
    expect(opt.dataset.fieldType).toBe("")
    expect(opt.textContent).toBe("bare")
  })

  it("addAction's initial target select falls back to id when an actionField has no label", async () => {
    const { element, ctrl } = await mount({ actionFields: [{ id: "nolabel" }] })
    ctrl.addAction({ currentTarget: {} })
    const targetSelect = element.querySelector('[data-action-target="0"]')
    expect([...targetSelect.options].map(o => o.textContent)).toContain("nolabel")
  })
})

describe("rule-builder — removeAction", () => {
  it("removes the matching action row and no-ops for an unknown index", async () => {
    const { element, ctrl } = await mount()
    ctrl.addAction({ currentTarget: {} })
    expect(element.querySelector('[data-action-item="0"]')).toBeTruthy()
    expect(() => ctrl.removeAction({ currentTarget: { dataset: { actionIndex: "99" } } })).not.toThrow()
    expect(element.querySelector('[data-action-item="0"]')).toBeTruthy()
    ctrl.removeAction({ currentTarget: { dataset: { actionIndex: "0" } } })
    expect(element.querySelector('[data-action-item="0"]')).toBeNull()
  })
})
