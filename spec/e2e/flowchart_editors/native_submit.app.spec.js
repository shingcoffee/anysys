import { test, expect, observeDrag } from "../helpers/drag_fixtures.js"

const BASE = process.env.APP_BASE_URL

test.use({ dragKind: "flowchart", flowchartEndResponse: "value", viewport: { width: 1440, height: 1000 } })

test.describe("property editor / deployed Rails form and persistence", () => {
  test.skip(!BASE, "set APP_BASE_URL to run app-backed e2e (see spec/e2e/README.md)")

  test("native End submit persists a cleared return value across reload", async ({ page, dragFixture }, testInfo) => {
    test.setTimeout(90_000)
    const before = dragFixture.initialSnapshot.flowchart
    expect(before.status).toBe("draft")
    expect(before.configuration.elements.find(node => node.id === "end_1").properties).toMatchObject({
      responseType: "value", returnValue: "ctx.result"
    })
    const loaded = await page.goto(BASE + dragFixture.flowchart_edit_path)
    expect(loaded?.ok()).toBeTruthy()
    await page.waitForFunction(() => {
      const root = document.querySelector('[data-controller~="flowchart-canvas"]')
      return root && window.Stimulus?.getControllerForElementAndIdentifier(root, "flowchart-canvas")?.isCanvasReady
    })
    const root = page.locator('[data-controller~="flowchart-canvas"]')
    await expect(root).toHaveAttribute("data-flowchart-canvas-read-only-value", "false")
    const end = root.locator('[data-flowchart-canvas-target="canvasWrapper"] [data-element-id="end_1"]')
    await expect(end).toBeVisible()
    const events = await observeDrag(page)
    await end.dblclick()
    const form = page.locator('[data-property-editor-target="form"]')
    await expect(form.locator('[name="responseType"]')).toHaveValue("value")
    await form.locator('[name="responseType"]').selectOption("none")
    await form.evaluate(element => element.addEventListener("submit", event => {
      window.__nativeSubmitProof = { trusted: event.isTrusted, submitter: event.submitter?.getAttribute("data-property-editor-target") }
    }, { capture: true, once: true }))
    const response = page.waitForResponse(response => response.request().method() === "PATCH" &&
      new URL(response.url()).pathname === dragFixture.flowchart_edit_path.replace(/\/edit$/, ""))
    await form.locator('[data-property-editor-target="saveButton"]').click()
    const saved = await response
    expect(saved.ok()).toBe(true)
    const nativeSubmit = await page.evaluate(() => window.__nativeSubmitProof)
    expect(nativeSubmit).toEqual({ trusted: true, submitter: "saveButton" })
    const input = await events()
    expect(input.some(event => event.type === "mousedown" && event.trusted && event.id === "end_1")).toBe(true)
    const persisted = dragFixture.snapshot().flowchart
    expect(persisted.version_id).not.toBe(before.version_id)
    const properties = persisted.configuration.elements.find(node => node.id === "end_1").properties
    expect(properties.responseType).toBe("none")
    expect(properties).not.toHaveProperty("returnValue")
    expect(properties).not.toHaveProperty("httpStatus")
    expect(properties).not.toHaveProperty("responseBody")

    await page.reload()
    await expect(end).toBeVisible()
    const reloaded = JSON.parse(await root.getAttribute("data-flowchart-canvas-configuration-value"))
      .elements.find(node => node.id === "end_1").properties
    expect(reloaded).toEqual(properties)
    await end.dblclick()
    await expect(form.locator('[name="responseType"]')).toHaveValue("none")
    expect(dragFixture.errors).toEqual([])
    await testInfo.attach("native-submit-persistence-proof", {
      body: JSON.stringify({ flowchartId: dragFixture.flowchart_id, before, persisted, reloaded, nativeSubmit, input, saveStatus: saved.status() }, null, 2),
      contentType: "application/json"
    })
  })
})
