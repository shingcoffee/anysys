import { describe, it, expect, vi, beforeEach } from "vitest"
import { ValidatorManager, VALIDATOR_CONFIG_TYPES, VALIDATOR_CONFIG_LABELS } from "controllers/entity_form/validator_manager"
import { TemplateBuilder } from "controllers/entity_form/template_builder"
import { TypeManager } from "controllers/entity_form/type_manager"
import { buildController, fakeEvent } from "./support.js"

beforeEach(() => { globalThis.alert = vi.fn() })

describe("validator_manager — constant exports", () => {
  it("maps validator keys to config types", () => {
    expect(VALIDATOR_CONFIG_TYPES.greater_than).toBe("single_value")
    expect(VALIDATOR_CONFIG_TYPES.length_in_range).toBe("range")
    expect(VALIDATOR_CONFIG_TYPES.format_custom).toBe("pattern")
    expect(VALIDATOR_CONFIG_TYPES.inclusion).toBe("list")
    expect(VALIDATOR_CONFIG_LABELS.length_minimum).toBe("Minimum Length")
  })
})

describe("ValidatorManager#buildValidatorLabelWithConfig", () => {
  const vm = () => new ValidatorManager({})
  it("single_value appends the value", () => {
    expect(vm().buildValidatorLabelWithConfig("greater_than_or_equal_to", { value: 5 })).toBe(">= 5")
  })
  it("range shows (min-max)", () => {
    expect(vm().buildValidatorLabelWithConfig("length_in_range", { min: 1, max: 10 })).toBe("LenRange (1-10)")
  })
  it("pattern shows label: pattern", () => {
    expect(vm().buildValidatorLabelWithConfig("format_custom", { pattern: "\\d+" })).toBe("Regex: \\d+")
  })
  it("list previews first two + overflow count", () => {
    expect(vm().buildValidatorLabelWithConfig("inclusion", { values: ["a", "b"] })).toBe("InList: a, b")
    expect(vm().buildValidatorLabelWithConfig("inclusion", { values: ["a", "b", "c", "d"] })).toBe("InList: a, b... (+2)")
  })
  it("unknown config type -> base label", () => {
    expect(vm().buildValidatorLabelWithConfig("presence", null)).toBe("Required")
  })

  it("uses Stimulus validatorLabelsValue when present", () => {
    const labeled = new ValidatorManager({ validatorLabelsValue: { presence: "必填" } })
    expect(labeled.buildValidatorLabelWithConfig("presence", null)).toBe("必填")
  })
})

// Wire a controller with a validators container + real TemplateBuilder so
// appended badges land in the DOM, plus the validator config input targets.
function configController(pendingType, extraHtml = "", values = {}) {
  const { controller } = buildController(
    `<div data-entity-form-target="validatorsContainer"></div>` +
    `<select data-entity-form-target="modalValidatorSelect"><option value="">--</option></select>` +
    `<div data-entity-form-target="validatorConfigSection" class="hidden"></div>` +
    `<div data-entity-form-target="validatorSingleValueConfig" class="hidden"></div>` +
    `<div data-entity-form-target="validatorRangeConfig" class="hidden"></div>` +
    `<div data-entity-form-target="validatorPatternConfig" class="hidden"></div>` +
    `<div data-entity-form-target="validatorListConfig" class="hidden"></div>` +
    extraHtml,
    { values: { pendingValidator: pendingType ? { type: pendingType } : null, ...values } }
  )
  controller.templateBuilder = new TemplateBuilder(controller)
  controller.typeManager = new TypeManager(controller)
  controller.validatorManager = new ValidatorManager(controller)
  return controller
}

describe("ValidatorManager#addValidatorWithConfig", () => {
  it("single_value: rejects blank, appends badge on valid value", () => {
    const c = configController("greater_than", `<input data-entity-form-target="validatorConfigValue" value="">`)
    c.validatorManager.addValidatorWithConfig(fakeEvent())
    expect(alert).toHaveBeenCalledWith("Please enter a value")
    expect(c.validatorsContainerTarget.children.length).toBe(0)

    c.validatorConfigValueTarget.value = "7"
    c.validatorManager.addValidatorWithConfig(fakeEvent())
    const badge = c.validatorsContainerTarget.querySelector("[data-validator-item]")
    expect(badge.dataset.validatorValue).toBe("greater_than")
    expect(JSON.parse(badge.dataset.validatorObject)).toEqual({
      type: "greater_than",
      config: { value: 7 }
    })
  })

  it("range: rejects min>=max", () => {
    const c = configController("length_in_range",
      `<input data-entity-form-target="validatorConfigMinValue" value="10">` +
      `<input data-entity-form-target="validatorConfigMaxValue" value="5">`)
    c.validatorManager.addValidatorWithConfig(fakeEvent())
    expect(alert).toHaveBeenCalledWith("Minimum value must be less than maximum value")
    expect(c.validatorsContainerTarget.children.length).toBe(0)
  })

  it("range: appends {min,max} when valid", () => {
    const c = configController("length_in_range",
      `<input data-entity-form-target="validatorConfigMinValue" value="2">` +
      `<input data-entity-form-target="validatorConfigMaxValue" value="8">`)
    c.validatorManager.addValidatorWithConfig(fakeEvent())
    const badge = c.validatorsContainerTarget.querySelector("[data-validator-item]")
    expect(JSON.parse(badge.dataset.validatorObject).config).toEqual({ min: 2, max: 8 })
  })

  it("pattern: rejects an invalid regex", () => {
    const c = configController("format_custom", `<input data-entity-form-target="validatorConfigPattern" value="(">`)
    c.validatorManager.addValidatorWithConfig(fakeEvent())
    expect(alert).toHaveBeenCalledWith("Invalid regex pattern")
  })

  it("list: splits lines, trims, drops blanks", () => {
    const c = configController("inclusion",
      `<textarea data-entity-form-target="validatorConfigList"> a \n\n b \nc</textarea>`)
    c.validatorManager.addValidatorWithConfig(fakeEvent())
    const badge = c.validatorsContainerTarget.querySelector("[data-validator-item]")
    expect(JSON.parse(badge.dataset.validatorObject).config).toEqual({ values: ["a", "b", "c"] })
  })

  it("does nothing when there is no pending validator and no select value", () => {
    const c = configController(null)
    c.validatorManager.addValidatorWithConfig(fakeEvent())
    expect(c.validatorsContainerTarget.children.length).toBe(0)
  })

  it("highlights instead of re-adding an already-present validator", () => {
    const c = configController("greater_than", `<input data-entity-form-target="validatorConfigValue" value="1">`)
    c.validatorsContainerTarget.innerHTML = `<div data-validator-item data-validator-value="greater_than"></div>`
    c.validatorManager.addValidatorWithConfig(fakeEvent())
    // still only the original badge (no duplicate)
    expect(c.validatorsContainerTarget.querySelectorAll("[data-validator-item]").length).toBe(1)
  })
})

describe("ValidatorManager#getSelectedValidators", () => {
  it("prefers the parsed data-validator-object, falls back to the value key, and strips legacy visibility", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="validatorsContainer">` +
      `<div data-validator-item data-validator-value="inclusion" data-validator-object='{"type":"inclusion","config":{"values":["x"]},"visibility":{"admin":true}}'></div>` +
      `<div data-validator-item data-validator-value="presence"></div>` +
      `<div data-validator-item data-validator-value="broken" data-validator-object='{bad json'></div>` +
      `</div>`
    )
    expect(new ValidatorManager(controller).getSelectedValidators()).toEqual([
      { type: "inclusion", config: { values: ["x"] } },
      { type: "presence" },
      { type: "broken" },
    ])
  })

  it("returns [] without a container", () => {
    expect(new ValidatorManager(buildController("").controller).getSelectedValidators()).toEqual([])
  })

  it("filters out validators that lack a type when collecting", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="validatorsContainer">` +
      `<div data-validator-item data-validator-object='{"config":{}}'></div>` +
      `</div>`
    )
    expect(new ValidatorManager(controller).getSelectedValidators()).toEqual([])
  })

  it("strips visibility when appending a badge from a legacy object", () => {
    const c = configController(null)
    c.validatorManager.appendValidatorBadge("presence", "Required", {
      type: "presence",
      visibility: { admin: true, member: false, public: true }
    })
    const badge = c.validatorsContainerTarget.querySelector("[data-validator-item]")
    expect(JSON.parse(badge.dataset.validatorObject)).toEqual({ type: "presence" })
    expect(badge.querySelectorAll("[data-validator-audience]").length).toBe(0)
  })

  it("delegates getSelectedOptions to the type manager", () => {
    const c = configController(null)
    c.typeManager.getSelectedOptions = vi.fn(() => [{ label: "A", value: "a" }])
    expect(c.validatorManager.getSelectedOptions()).toEqual([{ label: "A", value: "a" }])
  })

  it("syncInclusionValidator treats a missing html-type target as blank", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="validatorsContainer"></div>`,
      { values: { inclusionManuallyRemoved: false } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.templateBuilder = new TemplateBuilder(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.validatorManager.syncInclusionValidator()
    expect(controller.validatorsContainerTarget.children.length).toBe(0)
  })
})

describe("ValidatorManager#removeValidator", () => {
  it("removes the badge and flags manual inclusion removal", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="validatorsContainer">` +
      `<div data-validator-item data-validator-value="inclusion"><button></button></div>` +
      `</div>`,
      { values: { inclusionManuallyRemoved: false } }
    )
    const btn = controller.validatorsContainerTarget.querySelector("button")
    new ValidatorManager(controller).removeValidator(fakeEvent({ target: btn }))
    expect(controller.validatorsContainerTarget.querySelector("[data-validator-item]")).toBeNull()
    expect(controller.inclusionManuallyRemoved).toBe(true)
  })
})

describe("ValidatorManager#filterValidatorsByHtmlType", () => {
  it("hides disallowed options, hides empty optgroups, drops incompatible badges", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="modalValidatorSelect">` +
      `<optgroup label="num"><option value="greater_than" data-validator-key="greater_than">gt</option></optgroup>` +
      `<optgroup label="len"><option value="length_minimum" data-validator-key="length_minimum">min</option></optgroup>` +
      `</select>` +
      `<div data-entity-form-target="validatorsContainer">` +
      `<div data-validator-item data-validator-value="length_minimum"></div>` +
      `</div>`,
      { values: { htmlTypeValidatorsValue: { number: ["greater_than"] } } }
    )
    new ValidatorManager(controller).filterValidatorsByHtmlType("number")
    const opts = controller.modalValidatorSelectTarget.querySelectorAll("option[data-validator-key]")
    const gt = [...opts].find((o) => o.dataset.validatorKey === "greater_than")
    const min = [...opts].find((o) => o.dataset.validatorKey === "length_minimum")
    expect(gt.hidden).toBe(false)
    expect(min.hidden).toBe(true)
    expect(min.disabled).toBe(true)
    // incompatible badge removed
    expect(controller.validatorsContainerTarget.querySelector("[data-validator-item]")).toBeNull()
    // the "len" optgroup is fully hidden, "num" stays visible
    const groups = controller.modalValidatorSelectTarget.querySelectorAll("optgroup")
    expect(groups[0].hidden).toBe(false)
    expect(groups[1].hidden).toBe(true)
  })

  it("no mapping -> all options visible", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="modalValidatorSelect">` +
      `<option value="greater_than" data-validator-key="greater_than">gt</option></select>` +
      `<div data-entity-form-target="validatorsContainer"></div>`,
      { values: { htmlTypeValidatorsValue: {} } }
    )
    new ValidatorManager(controller).filterValidatorsByHtmlType("text")
    const opt = controller.modalValidatorSelectTarget.querySelector("option")
    expect(opt.hidden).toBe(false)
  })
})

describe("ValidatorManager#syncInclusionValidator", () => {
  it("no-ops when inclusion was manually removed", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="validatorsContainer"></div>` +
      `<select data-entity-form-target="modalHtmlType"><option value="select" selected>select</option></select>`,
      { values: { inclusionManuallyRemoved: true } }
    )
    new ValidatorManager(controller).syncInclusionValidator()
    expect(controller.validatorsContainerTarget.children.length).toBe(0)
  })

  it("builds an inclusion badge from manual option values for a selection type", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="validatorsContainer"></div>` +
      `<select data-entity-form-target="modalHtmlType"><option value="select" selected>select</option></select>` +
      `<div data-entity-form-target="optionsContainer">` +
      `<div data-option-item><input data-option-label value="Red"><input data-option-value value="red"><input type="checkbox" data-option-default></div>` +
      `</div>`,
      { values: { inclusionManuallyRemoved: false, optionsSourceMode: "manual" } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.templateBuilder = new TemplateBuilder(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.validatorManager.syncInclusionValidator()
    const badge = controller.validatorsContainerTarget.querySelector('[data-validator-value="inclusion"]')
    expect(badge).not.toBeNull()
    expect(JSON.parse(badge.dataset.validatorObject).config).toEqual({ values: ["red"] })
  })

  it("skips non-selection html types", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="validatorsContainer"></div>` +
      `<select data-entity-form-target="modalHtmlType"><option value="text" selected>text</option></select>`,
      { values: { inclusionManuallyRemoved: false } }
    )
    new ValidatorManager(controller).syncInclusionValidator()
    expect(controller.validatorsContainerTarget.children.length).toBe(0)
  })
})

describe("ValidatorManager#validatorSelectChanged / addValidator", () => {
  it("addValidator with no config type appends a plain badge and resets the select", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="modalValidatorSelect"><option value="">--</option><option value="presence" selected>Required</option></select>` +
      `<div data-entity-form-target="validatorsContainer"></div>`
    )
    controller.templateBuilder = new TemplateBuilder(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.validatorManager.addValidator(fakeEvent())
    const badge = controller.validatorsContainerTarget.querySelector("[data-validator-item]")
    expect(badge.dataset.validatorValue).toBe("presence")
    expect(controller.modalValidatorSelectTarget.selectedIndex).toBe(0)
  })

  it("validatorSelectChanged opens the config preview for a config-bearing type", () => {
    const c = configController(null,
      `<span data-entity-form-target="validatorConfigLabel"></span>` +
      `<input data-entity-form-target="validatorConfigValue">`)
    c.validatorManager.validatorSelectChanged(fakeEvent({ target: { value: "greater_than" } }))
    expect(c.validatorConfigSectionTarget.classList.contains("hidden")).toBe(false)
    expect(c.validatorSingleValueConfigTarget.classList.contains("hidden")).toBe(false)
    expect(c.pendingValidator).toEqual({ type: "greater_than" })
  })

  it("validatorSelectChanged returns for a blank value and no-ops for a config-less type", () => {
    const c = configController(null)
    c.validatorManager.validatorSelectChanged(fakeEvent({ target: { value: "" } }))
    expect(c.pendingValidator).toBeNull()
    c.validatorManager.validatorSelectChanged(fakeEvent({ target: { value: "presence" } }))
    expect(c.validatorConfigSectionTarget.classList.contains("hidden")).toBe(true)
  })

  it("validatorSelectChanged shows the range/pattern/list previews", () => {
    const c = configController(null,
      `<input data-entity-form-target="validatorConfigMinValue">` +
      `<input data-entity-form-target="validatorConfigPattern">` +
      `<span data-entity-form-target="validatorListLabel"></span>` +
      `<textarea data-entity-form-target="validatorConfigList"></textarea>`)
    c.validatorManager.validatorSelectChanged(fakeEvent({ target: { value: "length_in_range" } }))
    expect(c.validatorRangeConfigTarget.classList.contains("hidden")).toBe(false)
    c.validatorManager.validatorSelectChanged(fakeEvent({ target: { value: "format_custom" } }))
    expect(c.validatorPatternConfigTarget.classList.contains("hidden")).toBe(false)
    c.validatorManager.validatorSelectChanged(fakeEvent({ target: { value: "exclusion" } }))
    expect(c.validatorListConfigTarget.classList.contains("hidden")).toBe(false)
    expect(c.validatorListLabelTarget.textContent).toBe("Forbidden Values")
    c.validatorManager.validatorSelectChanged(fakeEvent({ target: { value: "inclusion" } }))
    expect(c.validatorListLabelTarget.textContent).toBe("Allowed Values")
  })
})

describe("ValidatorManager#addValidator config path + guards", () => {
  it("opens the config section (and focuses via setTimeout) for a config-bearing validator", () => {
    vi.useFakeTimers()
    try {
      const c = configController(null,
        `<span data-entity-form-target="validatorConfigLabel"></span>` +
        `<input data-entity-form-target="validatorConfigValue">`)
      c.modalValidatorSelectTarget.innerHTML = `<option value="greater_than" selected>gt</option>`
      const focus = vi.fn()
      c.validatorConfigValueTarget.focus = focus
      c.validatorManager.addValidator(fakeEvent())
      expect(c.validatorConfigSectionTarget.classList.contains("hidden")).toBe(false)
      expect(c.pendingValidator).toEqual({ type: "greater_than" })
      vi.runAllTimers()
      expect(focus).toHaveBeenCalled()
    } finally {
      vi.useRealTimers()
    }
  })

  it("bails without the required targets", () => {
    const { controller } = buildController(``)
    controller.validatorManager = new ValidatorManager(controller)
    expect(() => controller.validatorManager.addValidator(fakeEvent())).not.toThrow()
  })

  it("returns when no value is selected", () => {
    const c = configController(null)
    c.modalValidatorSelectTarget.innerHTML = `<option value="" selected>--</option>`
    c.validatorManager.addValidator(fakeEvent())
    expect(c.validatorsContainerTarget.children.length).toBe(0)
  })

  it("highlights an already-added validator instead of re-opening config", () => {
    const c = configController(null)
    c.modalValidatorSelectTarget.innerHTML = `<option value="greater_than" selected>gt</option>`
    c.validatorsContainerTarget.innerHTML = `<div data-validator-item data-validator-value="greater_than"></div>`
    c.validatorManager.addValidator(fakeEvent())
    expect(c.validatorsContainerTarget.querySelectorAll("[data-validator-item]").length).toBe(1)
  })
})

describe("ValidatorManager#focusConfigInput", () => {
  it("skips focusing for an unknown config type", () => {
    vi.useFakeTimers()
    try {
      const c = configController(null)
      // No mapped target for this type -> the inner focus lookup is a no-op.
      expect(() => { c.validatorManager.focusConfigInput("unknown"); vi.runAllTimers() }).not.toThrow()
    } finally {
      vi.useRealTimers()
    }
  })
})

describe("ValidatorManager#showSingleValueConfig label fallback", () => {
  it("uses a generic label when the validator has no configured label", () => {
    const c = configController(null,
      `<span data-entity-form-target="validatorConfigLabel"></span>` +
      `<input data-entity-form-target="validatorConfigValue">`)
    // equal_to has no VALIDATOR_CONFIG_LABELS entry? it does -> use a bare unknown type
    c.validatorManager.showSingleValueConfig("some_unlabeled_single")
    expect(c.validatorConfigLabelTarget.textContent).toBe("Configuration Value")
  })
})

describe("ValidatorManager#addValidatorWithConfig extra branches", () => {
  it("range: rejects when only one bound is provided", () => {
    const c = configController("length_in_range",
      `<input data-entity-form-target="validatorConfigMinValue" value="2">` +
      `<input data-entity-form-target="validatorConfigMaxValue" value="">`)
    c.validatorManager.addValidatorWithConfig(fakeEvent())
    expect(alert).toHaveBeenCalledWith("Please enter both minimum and maximum values")
  })

  it("pattern: rejects a blank pattern", () => {
    const c = configController("format_custom", `<input data-entity-form-target="validatorConfigPattern" value="">`)
    c.validatorManager.addValidatorWithConfig(fakeEvent())
    expect(alert).toHaveBeenCalledWith("Please enter a regex pattern")
  })

  it("pattern: appends a badge for a valid regex", () => {
    const c = configController("format_custom", `<input data-entity-form-target="validatorConfigPattern" value="\\d+">`)
    c.validatorManager.addValidatorWithConfig(fakeEvent())
    const badge = c.validatorsContainerTarget.querySelector("[data-validator-item]")
    expect(JSON.parse(badge.dataset.validatorObject).config).toEqual({ pattern: "\\d+" })
  })

  it("list: rejects a blank list and a whitespace-only list", () => {
    const blank = configController("inclusion", `<textarea data-entity-form-target="validatorConfigList"></textarea>`)
    blank.validatorManager.addValidatorWithConfig(fakeEvent())
    expect(alert).toHaveBeenCalledWith("Please enter at least one value")

    const spaces = configController("inclusion", `<textarea data-entity-form-target="validatorConfigList">  \n  </textarea>`)
    spaces.validatorManager.addValidatorWithConfig(fakeEvent())
    expect(alert).toHaveBeenCalledWith("Please enter at least one value")
  })

  it("falls back to the raw type when the select supplies the pending validator", () => {
    const c = configController(null)
    c.modalValidatorSelectTarget.innerHTML = `<option value="presence" selected>Required</option>`
    c.validatorManager.addValidatorWithConfig(fakeEvent())
    const badge = c.validatorsContainerTarget.querySelector("[data-validator-item]")
    expect(badge.dataset.validatorValue).toBe("presence")
  })

  it("highlights instead of re-adding when the pending validator already exists", () => {
    const c = configController("greater_than", `<input data-entity-form-target="validatorConfigValue" value="1">`)
    c.validatorsContainerTarget.innerHTML = `<div data-validator-item data-validator-value="greater_than"></div>`
    c.validatorManager.addValidatorWithConfig(fakeEvent())
    expect(c.validatorsContainerTarget.querySelectorAll("[data-validator-item]").length).toBe(1)
  })
})

describe("ValidatorManager#buildValidatorLabelWithConfig unknown type", () => {
  it("returns the raw type when there is no label and no config type", () => {
    expect(new ValidatorManager({}).buildValidatorLabelWithConfig("totally_unknown", null)).toBe("totally_unknown")
  })
})

describe("ValidatorManager#cancelValidatorConfig / handleValidatorConfigKeydown", () => {
  function keydownController() {
    const c = configController("greater_than",
      `<span data-entity-form-target="validatorConfigLabel"></span>` +
      `<input data-entity-form-target="validatorConfigValue" value="5">`)
    return c
  }

  it("cancelValidatorConfig hides the section and resets the select", () => {
    const c = keydownController()
    c.modalValidatorSelectTarget.innerHTML = `<option value="">--</option><option value="greater_than" selected>gt</option>`
    c.validatorConfigSectionTarget.classList.remove("hidden")
    c.validatorManager.cancelValidatorConfig(fakeEvent())
    expect(c.validatorConfigSectionTarget.classList.contains("hidden")).toBe(true)
    expect(c.modalValidatorSelectTarget.selectedIndex).toBe(0)
  })

  it("Enter (non-textarea) submits the config", () => {
    const c = keydownController()
    const spy = vi.spyOn(c.validatorManager, "addValidatorWithConfig")
    c.validatorManager.handleValidatorConfigKeydown({ key: "Enter", target: { tagName: "INPUT" }, preventDefault() {} })
    expect(spy).toHaveBeenCalled()
  })

  it("Enter inside a textarea does not submit", () => {
    const c = keydownController()
    const spy = vi.spyOn(c.validatorManager, "addValidatorWithConfig")
    c.validatorManager.handleValidatorConfigKeydown({ key: "Enter", target: { tagName: "TEXTAREA" }, preventDefault() {} })
    expect(spy).not.toHaveBeenCalled()
  })

  it("Escape cancels the config", () => {
    const c = keydownController()
    const spy = vi.spyOn(c.validatorManager, "cancelValidatorConfig")
    c.validatorManager.handleValidatorConfigKeydown({ key: "Escape", target: { tagName: "INPUT" }, preventDefault() {} })
    expect(spy).toHaveBeenCalled()
  })

  it("ignores other keys", () => {
    const c = keydownController()
    const add = vi.spyOn(c.validatorManager, "addValidatorWithConfig")
    const cancel = vi.spyOn(c.validatorManager, "cancelValidatorConfig")
    c.validatorManager.handleValidatorConfigKeydown({ key: "a", target: { tagName: "INPUT" } })
    expect(add).not.toHaveBeenCalled()
    expect(cancel).not.toHaveBeenCalled()
  })
})

describe("ValidatorManager#highlightExistingValidator missing badge", () => {
  it("no-ops when the badge is absent", () => {
    const { controller } = buildController(`<div data-entity-form-target="validatorsContainer"></div>`)
    expect(() => new ValidatorManager(controller).highlightExistingValidator("nope")).not.toThrow()
  })
})

describe("ValidatorManager#filterValidatorsByHtmlType guard", () => {
  it("bails without a select target", () => {
    const { controller } = buildController(``)
    expect(() => new ValidatorManager(controller).filterValidatorsByHtmlType("text")).not.toThrow()
  })

  it("treats a missing htmlTypeValidatorsValue as an empty mapping", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="modalValidatorSelect">` +
      `<option value="greater_than" data-validator-key="greater_than">gt</option></select>`
      // no htmlTypeValidatorsValue -> `|| {}` fallback
    )
    new ValidatorManager(controller).filterValidatorsByHtmlType("number")
    expect(controller.modalValidatorSelectTarget.querySelector("option").hidden).toBe(false)
  })
})

describe("ValidatorManager#syncInclusionValidator constant + edge branches", () => {
  it("builds a badge from a selected constant's options (strings and objects)", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="validatorsContainer"></div>` +
      `<select data-entity-form-target="modalHtmlType"><option value="select" selected>select</option></select>` +
      `<select data-entity-form-target="constantSelect"><option value="7" selected>c</option></select>`,
      {
        values: {
          inclusionManuallyRemoved: false,
          optionsSourceMode: "constant",
          constants: [{ id: 7, options: ["a", { value: "b" }, { label: "c" }, { value: "", label: "" }] }],
        },
      }
    )
    controller.typeManager = new TypeManager(controller)
    controller.templateBuilder = new TemplateBuilder(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.validatorManager.syncInclusionValidator()
    const badge = controller.validatorsContainerTarget.querySelector('[data-validator-value="inclusion"]')
    expect(JSON.parse(badge.dataset.validatorObject).config).toEqual({ values: ["a", "b", "c"] })
  })

  it("replaces an existing inclusion badge and uses option labels when values are blank", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="validatorsContainer">` +
      `<div data-validator-item data-validator-value="inclusion">old</div></div>` +
      `<select data-entity-form-target="modalHtmlType"><option value="select" selected>select</option></select>` +
      `<div data-entity-form-target="optionsContainer">` +
      `<div data-option-item><input data-option-label value="Green"><input data-option-value value=""><input type="checkbox" data-option-default></div>` +
      `</div>`,
      { values: { inclusionManuallyRemoved: false, optionsSourceMode: "manual" } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.templateBuilder = new TemplateBuilder(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.validatorManager.syncInclusionValidator()
    const badges = controller.validatorsContainerTarget.querySelectorAll('[data-validator-value="inclusion"]')
    expect(badges.length).toBe(1) // old removed, new added
    expect(JSON.parse(badges[0].dataset.validatorObject).config).toEqual({ values: ["Green"] })
  })

  it("bails out when there are no values to include", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="validatorsContainer"></div>` +
      `<select data-entity-form-target="modalHtmlType"><option value="select" selected>select</option></select>`,
      { values: { inclusionManuallyRemoved: false, optionsSourceMode: "manual" } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.templateBuilder = new TemplateBuilder(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.validatorManager.syncInclusionValidator()
    expect(controller.validatorsContainerTarget.children.length).toBe(0)
  })

  it("drops an existing inclusion badge in entity_entries mode", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="validatorsContainer">` +
      `<div data-validator-item data-validator-value="inclusion">old</div></div>` +
      `<select data-entity-form-target="modalHtmlType"><option value="select" selected>select</option></select>` +
      `<div data-entity-form-target="optionsContainer">` +
      `<div data-option-item><input data-option-label value="A"><input data-option-value value="a"><input type="checkbox" data-option-default></div>` +
      `</div>`,
      { values: { inclusionManuallyRemoved: false, optionsSourceMode: "entity_entries" } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.templateBuilder = new TemplateBuilder(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.validatorManager.syncInclusionValidator()
    expect(controller.validatorsContainerTarget.querySelector('[data-validator-value="inclusion"]')).toBeNull()
  })

  it("uses an empty constant id when no constantSelect target exists (and no validators container)", () => {
    // constant mode without a constantSelect target -> constantId "" -> no constant
    // found -> values empty -> early return; also no validatorsContainer target so the
    // existing-badge lookup ternary takes its null branch.
    const { controller } = buildController(
      `<select data-entity-form-target="modalHtmlType"><option value="select" selected>select</option></select>`,
      { values: { inclusionManuallyRemoved: false, optionsSourceMode: "constant", constants: [] } }
    )
    controller.typeManager = new TypeManager(controller)
    controller.templateBuilder = new TemplateBuilder(controller)
    controller.validatorManager = new ValidatorManager(controller)
    expect(() => controller.validatorManager.syncInclusionValidator()).not.toThrow()
  })
})
