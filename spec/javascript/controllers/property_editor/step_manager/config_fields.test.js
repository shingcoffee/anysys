import { describe, it, expect, beforeEach, vi } from "vitest"
import { makeStepManager } from "../_step_support.js"
import { getActionConfig } from "flowchart/constants/action_registry"

describe("StepManager ConfigFieldsMixin", () => {
  let mgr, controller
  beforeEach(() => {
    ;({ mgr, controller } = makeStepManager())
  })

  describe("handleConfigFieldChange", () => {
    beforeEach(() => {
      controller.formTarget.innerHTML = `
        <div data-step-item data-step-id="s1">
          <div data-config-field="mode"><input data-config-input value="advanced"></div>
          <div data-config-field="threshold" data-visible-when='{"field":"mode","value":"advanced"}'>
            <input data-config-input value="5">
          </div>
          <input type="hidden" data-step-config value="{}">
        </div>`
    })

    const modeInput = () => controller.formTarget.querySelector('[data-config-field="mode"] [data-config-input]')
    const thresholdField = () => controller.formTarget.querySelector('[data-config-field="threshold"]')
    const storedConfig = () => JSON.parse(controller.formTarget.querySelector("[data-step-config]").value)

    it("no-ops when the target is not inside a step item", () => {
      const loose = document.createElement("input")
      const spy = vi.spyOn(mgr, "_dispatchEvent")
      mgr.handleConfigFieldChange({ target: loose })
      expect(spy).not.toHaveBeenCalled()
    })

    it("writes collected config to the hidden [data-step-config] and dispatches stepChanged", () => {
      const spy = vi.spyOn(mgr, "_dispatchEvent")
      mgr.handleConfigFieldChange({ target: modeInput() })
      expect(storedConfig()).toEqual({ mode: "advanced", threshold: "5" })
      expect(spy).toHaveBeenCalledWith("stepChanged")
    })

    it("keeps a visibleWhen-matched field visible, then hides it when the controlling value diverges", () => {
      mgr.handleConfigFieldChange({ target: modeInput() })
      expect(thresholdField().classList.contains("hidden")).toBe(false)

      modeInput().value = "basic"
      mgr.handleConfigFieldChange({ target: modeInput() })
      expect(thresholdField().classList.contains("hidden")).toBe(true)
    })

    it("mirrors live config onto the in-memory step and notifies stepIoManager when present", () => {
      const onStepConfigChanged = vi.fn()
      const step = { id: "s1", config: { old: 1 } }
      controller.stepIoManager = { onStepConfigChanged }
      controller.canvas = { findStepById: (id) => (id === "s1" ? { step } : null) }
      mgr.handleConfigFieldChange({ target: modeInput() })
      expect(step.config).toMatchObject({ old: 1, mode: "advanced", threshold: "5" })
      expect(onStepConfigChanged).toHaveBeenCalledWith(step)
    })

    it("defaults found.step.config to {} when the in-memory step has none yet", () => {
      const onStepConfigChanged = vi.fn()
      const step = { id: "s1" } // no `config` key at all
      controller.stepIoManager = { onStepConfigChanged }
      controller.canvas = { findStepById: (id) => (id === "s1" ? { step } : null) }
      mgr.handleConfigFieldChange({ target: modeInput() })
      expect(step.config).toEqual({ mode: "advanced", threshold: "5" })
    })

    it("treats a visibleWhen field absent from currentConfig as an empty string", () => {
      // "otherField" is never rendered, so collectStepConfig() never produces
      // a value for it — currentConfig["otherField"] is undefined, exercising
      // the `?? ""` fallback.
      thresholdField().dataset.visibleWhen = JSON.stringify({ field: "otherField", value: "advanced" })
      mgr.handleConfigFieldChange({ target: modeInput() })
      expect(thresholdField().classList.contains("hidden")).toBe(true)
    })

    it("matches an array `values` list (not just a scalar `value`)", () => {
      thresholdField().dataset.visibleWhen = JSON.stringify({ field: "mode", values: ["advanced", "expert"] })
      mgr.handleConfigFieldChange({ target: modeInput() })
      expect(thresholdField().classList.contains("hidden")).toBe(false)
    })

    it("matches the export visibleWhen shape { fieldName: [values] }", () => {
      thresholdField().dataset.visibleWhen = JSON.stringify({ mode: ["advanced", "expert"] })
      mgr.handleConfigFieldChange({ target: modeInput() })
      expect(thresholdField().classList.contains("hidden")).toBe(false)

      modeInput().value = "basic"
      mgr.handleConfigFieldChange({ target: modeInput() })
      expect(thresholdField().classList.contains("hidden")).toBe(true)
    })

    it("silently ignores an unparsable visibleWhen and leaves visibility untouched", () => {
      thresholdField().dataset.visibleWhen = "{not json"
      thresholdField().classList.add("hidden")
      expect(() => mgr.handleConfigFieldChange({ target: modeInput() })).not.toThrow()
      expect(thresholdField().classList.contains("hidden")).toBe(true)
    })

    it("toggles required from requiredWhen, including unparsable JSON and checkbox inputs", () => {
      controller.formTarget.innerHTML = `
        <div data-step-item data-step-id="s1">
          <div data-config-field="mode"><input data-config-input value="advanced"></div>
          <div data-config-field="threshold" data-required-when='{"mode":["advanced"]}'>
            <input data-config-input value="5">
            <input type="checkbox" data-config-input>
            <input type="hidden" data-config-input value="x">
          </div>
          <div data-config-field="broken" data-required-when="{not json">
            <input data-config-input>
          </div>
          <div data-config-field="plain">
            <input data-config-input>
          </div>
          <input type="hidden" data-step-config value="{}">
        </div>`
      const thresholdInput = controller.formTarget.querySelector('[data-config-field="threshold"] input:not([type="checkbox"]):not([type="hidden"])')
      mgr.handleConfigFieldChange({ target: modeInput() })
      expect(thresholdInput.required).toBe(true)
      expect(controller.formTarget.querySelector('[data-config-field="broken"] input').required).toBe(false)
      expect(controller.formTarget.querySelector('[data-config-field="plain"] input').required).toBe(false)

      controller.formTarget.querySelector('[data-config-field="mode"] input').value = "basic"
      mgr.handleConfigFieldChange({ target: modeInput() })
      expect(thresholdInput.required).toBe(false)
    })
  })

  describe("key-value list rows", () => {
    const kvHtml = () => `
      <div data-key-value-list data-key-placeholder="K" data-value-placeholder="V">
        <div data-kv-row>
          <input data-kv-key value="a"><input data-kv-value value="1">
          <button data-action="click->property-editor#removeConfigKvRow">x</button>
        </div>
        <button data-action="click->property-editor#addConfigKvRow">Add</button>
      </div>`

    it("addConfigKvRow inserts a fresh row before the Add button and honours placeholders", () => {
      controller.formTarget.innerHTML = kvHtml()
      const addBtn = controller.formTarget.querySelector("[data-action*='addConfigKvRow']")
      mgr.addConfigKvRow({ preventDefault() {}, target: addBtn })

      const list = controller.formTarget.querySelector("[data-key-value-list]")
      const rows = list.querySelectorAll("[data-kv-row]")
      expect(rows.length).toBe(2)
      // The new (last) row precedes the Add button and uses the configured placeholders.
      const newRow = rows[1]
      expect(newRow.nextElementSibling).toBe(addBtn)
      expect(newRow.querySelector("[data-kv-key]").placeholder).toBe("K")
      expect(newRow.querySelector("[data-kv-value]").placeholder).toBe("V")
    })

    it("removeConfigKvRow removes the row and re-adds an empty one when the list would be empty", () => {
      controller.formTarget.innerHTML = kvHtml()
      const removeBtn = controller.formTarget.querySelector("[data-kv-row] button")
      mgr.removeConfigKvRow({ preventDefault() {}, target: removeBtn })

      const rows = controller.formTarget.querySelectorAll("[data-kv-row]")
      expect(rows.length).toBe(1)
      // The survivor is a fresh, empty row (not the original a=1 row).
      expect(rows[0].querySelector("[data-kv-key]").value).toBe("")
    })

    it("removeConfigKvRow on an element field notifies the form with a bubbling change", () => {
      controller.formTarget.innerHTML = `<div data-element-field="inputVariables">${kvHtml()}</div>`
      const changed = vi.fn()
      controller.formTarget.addEventListener("change", changed)
      mgr.removeConfigKvRow({ preventDefault() {}, target: controller.formTarget.querySelector("[data-kv-row] button") })

      expect(changed).toHaveBeenCalledTimes(1)
    })

    it("removeConfigKvRow inside a step leaves syncing to the step path", () => {
      controller.formTarget.innerHTML = `<div data-step-item>${kvHtml()}</div>`
      const changed = vi.fn()
      controller.formTarget.addEventListener("change", changed)
      mgr.removeConfigKvRow({ preventDefault() {}, target: controller.formTarget.querySelector("[data-kv-row] button") })

      expect(changed).not.toHaveBeenCalled()
    })

    it("addConfigKvRow no-ops when the target is not inside a [data-key-value-list]", () => {
      controller.formTarget.innerHTML = `<button id="lonely">Add</button>`
      const btn = controller.formTarget.querySelector("#lonely")
      mgr.addConfigKvRow({ preventDefault() {}, target: btn })
      expect(controller.formTarget.querySelector("[data-kv-row]")).toBeNull()
    })

    it("addConfigKvRow falls back to default Key/Value placeholders when none are set", () => {
      controller.formTarget.innerHTML = `
        <div data-key-value-list>
          <button data-action="click->property-editor#addConfigKvRow">Add</button>
        </div>`
      const addBtn = controller.formTarget.querySelector("[data-action*='addConfigKvRow']")
      mgr.addConfigKvRow({ preventDefault() {}, target: addBtn })
      const row = controller.formTarget.querySelector("[data-kv-row]")
      expect(row.querySelector("[data-kv-key]").placeholder).toBe("Key")
      expect(row.querySelector("[data-kv-value]").placeholder).toBe("Value")
      expect(row.querySelector("button").title).toBe("Remove row")
    })

    it("addConfigKvRow reads the translated remove-row title off the controller", () => {
      controller.kvRemoveRowTitleValue = "删除行"
      controller.formTarget.innerHTML = `
        <div data-key-value-list>
          <button data-action="click->property-editor#addConfigKvRow">Add</button>
        </div>`
      const addBtn = controller.formTarget.querySelector("[data-action*='addConfigKvRow']")
      mgr.addConfigKvRow({ preventDefault() {}, target: addBtn })
      const row = controller.formTarget.querySelector("[data-kv-row]")
      expect(row.querySelector("button").title).toBe("删除行")
    })

    it("removeConfigKvRow no-ops when the target is not inside a [data-kv-row]", () => {
      controller.formTarget.innerHTML = `<button id="lonely">x</button>`
      const btn = controller.formTarget.querySelector("#lonely")
      mgr.removeConfigKvRow({ preventDefault() {}, target: btn })
      // No throw is the assertion — nothing to remove/re-add.
    })

    it("removeConfigKvRow falls back to the list itself when no Add button exists", () => {
      controller.formTarget.innerHTML = `
        <div data-key-value-list>
          <div data-kv-row><input data-kv-key value="a"><button id="rm">x</button></div>
        </div>`
      const removeBtn = controller.formTarget.querySelector("#rm")
      mgr.removeConfigKvRow({ preventDefault() {}, target: removeBtn })
      // addConfigKvRow was re-invoked with target = the list itself (no Add
      // button to find), and it still inserts a fresh empty row.
      const rows = controller.formTarget.querySelectorAll("[data-kv-row]")
      expect(rows.length).toBe(1)
      expect(rows[0].querySelector("[data-kv-key]").value).toBe("")
    })
  })

  describe("refreshMoreOptionsBadges", () => {
    it("counts config fields whose value differs from data-field-default and toggles the badge", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item>
            <div data-disclosure>
              <span data-set-count-badge class="hidden"></span>
              <div data-disclosure-body>
                <div data-config-field data-field-default="">
                  <input data-config-input value="changed">
                </div>
                <div data-config-field data-field-default="keep">
                  <input data-config-input value="keep">
                </div>
              </div>
            </div>
          </div>
        </div>`
      mgr.refreshMoreOptionsBadges()
      const badge = controller.formTarget.querySelector("[data-set-count-badge]")
      expect(badge.textContent).toBe("1 set")
      expect(badge.classList.contains("hidden")).toBe(false)
    })

    it("hides the badge when nothing is set", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item>
            <div data-disclosure>
              <span data-set-count-badge></span>
              <div data-disclosure-body>
                <div data-config-field data-field-default="d"><input data-config-input value="d"></div>
              </div>
            </div>
          </div>
        </div>`
      mgr.refreshMoreOptionsBadges()
      const badge = controller.formTarget.querySelector("[data-set-count-badge]")
      expect(badge.textContent).toBe("0 set")
      expect(badge.classList.contains("hidden")).toBe(true)
    })

    it("no-ops when [data-steps-container] is absent", () => {
      controller.formTarget.innerHTML = `<div>no container here</div>`
      expect(() => mgr.refreshMoreOptionsBadges()).not.toThrow()
    })

    it("skips a step item that has no [data-set-count-badge]", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item><div data-disclosure><div data-disclosure-body></div></div></div>
        </div>`
      expect(() => mgr.refreshMoreOptionsBadges()).not.toThrow()
    })

    it("skips a badge whose disclosure has no [data-disclosure-body]", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item>
            <div data-disclosure><span data-set-count-badge>stale</span></div>
          </div>
        </div>`
      mgr.refreshMoreOptionsBadges()
      // Untouched — the early return means "stale" is never overwritten.
      expect(controller.formTarget.querySelector("[data-set-count-badge]").textContent).toBe("stale")
    })

    it("counts a key_value_list field only when at least one row has a non-blank key", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item>
            <div data-disclosure>
              <span data-set-count-badge></span>
              <div data-disclosure-body>
                <div data-config-field>
                  <div data-key-value-list>
                    <div data-kv-row><input data-kv-key value="  "></div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>`
      mgr.refreshMoreOptionsBadges()
      const badge = controller.formTarget.querySelector("[data-set-count-badge]")
      expect(badge.textContent).toBe("0 set")

      controller.formTarget.querySelector("[data-kv-key]").value = "real_key"
      mgr.refreshMoreOptionsBadges()
      expect(badge.textContent).toBe("1 set")
    })

    it("does not count a config field that has no [data-config-input] at all", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item>
            <div data-disclosure>
              <span data-set-count-badge></span>
              <div data-disclosure-body>
                <div data-config-field data-field-default="d"><span>no input here</span></div>
              </div>
            </div>
          </div>
        </div>`
      mgr.refreshMoreOptionsBadges()
      expect(controller.formTarget.querySelector("[data-set-count-badge]").textContent).toBe("0 set")
    })

    it("treats a [data-config-input] element with no `.value` property as an empty string", () => {
      // Defensive `input.value ?? ""` guard: exercise it with a non-form element
      // that carries the marker attribute but has no `.value` (undefined, not "").
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item>
            <div data-disclosure>
              <span data-set-count-badge></span>
              <div data-disclosure-body>
                <div data-config-field data-field-default=""><span data-config-input></span></div>
              </div>
            </div>
          </div>
        </div>`
      mgr.refreshMoreOptionsBadges()
      expect(controller.formTarget.querySelector("[data-set-count-badge]").textContent).toBe("0 set")
    })
  })

  describe("entity column select widgets", () => {
    const entityHtml = () => `
      <div data-step-item data-step-id="s1">
        <div data-config-field="findField" data-entity-field-wrapper>
          <select data-entity-column-select data-action="change->property-editor#handleEntityColumnSelectChange">
            <option value="">--</option>
            <option value="email">email</option>
            <option value="__manual__">Manual…</option>
          </select>
          <div data-entity-manual-wrap class="hidden">
            <input data-entity-column-manual>
          </div>
          <input type="hidden" data-config-input="findField">
        </div>
        <input type="hidden" data-step-config value="{}">
      </div>`

    beforeEach(() => {
      controller.formTarget.innerHTML = entityHtml()
    })

    const select = () => controller.formTarget.querySelector("[data-entity-column-select]")
    const hidden = () => controller.formTarget.querySelector("input[type='hidden'][data-config-input]")
    const manualWrap = () => controller.formTarget.querySelector("[data-entity-manual-wrap]")

    it("mirrors a real column choice into the hidden config input", () => {
      const sel = select()
      sel.value = "email"
      mgr.handleEntityColumnSelectChange({ target: sel })
      expect(hidden().value).toBe("email")
    })

    it("__manual__ swaps to the manual input and clears the hidden value", () => {
      const sel = select()
      sel.value = "__manual__"
      mgr.handleEntityColumnSelectChange({ target: sel, preventDefault() {} })
      expect(select().classList.contains("hidden")).toBe(true)
      expect(manualWrap().classList.contains("hidden")).toBe(false)
      expect(hidden().value).toBe("")
    })

    it("swapEntityColumnToSelect re-shows the select and hides the manual input", () => {
      // Start in manual mode.
      manualWrap().classList.remove("hidden")
      select().classList.add("hidden")
      mgr.swapEntityColumnToSelect({ target: select(), preventDefault() {} })
      expect(select().classList.contains("hidden")).toBe(false)
      expect(manualWrap().classList.contains("hidden")).toBe(true)
    })

    it("syncEntityColumnManual mirrors manual typing into the hidden input", () => {
      const input = manualWrap().querySelector("[data-entity-column-manual]")
      input.value = "custom_col"
      mgr.syncEntityColumnManual({ target: input })
      expect(hidden().value).toBe("custom_col")
    })

    it("handleEntityColumnSelectChange no-ops when the target is not inside a wrapper", () => {
      const loose = document.createElement("select")
      expect(() => mgr.handleEntityColumnSelectChange({ target: loose })).not.toThrow()
    })

    it("swapEntityColumnToManual no-ops when the target is not inside a wrapper", () => {
      const loose = document.createElement("button")
      expect(() => mgr.swapEntityColumnToManual({ target: loose })).not.toThrow()
    })

    it("swapEntityColumnToSelect no-ops when the target is not inside a wrapper", () => {
      const loose = document.createElement("button")
      expect(() => mgr.swapEntityColumnToSelect({ target: loose, preventDefault() {} })).not.toThrow()
    })
  })

  describe("_updatePairedValueTypeAssist", () => {
    // findField is the only PAIRED_VALUE_FIELDS key exercised elsewhere in this
    // file; its partner is findValue (see templates/var_refs.js).
    const wrapperHtml = (pairedFieldHtml = "") => `
      <div data-step-item>
        <div data-config-field="findField" data-entity-field-wrapper>
          <input type="hidden" data-config-input="findField">
        </div>
        ${pairedFieldHtml}
      </div>`

    it("returns early when the field key has no paired-value counterpart", () => {
      controller.formTarget.innerHTML = `
        <div data-step-item>
          <div data-config-field="sortField" data-entity-field-wrapper>
            <input type="hidden" data-config-input="sortField">
          </div>
        </div>`
      const wrapper = controller.formTarget.querySelector("[data-entity-field-wrapper]")
      expect(() => mgr._updatePairedValueTypeAssist(wrapper, "email")).not.toThrow()
    })

    it("returns early when the paired field is not rendered", () => {
      controller.formTarget.innerHTML = wrapperHtml() // no findValue field present
      const wrapper = controller.formTarget.querySelector("[data-entity-field-wrapper]")
      expect(() => mgr._updatePairedValueTypeAssist(wrapper, "email")).not.toThrow()
    })

    it("returns early when the paired field has no [data-config-input]", () => {
      controller.formTarget.innerHTML = wrapperHtml(`
        <div data-config-field="findValue"><label>Value</label></div>`)
      const wrapper = controller.formTarget.querySelector("[data-entity-field-wrapper]")
      expect(() => mgr._updatePairedValueTypeAssist(wrapper, "email")).not.toThrow()
      expect(controller.formTarget.querySelector('[data-config-field="findValue"] label [data-type-chip]')).toBeNull()
    })

    it("resolves an unknown column to no chip and no soft-type expectation", () => {
      controller.formTarget.innerHTML = wrapperHtml(`
        <div data-config-field="findValue">
          <input data-config-input>
        </div>`)
      const wrapper = controller.formTarget.querySelector("[data-entity-field-wrapper]")
      controller.canvas = { entityAttributes: [] }
      mgr._updatePairedValueTypeAssist(wrapper, "not_a_real_column")
      const pairedInput = controller.formTarget.querySelector('[data-config-field="findValue"] [data-config-input]')
      expect(pairedInput.dataset.expectedType).toBeUndefined()
    })

    it("adds a type chip to the label and wires soft-type validation for a known column", () => {
      controller.formTarget.innerHTML = wrapperHtml(`
        <div data-config-field="findValue">
          <label>Value</label>
          <input data-config-input value="not-a-number">
        </div>`)
      const wrapper = controller.formTarget.querySelector("[data-entity-field-wrapper]")
      controller.canvas = { entityAttributes: [{ name_slug: "email", type: "string", html_type: "number" }] }
      mgr._updatePairedValueTypeAssist(wrapper, "email")

      const label = controller.formTarget.querySelector('[data-config-field="findValue"] label')
      expect(label.querySelector("[data-type-chip]").textContent).toBe("number")
      const pairedInput = controller.formTarget.querySelector('[data-config-field="findValue"] [data-config-input]')
      expect(pairedInput.dataset.expectedType).toBe("number")
    })
  })

  describe("structured field dispatch", () => {
    it("collects list, conditions, and localized text in catalog shape", () => {
      const item = document.createElement("div")
      item.innerHTML = `
        <div data-config-field="tags">
          <div data-list-editor>
            <div data-list-row><input data-list-value value="a"></div>
            <div data-list-row><input data-list-value value=""></div>
          </div>
        </div>
        <div data-config-field="filter">
          <div data-conditions-editor>
            <div data-condition-row>
              <input data-condition-left value="ctx.a">
              <select data-condition-op><option value="==" selected></option></select>
              <input data-condition-right value="1">
            </div>
          </div>
        </div>
        <div data-config-field="title">
          <div data-localized-text>
            <input data-locale-input data-locale="en" value="Hi">
          </div>
        </div>`
      expect(mgr.collectStepConfig(item)).toEqual({
        tags: ["a"],
        filter: { type: "group", joins: [], conditions: [{ kind: "field", leftOperand: "ctx.a", operator: "==", rightOperand: "1" }] },
        title: { en: "Hi" },
      })
    })

    it("clones a mapping template row and ignores a click outside a list", () => {
      controller.formTarget.innerHTML = `
        <div data-key-value-list>
          <template data-kv-row-template>
            <div data-kv-row><input data-kv-key value="seed"><input data-kv-value></div>
          </template>
          <button data-action="click->property-editor#addConfigKvRow">Add</button>
        </div>
        <button id="loose">x</button>`
      const addBtn = controller.formTarget.querySelector("[data-action*='addConfigKvRow']")
      mgr.addConfigKvRow({ preventDefault() {}, target: addBtn })
      const row = controller.formTarget.querySelector("[data-kv-row]")
      expect(row.querySelector("[data-kv-key]").value).toBe("")

      mgr.addConfigListRow({ preventDefault() {}, target: controller.formTarget.querySelector("#loose") })
      mgr.removeConfigListRow({ preventDefault() {}, target: controller.formTarget.querySelector("#loose") })
      mgr.addConfigConditionRow({ preventDefault() {}, target: controller.formTarget.querySelector("#loose") })
      mgr.removeConfigConditionRow({ preventDefault() {}, target: controller.formTarget.querySelector("#loose") })
      mgr.toggleStepConditionJoin({ preventDefault() {}, target: controller.formTarget.querySelector("#loose") })
      mgr.switchLocalizedLocale({ preventDefault() {}, target: controller.formTarget.querySelector("#loose") })
    })

    it("adds and removes list rows, restoring one empty row", () => {
      controller.formTarget.innerHTML = `
        <div data-step-item>
          <div data-list-editor>
            <div data-list-row><input data-list-value value="keep"></div>
            <template data-list-row-template><div data-list-row><input data-list-value value="x"></div></template>
            <button data-action="click->property-editor#addConfigListRow">Add</button>
          </div>
          <input data-step-config value="{}">
        </div>`
      const addBtn = controller.formTarget.querySelector("[data-action*='addConfigListRow']")
      mgr.addConfigListRow({ preventDefault() {}, target: addBtn })
      expect(controller.formTarget.querySelectorAll("[data-list-row]").length).toBe(2)

      const editor = controller.formTarget.querySelector("[data-list-editor]")
      editor.querySelector("[data-list-row-template]")?.remove()
      mgr.addConfigListRow({ preventDefault() {}, target: addBtn })
      expect(controller.formTarget.querySelectorAll("[data-list-row]").length).toBe(2)

      controller.formTarget.querySelectorAll("[data-list-row]").forEach((row, i) => {
        if (i === 0) mgr.removeConfigListRow({ preventDefault() {}, target: row.querySelector("input") })
      })
      expect(controller.formTarget.querySelectorAll("[data-list-row]").length).toBe(1)
    })

    it("covers list/condition editors missing chrome and orphaned rows", () => {
      controller.formTarget.innerHTML = `<div data-list-row><input data-list-value value="orphan"></div>`
      mgr.removeConfigListRow({
        preventDefault() {},
        target: controller.formTarget.querySelector("[data-list-value]"),
      })
      expect(controller.formTarget.querySelector("[data-list-row]")).toBeNull()

      controller.formTarget.innerHTML = `
        <div data-list-editor>
          <div data-list-row><input data-list-value value="only"></div>
          <template data-list-row-template><div data-list-row><input data-list-value></div></template>
        </div>
        <input data-step-config value="{}">`
      mgr.removeConfigListRow({
        preventDefault() {},
        target: controller.formTarget.querySelector("[data-list-value]"),
      })
      expect(controller.formTarget.querySelectorAll("[data-list-row]").length).toBe(1)

      controller.formTarget.innerHTML = `
        <div data-conditions-editor>
          <button data-action="click->property-editor#addConfigConditionRow">Add</button>
        </div>`
      mgr.addConfigConditionRow({
        preventDefault() {},
        target: controller.formTarget.querySelector("[data-action*='addConfigConditionRow']"),
      })
      expect(controller.formTarget.querySelector("[data-condition-row]")).toBeNull()

      controller.formTarget.innerHTML = `
        <div data-conditions-editor>
          <div data-condition-rows></div>
          <template data-condition-row-template></template>
        </div>`
      mgr.addConfigConditionRow({
        preventDefault() {},
        target: controller.formTarget.querySelector("[data-conditions-editor]"),
      })

      controller.formTarget.innerHTML = `
        <div data-condition-row><input data-condition-left value="orphan"></div>`
      mgr.removeConfigConditionRow({
        preventDefault() {},
        target: controller.formTarget.querySelector("input"),
      })
      expect(controller.formTarget.querySelector("[data-condition-row]")).toBeNull()

      controller.formTarget.innerHTML = `
        <div data-conditions-editor>
          <div data-condition-rows>
            <div data-condition-row><input data-condition-left value="only"></div>
          </div>
          <template data-condition-row-template>
            <div data-condition-row><input data-condition-left></div>
          </template>
        </div>
        <input data-step-config value="{}">`
      mgr.removeConfigConditionRow({
        preventDefault() {},
        target: controller.formTarget.querySelector("input"),
      })
      expect(controller.formTarget.querySelectorAll("[data-condition-row]").length).toBe(1)
    })

    it("re-adds an empty list row when the last one is removed", () => {
      controller.formTarget.innerHTML = `
        <div data-step-item>
          <div data-list-editor>
            <div data-list-row><input data-list-value value="only"></div>
            <template data-list-row-template><div data-list-row><input data-list-value></div></template>
            <button data-action="click->property-editor#addConfigListRow">Add</button>
          </div>
          <input data-step-config value="{}">
        </div>`
      mgr.removeConfigListRow({
        preventDefault() {},
        target: controller.formTarget.querySelector("[data-list-row] input"),
      })
      expect(controller.formTarget.querySelectorAll("[data-list-row]").length).toBe(1)
      expect(controller.formTarget.querySelector("[data-list-value]").value).toBe("")
    })

    it("re-adds the last list row even when the add button is missing", () => {
      controller.formTarget.innerHTML = `
        <div data-step-item>
          <div data-list-editor>
            <div data-list-row><input data-list-value value="only"></div>
            <template data-list-row-template><div data-list-row><input data-list-value></div></template>
          </div>
          <input data-step-config value="{}">
        </div>`
      mgr.removeConfigListRow({
        preventDefault() {},
        target: controller.formTarget.querySelector("[data-list-row] input"),
      })
      expect(controller.formTarget.querySelectorAll("[data-list-row]").length).toBeGreaterThan(0)
    })

    it("adds, joins, and removes condition rows", () => {
      controller.formTarget.innerHTML = `
        <div data-step-item>
          <div data-conditions-editor>
            <div data-condition-rows>
              <div data-condition-row>
                <input data-condition-left value="a">
                <select data-condition-op></select>
                <input data-condition-right>
              </div>
            </div>
            <template data-condition-row-template>
              <div data-condition-row>
                <input data-condition-left value="z">
                <select data-condition-op></select>
                <input data-condition-right>
              </div>
            </template>
            <button data-action="click->property-editor#addConfigConditionRow">Add</button>
          </div>
          <input data-step-config value="{}">
        </div>`
      const addBtn = controller.formTarget.querySelector("[data-action*='addConfigConditionRow']")
      mgr.addConfigConditionRow({ preventDefault() {}, target: addBtn })
      expect(controller.formTarget.querySelectorAll("[data-condition-row]").length).toBe(2)
      expect(controller.formTarget.querySelector("[data-condition-join]").dataset.conditionJoin).toBe("AND")

      const join = controller.formTarget.querySelector("[data-condition-join]")
      mgr.toggleStepConditionJoin({ preventDefault() {}, target: join })
      expect(join.dataset.conditionJoin).toBe("OR")
      mgr.toggleStepConditionJoin({ preventDefault() {}, target: join })
      expect(join.dataset.conditionJoin).toBe("AND")

      controller.joinOrLabelValue = ""
      controller.joinAndLabelValue = ""
      mgr.toggleStepConditionJoin({ preventDefault() {}, target: join })
      expect(join.textContent).toBe("OR")
      mgr.toggleStepConditionJoin({ preventDefault() {}, target: join })
      expect(join.textContent).toBe("AND")

      controller.joinOrLabelValue = ""
      controller.joinAndLabelValue = ""
      mgr.toggleStepConditionJoin({ preventDefault() {}, target: join })
      expect(join.textContent).toBe("OR")
      mgr.toggleStepConditionJoin({ preventDefault() {}, target: join })
      expect(join.textContent).toBe("AND")

      const second = controller.formTarget.querySelectorAll("[data-condition-row]")[1]
      mgr.removeConfigConditionRow({ preventDefault() {}, target: second.querySelector("input") })
      expect(controller.formTarget.querySelectorAll("[data-condition-row]").length).toBe(1)

      const first = controller.formTarget.querySelector("[data-condition-row]")
      mgr.removeConfigConditionRow({ preventDefault() {}, target: first.querySelector("input") })
      expect(controller.formTarget.querySelectorAll("[data-condition-row]").length).toBe(1)

      controller.joinAndLabelValue = ""
      mgr.addConfigConditionRow({ preventDefault() {}, target: addBtn })
      const labels = [...controller.formTarget.querySelectorAll("[data-condition-join]")].map(el => el.textContent)
      expect(labels).toContain("AND")
    })

    it("removes a leading join when the first condition row is deleted", () => {
      controller.formTarget.innerHTML = `
        <div data-step-item>
          <div data-conditions-editor>
            <div data-condition-rows>
              <div data-condition-row><input data-condition-left value="a"></div>
              <button data-condition-join="OR"></button>
              <div data-condition-row><input data-condition-left value="b"></div>
            </div>
          </div>
          <input data-step-config value="{}">
        </div>`
      const first = controller.formTarget.querySelector("[data-condition-row]")
      mgr.removeConfigConditionRow({ preventDefault() {}, target: first.querySelector("input") })
      expect(controller.formTarget.querySelector("[data-condition-join]")).toBeNull()
      expect(controller.formTarget.querySelectorAll("[data-condition-row]").length).toBe(1)
    })

    it("adds the first condition row without a join", () => {
      controller.formTarget.innerHTML = `
        <div data-step-item>
          <div data-conditions-editor>
            <div data-condition-rows></div>
            <template data-condition-row-template>
              <div data-condition-row>
                <input data-condition-left>
              </div>
            </template>
            <button data-action="click->property-editor#addConfigConditionRow">Add</button>
          </div>
          <input data-step-config value="{}">
        </div>`
      mgr.addConfigConditionRow({
        preventDefault() {},
        target: controller.formTarget.querySelector("[data-action*='addConfigConditionRow']"),
      })
      expect(controller.formTarget.querySelectorAll("[data-condition-row]").length).toBe(1)
      expect(controller.formTarget.querySelector("[data-condition-join]")).toBeNull()
    })

    it("re-adds the last condition row when the add button is missing", () => {
      controller.formTarget.innerHTML = `
        <div data-step-item>
          <div data-conditions-editor>
            <div data-condition-rows>
              <div data-condition-row><input data-condition-left value="a"></div>
            </div>
            <template data-condition-row-template>
              <div data-condition-row><input data-condition-left></div>
            </template>
          </div>
          <input data-step-config value="{}">
        </div>`
      mgr.removeConfigConditionRow({
        preventDefault() {},
        target: controller.formTarget.querySelector("[data-condition-row] input"),
      })
      expect(controller.formTarget.querySelectorAll("[data-condition-row]").length).toBeGreaterThan(0)
    })

    it("switches localized locale tabs and skips required on a hidden panel", () => {
      controller.formTarget.innerHTML = `
        <div data-step-item data-step-id="s1">
          <div data-config-field="title" data-conditionally-required>
            <div data-localized-text>
              <button data-locale-tab="en" aria-selected="true" class="bg-white text-slate-900 shadow-sm">en</button>
              <button data-locale-tab="zh-CN" aria-selected="false" class="text-slate-500">zh</button>
              <div data-locale-panel="en"><input data-locale-input data-locale="en"></div>
              <div data-locale-panel="zh-CN" class="hidden"><input data-locale-input data-locale="zh-CN"></div>
            </div>
          </div>
          <input data-step-config value="{}">
        </div>`
      const zh = controller.formTarget.querySelector('[data-locale-tab="zh-CN"]')
      mgr.switchLocalizedLocale({ preventDefault() {}, target: zh })
      expect(zh.getAttribute("aria-selected")).toBe("true")
      expect(controller.formTarget.querySelector('[data-locale-panel="en"]').classList.contains("hidden")).toBe(true)
      expect(controller.formTarget.querySelector('[data-locale-panel="zh-CN"]').classList.contains("hidden")).toBe(false)

      mgr.handleConfigFieldChange({ target: zh })
      const enInput = controller.formTarget.querySelector('[data-locale="en"]')
      const zhInput = controller.formTarget.querySelector('[data-locale="zh-CN"]')
      expect(enInput.required).toBe(false)
      expect(zhInput.required).toBe(true)
    })

    it("counts list, conditions, localized, and checkbox fields in the more-options badge", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item>
            <div data-disclosure>
              <span data-set-count-badge class="hidden"></span>
              <div data-disclosure-body>
                <div data-config-field>
                  <div data-list-editor><input data-list-value value="a"></div>
                </div>
                <div data-config-field>
                  <div data-conditions-editor><input data-condition-left value="ctx.a"></div>
                </div>
                <div data-config-field>
                  <div data-localized-text><input data-locale-input value="Hi"></div>
                </div>
                <div data-config-field data-field-default="false">
                  <input type="checkbox" data-config-input checked>
                </div>
                <div data-config-field data-field-default="false">
                  <input type="checkbox" data-config-input>
                </div>
              </div>
            </div>
          </div>
        </div>`
      mgr.refreshMoreOptionsBadges()
      expect(controller.formTarget.querySelector("[data-set-count-badge]").textContent).toBe("4 set")
    })
  })

  describe("F6 field errors / F7 retry / F8 timeout", () => {
    it("capabilityChromeHTML is empty without timeouts and uses the format template", () => {
      expect(mgr.capabilityChromeHTML({ capabilities: {} }, {})).toBe("")
      expect(mgr.capabilityChromeHTML(null, {})).toBe("")
      const html = mgr.capabilityChromeHTML(
        { capabilities: { timeouts: { open: 3, read: 7, cap: 10 } }, fields: [] },
        { connectTimeout: 3, readTimeout: 7 },
        { timeoutGivesUpFormat: "Give up {seconds}" }
      )
      expect(html).toContain("Give up 10")
      expect(html).toContain("data-step-timeout-hint")
    })

    it("falls back to the controller timeout format then the English default", () => {
      const entry = { capabilities: { timeouts: { open: 2, read: 2, cap: 10 } }, fields: [] }
      const withController = mgr.capabilityChromeHTML(entry, { connectTimeout: 2, readTimeout: 2 }, {})
      expect(withController).toContain("Gives up after 4 s")
      controller.stepTimeoutGivesUpFormatValue = ""
      const fallback = mgr.capabilityChromeHTML(entry, { connectTimeout: 2, readTimeout: 2 }, {})
      expect(fallback).toContain("Gives up after 4 s")
    })

    it("enables retry for GET and disables it for POST without an idempotency key", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item data-step-action="api_call">
            <div data-config-field="httpMethod"><input data-config-input value="GET"></div>
            <div data-config-field="idempotencyKey"><input data-config-input value=""></div>
            <div data-config-field="retryOnTransportError"><input type="checkbox" data-config-input></div>
            <div data-config-field="retryAttempts"><input data-config-input type="number" value="1"></div>
            <div data-config-field="connectTimeout"><input data-config-input type="number" value="3"></div>
            <div data-config-field="readTimeout"><input data-config-input type="number" value="7"></div>
            <p data-step-timeout-hint></p>
            <input type="hidden" data-step-config value="{}">
            <span data-step-error-badge class="hidden">Error</span>
          </div>
        </div>`
      const item = controller.formTarget.querySelector("[data-step-item]")
      mgr._refreshCapabilityChrome(item)
      const retry = item.querySelector('[data-config-field="retryOnTransportError"] [data-config-input]')
      expect(retry.disabled).toBe(false)
      expect(item.querySelector("[data-step-timeout-hint]").textContent).toContain("10")

      item.querySelector('[data-config-field="httpMethod"] [data-config-input]').value = "POST"
      mgr._refreshCapabilityChrome(item)
      expect(retry.disabled).toBe(true)
      expect(retry.checked).toBe(false)
      expect(item.querySelector("[data-retry-idempotent-hint]").textContent).toContain("idempotent")

      item.querySelector('[data-config-field="idempotencyKey"] [data-config-input]').value = "abc"
      mgr._refreshCapabilityChrome(item)
      expect(retry.disabled).toBe(false)
      expect(item.querySelector("[data-retry-idempotent-hint]").classList.contains("hidden")).toBe(true)
      retry.checked = true
      mgr._refreshCapabilityChrome(item)
      expect(item.querySelector('[data-config-field="retryAttempts"] [data-config-input]').disabled).toBe(false)

      item.querySelector("[data-step-config]").value = JSON.stringify({ httpMethod: "POST", idempotencyKey: "abc", legacy: "kept" })
      item.querySelector('[data-config-field="idempotencyKey"] [data-config-input]').value = ""
      mgr._refreshCapabilityChrome(item)
      expect(retry.disabled).toBe(true)
    })

    it("hides retry fields when the action has no transportRetry capability", () => {
      controller.formTarget.innerHTML = `
        <div data-step-item data-step-action="find_model">
          <div data-config-field="retryOnTransportError">
            <input type="checkbox" data-config-input>
            <p data-retry-idempotent-hint>stale</p>
          </div>
          <div data-config-field="retryAttempts"><input data-config-input></div>
          <input type="hidden" data-step-config value="{}">
        </div>`
      mgr._refreshCapabilityChrome(controller.formTarget.querySelector("[data-step-item]"))
      expect(controller.formTarget.querySelector('[data-config-field="retryOnTransportError"]').classList.contains("hidden")).toBe(true)
      expect(controller.formTarget.querySelector("[data-retry-idempotent-hint]")).toBeNull()
    })

    it("no-ops capability chrome without a catalog entry, retry field, or timeout hint", () => {
      controller.formTarget.innerHTML = `<div data-step-item data-step-action="no_such_action"></div>`
      expect(() => mgr._refreshCapabilityChrome(controller.formTarget.querySelector("[data-step-item]"))).not.toThrow()

      controller.formTarget.innerHTML = `
        <div data-step-item data-step-action="api_call">
          <input type="hidden" data-step-config value="{">
        </div>`
      expect(() => mgr._refreshCapabilityChrome(controller.formTarget.querySelector("[data-step-item]"))).not.toThrow()
    })

    it("refreshAllCapabilityChrome walks every step and no-ops without a container", () => {
      controller.formTarget.innerHTML = `<div>none</div>`
      expect(() => mgr.refreshAllCapabilityChrome()).not.toThrow()
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item data-step-action="find_model"></div>
        </div>`
      expect(() => mgr.refreshAllCapabilityChrome()).not.toThrow()
    })

    it("applyConfigProblems paints field errors, aria-invalid, and the header badge", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item>
            <span data-step-error-badge class="hidden">Error</span>
            <div data-step-details class="hidden"></div>
            <span data-step-expand-icon><svg></svg></span>
            <div data-config-field="findBy"><input data-config-input></div>
            <div data-config-field="other"><input data-config-input></div>
          </div>
        </div>`
      mgr.applyConfigProblems([
        { type: "step_config_invalid", field: "findBy", message: "findBy is invalid", elementId: "p1" },
        { type: "codegen_failed", message: "nope" },
      ])
      const input = controller.formTarget.querySelector('[data-config-field="findBy"] [data-config-input]')
      expect(input.getAttribute("aria-invalid")).toBe("true")
      expect(controller.formTarget.querySelector("[data-field-error]").textContent).toBe("findBy is invalid")
      expect(controller.formTarget.querySelector("[data-step-error-badge]").classList.contains("hidden")).toBe(false)

      mgr.handleConfigFieldChange({ target: input })
      expect(controller.formTarget.querySelector("[data-field-error]")).toBeNull()
      expect(input.getAttribute("aria-invalid")).toBeNull()
      expect(controller.formTarget.querySelector("[data-step-error-badge]").classList.contains("hidden")).toBe(true)
    })

    it("applyConfigProblems no-ops without a container and skips unknown fields", () => {
      const savedFields = controller.formFieldsTarget
      controller.formFieldsTarget = null
      expect(() => mgr.applyConfigProblems([{ type: "step_config_invalid" }])).not.toThrow()
      controller.formFieldsTarget = savedFields
      controller.formTarget.innerHTML = `<div data-steps-container></div>`
      expect(() => mgr.applyConfigProblems()).not.toThrow()
      expect(() => mgr.applyConfigProblems(null)).not.toThrow()
      expect(() => mgr.applyConfigProblems([{ type: "step_config_invalid", field: "x" }])).not.toThrow()
      controller.currentElement = {}
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item>
            <div data-config-field="keep"><input data-config-input></div>
          </div>
        </div>`
      mgr.applyConfigProblems([
        { type: "step_config_invalid", field: "missing", message: "gone" },
        { type: "step_config_invalid", message: "no field" },
        { type: "step_config_invalid", field: "keep", message: "x", element_id: "p1" },
      ])
      expect(controller.formTarget.querySelector("[data-field-error]").textContent).toBe("x")
      controller.currentElement = { id: "other" }
      mgr.applyConfigProblems([
        { type: "step_config_invalid", field: "keep", message: "filtered", elementId: "p1" },
      ])
      expect(controller.formTarget.querySelector("[data-field-error]")).toBeNull()
      mgr._showStepFieldError(controller.formTarget.querySelector("[data-step-item]"), "nope", "gone")
    })

    it("applyConfigProblemsFromCanvas treats a missing canvas controller as no problems", () => {
      const canvasEl = document.createElement("div")
      canvasEl.setAttribute("data-controller", "flowchart-canvas")
      const form = document.createElement("form")
      canvasEl.appendChild(form)
      document.body.appendChild(canvasEl)
      controller.formTarget = form
      controller.formFieldsTarget = form
      controller.element = form
      form.innerHTML = `<div data-steps-container><div data-step-item></div></div>`
      controller.application = { getControllerForElementAndIdentifier: () => null }
      expect(() => mgr.applyConfigProblemsFromCanvas()).not.toThrow()
      canvasEl.remove()
    })

    it("applyConfigProblemsFromCanvas reads the sibling canvas controller", () => {
      const canvasEl = document.createElement("div")
      canvasEl.setAttribute("data-controller", "flowchart-canvas")
      const form = document.createElement("form")
      canvasEl.appendChild(form)
      document.body.appendChild(canvasEl)
      controller.formTarget = form
      controller.formFieldsTarget = form
      controller.element = form
      form.innerHTML = `<div data-steps-container><div data-step-item><span data-step-error-badge class="hidden"></span></div></div>`
      controller.application = {
        getControllerForElementAndIdentifier: () => ({
          _validationProblems: [{ type: "step_config_invalid", message: "bad" }],
        }),
      }
      mgr.applyConfigProblemsFromCanvas()
      expect(form.querySelector("[data-step-error-badge]").classList.contains("hidden")).toBe(false)
      canvasEl.remove()
    })

    it("applyConfigProblemsFromCanvas no-ops without a canvas mount", () => {
      expect(() => mgr.applyConfigProblemsFromCanvas()).not.toThrow()
      controller.application = null
      expect(() => mgr.applyConfigProblemsFromCanvas()).not.toThrow()
    })

    it("syncs retry chrome when the toggle input is missing", () => {
      controller.formTarget.innerHTML = `
        <div data-step-item data-step-action="api_call">
          <div data-config-field="retryOnTransportError"></div>
          <div data-config-field="retryAttempts"></div>
          <input type="hidden" data-step-config value="{}">
        </div>`
      expect(() => mgr._refreshCapabilityChrome(controller.formTarget.querySelector("[data-step-item]"))).not.toThrow()
    })

    it("computes timeout with retries and missing capability as 0", () => {
      expect(mgr._effectiveTimeoutSeconds({}, {})).toBe(0)
      expect(mgr._effectiveTimeoutSeconds({ capabilities: { timeouts: {} } }, {})).toBe(10)
      expect(mgr._effectiveTimeoutSeconds(
        { capabilities: { timeouts: { open: 1, read: 1, cap: 10 } } },
        { retryOnTransportError: true, retryAttempts: 0 }
      )).toBe(2)
      const entry = getActionConfig("api_call")
      expect(mgr._effectiveTimeoutSeconds(entry, {
        connectTimeout: 3, readTimeout: 7, retryOnTransportError: true, retryAttempts: 1,
      })).toBe(10)
      expect(mgr._effectiveTimeoutSeconds(entry, {
        connectTimeout: 1, readTimeout: 1, retryOnTransportError: "true", retryAttempts: 1,
      })).toBe(4)
      expect(mgr._configIsIdempotent(null, {})).toBe(false)
      expect(mgr._configIsIdempotent({ orPresent: "idempotencyKey" }, { idempotencyKey: "k" })).toBe(true)
      expect(mgr._configIsIdempotent({ idempotentWhen: {} }, {})).toBe(true)
      expect(mgr._configIsIdempotent({ idempotentWhen: { httpMethod: "GET" } }, { httpMethod: "GET" })).toBe(true)
      expect(mgr._configIsIdempotent({ idempotentWhen: { httpMethod: ["GET"] } }, {})).toBe(false)
      expect(mgr._configIsIdempotent({ idempotentWhen: { httpMethod: ["GET"] } }, { httpMethod: null })).toBe(false)
      expect(mgr._effectiveTimeoutSeconds(
        { capabilities: { timeouts: { open: 1, read: 1, cap: "x" } } },
        { retryOnTransportError: true, retryAttempts: "nope" }
      )).toBe(2)
      expect(mgr._effectiveTimeoutSeconds(
        { capabilities: { timeouts: { open: 1, read: 1, cap: 10 } } },
        { retryOnTransportError: false, retryAttempts: 9 }
      )).toBe(2)
      expect(mgr._effectiveTimeoutSeconds(
        { capabilities: { timeouts: { cap: 0 } } },
        { connectTimeout: 0, readTimeout: 0 }
      )).toBe(0)
      expect(mgr._effectiveTimeoutSeconds(
        { capabilities: { timeouts: { open: 4 } } },
        { retryOnTransportError: true, retryAttempts: null }
      )).toBe(10)
      expect(mgr._configWithDefaults(
        { fields: [{ key: "viaKey", default: 1 }, { name: "viaName", default: 2 }, { name: "", key: "emptyName", default: 3 }, { name: "skipNull", default: null }, { name: "skipUndef" }] },
        { viaName: "keep" }
      )).toEqual({ viaKey: 1, viaName: "keep", emptyName: 3 })
      controller.stepTimeoutGivesUpFormatValue = ""
      controller.formTarget.innerHTML = `
        <div data-step-item data-step-action="api_call">
          <p data-step-timeout-hint>stale</p>
          <input type="hidden" data-step-config value="">
        </div>`
      mgr._syncTimeoutHint(
        controller.formTarget.querySelector("[data-step-item]"),
        getActionConfig("api_call"),
        { connectTimeout: 2, readTimeout: 2 }
      )
      expect(controller.formTarget.querySelector("[data-step-timeout-hint]").textContent).toContain("4")
    })

    it("skips a field error when the field has no control", () => {
      controller.formTarget.innerHTML = `
        <div data-step-item>
          <div data-config-field="findBy"></div>
        </div>`
      mgr._showStepFieldError(controller.formTarget.querySelector("[data-step-item]"), "findBy")
      expect(controller.formTarget.querySelector("[data-field-error]").textContent).toBe("")
    })

    it("reuses an existing field-error node and hides a badge when none remains", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item>
            <span data-step-error-badge>Error</span>
            <div data-config-field="findBy">
              <input data-config-input>
              <p data-field-error>old</p>
            </div>
          </div>
        </div>`
      mgr._showStepFieldError(controller.formTarget.querySelector("[data-step-item]"), "findBy", "new")
      expect(controller.formTarget.querySelectorAll("[data-field-error]").length).toBe(1)
      expect(controller.formTarget.querySelector("[data-field-error]").textContent).toBe("new")
      mgr._refreshStepErrorBadge(controller.formTarget.querySelector("[data-step-item]"))
      expect(controller.formTarget.querySelector("[data-step-error-badge]").classList.contains("hidden")).toBe(false)
      mgr._refreshStepErrorBadge(document.createElement("div"))
    })
  })
})
