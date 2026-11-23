import { test, expect } from "@playwright/test"
import { bootEditor, nativeSave } from "./_browser_modules.js"

test.describe("native property-editor submit / real production modules", () => {
  test("flat conditions preserve false/zero and remove only the selected row", async ({ page }) => {
    const field = (value, operator = "==") => ({
      kind: "field", leftOperand: "signal", operator, rightOperand: value
    })
    await bootEditor(page, {
      type: "decision",
      properties: {
        routeBy: "condition",
        condition: { type: "group", joins: ["OR"], conditions: [field(false), field(0)] }
      },
      extraElements: [
        { id: "yes_box", type: "process", label: "Yes", x: 80, y: 240 },
        { id: "no_box", type: "process", label: "No", x: 320, y: 240 }
      ],
      connections: [
        { from: "__node__", to: "yes_box", fromPort: "port_0", label: "Yes", matchValue: "true" },
        { from: "__node__", to: "no_box", fromPort: "port_1", label: "No", matchValue: "false" }
      ]
    })
    await page.locator('[data-tab="general"]').click()
    const rows = page.locator("[data-condition-row]")
    await expect(rows).toHaveCount(2)
    await expect(rows.nth(0).locator("[data-condition-right]")).toHaveValue("false")
    await expect(rows.nth(1).locator("[data-condition-right]")).toHaveValue("0")
    await rows.nth(1).locator("[data-condition-right]").fill("updated")
    await rows.nth(0).locator('[data-action*="#removeRow"]').click()
    const saved = await nativeSave(page)
    expect(saved.elements[0].properties.condition).toEqual({
      type: "group",
      joins: [],
      conditions: [field("updated")]
    })
  })

  test("key-value deletion autosyncs before native Save and preserves false/zero values", async ({ page }) => {
    await bootEditor(page, {
      type: "process",
      properties: {
        steps: [{
          id: "api",
          action: "api_call",
          config: {
            url: "https://example.test",
            headers: [{ key: "zero", value: 0 }, { key: "flag", value: false }]
          }
        }]
      }
    })
    await page.locator('[data-tab="steps"]').click()
    await page.locator('[data-step-item] [data-action*="#toggleStep"]').click({ force: true })
    const list = page.locator('[data-config-field="headers"]')
    await expect(list.locator("[data-kv-value]").first()).toHaveValue("0")
    await expect(list.locator("[data-kv-value]").last()).toHaveValue("false")
    await list.locator('[data-action*="#removeConfigKvRow"]').first().click()
    await expect.poll(() => page.evaluate(() => window.editorFixture.node.properties.steps[0].config.headers))
      .toEqual([{ key: "flag", value: "false" }])
    expect((await nativeSave(page)).elements[0].properties.steps[0].config.headers)
      .toEqual([{ key: "flag", value: "false" }])
  })

  test("returning from read-only to draft restores the native Save control", async ({ page }) => {
    await bootEditor(page, { type: "end", properties: { responseType: "none" } })
    await page.evaluate(() => {
      const { editor, canvasController, node } = window.editorFixture
      canvasController.readOnlyValue = true
      editor.openEditor(node, canvasController.canvas)
    })
    await expect(page.locator('[data-property-editor-target="saveButton"]')).toBeDisabled()
    await page.evaluate(() => {
      const { editor, canvasController, node } = window.editorFixture
      editor.close()
      canvasController.readOnlyValue = false
      editor.openEditor(node, canvasController.canvas)
    })
    await expect(page.locator('[data-property-editor-target="saveButton"]')).toBeEnabled()
    expect((await nativeSave(page)).elements[0].properties.responseType).toBe("none")
  })

  test("find_model manual attribute is the sole required widget and permits native submission", async ({ page }) => {
    await bootEditor(page, {
      type: "process",
      properties: { steps: [{ id: "lookup", action: "find_model", config: { findBy: "attribute" } }] }
    })
    await page.evaluate(() => {
      const { editor, canvasController, node } = window.editorFixture
      canvasController.canvas.entityAttributes = [{ name_slug: "amount", name: "Amount", html_type: "number" }]
      editor.openEditor(node, canvasController.canvas)
    })
    await page.locator('[data-tab="steps"]').click()
    await page.locator('[data-step-item] [data-action*="#toggleStep"]').click({ force: true })
    const select = page.locator('[data-config-field="findField"] [data-entity-column-select]')
    const manual = page.locator('[data-config-field="findField"] [data-entity-column-manual]')
    await select.selectOption("amount")
    await select.selectOption("__manual__")
    await manual.fill("external_amount")
    await page.locator('[data-config-field="findValue"] [data-config-input]').fill("ctx.amount")
    expect(await select.evaluate(input => input.required)).toBe(false)
    expect(await manual.evaluate(input => input.required)).toBe(true)
    expect(await page.locator("form").evaluate(form => form.checkValidity())).toBe(true)
    expect((await nativeSave(page)).elements[0].properties.steps[0].config.findField).toBe("external_amount")
  })

  test("entity-column selection submits without validating the hidden manual alternative", async ({ page }) => {
    await bootEditor(page, {
      type: "process",
      properties: { steps: [{ id: "lookup", action: "find_model", config: { findBy: "attribute" } }] }
    })
    await page.evaluate(() => {
      const { editor, canvasController, node } = window.editorFixture
      canvasController.canvas.entityAttributes = [{ name_slug: "email", name: "Email", html_type: "text" }]
      editor.openEditor(node, canvasController.canvas)
    })
    await page.locator('[data-tab="steps"]').click()
    await page.locator('[data-step-item] [data-action*="#toggleStep"]').click({ force: true })
    await page.locator('[data-config-field="findField"] [data-entity-column-select]').selectOption("email")
    await page.locator('[data-config-field="findValue"] [data-config-input]').fill("ctx.email")
    await expect(page.locator("[data-entity-column-manual]")).toBeHidden()
    const properties = (await nativeSave(page)).elements[0].properties
    expect(properties.steps[0].config.findField).toBe("email")
  })

  test("an empty Subflow target is flagged inline and saves a numeric id after pick", async ({ page }) => {
    await bootEditor(page, { type: "subflow" })
    await expect(page.locator('[data-element-field="flowchartId"]')).toBeVisible()
    await page.locator('[data-property-editor-target="saveButton"]').click()
    await expect(page.locator('[data-element-field="flowchartId"] [data-field-error]')).toBeVisible()
    await expect(page.locator('[data-element-field="flowchartId"] [aria-invalid="true"]')).toHaveCount(1)
    await page.locator('[data-property-editor--controls--reference-picker-target="trigger"]').click()
    await page.locator("[data-reference-option='9']").click()
    expect(Number((await nativeSave(page)).elements[0].properties.flowchartId)).toBe(9)
  })

  test("loop type switch hides inactive required fields and persist prunes them", async ({ page }) => {
    await bootEditor(page, {
      type: "loop",
      properties: { loopType: "for_each", collection: "items", maxIterations: 5 }
    })
    await page.locator('[name="loopType"]').selectOption("while")
    await expect(page.locator('[data-element-field="collection"]')).toBeHidden()
    await page.locator('[data-element-field="condition"] [data-condition-left]').fill("keep_going")
    await page.locator('[data-element-field="condition"] [data-condition-op]').selectOption("is_true")
    const live = await page.evaluate(() => {
      window.editorFixture.editor._performSync()
      return window.editorFixture.node.properties
    })
    expect(live.collection).toBe("items")
    const saved = (await nativeSave(page)).elements[0].properties
    expect(saved.loopType).toBe("while")
    expect(saved).not.toHaveProperty("collection")
    expect(saved.maxIterations).toBe(5)
  })

  test("End Nothing submits without Return Value", async ({ page }) => {
    await bootEditor(page, {
      type: "end",
      properties: { responseType: "value", returnValue: "ctx.result" }
    })
    await expect(page.locator('[name="responseType"]')).toHaveValue("value")
    await page.locator('[name="responseType"]').selectOption("none")
    await expect(page.locator('[data-element-field="returnValue"]')).toBeHidden()
    const properties = (await nativeSave(page)).elements[0].properties
    expect(properties.responseType).toBe("none")
    expect(properties).not.toHaveProperty("returnValue")
    expect(properties).not.toHaveProperty("httpStatus")
    expect(properties).not.toHaveProperty("responseBody")
  })

  test("find_model changes required-field applicability and preserves the selected strategy on reopen", async ({ page }) => {
    await bootEditor(page, {
      type: "process",
      properties: { steps: [{ id: "lookup", action: "find_model", config: { findBy: "attribute", findField: "" } }] }
    })
    await page.locator('[data-tab="steps"]').click()
    await page.locator('[data-step-item] [data-action*="#toggleStep"]').click({ force: true })
    const strategy = page.locator('[data-config-input="findBy"]')
    await expect(strategy).toHaveValue("attribute")
    await expect(page.locator('[data-config-field="findField"]')).toBeVisible()
    await strategy.selectOption("id")
    await expect(page.locator('[data-config-field="findField"]')).toBeHidden()
    const properties = (await nativeSave(page)).elements[0].properties
    expect(properties.steps[0]).toMatchObject({ id: "lookup", action: "find_model", config: { findBy: "id" } })
    await expect(page.locator('[data-controller="property-editor"]')).toBeHidden()
    await page.evaluate(() => {
      const { editor, canvasController, node } = window.editorFixture
      editor.openEditor(node, canvasController.canvas)
    })
    await page.locator('[data-tab="steps"]').click()
    await page.locator('[data-step-item] [data-action*="#toggleStep"]').click({ force: true })
    await expect(strategy).toHaveValue("id")
  })
})
