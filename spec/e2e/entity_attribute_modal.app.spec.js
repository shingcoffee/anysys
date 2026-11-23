import { test, expect } from "@playwright/test"

// App-backed: Add Attribute modal layout on entity create.
// Requires SKIP_AUTH=1 on the Rails server. See spec/e2e/README.md.
const BASE = process.env.APP_BASE_URL
const NEW_ENTITY = "/81721200/admin/maintenance/entities/new"

test.use({ ignoreHTTPSErrors: true })

async function openAttributeModal(page) {
  const response = await page.goto(`${BASE}${NEW_ENTITY}`, { waitUntil: "networkidle" })
  expect(response?.ok()).toBeTruthy()
  const addBtn = page.locator("[data-action='click->entity-form#openModal']")
  await expect(addBtn).toBeVisible()
  await addBtn.click()
  const dialog = page.getByRole("dialog")
  await expect(dialog).toBeVisible({ timeout: 10_000 })
  return dialog
}

test.describe("entity add-attribute modal", () => {
  test.skip(!BASE, "set APP_BASE_URL to run app-backed e2e (see spec/e2e/README.md)")

  test("opens a tabbed dialog, switches sections, and adds a field", async ({ page }) => {
    test.setTimeout(60_000)
    await page.setViewportSize({ width: 1280, height: 800 })
    const dialog = await openAttributeModal(page)

    await expect(dialog.getByRole("heading", { name: "Add Attribute" })).toBeVisible()
    await expect(dialog.getByRole("tab", { name: "Field" })).toHaveAttribute("aria-selected", "true")
    await expect(dialog.locator("#attr-modal-name")).toBeFocused({ timeout: 2000 })
    await expect(dialog.locator("#attr-modal-name")).toBeVisible()
    await expect(dialog.locator("#attr-modal-display-label")).toBeVisible()
    await expect(dialog.locator("#attr-modal-html-type")).toBeVisible()
    await expect(dialog.getByText("Value source")).toBeHidden()
    const panel = dialog.locator("[data-attr-modal-panel]")
    const fieldHeight = (await panel.boundingBox())?.height
    expect(fieldHeight).toBeGreaterThan(0)
    await dialog.screenshot({ path: "/tmp/attr-modal-field.png" })

    await dialog.getByRole("tab", { name: "Rules" }).click()
    await expect(dialog.getByRole("heading", { name: "Validators" })).toBeVisible()
    await expect(dialog.locator("#attr-modal-name")).toBeHidden()
    expect((await panel.boundingBox())?.height).toBe(fieldHeight)
    await dialog.screenshot({ path: "/tmp/attr-modal-rules.png" })

    await dialog.getByRole("tab", { name: "Access" }).click()
    await expect(dialog.getByRole("heading", { name: "Field visibility" })).toBeVisible()
    await expect(dialog.locator("input[data-entity-form-target='modalVisibilityAdmin']")).toBeChecked()
    expect((await panel.boundingBox())?.height).toBe(fieldHeight)
    await dialog.screenshot({ path: "/tmp/attr-modal-access.png" })

    await dialog.getByRole("tab", { name: "Field" }).click()
    await dialog.locator("#attr-modal-name").fill("Playwright Note")
    await expect(dialog.locator("#attr-modal-display-label")).toHaveValue("Playwright Note")
    await dialog.getByRole("button", { name: "Add Attribute" }).click()

    await expect(dialog).toBeHidden()
    await expect(page.locator("[data-attribute-item]", { hasText: "Playwright Note" })).toBeVisible()
  })

  test("places dropdown selection options between HTML type and description", async ({ page }) => {
    test.setTimeout(45_000)
    await page.setViewportSize({ width: 1280, height: 800 })
    const dialog = await openAttributeModal(page)

    await dialog.locator("#attr-modal-html-type").selectOption("select")
    const optionsHeading = dialog.getByRole("heading", { name: "Selection Options" })
    await expect(optionsHeading).toBeVisible()
    await expect(dialog.getByText("Choices people can pick. The label is shown; the value is stored.")).toBeVisible()
    await expect(dialog.getByText("Default", { exact: true }).first()).toBeVisible()
    await expect(dialog.locator("[data-entity-form-target='manualOptionsSection']").getByText("Label", { exact: true })).toBeVisible()
    await expect(dialog.locator("[data-entity-form-target='manualOptionsSection']").getByText("Value", { exact: true })).toBeVisible()
    await expect(dialog.getByPlaceholder("Label (displayed to user)")).toBeVisible()
    await expect(dialog.getByPlaceholder("Value (stored in database)")).toBeVisible()

    const typeBox = await dialog.locator("#attr-modal-html-type").boundingBox()
    const optionsBox = await optionsHeading.boundingBox()
    const descBox = await dialog.locator("#attr-modal-description").boundingBox()
    expect(typeBox).toBeTruthy()
    expect(optionsBox).toBeTruthy()
    expect(descBox).toBeTruthy()
    expect(optionsBox.y).toBeGreaterThan(typeBox.y)
    expect(descBox.y).toBeGreaterThan(optionsBox.y)

    await dialog.screenshot({ path: "/tmp/attr-modal-select.png" })
    await dialog.getByRole("button", { name: "Add Option" }).click()
    await expect(dialog.locator("[data-option-item]")).toHaveCount(2)
    await dialog.locator("[data-option-label]").first().fill("Active")
    await expect(dialog.locator("[data-option-value]").first()).not.toHaveValue("")
  })

  test("stacks the dialog for a narrow viewport", async ({ page }) => {
    test.setTimeout(45_000)
    await page.setViewportSize({ width: 390, height: 844 })
    const dialog = await openAttributeModal(page)
    await expect(dialog.getByRole("tab", { name: "Field" })).toBeVisible()
    await expect(dialog.getByRole("tab", { name: "Rules" })).toBeVisible()
    await expect(dialog.getByRole("button", { name: "Cancel" })).toBeVisible()
    await dialog.screenshot({ path: "/tmp/attr-modal-mobile.png" })
  })
})
