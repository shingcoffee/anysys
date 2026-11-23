import { expect } from "@playwright/test"
import { isolatedAssistantTest as test } from "./support/assistant_test.js"
import { runRails } from "./helpers/rails_runner.js"
import { waitForAssistantController, waitForAssistantStreams } from "./helpers/assistant_ui.js"

// App-backed: AI assistant create → unconfirmed update → confirmed update.
// Requires the isolated bootstrap + local HTTP provider launcher. Rails still
// validates and persists the provider's structured output. See spec/e2e/README.md.
const BASE = process.env.APP_BASE_URL
const ENTITIES = "/81721200/admin/maintenance/entities"

test.use({ ignoreHTTPSErrors: true })

test.describe("assistant entity create/update", () => {
  test.skip(!BASE, "set APP_BASE_URL to run app-backed e2e (see spec/e2e/README.md)")

  test("creates an entity, waits for confirmation on update, then applies", async ({ page, assistantThread }) => {
    test.setTimeout(180_000)
    const name = assistantThread.entityName
    await page.setViewportSize({ width: 1280, height: 800 })

    const response = await page.goto(`${BASE}${assistantThread.path}`)
    expect(response?.ok()).toBeTruthy()

    const composer = page.locator("#ai_assistant_composer")
    await expect(composer).toBeVisible()
    const createPrompt = page.getByRole("button", { name: "Create a Student entity with name, email, and enrollment date." })
    if (await createPrompt.count()) {
      await expect(createPrompt).toBeVisible()
    }

    await sendAssistant(page, `Create a ${name} entity with a title field.`)
    await expect(page.getByText(`Creating ${name} with a Title field.`)).toBeVisible({ timeout: 20000 })
    await expect(page.getByText(`Created: ${name}.`)).toBeVisible()

    await page.goto(`${BASE}${ENTITIES}?q=${name}`)
    await expect(page.getByRole("link", { name })).toBeVisible({ timeout: 15000 })

    await page.goto(`${BASE}${assistantThread.path}`)
    await sendAssistant(page, `Add a notes field to ${name}`)
    await expect(page.getByText(
      `I can add Notes to ${name}. Proceed? Review the proposed changes below, then apply them or tell me what to adjust. Nothing is saved until you do.`,
      { exact: true }
    )).toBeVisible({ timeout: 20000 })
    await expect(page.getByRole("region", { name: "Proposed changes", exact: true })).toContainText("Added field Notes")
    expect(entitySlugs(name)).toEqual(["title"])

    await page.goto(`${BASE}${assistantThread.path}`)
    await sendAssistant(page, "Yes")
    await expect(page.getByText(`Updated: ${name}.`)).toBeVisible({ timeout: 20000 })
    expect(entitySlugs(name)).toEqual(["title", "notes"])

    await page.goto(`${BASE}${ENTITIES}?q=${name}`)
    await expect(page.getByRole("link", { name })).toBeVisible({ timeout: 15000 })
  })
})

function entitySlugs(name) {
  const output = runRails(`
    Current.with_customer(Customer.find(81721200)) do
      entity = Entity.find_by!(customer_id: 81721200, name: ${JSON.stringify(name)})
      puts entity.property_schema_json.map { |attribute| attribute.fetch("name_slug") }.to_json
    end
  `)
  return JSON.parse(output.trim().split("\n").at(-1))
}

async function sendAssistant(page, body) {
  const composer = page.locator("#ai_assistant_composer")
  await expect(composer).toBeVisible()
  await waitForAssistantController(page)
  await waitForAssistantStreams(page)
  await composer.fill(body)
  const accepted = page.waitForResponse(response => response.request().method() === "POST" && /\/ai_assistant\/messages$/.test(new URL(response.url()).pathname))
  await page.locator("button[aria-label='Send']").click()
  expect((await accepted).status()).toBe(202)
  await expect(composer).toHaveValue("", { timeout: 5000 })
}
