import { test, expect } from "@playwright/test"

const APP_BASE_URL = process.env.APP_BASE_URL || "http://127.0.0.1:3000"

test.describe("Email template builder — insert + editor sync", () => {
  test("inserts a variable and syncs Rich Text ↔ HTML", async ({ page }) => {
    await page.goto(`${APP_BASE_URL}/81721200/admin/modules/emails/templates/new`)
    await page.waitForLoadState("networkidle")

    const name = page.locator('input[name="email_template[name]"]')
    const subject = page.locator('input[name="email_template[subject]"]')
    await expect(name).toBeVisible()
    await name.fill("Browser Sync Check")
    await subject.fill("Hi {{first_name}}")

    const modeButton = (mode) => page.locator(`[data-template-editor-mode-target="modeButton"][data-mode="${mode}"]`)
    await modeButton("rich_text").click()

    const lexxy = page.locator("lexxy-editor").first()
    await expect(lexxy).toBeVisible()
    const editable = lexxy.locator('[contenteditable="true"]').first()
    await editable.click()
    await editable.pressSequentially("Hello world")

    // Park the caret mid-text so the token must land at the cursor, not the tail.
    await editable.press("Home")
    for (let i = 0; i < "Hello ".length; i++) await editable.press("ArrowRight")

    // Insert variable via searchable picker (mouse). Option values are the
    // token's display label, which varies by environment — derive the expected
    // label from the clicked option instead of hard-coding it.
    const searchInput = page.locator('[data-controller="template-token-picker"] [data-searchable-select-target="search"]')
    await expect(searchInput).toBeVisible()
    await searchInput.click()
    await searchInput.fill("first")

    const option = page.locator('[data-searchable-select-target="option"]').filter({ hasText: /first/i }).first()
    await expect(option).toBeVisible({ timeout: 5000 })
    const insertedLabel = await option.getAttribute("data-value")
    await option.click()

    // The token must appear exactly where the caret was parked — mid-text.
    const escapedLabel = insertedLabel.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
    await expect.poll(async () => (await editable.textContent()) || "")
      .toMatch(new RegExp(`Hello \\{\\{${escapedLabel}\\}\\}world`))

    // Switch to HTML code — content must reflect rich text (including variable)
    await modeButton("code").click()
    const htmlArea = page.locator('textarea[name="email_template[body_html]"]')
    await expect(htmlArea).toBeVisible()
    await expect.poll(async () => htmlArea.inputValue())
      .toMatch(new RegExp(`Hello \\{\\{${escapedLabel}\\}\\}world`))

    // Edit in HTML mode, then switch back to Rich Text — must reflect
    const current = await htmlArea.inputValue()
    const updated = current.includes("</p>")
      ? current.replace(/<\/p>\s*$/i, " from code</p>")
      : `${current}<p> from code</p>`
    await htmlArea.fill(updated)

    await modeButton("rich_text").click()
    await expect(lexxy).toBeVisible()
    await expect.poll(async () => (await editable.textContent()) || "").toMatch(/from code/i)
    await expect.poll(async () => (await editable.textContent()) || "").toContain(`{{${insertedLabel}}}`)
  })

  test("preview HTML matches rich text editor fragment", async ({ page }) => {
    await page.goto(`${APP_BASE_URL}/81721200/admin/modules/emails/templates/new`)
    await page.waitForLoadState("networkidle")

    await page.locator('input[name="email_template[name]"]').fill("Preview Match Check")
    await page.locator('input[name="email_template[subject]"]').fill("Subject line")
    await page.locator('[data-template-editor-mode-target="modeButton"][data-mode="rich_text"]').click()

    const lexxy = page.locator("lexxy-editor").first()
    await expect(lexxy).toBeVisible()
    const editable = lexxy.locator('[contenteditable="true"]').first()
    await editable.click()
    await editable.pressSequentially("Preview parity check ")

    // Bold selection via Lexxy toolbar if present; otherwise rely on typed text
    const marker = "Preview parity check"
    await expect.poll(async () => (await editable.textContent()) || "").toContain(marker)

    // The preview rail auto-refreshes as you type — wait for the debounced POST
    const response = await page.waitForResponse(
      (res) =>
        res.url().includes("/templates/preview") &&
        res.request().method() === "POST" &&
        (res.request().postData() || "").includes(marker),
      { timeout: 15000 }
    )
    expect(response.ok()).toBeTruthy()
    const json = await response.json()

    expect(json.body_html).toContain(marker)
    expect(json.body_html).not.toContain("trix-content")
    expect(json.body_html).not.toMatch(/<!--\s*BEGIN/)

    // Iframe should render the same fragment (no ActionText chrome)
    const iframe = page.locator('iframe[data-remote-template-preview-target="iframe"]').first()
    await expect(iframe).toBeVisible({ timeout: 10000 })
    const srcdoc = await iframe.getAttribute("srcdoc")
    expect(srcdoc || "").toContain(marker)
    expect(srcdoc || "").not.toContain("trix-content")
  })
})
