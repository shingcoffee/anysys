import { test, expect, observeDrag } from "./helpers/drag_fixtures.js"

// Tier C: native HTML5 drag from the visible grip, using real Chromium input and
// measured row geometry. Each test owns its entity in the checked E2E database.
const BASE = process.env.APP_BASE_URL

test.use({ viewport: { width: 1440, height: 1000 } })

test.describe("entity attribute drag reorder (dnd_manager)", () => {
  test.skip(!BASE, "set APP_BASE_URL to run app-backed e2e (see spec/e2e/README.md)")

  test("dragging a row reorders the attribute list and persists after reload", async ({ page, dragFixture }, testInfo) => {
    test.setTimeout(90_000)
    const response = await page.goto(BASE + dragFixture.entity_edit_path)
    expect(response?.ok()).toBeTruthy()
    // Server-rendered rows precede asynchronous Stimulus module loading. Native
    // dragover must reach the connected controller for Chromium to allow a drop.
    await page.waitForLoadState("networkidle")

    const rowSel = "[data-attribute-item][data-attr-name-slug]"
    const rows = page.locator(rowSel)
    const slugs = () => rows.evaluateAll(elements => elements.map(element => element.getAttribute("data-attr-name-slug")))
    await expect(rows).toHaveCount(3)
    const before = await slugs()
    expect(before).toEqual(["first_name", "status", "note"])
    const events = await observeDrag(page)
    const source = rows.last().locator("td.cursor-grab")
    const target = rows.first().locator("td.cursor-grab")
    await expect(source).toBeVisible()
    await expect(target).toBeVisible()
    // Scroll before pressing: dragTo's per-target automatic scrolling can move
    // the table while a native drag is already active.
    await source.scrollIntoViewIfNeeded()
    await target.scrollIntoViewIfNeeded()
    const sourceBox = await source.boundingBox()
    const targetBox = await target.boundingBox()
    expect(sourceBox).not.toBeNull()
    expect(targetBox).not.toBeNull()
    expect(sourceBox.y + sourceBox.height).toBeLessThan(page.viewportSize().height)
    expect(targetBox.y).toBeGreaterThan(0)

    // Real mouse input creates Chromium's native DataTransfer and crosses the
    // drag threshold while both handles remain inside the viewport.
    const sx = sourceBox.x + sourceBox.width / 2
    const sy = sourceBox.y + sourceBox.height / 2
    const tx = targetBox.x + targetBox.width / 2
    const ty = targetBox.y + targetBox.height / 2
    await page.mouse.move(sx, sy)
    await page.mouse.down()
    await page.mouse.move(sx + 8, sy, { steps: 4 })
    await page.mouse.move(tx, ty, { steps: 12 })
    await page.mouse.move(tx, ty + 2)
    await page.mouse.up()
    await expect.poll(slugs).toEqual(["note", "first_name", "status"])
    const after = await slugs()
    const input = await events()
    expect(input.some(event => event.type === "dragstart" && event.trusted && event.id === "note")).toBe(true)
    expect(input.some(event => event.type === "drop" && event.trusted && event.id === "first_name")).toBe(true)

    const form = page.locator("form[data-controller~='entity-form']")
    const saveResponse = page.waitForResponse(response =>
      new URL(response.url()).pathname === dragFixture.entity_edit_path.replace(/\/edit$/, "") && response.request().method() === "POST")
    await form.locator("button[type='submit']").click()
    const saved = await saveResponse
    expect(saved.ok() || saved.status() === 302 || saved.status() === 303).toBe(true)
    const persisted = dragFixture.snapshot()
    expect(persisted.entity.slugs).toEqual(after)
    expect(persisted.entity.version_id).not.toBe(dragFixture.initialSnapshot.entity.version_id)

    await page.goto(BASE + dragFixture.entity_edit_path)
    await page.reload()
    await expect.poll(slugs).toEqual(after)
    expect(dragFixture.errors).toEqual([])
    await testInfo.attach("drag-persistence-proof", {
      body: JSON.stringify({ before, after, persisted, reloaded: await slugs(), sourceBox, targetBox, input, saveStatus: saved.status() }, null, 2),
      contentType: "application/json"
    })
  })
})
