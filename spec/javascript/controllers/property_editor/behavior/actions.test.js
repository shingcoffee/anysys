import { describe, it, expect, afterEach } from "vitest"
import { getAllActions, getActionsByCategory, fieldName } from "flowchart/constants/action_registry"
import { configFieldType } from "controllers/property_editor/templates/fields"
import { SAMPLE_ACTION_CATALOG } from "../../../support/action_catalog.js"
import { mountEditor, change, press, sync } from "./_support.js"

let editor
afterEach(async () => { await editor?.dispose(); editor = null })

const optionValue = option => typeof option === "string" ? option : option.value
const sample = field => {
  switch (configFieldType(field)) {
    case "select": return String(optionValue(field.options.filter(opt => optionValue(opt) !== "").at(-1)))
    case "number": return Math.max(field.min ?? 0, Math.min(field.max ?? 17, 17))
    case "key_value_list": return [{ key: "payload", value: "ctx[:order]" }]
    case "toggle": return true
    case "list": return ["ctx[:tag]"]
    case "conditions": return {
      type: "group",
      joins: [],
      conditions: [{ kind: "field", leftOperand: "ctx[:left]", operator: "==", rightOperand: "1" }]
    }
    case "localized_text": return { en: `ctx[:${fieldName(field)}] < & "quoted"` }
    case "reference_picker": return "ref-1"
    default: return `ctx[:${fieldName(field)}] < & "quoted"`
  }
}

function legacyWhen(field) {
  const vw = field.visibleWhen
  if (!vw) return null
  if (vw.field) return vw
  const [name, allowed] = Object.entries(vw)[0] || []
  return name ? { field: name, values: Array.isArray(allowed) ? allowed : [allowed] } : null
}

async function fillConfig(schema) {
  const expected = {}
  for (const field of schema) {
    const key = fieldName(field)
    const type = configFieldType(field)
    const wrapper = editor.controller.formTarget.querySelector(`[data-config-field="${key}"]`)
    expect(wrapper, `render ${key}`).not.toBeNull()
    const value = sample(field)
    expected[key] = value
    if (type === "key_value_list") {
      await change(wrapper.querySelector("[data-kv-key]"), value[0].key)
      await change(wrapper.querySelector("[data-kv-value]"), value[0].value)
    } else if (type === "toggle") {
      const box = wrapper.querySelector("[data-config-input]")
      box.checked = value
      box.dispatchEvent(new Event("change", { bubbles: true }))
    } else if (type === "list") {
      await change(wrapper.querySelector("[data-list-value]"), value[0])
    } else if (type === "conditions") {
      const row = value.conditions[0]
      await change(wrapper.querySelector("[data-condition-left]"), row.leftOperand)
      await change(wrapper.querySelector("[data-condition-op]"), row.operator)
      await change(wrapper.querySelector("[data-condition-right]"), row.rightOperand)
    } else if (type === "localized_text") {
      await change(wrapper.querySelector('[data-locale-input][data-locale="en"]'), value.en)
    } else {
      await change(wrapper.querySelector("[data-config-input]"), value)
    }
  }
  return expected
}

function expectInitialVisibility(schema) {
  for (const dependent of schema.filter(field => field.visibleWhen)) {
    const root = editor.controller.formTarget
    const clause = legacyWhen(dependent)
    const controlling = root.querySelector(`[data-config-field="${clause.field}"] [data-config-input]`)
    const raw = clause.values ?? clause.value
    const visible = (Array.isArray(raw) ? raw : [raw]).map(String).includes(String(controlling.type === "checkbox" ? controlling.checked : controlling.value))
    const wrapper = root.querySelector(`[data-config-field="${fieldName(dependent)}"]`)
    expect(wrapper.classList.contains("hidden"), `${fieldName(dependent)} initial visibility`).toBe(!visible)
  }
}

it("covers the installed fixture catalog, with unique action keys", () => {
  expect(getAllActions()).toHaveLength(SAMPLE_ACTION_CATALOG.actions.length)
  expect(new Set(getAllActions().map(action => action.key)).size).toBe(SAMPLE_ACTION_CATALOG.actions.length)
})

for (const { category, actions } of getActionsByCategory()) {
  describe(`action configs / ${category.key}`, () => {
    for (const action of actions) {
      describe(action.key, () => {
        const schema = action.fields || []

        it("round-trips every rendered config field, clears stored values, and preserves stable step identity", async () => {
          editor = await mountEditor("process", { steps: [{ id: "stable-step", action: action.key, config: {} }] })
          expectInitialVisibility(schema)
          const expected = await fillConfig(schema)
          expect(sync(editor).steps[0]).toMatchObject({ id: "stable-step", action: action.key })
          expect(editor.node.properties.steps[0].config || {}).toEqual(expected)
          await editor.reopen()
          expect(editor.controller.stepManager.collectSteps()[0].config || {}).toEqual(expected)

          for (const field of schema.filter(field => configFieldType(field) !== "select" && configFieldType(field) !== "toggle")) {
            const key = fieldName(field)
            const type = configFieldType(field)
            const wrapper = editor.controller.formTarget.querySelector(`[data-config-field="${key}"]`)
            if (type === "key_value_list") {
              const originalRow = wrapper.querySelector("[data-kv-row]")
              await press(wrapper.querySelector('[data-action*="#removeConfigKvRow"]'))
              expect(originalRow.isConnected, `${key} row removed`).toBe(false)
              expect(wrapper.querySelectorAll("[data-kv-row]")).toHaveLength(1)
              delete expected[key]
            } else if (type === "list") {
              await change(wrapper.querySelector("[data-list-value]"), "")
              delete expected[key]
            } else if (type === "conditions") {
              await change(wrapper.querySelector("[data-condition-left]"), "")
              await change(wrapper.querySelector("[data-condition-op]"), "")
              await change(wrapper.querySelector("[data-condition-right]"), "")
              expected[key] = { type: "group", joins: [], conditions: [] }
            } else if (type === "localized_text") {
              for (const input of wrapper.querySelectorAll("[data-locale-input]")) {
                await change(input, "")
              }
              delete expected[key]
            } else {
              await change(wrapper.querySelector("[data-config-input]"), "")
              delete expected[key]
            }
          }
          const transportRetry = action.capabilities?.transportRetry
          if (transportRetry && "retryOnTransportError" in expected) {
            const stillIdempotent = Object.entries(transportRetry.idempotentWhen || {})
              .every(([key, allowed]) => [allowed].flat().map(String).includes(String(expected[key] ?? "")))
            if (!stillIdempotent) expected.retryOnTransportError = false
          }
          expect(sync(editor).steps[0].config || {}).toEqual(expected)
          await editor.reopen()
          expect(editor.node.properties.steps[0].config || {}).toEqual(expected)
        })

        for (const controlling of schema.filter(field => schema.some(dependent => legacyWhen(dependent)?.field === fieldName(field)))) {
          it(`updates ${fieldName(controlling)} dependent visibility and required validation for every option`, async () => {
            editor = await mountEditor("process", { steps: [{ id: "stable-step", action: action.key,
              config: Object.fromEntries(schema.filter(f => f.default !== undefined && f.default !== null).map(f => [fieldName(f), f.default])) }] })
            const root = editor.controller.formTarget
            const input = root.querySelector(`[data-config-field="${fieldName(controlling)}"] [data-config-input]`)
            for (const option of controlling.options.filter(opt => optionValue(opt) !== "")) {
              const value = String(optionValue(option))
              await change(input, value)
              for (const dependent of schema.filter(field => legacyWhen(field)?.field === fieldName(controlling))) {
                const clause = legacyWhen(dependent)
                const raw = clause.values ?? clause.value
                const visible = (Array.isArray(raw) ? raw : [raw]).map(String).includes(value)
                const field = root.querySelector(`[data-config-field="${fieldName(dependent)}"]`)
                expect(field.classList.contains("hidden"), `${fieldName(dependent)} when ${value}`).toBe(!visible)
                const depType = configFieldType(dependent)
                if (dependent.required && ["text", "textarea"].includes(depType)) {
                  expect(field.querySelector("[data-config-input]").required, `${fieldName(dependent)} required when ${value}`).toBe(visible)
                }
              }
            }
          })
        }

        it("commits the action from the real picker with schema defaults", async () => {
          editor = await mountEditor("process")
          const leaves = Object.entries(editor.controller.stepManager._pickerLeafMap).filter(([, leaf]) => leaf.action === action.key)
          expect(leaves.length).toBeGreaterThan(0)
          const [value] = leaves[0]
          await change(editor.controller.formTarget.querySelector('[data-step-picker] input[type="hidden"]'), value)
          const step = sync(editor).steps[0]
          expect(step.action).toBe(action.key)
          expect(step.id).toBeTruthy()
          for (const field of schema.filter(field => {
            const value = field.default
            if (value === undefined || value === null || value === "") return false
            return !(Array.isArray(value) && value.length === 0)
          })) {
            expect(step.config[fieldName(field)], `${fieldName(field)} default`).toEqual(field.default)
          }
          expect(editor.controller.formTarget.querySelectorAll("[data-step-item]")).toHaveLength(1)
        })
      })
    }
  })
}
