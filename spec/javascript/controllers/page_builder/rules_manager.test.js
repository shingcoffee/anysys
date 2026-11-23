import { describe, it, expect, beforeEach, vi, afterEach } from "vitest"
import { RulesManager, OPERATORS, ACTION_TYPES } from "controllers/page_builder/rules_manager"
import { makeCtrl, field } from "../../support/page_builder.js"

function rulesCtrl(rules = [], fields = []) {
  const ctrl = makeCtrl({
    configuration: { rules, pages: [], calculations: [] },
    currentPage: { id: "p1", fields },
  })
  ctrl.editingRuleIdValue = ""
  ctrl.currentEditingRule = null
  ctrl.hasRulesPanelTarget = true
  ctrl.rulesPanelTarget = document.createElement("div")
  return ctrl
}

function newRM(rules = [], fields = []) {
  const ctrl = rulesCtrl(rules, fields)
  return { rm: new RulesManager(ctrl), ctrl }
}

describe("RulesManager — exported constants", () => {
  it("OPERATORS carries stable {value,label} pairs", () => {
    expect(OPERATORS.find((o) => o.value === "equals").label).toBe("Equals")
    expect(OPERATORS.every((o) => o.value && o.label)).toBe(true)
    expect(OPERATORS).toHaveLength(14)
  })

  it("ACTION_TYPES tags each action with a target kind", () => {
    expect(ACTION_TYPES.find((a) => a.value === "show_field").target).toBe("field")
    expect(ACTION_TYPES.find((a) => a.value === "skip_to_page").target).toBe("page")
  })
})

describe("RulesManager.openRuleEditor", () => {
  it("seeds a fresh rule when there is no rule id", () => {
    const { rm, ctrl } = newRM()
    rm.openRuleEditor({ currentTarget: { dataset: {} } })
    expect(ctrl.editingRuleIdValue).toBe("")
    expect(ctrl.currentEditingRule.id).toBeNull()
    expect(ctrl.currentEditingRule.conditions.groups).toHaveLength(1)
    expect(ctrl.currentEditingRule.actions).toEqual([])
  })

  it("prefills an action target when data-prefill-target-field is set", () => {
    const { rm, ctrl } = newRM()
    rm.openRuleEditor({ currentTarget: { dataset: { prefillTargetField: "fX" } } })
    expect(ctrl.currentEditingRule.actions).toEqual([{ type: "show_field", target_id: "fX" }])
  })

  it("loads and deep-clones an existing rule for editing", () => {
    const existing = { id: "r1", name: "Rule 1", enabled: true, conditions: { logic: "all", groups: [{ logic: "all", items: [] }] }, actions: [] }
    const { rm, ctrl } = newRM([existing])
    rm.openRuleEditor({ currentTarget: { dataset: { ruleId: "r1" } } })
    expect(ctrl.editingRuleIdValue).toBe("r1")
    expect(ctrl.currentEditingRule).toEqual(existing)
    expect(ctrl.currentEditingRule).not.toBe(existing) // cloned
  })

  it("repairs a rule that has no condition groups", () => {
    const broken = { id: "r2", name: "R2", conditions: { groups: [] }, actions: [] }
    const { rm, ctrl } = newRM([broken])
    rm.openRuleEditor({ currentTarget: { dataset: { ruleId: "r2" } } })
    expect(ctrl.currentEditingRule.conditions.groups).toHaveLength(1)
  })

  it("falls back to an empty object when the rule id no longer matches any rule", () => {
    const { rm, ctrl } = newRM([{ id: "other", name: "Other" }])
    rm.openRuleEditor({ currentTarget: { dataset: { ruleId: "gone" } } })
    expect(ctrl.currentEditingRule.id).toBeUndefined()
    // repaired with default condition groups since the cloned {} has none
    expect(ctrl.currentEditingRule.conditions.groups).toHaveLength(1)
  })
})

describe("RulesManager.editRule", () => {
  it("delegates to openRuleEditor", () => {
    const { rm, ctrl } = newRM()
    rm.editRule({ currentTarget: { dataset: { ruleId: "" } } })
    expect(ctrl.currentEditingRule).not.toBeNull()
    expect(ctrl.currentEditingRule.conditions.groups).toHaveLength(1)
  })
})

describe("RulesManager.renderRuleEditorModal", () => {
  function withTemplate(ctrl) {
    ctrl.hasRuleEditorModalTarget = true
    ctrl.ruleEditorModalTarget = document.createElement("div")
    const tpl = document.createElement("template")
    tpl.innerHTML =
      '<div data-controller="rule-builder">' +
      '<input data-rule-builder-target="ruleName">' +
      '<span data-rule-editor-title></span></div>'
    ctrl.hasRuleEditorTemplateTarget = true
    ctrl.ruleEditorTemplateTarget = tpl
  }

  it("clones the template and hydrates name, title, and rule data", () => {
    const { rm, ctrl } = newRM()
    withTemplate(ctrl)
    ctrl.currentEditingRule = { id: "r1", name: "My Rule", conditions: { groups: [{ items: [] }] }, actions: [] }
    rm.renderRuleEditorModal()
    const modal = ctrl.ruleEditorModalTarget
    expect(modal.querySelector("[data-rule-builder-target='ruleName']").value).toBe("My Rule")
    expect(modal.querySelector("[data-rule-editor-title]").textContent).toBe("Edit Rule")
    const rb = modal.querySelector("[data-controller~='rule-builder']")
    expect(rb.dataset.ruleId).toBe("r1")
    expect(JSON.parse(rb.dataset.ruleBuilderRuleValue).name).toBe("My Rule")
    expect(ctrl.tabManager.showDrawerEditor).toHaveBeenCalledWith("rules")
  })

  it("shows 'New Rule' for an unsaved rule", () => {
    const { rm, ctrl } = newRM()
    withTemplate(ctrl)
    ctrl.currentEditingRule = { id: null, name: "", conditions: { groups: [{ items: [] }] }, actions: [] }
    rm.renderRuleEditorModal()
    expect(ctrl.ruleEditorModalTarget.querySelector("[data-rule-editor-title]").textContent).toBe("New Rule")
  })

  it("clears the modal when no template target exists", () => {
    const { rm, ctrl } = newRM()
    ctrl.hasRuleEditorModalTarget = true
    ctrl.ruleEditorModalTarget = document.createElement("div")
    ctrl.ruleEditorModalTarget.innerHTML = "stale"
    ctrl.hasRuleEditorTemplateTarget = false
    ctrl.currentEditingRule = { conditions: { groups: [] } }
    rm.renderRuleEditorModal()
    expect(ctrl.ruleEditorModalTarget.innerHTML).toBe("")
  })
})

describe("RulesManager.closeRuleEditor", () => {
  it("resets editing state, clears the modal, and returns the drawer to the list", () => {
    const { rm, ctrl } = newRM()
    ctrl.hasRuleEditorModalTarget = true
    ctrl.ruleEditorModalTarget = document.createElement("div")
    ctrl.ruleEditorModalTarget.innerHTML = "x"
    ctrl.editingRuleIdValue = "r1"
    ctrl.currentEditingRule = { id: "r1" }
    rm.closeRuleEditor()
    expect(ctrl.editingRuleIdValue).toBe("")
    expect(ctrl.currentEditingRule).toBeNull()
    expect(ctrl.ruleEditorModalTarget.innerHTML).toBe("")
    expect(ctrl.tabManager.showDrawerList).toHaveBeenCalledWith("rules")
  })

  it("closeRuleEditorOnBackdrop only closes on a true backdrop click", () => {
    const { rm } = newRM()
    const spy = vi.spyOn(rm, "closeRuleEditor")
    const backdrop = {}
    rm.closeRuleEditorOnBackdrop({ target: backdrop, currentTarget: backdrop })
    expect(spy).toHaveBeenCalled()
    spy.mockClear()
    rm.closeRuleEditorOnBackdrop({ target: {}, currentTarget: backdrop })
    expect(spy).not.toHaveBeenCalled()
  })
})

describe("RulesManager.saveRule (fallback path, no rule-builder controller)", () => {
  function withModal(ctrl, nameValue) {
    ctrl.hasRuleEditorModalTarget = true
    ctrl.ruleEditorModalTarget = document.createElement("div")
    ctrl.ruleEditorModalTarget.innerHTML = `<input data-rule-builder-target="ruleName" value="${nameValue}">`
  }

  it("appends a new rule with a generated id", () => {
    const { rm, ctrl } = newRM()
    withModal(ctrl, "New One")
    rm.saveRule()
    expect(ctrl.configuration.rules).toHaveLength(1)
    expect(ctrl.configuration.rules[0].name).toBe("New One")
    expect(ctrl.configuration.rules[0].id).toMatch(/^rule_/)
    expect(ctrl.undoRedoManager.saveHistory).toHaveBeenCalled()
    expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
  })

  it("replaces an existing rule in place when editing", () => {
    const existing = { id: "r1", name: "Old", enabled: true, conditions: { logic: "all", groups: [] }, actions: [] }
    const { rm, ctrl } = newRM([existing])
    ctrl.editingRuleIdValue = "r1"
    withModal(ctrl, "Renamed")
    rm.saveRule()
    expect(ctrl.configuration.rules).toHaveLength(1)
    expect(ctrl.configuration.rules[0].id).toBe("r1")
    expect(ctrl.configuration.rules[0].name).toBe("Renamed")
  })

  it("returns early without a modal target", () => {
    const { rm, ctrl } = newRM()
    ctrl.hasRuleEditorModalTarget = false
    rm.saveRule()
    expect(ctrl.configuration.rules).toHaveLength(0)
  })

  it("collectRuleFallback defaults an unnamed rule", () => {
    const { rm } = newRM()
    const modal = document.createElement("div")
    expect(rm.collectRuleFallback(modal).name).toBe("Unnamed rule")
  })

  it("initializes configuration.rules when it was unset", () => {
    const { rm, ctrl } = newRM()
    ctrl.configuration.rules = undefined
    withModal(ctrl, "First")
    rm.saveRule()
    expect(ctrl.configuration.rules).toHaveLength(1)
  })
})

describe("RulesManager.saveRule (rule-builder controller path)", () => {
  function withRuleBuilderModal(ctrl) {
    ctrl.hasRuleEditorModalTarget = true
    ctrl.ruleEditorModalTarget = document.createElement("div")
    ctrl.ruleEditorModalTarget.innerHTML =
      '<div data-controller="rule-builder"><input data-rule-builder-target="ruleName" value="Fallback"></div>'
  }

  it("falls back to collectRuleFallback when no Stimulus application can resolve the controller", () => {
    const { rm, ctrl } = newRM()
    withRuleBuilderModal(ctrl)
    // no ctrl.application set, so this.application resolves to window.Stimulus (undefined)
    rm.saveRule()
    expect(ctrl.configuration.rules[0].name).toBe("Fallback")
  })

  it("reads the rule from the connected rule-builder controller when available", () => {
    const { rm, ctrl } = newRM()
    withRuleBuilderModal(ctrl)
    const builtRule = { name: "From Builder", enabled: true, conditions: { logic: "all", groups: [] }, actions: [] }
    ctrl.application = {
      getControllerForElementAndIdentifier: vi.fn(() => ({ getRule: () => builtRule })),
    }
    rm.saveRule()
    expect(ctrl.configuration.rules[0].name).toBe("From Builder")
  })
})

describe("RulesManager — delete / toggle / duplicate", () => {
  afterEach(() => vi.restoreAllMocks())

  it("deleteRule removes the rule when confirmed", () => {
    vi.spyOn(window, "confirm").mockReturnValue(true)
    const { rm, ctrl } = newRM([{ id: "r1", name: "A" }, { id: "r2", name: "B" }])
    rm.deleteRule({ currentTarget: { dataset: { ruleId: "r1" } } })
    expect(ctrl.configuration.rules.map((r) => r.id)).toEqual(["r2"])
    expect(ctrl.undoRedoManager.saveHistory).toHaveBeenCalled()
  })

  it("deleteRule aborts when the confirm is declined", () => {
    vi.spyOn(window, "confirm").mockReturnValue(false)
    const { rm, ctrl } = newRM([{ id: "r1", name: "A" }])
    rm.deleteRule({ currentTarget: { dataset: { ruleId: "r1" } } })
    expect(ctrl.configuration.rules).toHaveLength(1)
  })

  it("deleteRule tolerates configuration.rules being unset", () => {
    vi.spyOn(window, "confirm").mockReturnValue(true)
    const { rm, ctrl } = newRM()
    ctrl.configuration.rules = undefined
    expect(() => rm.deleteRule({ currentTarget: { dataset: { ruleId: "r1" } } })).not.toThrow()
    expect(ctrl.configuration.rules).toEqual([])
  })

  it("toggleRule flips the enabled flag", () => {
    const { rm, ctrl } = newRM([{ id: "r1", name: "A", enabled: true }])
    rm.toggleRule({ currentTarget: { dataset: { ruleId: "r1" } } })
    expect(ctrl.configuration.rules[0].enabled).toBe(false)
    rm.toggleRule({ currentTarget: { dataset: { ruleId: "r1" } } })
    expect(ctrl.configuration.rules[0].enabled).toBe(true)
  })

  it("duplicateRule clones with a new id and '(copy)' suffix", () => {
    const { rm, ctrl } = newRM([{ id: "r1", name: "A", enabled: true, actions: [] }])
    rm.duplicateRule({ currentTarget: { dataset: { ruleId: "r1" } } })
    expect(ctrl.configuration.rules).toHaveLength(2)
    const copy = ctrl.configuration.rules[1]
    expect(copy.name).toBe("A (copy)")
    expect(copy.id).not.toBe("r1")
  })

  it("duplicateRule is a no-op for an unknown rule id", () => {
    const { rm, ctrl } = newRM([{ id: "r1", name: "A" }])
    rm.duplicateRule({ currentTarget: { dataset: { ruleId: "nope" } } })
    expect(ctrl.configuration.rules).toHaveLength(1)
  })
})

describe("RulesManager.renderRulesPanel", () => {
  it("renders an empty state when there are no rules", () => {
    const { rm, ctrl } = newRM([])
    rm.renderRulesPanel()
    expect(ctrl.rulesPanelTarget.innerHTML).toContain("No rules defined")
    expect(ctrl.rulesPanelTarget.innerHTML).toContain("0 rules configured")
  })

  it("renders a card per rule with an escaped name and a summary", () => {
    const rules = [{
      id: "r1", name: "<x>", enabled: true,
      conditions: { groups: [{ items: [{ field_id: "f1", operator: "equals" }] }] },
      actions: [{ type: "hide_field", target_id: "f2" }],
    }]
    const fields = [field({ id: "f1", label: "Age" }), field({ id: "f2", label: "SSN" })]
    const { rm, ctrl } = newRM(rules, fields)
    rm.renderRulesPanel()
    const html = ctrl.rulesPanelTarget.innerHTML
    expect(html).toContain('data-rule-id="r1"')
    expect(html).toContain("&lt;x&gt;")
    expect(html).toContain("When Age equals")
    expect(html).toContain("hide field SSN")
    expect(html).toContain("1 rule configured")
  })

  it("adds a search box only when there are more than 6 rules", () => {
    const many = Array.from({ length: 7 }, (_, i) => ({ id: `r${i}`, name: `R${i}`, enabled: true }))
    const { rm, ctrl } = newRM(many)
    rm.renderRulesPanel()
    expect(ctrl.rulesPanelTarget.innerHTML).toContain('data-filter-items="rule-id"')
  })

  it("returns early without a panel target", () => {
    const { rm, ctrl } = newRM([{ id: "r1", name: "A" }])
    ctrl.hasRulesPanelTarget = false
    expect(() => rm.renderRulesPanel()).not.toThrow()
  })

  it("treats configuration.rules being unset as an empty list", () => {
    const { rm, ctrl } = newRM()
    ctrl.configuration.rules = undefined
    expect(() => rm.renderRulesPanel()).not.toThrow()
    expect(ctrl.rulesPanelTarget.innerHTML).toContain("No rules defined")
  })

  it("falls back to the raw field id in the summary when the field can't be found", () => {
    const rules = [{
      id: "r1", name: "R1", enabled: true,
      conditions: { groups: [{ items: [{ field_id: "missing-field", operator: "equals" }] }] },
      actions: [],
    }]
    const { rm, ctrl } = newRM(rules, []) // no fields at all
    rm.renderRulesPanel()
    expect(ctrl.rulesPanelTarget.innerHTML).toContain("When missing-field equals")
  })

  it("counts a condition group with no items as zero conditions", () => {
    const rules = [{
      id: "r1", name: "R1", enabled: true,
      conditions: { groups: [{ /* no items key */ }] },
      actions: [{ type: "hide_field", target_id: "f1" }],
    }]
    const { rm, ctrl } = newRM(rules, [field({ id: "f1", label: "Age" })])
    rm.renderRulesPanel()
    // summary only shows the action clause, not a "When ..." condition clause
    expect(ctrl.rulesPanelTarget.innerHTML).toContain("hide field Age")
    expect(ctrl.rulesPanelTarget.innerHTML).not.toContain("When")
  })

  it("shows 'Unnamed rule' for a rule with no name", () => {
    const rules = [{ id: "r1", name: "", enabled: true }]
    const { rm, ctrl } = newRM(rules)
    rm.renderRulesPanel()
    expect(ctrl.rulesPanelTarget.innerHTML).toContain("Unnamed rule")
  })
})

describe("RulesManager.application getter", () => {
  it("prefers the controller's application, falling back to window.Stimulus", () => {
    const { rm, ctrl } = newRM()
    ctrl.application = { id: "app" }
    expect(rm.application).toBe(ctrl.application)
    delete ctrl.application
    window.Stimulus = { id: "global" }
    expect(rm.application).toBe(window.Stimulus)
    delete window.Stimulus
  })

  it("legacy stub handlers are inert", () => {
    const { rm } = newRM()
    expect(() => {
      rm.addConditionGroup(); rm.removeConditionGroup(); rm.addConditionItem()
      rm.removeConditionItem(); rm.addAction(); rm.removeAction(); rm.onActionTypeChange()
    }).not.toThrow()
  })
})
