// NOTE: collectSteps() reads action/suboption/etc via bare-token
// attribute-substring selectors (`[name*='action']`, not `[name*='[action]']`)
// so happy-dom's selector engine resolves each to its OWN input — a bracket in
// the value would make happy-dom alias every query to the first match. Tests
// therefore provide a distinct named input per field.
import { describe, it, expect, beforeEach, vi } from "vitest"
import { makeStepManager } from "./_step_support.js"

// getActionConfig is real for every existing test. A couple of fake keys
// exercise empty / present `fields` without colliding with the fixture.
vi.mock("flowchart/constants/action_registry", async (importOriginal) => {
  const actual = await importOriginal()
  const FAKES = {
    fake_action_with_fields: {
      key: "fake_action_with_fields",
      fields: [{ name: "resultVar", control: "text", default: "from_fields" }],
    },
    fake_action_no_fields: {
      key: "fake_action_no_fields",
    },
  }
  return { ...actual, getActionConfig: (key) => FAKES[key] || actual.getActionConfig(key) }
})

describe("StepManager", () => {
  let mgr, controller
  beforeEach(() => {
    ;({ mgr, controller } = makeStepManager())
  })

  describe("reset", () => {
    it("resets stepIndex to 0 via BaseManager#reset", () => {
      mgr.stepIndex = 7
      mgr.reset()
      expect(mgr.stepIndex).toBe(0)
    })
  })

  describe("toggleStep", () => {
    const stepItemHTML = (expanded = false) => `
      <div data-step-item class="${expanded ? "step-expanded" : ""}">
        <div data-step-toggle-target></div>
        <div data-step-details class="${expanded ? "" : "hidden"}"></div>
      </div>`

    it("no-ops when the click target is inside a button", () => {
      controller.formTarget.innerHTML = stepItemHTML(false)
      const stepItem = controller.formTarget.querySelector("[data-step-item]")
      const btn = document.createElement("button")
      stepItem.appendChild(btn)
      const spy = vi.spyOn(mgr, "_setStepExpanded")
      mgr.toggleStep({ target: btn, currentTarget: stepItem })
      expect(spy).not.toHaveBeenCalled()
    })

    it("no-ops when the click target is inside a [data-drag-handle]", () => {
      controller.formTarget.innerHTML = stepItemHTML(false)
      const stepItem = controller.formTarget.querySelector("[data-step-item]")
      const handle = document.createElement("span")
      handle.setAttribute("data-drag-handle", "")
      stepItem.appendChild(handle)
      const spy = vi.spyOn(mgr, "_setStepExpanded")
      mgr.toggleStep({ target: handle, currentTarget: stepItem })
      expect(spy).not.toHaveBeenCalled()
    })

    it("no-ops when the click target is inside a select/textarea/input", () => {
      controller.formTarget.innerHTML = stepItemHTML(false)
      const stepItem = controller.formTarget.querySelector("[data-step-item]")
      const select = document.createElement("select")
      stepItem.appendChild(select)
      const spy = vi.spyOn(mgr, "_setStepExpanded")
      mgr.toggleStep({ target: select, currentTarget: stepItem })
      expect(spy).not.toHaveBeenCalled()

      const input = document.createElement("input")
      stepItem.appendChild(input)
      mgr.toggleStep({ target: input, currentTarget: stepItem })
      expect(spy).not.toHaveBeenCalled()

      const textarea = document.createElement("textarea")
      stepItem.appendChild(textarea)
      mgr.toggleStep({ target: textarea, currentTarget: stepItem })
      expect(spy).not.toHaveBeenCalled()
    })

    it("returns when currentTarget is not within a [data-step-item]", () => {
      const loose = document.createElement("div")
      const spy = vi.spyOn(mgr, "_setStepExpanded")
      expect(() => mgr.toggleStep({ target: loose, currentTarget: loose })).not.toThrow()
      expect(spy).not.toHaveBeenCalled()
    })

    it("returns when the step item has no [data-step-details]", () => {
      controller.formTarget.innerHTML = `<div data-step-item><div data-step-toggle-target></div></div>`
      const stepItem = controller.formTarget.querySelector("[data-step-item]")
      const target = stepItem.querySelector("[data-step-toggle-target]")
      const spy = vi.spyOn(mgr, "_setStepExpanded")
      mgr.toggleStep({ target, currentTarget: stepItem })
      expect(spy).not.toHaveBeenCalled()
    })

    it("expands a collapsed step and collapses an expanded step", () => {
      controller.formTarget.innerHTML = stepItemHTML(false)
      const stepItem = controller.formTarget.querySelector("[data-step-item]")
      const target = stepItem.querySelector("[data-step-toggle-target]")

      mgr.toggleStep({ target, currentTarget: stepItem })
      expect(stepItem.classList.contains("step-expanded")).toBe(true)

      mgr.toggleStep({ target, currentTarget: stepItem })
      expect(stepItem.classList.contains("step-expanded")).toBe(false)
    })
  })

  describe("removeStep", () => {
    it("returns without side effects when the event target is not within a [data-step-item]", () => {
      const loose = document.createElement("div")
      const spy = vi.spyOn(mgr, "_dispatchEvent")
      mgr.removeStep({ preventDefault: vi.fn(), target: loose })
      expect(spy).not.toHaveBeenCalled()
    })

    it("removes the step item, resets the change snapshot, reopens the picker, and dispatches stepRemoved", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item data-step-action="do_thing"><button data-remove></button></div>
        </div>
        <div data-step-picker-mount class="hidden"></div>`
      const stepItem = controller.formTarget.querySelector("[data-step-item]")
      const btn = stepItem.querySelector("[data-remove]")
      mgr._changeSnapshot = { some: "snapshot" }
      const dispatchSpy = vi.spyOn(mgr, "_dispatchEvent")
      const pickerSpy = vi.spyOn(mgr, "_showStepPicker")

      mgr.removeStep({ preventDefault: vi.fn(), target: btn })

      expect(controller.formTarget.querySelector("[data-step-item]")).toBeNull()
      expect(mgr._changeSnapshot).toBeNull()
      expect(pickerSpy).toHaveBeenCalled()
      expect(dispatchSpy).toHaveBeenCalledWith("stepRemoved")
    })
  })

  describe("collectSteps", () => {
    it("returns null when there is no steps container", () => {
      controller.formTarget.innerHTML = ""
      expect(mgr.collectSteps()).toBeNull()
    })

    it("collects action (fallback), description, and merged config; preserves stable id", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item data-step-id="keep-me" data-step-action="do_thing">
            <textarea data-step-description>  hello  </textarea>
            <div data-config-field="a"><input data-config-input value="1"></div>
            <input type="hidden" data-step-config value='{"a":"old","b":"kept"}'>
          </div>
        </div>`
      const steps = mgr.collectSteps()
      expect(steps).toEqual([
        { id: "keep-me", action: "do_thing", description: "hello", config: { b: "kept", a: "1" } },
      ])
    })

    it("mints and back-writes a step id when the DOM item lacks one", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item data-step-action="do_thing"></div>
        </div>`
      const steps = mgr.collectSteps()
      expect(steps).toHaveLength(1)
      expect(steps[0].id).toBeTruthy()
      // written back onto the DOM so subsequent collects stay stable
      const domId = controller.formTarget.querySelector("[data-step-item]").dataset.stepId
      expect(domId).toBe(steps[0].id)
    })

    it("skips items with no action at all", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item></div>
        </div>`
      expect(mgr.collectSteps()).toEqual([])
    })

    it("collects identity fields from distinct named inputs and never emits removed wrappers", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item data-step-id="full">
            <input name="steps[0][action]" value="submit">
            <input name="steps[0][suboption]" value="opt">
            <input name="steps[0][selectionLabels]" value='["a","b"]'>
            <input name="steps[0][keywordParams]" value='{"k":1}'>
            <input name="steps[0][retryCount]" value="2">
            <input name="steps[0][retryBackoff]" value="linear">
            <input name="steps[0][timeout]" value="30">
            <input name="steps[0][guardCondition]" value=" x > 1 ">
          </div>
        </div>`
      const steps = mgr.collectSteps()
      expect(steps).toHaveLength(1)
      const step = steps[0]
      expect(step.action).toBe("submit")
      expect(step.suboption).toBe("opt")
      expect(step.selectionLabels).toEqual(["a", "b"])
      expect(step.keywordParams).toEqual({ k: 1 })
      expect(step).not.toHaveProperty("retryCount")
      expect(step).not.toHaveProperty("retryBackoff")
      expect(step).not.toHaveProperty("timeout")
      expect(step).not.toHaveProperty("guardCondition")
    })

    it("swallows JSON.parse errors for selectionLabels/keywordParams", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item data-step-id="bad-json">
            <input name="steps[0][action]" value="submit">
            <input name="steps[0][selectionLabels]" value="not-json">
            <input name="steps[0][keywordParams]" value="also-bad">
          </div>
        </div>`
      const steps = mgr.collectSteps()
      expect(steps).toHaveLength(1)
      // keys are never set on stepData when JSON.parse throws (caught + ignored)
      expect(steps[0]).not.toHaveProperty("selectionLabels")
      expect(steps[0]).not.toHaveProperty("keywordParams")
    })

    it("omits storedConfig when the [data-step-config] hidden input is absent", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item data-step-action="do_thing" data-step-id="no-stored-config">
            <div data-config-field="a"><input data-config-input value="live"></div>
          </div>
        </div>`
      const steps = mgr.collectSteps()
      expect(steps[0].config).toEqual({ a: "live" })
    })

    it("swallows JSON.parse errors for an invalid [data-step-config] hidden input", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item data-step-action="do_thing" data-step-id="bad-stored-config">
            <input type="hidden" data-step-config value="not valid json">
          </div>
        </div>`
      expect(() => mgr.collectSteps()).not.toThrow()
      const steps = mgr.collectSteps()
      // storedConfig falls back to {} silently; no rendered config fields either -> no config key
      expect(steps[0]).not.toHaveProperty("config")
    })

    it("collects the detached Change card's action and edited config, not an empty list", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item data-step-id="keep-me" data-step-action="find_model">
            <input name="steps[0][action]" value="find_model">
            <div data-config-field="resultVar"><input data-config-input value="order"></div>
            <input type="hidden" data-step-config value='{"resultVar":"order"}'>
          </div>
        </div>
        <div data-step-picker-mount class="hidden"></div>`
      const stepItem = controller.formTarget.querySelector("[data-step-item]")
      mgr.changeStep({ preventDefault() {}, target: stepItem })
      expect(controller.formTarget.querySelector("[data-steps-container] [data-step-item]")).toBeNull()

      stepItem.querySelector("[data-config-input]").value = "edited_model"

      const steps = mgr.collectSteps()
      expect(steps).not.toEqual([])
      expect(steps).toEqual([
        { id: "keep-me", action: "find_model", description: "", config: { resultVar: "edited_model" } },
      ])
      mgr._disarmChangeOutsideClick()
    })
  })

  describe("collectStepConfig", () => {
    it("reads plain inputs, coerces number inputs, and skips blanks", () => {
      const item = document.createElement("div")
      item.innerHTML = `
        <div data-config-field="name"><input data-config-input value="Ada"></div>
        <div data-config-field="count"><input type="number" data-config-input value="7"></div>
        <div data-config-field="empty"><input data-config-input value="   "></div>`
      const config = mgr.collectStepConfig(item)
      expect(config).toEqual({ name: "Ada", count: 7 })
    })

    it("collects checkbox (toggle) values as booleans, including false", () => {
      const item = document.createElement("div")
      item.innerHTML = `
        <div data-config-field="skipNil"><input type="checkbox" data-config-input checked></div>
        <div data-config-field="circuitBreaker"><input type="checkbox" data-config-input></div>`
      expect(mgr.collectStepConfig(item)).toEqual({ skipNil: true, circuitBreaker: false })
    })

    it.each([
      ['{"code":"ctx.code","minutes":5}', { code: "ctx.code", minutes: 5 }],
      ["{}", {}],
      ["ctx.sms_vars", "ctx.sms_vars"],
      ["ctx[:sms_vars]", "ctx[:sms_vars]"],
      ['{"code":', '{"code":'],
      ['["not-an-object"]', '["not-an-object"]'],
      ["null", "null"]
    ])("collects marked object/expression input %s without losing its type or malformed text", (value, expected) => {
      const item = document.createElement("div")
      item.innerHTML = '<div data-config-field="smsVars" data-json-or-expression><textarea data-config-input></textarea></div>'
      item.querySelector("textarea").value = `  ${value}  `
      expect(mgr.collectStepConfig(item)).toEqual({ smsVars: expected })
    })

    it("preserves JSON-looking ordinary text verbatim even for an unmarked smsVars field", () => {
      const item = document.createElement("div")
      item.innerHTML = '<div data-config-field="smsVars"><input data-config-input></div>'
      item.querySelector("input").value = '{"code":"ctx.code"}'
      expect(mgr.collectStepConfig(item)).toEqual({ smsVars: '{"code":"ctx.code"}' })
    })

    it("collects key_value_list pairs and ignores keyless rows", () => {
      const item = document.createElement("div")
      item.innerHTML = `
        <div data-config-field="headers">
          <div data-key-value-list>
            <div data-kv-row><input data-kv-key value="A"><input data-kv-value value="1"></div>
            <div data-kv-row><input data-kv-key value=""><input data-kv-value value="ignored"></div>
          </div>
        </div>`
      expect(mgr.collectStepConfig(item)).toEqual({ headers: [{ key: "A", value: "1" }] })
    })

    it("defaults a kv row's value to '' when the value input is blank but the key is present", () => {
      const item = document.createElement("div")
      item.innerHTML = `
        <div data-config-field="headers">
          <div data-key-value-list>
            <div data-kv-row><input data-kv-key value="A"><input data-kv-value value="   "></div>
          </div>
        </div>`
      expect(mgr.collectStepConfig(item)).toEqual({ headers: [{ key: "A", value: "" }] })
    })
  })

  describe("collectRenderedConfigFieldKeys", () => {
    it("returns the set of rendered config-field keys", () => {
      const item = document.createElement("div")
      item.innerHTML = `<div data-config-field="a"></div><div data-config-field="b"></div><div data-config-field=""></div>`
      const keys = mgr.collectRenderedConfigFieldKeys(item)
      expect([...keys].sort()).toEqual(["a", "b"])
    })
  })

  describe("getUsedSingleUseActions", () => {
    it("returns single-use actions currently present in the steps list", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item data-step-action="find_model"></div>
          <div data-step-item data-step-action="do_thing"></div>
        </div>`
      // find_model is registered single-use; do_thing is not.
      expect(mgr.getUsedSingleUseActions()).toEqual(["find_model"])
    })

    it("returns [] when there is no container", () => {
      controller.formTarget.innerHTML = ""
      expect(mgr.getUsedSingleUseActions()).toEqual([])
    })
  })

  describe("HTML building", () => {
    it("buildStepsFieldHTML renders a container and a picker mount", () => {
      const html = mgr.buildStepsFieldHTML("steps", { label: "Steps" }, [])
      expect(html).toContain("data-steps-container")
      expect(html).toContain("data-step-picker-mount")
      expect(html).not.toContain("data-action-options")
      expect(html).toContain('class="mt-1"') // picker mount visible (steps.length < 1)
    })

    it("buildStepsFieldHTML falls back to [] for a non-array currentValue and defaults the label", () => {
      const html = mgr.buildStepsFieldHTML("steps", {}, null)
      expect(html).toContain("Step") // default label fallback
      expect(html).toContain('class="mt-1"')
    })

    it("buildStepsFieldHTML hides the picker mount once at least one step is present", () => {
      const html = mgr.buildStepsFieldHTML("steps", { actionOptions: [] }, [
        { action: "do_thing", description: "d1" },
      ])
      expect(html).toMatch(/data-step-picker-mount class="hidden"/)
    })

    it("buildStepsFieldHTML re-renders existing steps with object selectionLabels/keywordParams/config as-is", () => {
      const html = mgr.buildStepsFieldHTML("steps", { actionOptions: [{ value: "do_thing", label: "Do" }] }, [
        {
          action: "do_thing",
          description: "d1",
          suboption: "s1",
          selectionLabels: { a: 1 },
          keywordParams: [{ k: "v" }],
          config: { resultVar: "user" },
          retryCount: "2",
          retryBackoff: "linear",
          timeout: "30",
          guardCondition: "x > 1",
          id: "existing-1",
        },
      ])
      expect(html).toContain("existing-1")
      expect(html).not.toContain("retryCount")
      expect(html).not.toContain("guardCondition")
    })

    it("buildStepsFieldHTML re-parses string-encoded selectionLabels/keywordParams/config", () => {
      const html = mgr.buildStepsFieldHTML("steps", { actionOptions: [{ value: "do_thing", label: "Do" }] }, [
        {
          action: "do_thing",
          description: "d2",
          selectionLabels: JSON.stringify({ a: 1 }),
          keywordParams: JSON.stringify([{ k: "v" }]),
          config: JSON.stringify({ resultVar: "user" }),
        },
      ])
      expect(html).toContain("d2")
    })

    it("buildStepsFieldHTML swallows parse errors for malformed string-encoded selectionLabels/keywordParams/config", () => {
      expect(() =>
        mgr.buildStepsFieldHTML("steps", { actionOptions: [] }, [
          {
            action: "do_thing",
            description: "d3",
            selectionLabels: "not json",
            keywordParams: "not json",
            config: "not json",
          },
        ])
      ).not.toThrow()
    })

    it("buildStepsFieldHTML mints a step id via generateStepId when the step data lacks one", () => {
      const html = mgr.buildStepsFieldHTML("steps", { actionOptions: [] }, [
        { action: "do_thing", description: "no-id-step" },
      ])
      expect(html).toContain("no-id-step")
    })

    it("buildStepsFieldHTML defaults action and description to '' when a reloaded step omits them", () => {
      expect(() =>
        mgr.buildStepsFieldHTML("steps", { actionOptions: [] }, [{ id: "no-action-no-desc" }])
      ).not.toThrow()
    })

    it("buildStepItemHTML embeds the id and action", () => {
      const html = mgr.buildStepItemHTML(0, "do_thing", "desc", [], false, "", null, null, [], {}, "sid-1")
      expect(html).toContain("sid-1")
      expect(html).toContain("do_thing")
    })

    it("buildStepItemHTML mints an id when none is given", () => {
      const html = mgr.buildStepItemHTML(0, "do_thing", "desc")
      expect(html).toContain("do_thing")
    })

    it("buildStepItemHTML looks up the installed catalog when actionOptionData is omitted", () => {
      const html = mgr.buildStepItemHTML(0, "find_model", "desc")
      expect(html).toContain("Find record")
    })

    it("buildStepItemHTML defaults context.elementId/entityAttributes to fallbacks when currentElement/canvas are absent", () => {
      const bareController = { ...controller, currentElement: null, canvas: null }
      const bareMgr = new mgr.constructor(bareController)
      expect(() => bareMgr.buildStepItemHTML(0, "do_thing", "desc", [])).not.toThrow()
    })

    it("buildStepConfigHTML returns fields for a known action and empty string for an unknown one", () => {
      expect(mgr.buildStepConfigHTML("totally_unknown_action")).toBe("")
      const html = mgr.buildStepConfigHTML("find_model", { resultVar: "user" })
      expect(html).toContain("resultVar")
    })

    it("buildStepConfigHTML renders export fields for a fake catalog action", () => {
      const html = mgr.buildStepConfigHTML("fake_action_with_fields", {})
      expect(html).toContain("resultVar")
    })

    it("buildStepConfigHTML returns '' when the action has no fields", () => {
      expect(mgr.buildStepConfigHTML("fake_action_no_fields", {})).toBe("")
    })

    it("buildStepConfigHTML appends the timeout hint for HTTP-style actions", () => {
      const html = mgr.buildStepConfigHTML("api_call", { connectTimeout: 3, readTimeout: 7 })
      expect(html).toContain("data-step-timeout-hint")
      expect(html).toContain("Gives up after 10 s")
    })
  })
})
