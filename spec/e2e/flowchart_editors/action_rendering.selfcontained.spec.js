import { test, expect } from "@playwright/test"
import { readFileSync } from "node:fs"
import { loadEditorFixture } from "./_browser_modules.js"

const catalog = JSON.parse(readFileSync(new URL("../../../spec/javascript/fixtures/action_catalog.sample.json", import.meta.url)))
const categories = catalog.categories.map(category => category.key).sort()

// One module load per category, one named step per installed catalog action.
// Rendering-only: no FlowchartCanvasController, diagram mutations, save, pin
// requests, or backend fixtures. All widgets and collection use the real
// StepManager on a mounted PropertyEditorController, without compatibility shims.
for (const category of categories) {
  test(`native action rendering / ${category}`, async ({ page }) => {
    const apiRequests = []
    page.on("request", request => {
      if (["fetch", "xhr"].includes(request.resourceType())) apiRequests.push(request.url())
    })
    await loadEditorFixture(page)
    const actions = await page.evaluate(async ({ category, catalog }) => {
      const [{ Application }, { default: Editor }, registry] = await Promise.all([
        import("@hotwired/stimulus"), import("controllers/property_editor_controller"), import("flowchart/constants/action_registry")
      ])
      registry.setActionCatalog(catalog)
      const application = Application.start()
      application.register("property-editor", Editor)
      await new Promise(resolve => requestAnimationFrame(resolve))
      const editor = application.getControllerForElementAndIdentifier(document.querySelector('[data-controller="property-editor"]'), "property-editor")
      editor.canvas = { entityAttributes: [{ name_slug: "amount", name: "Amount", html_type: "number" }] }
      editor.currentElement = { id: "rendering", type: "process", properties: {} }
      editor.tabManager.configureForElementType("process")
      window.actionRendering = { editor, registry }
      if (registry.getAllActions().length !== catalog.actions.length) {
        throw new Error(`Expected ${catalog.actions.length} catalog actions`)
      }
      const registeredCategories = registry.getActionsByCategory().map(group => group.category.key).sort()
      return {
        keys: registry.getActionsByCategory().find(group => group.category.key === category).actions.map(action => action.key),
        registeredCategories
      }
    }, { category, catalog })
    expect(actions.registeredCategories).toEqual(categories)

    for (const action of actions.keys) {
      await test.step(action, async () => {
        await page.evaluate(async actionKey => {
          const { editor, registry } = window.actionRendering
          const action = registry.getActionConfig(actionKey)
          const schema = action.fields || []
          const fieldName = field => field.name || field.key
          const fieldControl = field => field.control || field.type
          const optionValue = option => typeof option === "string" ? option : option.value
          const change = (input, value) => {
            if (input.type === "checkbox") input.checked = value === true || value === "true"
            else input.value = String(value)
            input.dispatchEvent(new Event("input", { bubbles: true }))
            input.dispatchEvent(new Event("change", { bubbles: true }))
          }
          const check = (actual, expected, detail) => {
            if (actual !== expected) throw new Error(`${actionKey}: ${detail}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`)
          }
          const field = key => editor.formTarget.querySelector(`[data-config-field="${key}"]`)
          const input = key => field(key).querySelector("[data-config-input]")
          const controlValue = key => {
            const el = input(key)
            return el.type === "checkbox" ? el.checked : el.value
          }
          const matchesClause = clause => {
            if (clause.field) {
              const raw = clause.values ?? clause.value
              return (Array.isArray(raw) ? raw : [raw]).map(String).includes(String(controlValue(clause.field)))
            }
            return Object.entries(clause).every(([name, allowed]) => {
              const raw = Array.isArray(allowed) ? allowed : [allowed]
              return raw.map(String).includes(String(controlValue(name)))
            })
          }
          const applies = schemaField => !schemaField.visibleWhen || matchesClause(schemaField.visibleWhen)
          const isRequired = schemaField => schemaField.requiredWhen
            ? matchesClause(schemaField.requiredWhen)
            : Boolean(schemaField.required)
          const checkVisibility = schema => {
            for (const schemaField of schema.filter(item => item.visibleWhen)) {
              const key = fieldName(schemaField)
              check(field(key).classList.contains("hidden"), !applies(schemaField), `${key} visibility`)
              const control = fieldControl(schemaField)
              if (schemaField.required && !schemaField.entityField && ["text", "textarea"].includes(control)) {
                check(input(key).required, applies(schemaField), `${key} required`)
              }
            }
          }

          const render = async config => {
            editor.stepManager.reset()
            editor.formFieldsStepsTarget.innerHTML = editor.stepManager.buildStepsFieldHTML("steps", { type: "steps" }, [
              { id: "rendered-step", action: actionKey, config }
            ])
            await new Promise(resolve => requestAnimationFrame(resolve))
          }
          await render({})
          check(editor.formTarget.querySelectorAll("[data-config-field]").length, schema.length, "rendered schema fields")
          for (const schemaField of schema.filter(item => fieldControl(item) === "select")) {
            const key = fieldName(schemaField)
            const expected = String(schemaField.default ?? optionValue(schemaField.options[0]))
            check(input(key).value, expected, `${key} native default selection`)
          }
          checkVisibility(schema)

          const selections = {}
          for (const schemaField of schema.filter(item => fieldControl(item) === "select")) {
            const key = fieldName(schemaField)
            for (const option of schemaField.options) {
              const value = String(optionValue(option))
              change(input(key), value)
              check(input(key).value, value, `${key} native selection`)
              check(editor.stepManager.collectSteps()[0].config?.[key] ?? "", value, `${key} collection`)
              checkVisibility(schema)
              selections[key] = value
            }
          }
          await render(editor.stepManager.collectSteps()[0].config || {})
          for (const [key, value] of Object.entries(selections)) check(input(key).value, value, `${key} native selection after re-render`)

          for (const schemaField of schema.filter(item => item.entityField === true || fieldControl(item) === "attribute_picker")) {
            const config = {}
            if (schemaField.visibleWhen) {
              const clause = schemaField.visibleWhen
              if (clause.field) {
                const raw = clause.values ?? clause.value
                config[clause.field] = Array.isArray(raw) ? raw[0] : raw
              } else {
                Object.entries(clause).forEach(([name, allowed]) => {
                  config[name] = Array.isArray(allowed) ? allowed[0] : allowed
                })
              }
            }
            await render(config)
            const key = fieldName(schemaField)
            const wrapper = field(key)
            const select = wrapper.querySelector("[data-entity-column-select]")
            const manual = wrapper.querySelector("[data-entity-column-manual]")
            if (!select || !manual) continue
            const required = isRequired(schemaField)
            change(select, "amount")
            check(select.required, required, `${key} dropdown required`)
            check(manual.required, false, `${key} inactive manual required`)
            change(select, "__manual__")
            check(select.required, false, `${key} inactive dropdown required`)
            check(manual.required, required, `${key} manual required`)
            check(manual.checkValidity(), !required, `${key} empty manual validity`)
            change(manual, "external_amount")
            check(select.checkValidity() && manual.checkValidity(), true, `${key} populated manual validity`)
            check(editor.stepManager.collectSteps()[0].config[key], "external_amount", `${key} manual collection`)
            wrapper.querySelector('[data-action*="#swapEntityColumnToSelect"]').click()
            check(select.required, required, `${key} restored dropdown required`)
            check(manual.required, false, `${key} restored inactive manual required`)
            check(select.checkValidity(), !required, `${key} empty dropdown validity`)
            change(select, "amount")
            check(select.checkValidity() && manual.checkValidity(), true, `${key} populated dropdown validity`)
            check(editor.stepManager.collectSteps()[0].config[key], "amount", `${key} dropdown collection`)
          }
        }, action)
      })
    }
    expect(apiRequests, "rendering must not issue API requests").toEqual([])
  })
}
