import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"

// stepPickerCommit fires an async post-commit refinement that calls
// getAvailableVariables (network). Stub it so commit's synchronous behavior is
// isolated and no fetch escapes.
vi.mock("flowchart/context_variable_provider", () => ({
  getAvailableVariables: vi.fn().mockResolvedValue({ groups: [] }),
}))

// getActionConfig is real for every existing test (it drives buildStepPickerHTML
// against the installed catalog). Fake keys exercise empty / present `fields`.
vi.mock("flowchart/constants/action_registry", async (importOriginal) => {
  const actual = await importOriginal()
  const FAKES = {
    fake_action_with_fields: {
      key: "fake_action_with_fields",
      fields: [{ name: "resultVar", default: "from_fields" }],
    },
    fake_action_no_fields: {
      key: "fake_action_no_fields",
    },
  }
  return { ...actual, getActionConfig: (key) => FAKES[key] || actual.getActionConfig(key) }
})

import { makeStepManager } from "../_step_support.js"
import { getAvailableVariables } from "flowchart/context_variable_provider"
import { setActionCatalog } from "flowchart/constants/action_registry"
import { installSampleActionCatalog } from "../../../support/action_catalog.js"

describe("StepManager ActionPickerMixin", () => {
  let mgr, controller
  beforeEach(() => {
    ;({ mgr, controller } = makeStepManager())
  })

  describe("_deriveOutputVarBase", () => {
    it("maps *_models -> models, *_model -> model, else result", () => {
      expect(mgr._deriveOutputVarBase("create_models")).toBe("models")
      expect(mgr._deriveOutputVarBase("new_model")).toBe("model")
      expect(mgr._deriveOutputVarBase("send_email")).toBe("result")
    })
  })

  describe("_isCanonicalOutputVar", () => {
    it("is true only for model and contract", () => {
      expect(mgr._isCanonicalOutputVar("model")).toBe(true)
      expect(mgr._isCanonicalOutputVar("contract")).toBe(true)
      expect(mgr._isCanonicalOutputVar("result")).toBe(false)
      expect(mgr._isCanonicalOutputVar("model_2")).toBe(false)
    })
  })

  describe("_flattenActionLeaves", () => {
    it("flattens nested subOptions into encoded leaf values and builds the leaf map", () => {
      mgr._pickerLeafMap = {}
      const actions = [
        { value: "root", label: "Root", icon: "i", color: "c", description: "d", subOptions: [] },
        {
          value: "parent", label: "Parent", icon: "i2", color: "c2", description: "d2",
          subOptions: [{ value: "child", label: "Child", subOptions: [] }],
        },
      ]
      const items = mgr._flattenActionLeaves(actions, [], [])
      const values = items.map((i) => i[1])
      expect(values).toEqual(["root", "parent::child"])
      expect(items[1][0]).toBe("Parent › Child")
      expect(mgr._pickerLeafMap["parent::child"]).toMatchObject({ action: "parent", suboption: "child" })
      expect(mgr._pickerLeafMap["root"]).toMatchObject({ action: "root", suboption: "" })
    })

    it("marks a used single-use root action as disabled", () => {
      mgr._pickerLeafMap = {}
      const actions = [{ key: "once", label: "Once", singleUse: true, subOptions: [] }]
      const items = mgr._flattenActionLeaves(actions, ["once"])
      expect(items[0][2].disabled).toBe(true)
    })
  })

  describe("buildStepPickerHTML", () => {
    it("threads the translated search placeholder off the controller", () => {
      controller.stepPickerSearchPlaceholderValue = "搜索操作…"
      const html = mgr.buildStepPickerHTML()
      expect(html).toContain('placeholder="搜索操作…"')
    })

    it("defaults to the English search placeholder", () => {
      const html = mgr.buildStepPickerHTML()
      expect(html).toContain('placeholder="Search actions…"')
    })
  })

  describe("_applyResultVarAutoSuggest", () => {
    it("fills an output-var field from the derived base and suffixes on sibling collision", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item>
            <input type="hidden" data-step-config value='{"resultVar":"result"}'>
          </div>
        </div>`
      const schema = [{ key: "resultVar" }]
      const defaultConfig = {}
      mgr._applyResultVarAutoSuggest(schema, defaultConfig, "send_email")
      // base "result" collides with the sibling -> _2
      expect(defaultConfig.resultVar).toBe("result_2")
    })

    it("never suffixes the canonical names model or contract on sibling collision", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item>
            <input type="hidden" data-step-config value='{"resultVar":"model"}'>
          </div>
        </div>`
      const schema = [{ key: "resultVar" }]
      const defaultConfig = {}
      mgr._applyResultVarAutoSuggest(schema, defaultConfig, "new_model")
      expect(defaultConfig.resultVar).toBe("model")

      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item>
            <input type="hidden" data-step-config value='{"resultVar":"contract"}'>
          </div>
        </div>`
      const contractConfig = { resultVar: "contract" }
      mgr._applyResultVarAutoSuggest(schema, contractConfig, "build_contract")
      expect(contractConfig.resultVar).toBe("contract")
    })

    it("leaves non-output-var fields untouched", () => {
      const defaultConfig = { klass: "User" }
      mgr._applyResultVarAutoSuggest([{ key: "klass" }], defaultConfig, "new_model")
      expect(defaultConfig).toEqual({ klass: "User" })
    })
  })

  describe("_collectSiblingOutputVars", () => {
    it("gathers output-var values from sibling step configs, de-duplicated", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item><input data-step-config value='{"resultVar":"user"}'></div>
          <div data-step-item><input data-step-config value='{"outputKey":"token","resultVar":"user"}'></div>
          <div data-step-item><input data-step-config value='not json'></div>
        </div>`
      expect(mgr._collectSiblingOutputVars().sort()).toEqual(["token", "user"])
    })

    it("returns [] when there is no [data-steps-container]", () => {
      controller.formTarget.innerHTML = `<div>nothing here</div>`
      expect(mgr._collectSiblingOutputVars()).toEqual([])
    })
  })

  describe("_showStepPicker / _hideStepPicker", () => {
    beforeEach(() => {
      controller.formTarget.innerHTML = `
        <div data-steps-container></div>
        <div data-step-picker-mount class="hidden"></div>`
    })

    it("_showStepPicker renders the picker into the mount and unhides it", () => {
      mgr._showStepPicker()
      const mount = controller.formTarget.querySelector("[data-step-picker-mount]")
      expect(mount.classList.contains("hidden")).toBe(false)
      expect(mount.querySelector("[data-step-picker]")).toBeTruthy()
    })

    it("_hideStepPicker hides the mount and clears its inputs", () => {
      mgr._showStepPicker()
      const mount = controller.formTarget.querySelector("[data-step-picker-mount]")
      mount.querySelector("input[type='text']").value = "typed"
      mount.querySelector("input[type='hidden']").value = "val"
      mgr._hideStepPicker()
      expect(mount.classList.contains("hidden")).toBe(true)
      expect(mount.querySelector("input[type='text']").value).toBe("")
      expect(mount.querySelector("input[type='hidden']").value).toBe("")
    })

    it("_showStepPicker no-ops when there is no [data-step-picker-mount]", () => {
      controller.formTarget.innerHTML = `<div data-steps-container></div>`
      expect(() => mgr._showStepPicker()).not.toThrow()
    })

    it("_hideStepPicker no-ops when there is no [data-step-picker-mount]", () => {
      controller.formTarget.innerHTML = `<div data-steps-container></div>`
      expect(() => mgr._hideStepPicker()).not.toThrow()
    })
  })

  describe("stepPickerCommit", () => {
    beforeEach(() => {
      controller.formTarget.innerHTML = `
        <div data-steps-container></div>
        <div data-step-picker-mount>picker</div>`
      // populate the leaf map with the real registry
      mgr.buildStepPickerHTML()
    })

    it("commits a valid leaf: inserts one expanded step and dispatches stepAdded", () => {
      const spy = vi.spyOn(mgr, "_dispatchEvent")
      mgr.stepPickerCommit({ target: { value: "find_model" } })

      const items = controller.formTarget.querySelectorAll("[data-step-item]")
      expect(items.length).toBe(1)
      expect(mgr.stepIndex).toBe(1)
      expect(spy).toHaveBeenCalledWith("stepAdded")
    })

    it("ignores an empty or unknown value", () => {
      mgr.stepPickerCommit({ target: { value: "" } })
      mgr.stepPickerCommit({ target: { value: "does-not-exist" } })
      expect(controller.formTarget.querySelectorAll("[data-step-item]").length).toBe(0)
    })

    it("refuses to add a second step (one step per process)", () => {
      mgr.stepPickerCommit({ target: { value: "find_model" } })
      mgr.stepPickerCommit({ target: { value: "find_model" } })
      expect(controller.formTarget.querySelectorAll("[data-step-item]").length).toBe(1)
    })

    it("no-ops when there is no [data-steps-container] to insert into", () => {
      controller.formTarget.innerHTML = `<div data-step-picker-mount>picker</div>`
      mgr.buildStepPickerHTML()
      expect(() => mgr.stepPickerCommit({ target: { value: "find_model" } })).not.toThrow()
      expect(mgr.stepIndex).toBe(0)
    })

    // The committed card's stored config is asserted via the hidden
    // [data-step-config] JSON rather than a rendered field — buildStepConfigHTML
    // (step_manager.js) re-derives the schema for on-screen rendering with its
    // own (different) fallback rule, independent of the `schema` this mixin
    // computes for defaultConfig. Reading the stored JSON isolates what THIS
    // file's line under test actually produced.
    it("commits export field defaults from the fake catalog action", async () => {
      mgr._pickerLeafMap["fake_leaf"] = {
        action: "fake_action_with_fields", suboption: "", selectionLabels: ["Fake"],
        actionOption: { key: "fake_action_with_fields", label: "Fake" },
      }
      mgr.stepPickerCommit({ target: { value: "fake_leaf" } })
      const stored = JSON.parse(controller.formTarget.querySelector("[data-step-config]").value)
      expect(stored.resultVar).toBe("from_fields")
      await Promise.resolve()
    })

    it("stores {} when the action has no fields", async () => {
      mgr._pickerLeafMap["fake_leaf3"] = {
        action: "fake_action_no_fields", suboption: "", selectionLabels: ["Fake"],
        actionOption: { key: "fake_action_no_fields", label: "Fake" },
      }
      mgr.stepPickerCommit({ target: { value: "fake_leaf3" } })
      const stored = JSON.parse(controller.formTarget.querySelector("[data-step-config]").value)
      expect(stored).toEqual({})
      await Promise.resolve()
    })

    it("commits Find record with schema defaults", async () => {
      mgr.stepPickerCommit({ target: { value: "find_model" } })
      const stored = JSON.parse(controller.formTarget.querySelector("[data-step-config]").value)
      expect(stored.findBy).toBe("id")
      expect(stored.resultVar).toBe("model")
      await Promise.resolve()
    })

    it("commits api_call from the picker leaf map", async () => {
      mgr.buildStepPickerHTML()
      expect(mgr._pickerLeafMap["api_call"]).toBeTruthy()
      mgr.stepPickerCommit({ target: { value: "api_call" } })
      const item = controller.formTarget.querySelector("[data-step-item]")
      expect(item.dataset.stepAction).toBe("api_call")
      await Promise.resolve()
    })
  })

  describe("changeStep / stepPickerEscape", () => {
    beforeEach(() => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item data-step-id="s1"><input data-config-input value="edited"></div>
        </div>
        <div data-step-picker-mount class="hidden"></div>`
    })

    it("changeStep detaches the card into a snapshot and opens the picker", () => {
      const item = controller.formTarget.querySelector("[data-step-item]")
      mgr.changeStep({ preventDefault() {}, target: item })
      expect(mgr._changeSnapshot).toBe(item)
      expect(controller.formTarget.querySelectorAll("[data-step-item]").length).toBe(0)
      expect(controller.formTarget.querySelector("[data-step-picker-mount]").classList.contains("hidden")).toBe(false)
    })

    it("stepPickerEscape restores the detached card unchanged, stops Escape propagation, and hides the picker", () => {
      const item = controller.formTarget.querySelector("[data-step-item]")
      mgr.changeStep({ preventDefault() {}, target: item })
      const preventDefault = vi.fn()
      const stopPropagation = vi.fn()
      mgr.stepPickerEscape({ preventDefault, stopPropagation })
      expect(preventDefault).toHaveBeenCalledOnce()
      expect(stopPropagation).toHaveBeenCalledOnce()
      const restored = controller.formTarget.querySelector("[data-step-item]")
      expect(restored).toBe(item)
      expect(restored.querySelector("[data-config-input]").value).toBe("edited")
      expect(mgr._changeSnapshot).toBeNull()
    })

    it("stepPickerEscape is a no-op when nothing is pending", () => {
      expect(() => mgr.stepPickerEscape()).not.toThrow()
    })

    it("changeStep no-ops when the target is not inside a step item", () => {
      const loose = document.createElement("button")
      mgr.changeStep({ preventDefault() {}, target: loose })
      expect(mgr._changeSnapshot).toBeNull()
      expect(controller.formTarget.querySelectorAll("[data-step-item]").length).toBe(1)
    })
  })

  describe("_changeOutsideHandler (the closure armed by _armChangeOutsideClick)", () => {
    afterEach(() => mgr._disarmChangeOutsideClick())

    it("no-ops when there is no pending change snapshot", () => {
      mgr._armChangeOutsideClick()
      const escapeSpy = vi.spyOn(mgr, "stepPickerEscape")
      mgr._changeOutsideHandler({ target: document.createElement("div") })
      expect(escapeSpy).not.toHaveBeenCalled()
    })

    it("no-ops when the click lands inside the picker", () => {
      controller.formTarget.innerHTML = `<div data-step-picker><input id="search"></div>`
      mgr._changeSnapshot = document.createElement("div")
      mgr._armChangeOutsideClick()
      const escapeSpy = vi.spyOn(mgr, "stepPickerEscape")
      mgr._changeOutsideHandler({ target: controller.formTarget.querySelector("#search") })
      expect(escapeSpy).not.toHaveBeenCalled()
    })

    it("restores the snapshot when the click lands outside the picker", () => {
      mgr._changeSnapshot = document.createElement("div")
      mgr._armChangeOutsideClick()
      const escapeSpy = vi.spyOn(mgr, "stepPickerEscape")
      mgr._changeOutsideHandler({ target: document.createElement("div") })
      expect(escapeSpy).toHaveBeenCalled()
    })

    it("tolerates a target with no .closest (e.g. window/document as target)", () => {
      mgr._changeSnapshot = document.createElement("div")
      mgr._armChangeOutsideClick()
      const escapeSpy = vi.spyOn(mgr, "stepPickerEscape")
      expect(() => mgr._changeOutsideHandler({ target: {} })).not.toThrow()
      expect(escapeSpy).toHaveBeenCalled()
    })
  })

  describe("outside-click arming", () => {
    it("_armChangeOutsideClick installs a capture listener; _disarm removes it", () => {
      const addSpy = vi.spyOn(document, "addEventListener")
      const removeSpy = vi.spyOn(document, "removeEventListener")
      mgr._armChangeOutsideClick()
      expect(addSpy).toHaveBeenCalledWith("mousedown", expect.any(Function), true)
      expect(mgr._changeOutsideHandler).toBeTruthy()
      mgr._disarmChangeOutsideClick()
      expect(removeSpy).toHaveBeenCalledWith("mousedown", expect.any(Function), true)
      expect(mgr._changeOutsideHandler).toBeNull()
    })
  })

  describe("_refineOutputVarsWithUpstream", () => {
    const OUTPUT_SCHEMA = [{ key: "resultVar" }]

    const stepItemWithInput = (value) => {
      controller.formTarget.innerHTML = `
        <div data-step-item>
          <div data-config-field="resultVar"><input data-config-input value="${value}"></div>
        </div>`
      return controller.formTarget.querySelector("[data-step-item]")
    }

    beforeEach(() => {
      getAvailableVariables.mockReset()
      getAvailableVariables.mockResolvedValue({ groups: [] })
    })

    it("no-ops when stepItem is falsy", async () => {
      await mgr._refineOutputVarsWithUpstream(null, OUTPUT_SCHEMA, {})
      expect(getAvailableVariables).not.toHaveBeenCalled()
    })

    it("no-ops when the schema has no output-var field", async () => {
      const item = stepItemWithInput("result")
      await mgr._refineOutputVarsWithUpstream(item, [{ key: "klass" }], {})
      expect(getAvailableVariables).not.toHaveBeenCalled()
    })

    it("no-ops when the controller has no canvas", async () => {
      const item = stepItemWithInput("result")
      controller.canvas = null
      await mgr._refineOutputVarsWithUpstream(item, OUTPUT_SCHEMA, { resultVar: "result" })
      expect(getAvailableVariables).not.toHaveBeenCalled()
    })

    it("no-ops when the controller has no currentElement id", async () => {
      const item = stepItemWithInput("result")
      controller.currentElement = {}
      await mgr._refineOutputVarsWithUpstream(item, OUTPUT_SCHEMA, { resultVar: "result" })
      expect(getAvailableVariables).not.toHaveBeenCalled()
    })

    it("swallows a rejected getAvailableVariables call", async () => {
      const item = stepItemWithInput("result")
      getAvailableVariables.mockRejectedValueOnce(new Error("network"))
      await expect(mgr._refineOutputVarsWithUpstream(item, OUTPUT_SCHEMA, { resultVar: "result" })).resolves.toBeUndefined()
    })

    it("only collects string, non-blank variables from 'element'-sourced groups", async () => {
      const item = stepItemWithInput("result")
      getAvailableVariables.mockResolvedValueOnce({
        groups: [
          { source: "step", variables: ["result"] }, // wrong source -> ignored
          { source: "element", variables: [42, "   ", "result"] }, // non-string/blank ignored, "result" kept
        ],
      })
      const defaultConfig = { resultVar: "result" }
      await mgr._refineOutputVarsWithUpstream(item, OUTPUT_SCHEMA, defaultConfig)
      // "result" collides with the input's current value -> bumped to result_2
      expect(item.querySelector("[data-config-input]").value).toBe("result_2")
    })

    it("no-ops when no upstream variables are found at all", async () => {
      const item = stepItemWithInput("result")
      getAvailableVariables.mockResolvedValueOnce({ groups: [{ source: "element", variables: [] }] })
      await mgr._refineOutputVarsWithUpstream(item, OUTPUT_SCHEMA, { resultVar: "result" })
      expect(item.querySelector("[data-config-input]").value).toBe("result")
    })

    it("skips a schema field that is not an output-var key", async () => {
      const item = stepItemWithInput("result")
      getAvailableVariables.mockResolvedValueOnce({ groups: [{ source: "element", variables: ["result"] }] })
      await mgr._refineOutputVarsWithUpstream(item, [{ key: "klass" }, ...OUTPUT_SCHEMA], { klass: "User", resultVar: "result" })
      expect(item.querySelector("[data-config-input]").value).toBe("result_2")
    })

    it("skips when the field's input is not rendered", async () => {
      controller.formTarget.innerHTML = `<div data-step-item></div>`
      const item = controller.formTarget.querySelector("[data-step-item]")
      getAvailableVariables.mockResolvedValueOnce({ groups: [{ source: "element", variables: ["result"] }] })
      await expect(mgr._refineOutputVarsWithUpstream(item, OUTPUT_SCHEMA, { resultVar: "result" })).resolves.toBeUndefined()
    })

    it("skips when defaultConfig has no suggestion for the field", async () => {
      const item = stepItemWithInput("result")
      getAvailableVariables.mockResolvedValueOnce({ groups: [{ source: "element", variables: ["result"] }] })
      await mgr._refineOutputVarsWithUpstream(item, OUTPUT_SCHEMA, {})
      expect(item.querySelector("[data-config-input]").value).toBe("result")
    })

    it("skips when the input's live value diverges from the auto-suggestion (user already edited it)", async () => {
      const item = stepItemWithInput("user_typed")
      getAvailableVariables.mockResolvedValueOnce({ groups: [{ source: "element", variables: ["result"] }] })
      await mgr._refineOutputVarsWithUpstream(item, OUTPUT_SCHEMA, { resultVar: "result" })
      expect(item.querySelector("[data-config-input]").value).toBe("user_typed")
    })

    it("skips when the current value is not actually an upstream collision", async () => {
      const item = stepItemWithInput("result")
      getAvailableVariables.mockResolvedValueOnce({ groups: [{ source: "element", variables: ["something_else"] }] })
      await mgr._refineOutputVarsWithUpstream(item, OUTPUT_SCHEMA, { resultVar: "result" })
      expect(item.querySelector("[data-config-input]").value).toBe("result")
    })

    it("walks the _2.._9 suffix loop past sibling AND upstream collisions", async () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item>
            <div data-config-field="resultVar"><input data-config-input value="result"></div>
          </div>
          <div data-step-item><input data-step-config value='{"resultVar":"result_2"}'></div>
        </div>`
      const item = controller.formTarget.querySelectorAll("[data-step-item]")[0]
      getAvailableVariables.mockResolvedValueOnce({ groups: [{ source: "element", variables: ["result", "result_3"] }] })
      await mgr._refineOutputVarsWithUpstream(item, OUTPUT_SCHEMA, { resultVar: "result" })
      // result -> result_2 (sibling) -> result_3 (upstream) -> result_4 (free)
      expect(item.querySelector("[data-config-input]").value).toBe("result_4")
    })

    it("never suffixes the canonical names model or contract on an upstream collision", async () => {
      const item = stepItemWithInput("model")
      getAvailableVariables.mockResolvedValueOnce({ groups: [{ source: "element", variables: ["model"] }] })
      await mgr._refineOutputVarsWithUpstream(item, OUTPUT_SCHEMA, { resultVar: "model" })
      expect(item.querySelector("[data-config-input]").value).toBe("model")

      const contractItem = stepItemWithInput("contract")
      getAvailableVariables.mockResolvedValueOnce({ groups: [{ source: "element", variables: ["contract"] }] })
      await mgr._refineOutputVarsWithUpstream(contractItem, OUTPUT_SCHEMA, { resultVar: "contract" })
      expect(contractItem.querySelector("[data-config-input]").value).toBe("contract")
    })

    it("dispatches stepAdded and re-syncs the step's stored config after a rename", async () => {
      const item = stepItemWithInput("result")
      const stepConfig = document.createElement("input")
      stepConfig.setAttribute("data-step-config", "")
      item.appendChild(stepConfig)
      const dispatchSpy = vi.spyOn(mgr, "_dispatchEvent")
      const changeSpy = vi.spyOn(mgr, "handleConfigFieldChange")
      getAvailableVariables.mockResolvedValueOnce({ groups: [{ source: "element", variables: ["result"] }] })
      await mgr._refineOutputVarsWithUpstream(item, OUTPUT_SCHEMA, { resultVar: "result" })
      expect(changeSpy).toHaveBeenCalled()
      expect(dispatchSpy).toHaveBeenCalledWith("stepAdded")
    })
  })

  describe("F1 picker search, descriptions, keyboard", () => {
    const mountPicker = () => {
      controller.formTarget.innerHTML = `<div data-steps-container></div><div data-step-picker-mount></div>`
      mgr._showStepPicker()
      return controller.formTarget.querySelector("[data-step-picker]")
    }

    it("renders every category expanded with a visible one-line description", () => {
      const html = mgr.buildStepPickerHTML()
      expect(html).toContain("Find record")
      expect(html).toContain("Load one record of the bound entity by id or by an attribute.")
      expect(html).toContain("Records")
      expect(html).toContain("data-step-picker-group")
      expect(html).not.toContain("data-controller=\"searchable-select\"")
      expect(html).toContain("min-h-10")
    })

    it("filters by label, description, category, and action key", () => {
      const picker = mountPicker()
      const search = picker.querySelector("[data-step-picker-search]")
      const findOpt = () => picker.querySelector('[data-value="find_model"]')
      const empty = () => picker.querySelector("[data-step-picker-empty]")
      const list = () => picker.querySelector("[data-step-picker-list]")

      mgr.stepPickerFilter({ target: Object.assign(search, { value: "FIND RECORD" }) })
      expect(findOpt()).toBeTruthy()

      mgr.stepPickerFilter({ target: Object.assign(search, { value: "bound entity" }) })
      expect(findOpt()).toBeTruthy()

      mgr.stepPickerFilter({ target: Object.assign(search, { value: "Records" }) })
      expect(findOpt()).toBeTruthy()

      mgr.stepPickerFilter({ target: Object.assign(search, { value: "find_model" }) })
      expect(findOpt()).toBeTruthy()

      mgr.stepPickerFilter({ target: Object.assign(search, { value: "zzz_no_match" }) })
      expect(findOpt()).toBeNull()
      expect(empty().classList.contains("hidden")).toBe(false)
      expect(list().classList.contains("hidden")).toBe(true)

      mgr.stepPickerFilter({ target: Object.assign(search, { value: "" }) })
      expect(findOpt()).toBeTruthy()
      expect(empty().classList.contains("hidden")).toBe(true)
      expect(list().classList.contains("hidden")).toBe(false)
    })

    it("matches every query word in any order", () => {
      const picker = mountPicker()
      const search = picker.querySelector("[data-step-picker-search]")
      mgr.stepPickerFilter({ target: Object.assign(search, { value: "email send" }) })
      const values = [...picker.querySelectorAll("[data-step-picker-option]")].map(o => o.dataset.value)
      expect(values).toEqual(["send_template_email"])
    })

    it("ranks label matches above key, category, and description matches", () => {
      const picker = mountPicker()
      const search = picker.querySelector("[data-step-picker-search]")
      const values = () => [...picker.querySelectorAll("[data-step-picker-option]")].map(o => o.dataset.value)

      // "Query Models" matches on a label word; find_model only on its key.
      mgr.stepPickerFilter({ target: Object.assign(search, { value: "model" }) })
      expect(values()).toEqual(["query_models", "find_model"])

      // Label prefix beats description-only ("Set a ctx variable" vs "Send …").
      mgr.stepPickerFilter({ target: Object.assign(search, { value: "se" }) })
      expect(values()[0]).toBe("send_template_email")

      // An exact label wins outright.
      mgr.stepPickerFilter({ target: Object.assign(search, { value: "http request" }) })
      expect(values()[0]).toBe("api_call")
    })

    it("tags each search result with its category and bolds the matched words", () => {
      const picker = mountPicker()
      const search = picker.querySelector("[data-step-picker-search]")
      mgr.stepPickerFilter({ target: Object.assign(search, { value: "record" }) })
      const opt = picker.querySelector('[data-value="find_model"]')
      expect(opt.querySelector("[data-step-picker-option-category]").textContent).toBe("Records")
      expect(opt.querySelector("mark").textContent).toBe("record")
    })

    it("pre-highlights the best match while typing so Enter picks it", () => {
      const picker = mountPicker()
      const search = picker.querySelector("[data-step-picker-search]")
      mgr.stepPickerFilter({ target: Object.assign(search, { value: "assign" }) })
      expect(mgr._pickerHighlightIndex).toBe(0)
      const first = picker.querySelector("[data-step-picker-option]")
      expect(first.getAttribute("aria-selected")).toBe("true")

      const spy = vi.spyOn(mgr, "stepPickerSelect")
      mgr.stepPickerKeydown({ target: search, key: "Enter", preventDefault() {} })
      expect(spy.mock.calls[0][0].currentTarget.dataset.value).toBe("assign_value")

      mgr.stepPickerFilter({ target: Object.assign(search, { value: "" }) })
      expect(mgr._pickerHighlightIndex).toBe(-1)
    })

    it("narrows the list with category chips, alone or combined with a query", () => {
      const picker = mountPicker()
      const search = picker.querySelector("[data-step-picker-search]")
      const chip = (key) => picker.querySelector(`[data-step-picker-category="${key}"]`)
      const values = () => [...picker.querySelectorAll("[data-step-picker-option]")].map(o => o.dataset.value)

      expect(chip("").getAttribute("aria-pressed")).toBe("true")
      expect(chip("").textContent).toBe("All")

      const focusSpy = vi.spyOn(search, "focus")
      mgr.stepPickerCategory({ currentTarget: chip("communication") })
      expect(values()).toEqual(["api_call", "send_template_email"])
      expect(chip("communication").getAttribute("aria-pressed")).toBe("true")
      expect(chip("communication").classList.contains("bg-indigo-50")).toBe(true)
      expect(chip("").getAttribute("aria-pressed")).toBe("false")
      expect(focusSpy).toHaveBeenCalled()

      mgr.stepPickerFilter({ target: Object.assign(search, { value: "email" }) })
      expect(values()).toEqual(["send_template_email"])
      expect(picker.querySelector("[data-step-picker-option-category]")).toBeNull()

      mgr.stepPickerFilter({ target: Object.assign(search, { value: "find" }) })
      expect(values()).toEqual([])
      expect(picker.querySelector("[data-step-picker-empty]").classList.contains("hidden")).toBe(false)

      mgr.stepPickerFilter({ target: Object.assign(search, { value: "" }) })
      mgr.stepPickerCategory({ currentTarget: chip("") })
      expect(values()).toContain("find_model")
      expect(values()).toContain("api_call")
    })

    it("category and render helpers no-op without a picker or list", () => {
      expect(() => mgr.stepPickerCategory({ currentTarget: document.createElement("button") })).not.toThrow()
      expect(() => mgr.stepPickerCategory({ currentTarget: null })).not.toThrow()
      expect(() => mgr._renderPickerList(document.createElement("div"))).not.toThrow()

      const picker = mountPicker()
      picker.querySelector("[data-step-picker-empty]").remove()
      mgr.stepPickerFilter({ target: Object.assign(picker.querySelector("[data-step-picker-search]"), { value: "zzz" }) })
      expect(picker.querySelector("[data-step-picker-list]").classList.contains("hidden")).toBe(true)
    })

    it("starts with the empty state when the catalog has no actions", () => {
      setActionCatalog(null)
      const html = mgr.buildStepPickerHTML()
      installSampleActionCatalog()
      const div = document.createElement("div")
      div.innerHTML = html
      expect(div.querySelector("[data-step-picker-list]").classList.contains("hidden")).toBe(true)
      expect(div.querySelector("[data-step-picker-empty]").classList.contains("hidden")).toBe(false)
    })

    it("falls back to plain text when folding changes the label length", () => {
      expect(mgr._highlightPickerText("Cafe\u0301 <b>", ["cafe"])).toBe("Cafe\u0301 &lt;b&gt;")
      expect(mgr._highlightPickerText("a<b", [])).toBe("a&lt;b")
      expect(mgr._highlightPickerText("Save & save", ["save"]))
        .toBe('<mark class="bg-transparent font-semibold text-indigo-700">Save</mark> &amp; <mark class="bg-transparent font-semibold text-indigo-700">save</mark>')
    })

    describe("recently used", () => {
      const KEY = "anysys.flowchart.recentStepActions"
      beforeEach(() => window.localStorage.clear())
      afterEach(() => vi.restoreAllMocks())

      const groupHeadings = (picker) =>
        [...picker.querySelectorAll("[data-step-picker-group] > div:first-child")]
          .filter(el => !el.hasAttribute("role"))
          .map(el => el.textContent)

      it("shows no recent group until something has been picked", () => {
        const picker = mountPicker()
        expect(groupHeadings(picker)).not.toContain("Recently used")
      })

      it("lists remembered actions first, skipping unknown and already-used ones", () => {
        window.localStorage.setItem(KEY, JSON.stringify(["api_call", "gone_action", 7, "find_model"]))
        const picker = mountPicker()
        expect(groupHeadings(picker)[0]).toBe("Recently used")
        const recent = picker.querySelector("[data-step-picker-group]")
        expect([...recent.querySelectorAll("[data-step-picker-option]")].map(o => o.dataset.value))
          .toEqual(["api_call", "find_model"])

        mgr._pickerEntries.find(e => e.value === "api_call").meta.disabled = true
        expect(mgr._recentPickerEntries().map(e => e.value)).toEqual(["find_model"])
      })

      it("is hidden while a category chip is active", () => {
        window.localStorage.setItem(KEY, JSON.stringify(["api_call"]))
        const picker = mountPicker()
        mgr.stepPickerCategory({ currentTarget: picker.querySelector('[data-step-picker-category="model"]') })
        expect(groupHeadings(picker)).toEqual(["Records"])
      })

      it("ignores corrupt or non-array storage", () => {
        window.localStorage.setItem(KEY, "{not json")
        expect(mgr._readRecentPickerValues()).toEqual([])
        window.localStorage.setItem(KEY, JSON.stringify({ a: 1 }))
        expect(mgr._readRecentPickerValues()).toEqual([])
      })

      it("remembers committed actions most-recent first, de-duplicated, capped at five", () => {
        ;["a", "b", "c", "d", "e", "b"].forEach(v => mgr._rememberPickerValue(v))
        expect(JSON.parse(window.localStorage.getItem(KEY))).toEqual(["b", "e", "d", "c", "a"])
        mgr._rememberPickerValue("f")
        expect(JSON.parse(window.localStorage.getItem(KEY))).toEqual(["f", "b", "e", "d", "c"])
      })

      it("records the action on commit", () => {
        controller.formTarget.innerHTML = `<div data-steps-container></div><div data-step-picker-mount></div>`
        mgr.buildStepPickerHTML()
        mgr.stepPickerCommit({ target: { value: "find_model" } })
        expect(JSON.parse(window.localStorage.getItem(KEY))).toEqual(["find_model"])
      })

      it("swallows storage write failures", () => {
        const setItem = vi.fn(() => { throw new Error("quota") })
        vi.spyOn(window, "localStorage", "get").mockReturnValue({ getItem: () => null, setItem })
        expect(() => mgr._rememberPickerValue("x")).not.toThrow()
        expect(setItem).toHaveBeenCalled()
      })
    })

    it("folds combining marks so café matches cafe", () => {
      expect(mgr._foldPickerText("café")).toBe("cafe")
      expect(mgr._foldPickerText("CAFÉ")).toBe("cafe")
      expect(mgr._foldPickerText("查找记录")).toBe("查找记录")
      expect(mgr._foldPickerText("")).toBe("")
      expect(mgr._foldPickerText(null)).toBe("")
    })

    it("arrow/enter select a highlighted option; other keys and empty lists no-op", () => {
      const picker = mountPicker()
      const search = picker.querySelector("[data-step-picker-search]")
      const preventDefault = vi.fn()
      mgr.stepPickerKeydown({ target: search, key: "Tab", preventDefault })
      expect(preventDefault).not.toHaveBeenCalled()

      mgr.stepPickerKeydown({ target: search, key: "ArrowDown", preventDefault })
      expect(preventDefault).toHaveBeenCalled()
      expect(mgr._pickerHighlightIndex).toBe(0)

      mgr.stepPickerKeydown({ target: search, key: "ArrowDown", preventDefault })
      expect(mgr._pickerHighlightIndex).toBe(1)

      mgr.stepPickerKeydown({ target: search, key: "ArrowUp", preventDefault })
      expect(mgr._pickerHighlightIndex).toBe(0)

      mgr.stepPickerKeydown({ target: search, key: "ArrowUp", preventDefault })
      expect(mgr._pickerHighlightIndex).toBe(0)

      const spy = vi.spyOn(mgr, "stepPickerSelect")
      mgr.stepPickerKeydown({ target: search, key: "Enter", preventDefault })
      expect(spy).toHaveBeenCalled()
    })

    it("ArrowUp treats a missing highlight index as 0 and skips disabled/hidden-group options", () => {
      const picker = mountPicker()
      const search = picker.querySelector("[data-step-picker-search]")
      mgr._pickerHighlightIndex = undefined
      mgr.stepPickerKeydown({ target: search, key: "ArrowDown", preventDefault() {} })
      expect(mgr._pickerHighlightIndex).toBe(0)
      mgr._pickerHighlightIndex = undefined
      mgr.stepPickerKeydown({ target: search, key: "ArrowUp", preventDefault() {} })
      expect(mgr._pickerHighlightIndex).toBe(0)

      const opt = picker.querySelector("[data-step-picker-option]")
      opt.classList.add("hidden")
      expect(mgr._visiblePickerOptions(picker)).not.toContain(opt)
      opt.classList.remove("hidden")
      opt.dataset.disabled = "true"
      expect(mgr._visiblePickerOptions(picker)).not.toContain(opt)
      opt.dataset.disabled = "false"
      const group = opt.closest("[data-step-picker-group]")
      group.classList.add("hidden")
      expect(mgr._visiblePickerOptions(picker)).not.toContain(opt)
    })

    it("keyboard and filter no-op outside a picker, and Enter does nothing without a highlight", () => {
      expect(() => mgr.stepPickerFilter({ target: document.createElement("input") })).not.toThrow()
      expect(() => mgr.stepPickerKeydown({ target: document.createElement("input"), key: "ArrowDown", preventDefault() {} })).not.toThrow()

      const picker = mountPicker()
      picker.querySelectorAll("[data-step-picker-option]").forEach(opt => opt.classList.add("hidden"))
      mgr._pickerHighlightIndex = -1
      const preventDefault = vi.fn()
      mgr.stepPickerKeydown({
        target: picker.querySelector("[data-step-picker-search]"),
        key: "ArrowDown",
        preventDefault,
      })
      mgr.stepPickerKeydown({
        target: picker.querySelector("[data-step-picker-search]"),
        key: "ArrowUp",
        preventDefault,
      })
      mgr.stepPickerKeydown({
        target: picker.querySelector("[data-step-picker-search]"),
        key: "Enter",
        preventDefault,
      })
    })

    it("selects an option via click and ignores disabled or detached options", () => {
      const picker = mountPicker()
      const opt = picker.querySelector("[data-step-picker-option]")
      const hidden = picker.querySelector("input[type='hidden']")
      const onChange = vi.fn()
      hidden.addEventListener("change", onChange)
      mgr.stepPickerSelect({ currentTarget: opt, target: opt })
      expect(hidden.value).toBe(opt.dataset.value)
      expect(onChange).toHaveBeenCalled()

      mgr.stepPickerSelect({ currentTarget: null, target: document.createElement("div") })
      const disabled = document.createElement("button")
      disabled.dataset.disabled = "true"
      mgr.stepPickerSelect({ currentTarget: disabled, target: disabled })

      const orphan = document.createElement("button")
      orphan.dataset.value = "x"
      mgr.stepPickerSelect({ currentTarget: orphan, target: orphan })

      const blank = document.createElement("button")
      picker.appendChild(blank)
      mgr.stepPickerSelect({ currentTarget: blank, target: blank })
      expect(hidden.value).toBe("")

      mgr.stepPickerSelect({ currentTarget: undefined, target: { closest: () => opt } })
    })

    it("renders an option without icon or description and a disabled already-used suffix", () => {
      const entry = (display, value, meta) => mgr._pickerEntry(display, value, meta, { key: "cat", label: "Cat" })
      const html = mgr._pickerOptionHTML(entry("Bare", "bare", {}))
      expect(html).not.toContain("<svg")
      expect(html).not.toContain("text-[11px] text-slate-500")
      expect(html).not.toContain("data-step-picker-option-category")

      const used = mgr._pickerOptionHTML(entry("Once", "once", { disabled: true, icon: "M1", color: "unknown" }), [], true)
      expect(used).toContain("(already used)")
      expect(used).toContain("data-disabled=\"true\"")
      expect(used).toContain("text-slate-500")
      expect(used).not.toContain("data-step-picker-option-category")
    })

    it("skips empty categories when building the picker", () => {
      mgr._pickerLeafMap = {}
      const items = mgr._flattenActionLeaves([], [])
      expect(items).toEqual([])
    })

    it("renders description and icon color classes on an option", () => {
      const html = mgr._pickerOptionHTML(mgr._pickerEntry(
        "HTTP",
        "api_call",
        { description: "Make a request", icon: "M1 1", color: "amber" },
        { key: "communication", label: "Communication" }
      ))
      expect(html).toContain("Make a request")
      expect(html).toContain("text-amber-500")
    })

    it("omits empty categories from the picker HTML", () => {
      setActionCatalog({
        categories: [{ key: "empty", label: "Empty" }, { key: "data", label: "Data" }],
        actions: [{ key: "assign_value", category: "data", label: "Assign", description: "Set a value" }],
      })
      const html = mgr.buildStepPickerHTML()
      expect(html).not.toContain(">Empty<")
      expect(html).toContain(">Data<")
      installSampleActionCatalog()
    })
  })
})
