import { test, expect } from "@playwright/test"
import { bootEditor } from "./_browser_modules.js"

async function boot(page) {
  const requests = []
  await page.route("**/admin/maintenance/flowcharts/element_types/*/io_params", route => { requests.push(route) })
  await page.route("**/admin/maintenance/flowcharts/step_actions/*/io_params", route => route.fulfill({ json: { inputs: [], outputs: [] } }))
  await bootEditor(page, {
    type: "process",
    label: "Lookup",
    properties: { steps: [{ id: "lookup", action: "find_model", config: { resultVar: "model" } }] }
  })
  await page.evaluate(() => {
    const { editor, canvasController, node } = window.editorFixture
    editor._performSync()
    window.pinFixture = { editor, canvas: canvasController.canvas, node }
  })
  requests.splice(0)
  return requests
}

const finish = (request, pin) => request.fulfill({ json: { inputs: [], outputs: [{ pin }] } })
const pane = page => page.locator('[data-property-editor-target="formFieldsIo"]')
const pins = page => page.evaluate(() => {
  const { canvas, node } = window.pinFixture
  return canvas.getElementPins(node.id).outputs
})

test("close/reopen same element hands the shared background result to the active I/O pane", async ({ page }) => {
  const requests = await boot(page)
  await page.locator('[data-tab="io"]').click()
  await expect.poll(() => requests.length).toBe(1)
  await page.evaluate(() => {
    const { editor, canvas, node } = window.pinFixture
    editor.close()
    editor.openEditor(node, canvas)
    editor.tabManager.switchTo("io")
  })
  await expect.poll(() => requests.length).toBeGreaterThanOrEqual(1)
  await finish(requests[requests.length - 1], "model")
  await expect(pane(page)).toContainText("model")
  expect(await pins(page)).toEqual([{ pin: "model" }])
})

for (const order of ["old-first", "fresh-first"]) {
  test(`background config change updates the active pane without reopening (${order})`, async ({ page }) => {
    const requests = await boot(page)
    await page.locator('[data-tab="io"]').click()
    await expect.poll(() => requests.length).toBe(1)
    await page.evaluate(() => {
      const { canvas, node } = window.pinFixture
      canvas.updateElementProperties(node.id, node.label, { steps: [{ id: "lookup", action: "find_model", config: { resultVar: "new_model" } }] })
    })
    await expect.poll(() => requests.length).toBe(2)
    if (order === "old-first") {
      await finish(requests[0], "obsolete")
      await expect(pane(page)).not.toContainText("obsolete")
      await finish(requests[1], "new_model")
    } else {
      await finish(requests[1], "new_model")
      await expect(pane(page)).toContainText("new_model")
      await finish(requests[0], "obsolete")
    }
    await expect(pane(page)).toContainText("new_model")
    await page.waitForTimeout(700)
    await expect(pane(page)).not.toContainText("obsolete")
    expect(await pins(page)).toEqual([{ pin: "new_model" }])
    expect(requests).toHaveLength(2)
  })
}

test("background handoff cannot render into another selection", async ({ page }) => {
  const requests = await boot(page)
  await page.locator('[data-tab="io"]').click()
  await expect.poll(() => requests.length).toBe(1)
  await page.evaluate(() => {
    const { editor, canvas } = window.pinFixture
    editor.openConnectionEditor({ id: "edge", label: "Next", properties: {} }, canvas)
  })
  await finish(requests[0], "obsolete")
  await page.waitForTimeout(700)
  await expect(pane(page)).toBeEmpty()
  await expect(page.locator('[name="label"]')).toHaveValue("Next")
  expect(await page.evaluate(() => window.pinFixture.node.properties.io_overrides)).toBeUndefined()
})
