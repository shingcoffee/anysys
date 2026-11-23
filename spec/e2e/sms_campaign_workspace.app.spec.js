/* global URL, process, document, window */
import { test, expect } from "@playwright/test"
import { execFileSync } from "node:child_process"
import { fileURLToPath } from "node:url"

const fixtureScript = fileURLToPath(new URL("./helpers/sms_campaign_fixtures.rb", import.meta.url))
const root = fileURLToPath(new URL("../..", import.meta.url))
const ready = !!process.env.APP_BASE_URL && process.env.SMS_CAMPAIGN_UI_E2E === "1"

function fixture(mode, data = {}) {
  const output = execFileSync("bundle", ["exec", "ruby", fixtureScript, mode, JSON.stringify(data)], {
    // Match the server's SQLite WAL pragmas. A test-environment subprocess
    // would switch this live database to memory journaling and lock requests.
    cwd: root, env: { ...process.env, SKIP_AUTH: "0", RAILS_ENV: "development",
      DATABASE_URL: `sqlite3:${process.env.TEST_DATABASE}` }, encoding: "utf8"
  })
  return JSON.parse(output.trim().split("\n").at(-1))
}

async function noViewportOverflow(page) {
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true)
}

for (const width of [360, 768, 1280]) {
  test(`SMS consent → audience → preview → draft → schedule → cancel at ${width}px`, async ({ page }, testInfo) => {
    test.skip(!ready, "Requires the guarded SMS_CAMPAIGN_UI_E2E server and disposable TEST_DATABASE")
    test.setTimeout(90000)
    await page.setViewportSize({ width, height: 900 })
    const data = fixture("create")
    const base = `/${data.customer_id}/admin/modules/sms`
    const errors = []
    page.on("pageerror", error => errors.push(error.message))

    await page.goto(`${base}/contacts/new?locale=en`)
    await page.getByLabel("Phone number", { exact: true }).fill("13800138000")
    await page.getByLabel("Name", { exact: true }).fill(data.contact_name)
    await page.getByRole("button", { name: "Save contact", exact: true }).click()
    await expect(page.getByRole("heading", { name: data.contact_name, exact: true })).toBeVisible()
    expect(fixture("state", data).contacts).toEqual([[data.contact_name, "unknown"]])
    await page.getByLabel("Evidence reference", { exact: true }).fill("Browser signed form")
    await page.getByLabel("Consent statement", { exact: true }).fill("I agree to receive marketing SMS.")
    await page.getByRole("button", { name: "Record consent event", exact: true }).click()
    expect(fixture("state", data).contacts).toEqual([[data.contact_name, "granted"]])
    await noViewportOverflow(page)

    await page.goto(`${base}/segments/new?locale=en`)
    await page.getByLabel("Name", { exact: true }).fill(data.segment_name)
    await expect.poll(() => page.evaluate(() => {
      const mount = document.querySelector('[data-controller="segment-builder"]')
      return !!window.Stimulus?.getControllerForElementAndIdentifier(mount, "segment-builder")
    })).toBe(true)
    await page.getByRole("button", { name: "+ Add condition", exact: true }).click()
    const builder = page.locator('[data-controller="segment-builder"]')
    await builder.locator('[data-sb-field]').selectOption("consent_status")
    await builder.locator('[data-sb-operator]').selectOption("equals")
    await builder.locator('[data-sb-value]').fill("granted")
    await page.getByRole("button", { name: "Preview audience", exact: true }).click()
    await expect(page.getByText("Currently eligible", { exact: true }).first()).toBeVisible()
    await page.getByRole("button", { name: "Save segment", exact: true }).click()
    await expect(page.getByRole("heading", { name: data.segment_name, exact: true })).toBeVisible()

    await page.goto(`${base}/campaigns/new?locale=en`)
    await page.getByLabel("Name", { exact: true }).fill(data.campaign_name)
    await page.getByLabel("Segment", { exact: true }).selectOption({ label: data.segment_name })
    await page.getByLabel("Approved marketing template", { exact: true }).selectOption(String(data.template_id))
    await page.getByLabel("Variable mappings (JSON)").fill(JSON.stringify({
      name: { source: "field", field: "name", fallback: "Customer" },
      opt_out_url: { source: "field", field: "unsubscribe_url" }
    }))
    await page.getByLabel("Schedule campaign", { exact: true }).check()
    await page.getByLabel("Timezone", { exact: true }).fill("UTC")
    const scheduled = new Date(Date.now() + 86400000).toISOString().slice(0, 16)
    await page.getByLabel("Local date and time", { exact: true }).fill(scheduled)
    await page.getByRole("button", { name: "Preview campaign", exact: true }).click()
    await expect(page.getByLabel("Name", { exact: true })).toHaveValue(data.campaign_name)
    await expect(page.getByText(`Hi ${data.contact_name}`, { exact: false })).toBeVisible()
    expect(fixture("state", data)).toMatchObject({ messages: 0, recipients: 0, events: 1, campaign_id: null })
    await noViewportOverflow(page)
    await page.getByRole("button", { name: "Save draft", exact: true }).click()
    await expect(page.getByRole("heading", { name: data.campaign_name, exact: true })).toBeVisible()
    expect(fixture("state", data)).toMatchObject({ campaign_status: "draft", messages: 0, recipients: 0 })

    // Edit Preview must use native POST despite the record's PATCH Save action.
    await page.getByRole("link", { name: "Edit draft", exact: true }).first().click()
    await page.getByLabel("Name", { exact: true }).fill(`${data.campaign_name} edited`)
    const response = page.waitForResponse(r => r.url().endsWith("/preview") && r.request().method() === "POST")
    await page.getByRole("button", { name: "Preview campaign", exact: true }).click()
    expect((await response).status()).toBe(200)
    expect(fixture("state", data).campaign_name).toBe(data.campaign_name)
    await page.getByRole("button", { name: "Save draft", exact: true }).click()
    await page.getByRole("button", { name: "Schedule campaign", exact: true }).click()
    expect(fixture("state", data)).toMatchObject({ campaign_status: "scheduled", messages: 0, recipients: 0 })
    await page.getByRole("button", { name: "Cancel remaining messages", exact: true }).click()
    expect(fixture("state", data)).toMatchObject({ campaign_status: "cancelled", messages: 0, events: 1 })
    await page.getByRole("link", { name: "View report", exact: true }).click()
    await expect(page.getByRole("link", { name: "Download CSV", exact: true })).toBeVisible()
    await noViewportOverflow(page)

    await page.goto(`${base}/campaigns/new?locale=zh-CN`)
    await expect(page.getByRole("heading", { name: "创建活动", exact: true })).toBeVisible()
    await noViewportOverflow(page)
    expect(errors).toEqual([])
    await testInfo.attach(`sms-workspace-${width}`, { body: await page.screenshot({ fullPage: true }), contentType: "image/png" })
  })
}

test("SMS explicit Entity batch and signed GET → POST unsubscribe at 360px", async ({ page }) => {
  test.skip(!ready, "Requires the guarded SMS_CAMPAIGN_UI_E2E server and disposable TEST_DATABASE")
  test.setTimeout(60000)
  await page.setViewportSize({ width: 360, height: 900 })
  const data = fixture("create")
  const source = fixture("entity", data)
  const base = `/${data.customer_id}/admin/modules/sms`
  await page.goto(`${base}/contacts/entity_sync/new?locale=en`)
  await page.getByLabel("Entity", { exact: true }).selectOption(String(source.entity_id))
  await page.getByRole("button", { name: "Load fields", exact: true }).click()
  await page.getByLabel("Telephone field", { exact: true }).selectOption("mobile")
  await page.getByLabel("Name field", { exact: true }).selectOption("full_name")
  await page.getByRole("button", { name: "Preview first 100", exact: true }).click()
  expect(fixture("state", data)).toMatchObject({ contacts: [], events: 0 })
  await expect(page.getByRole("heading", { name: "Preview batch", exact: true })).toBeVisible()
  await noViewportOverflow(page)
  await page.getByRole("button", { name: "Sync this batch", exact: true }).click()
  expect(fixture("state", data)).toMatchObject({ contacts: [[source.name, "unknown"]], events: 0 })

  const { token } = fixture("unsubscribe", data)
  await page.goto(`/sms/unsubscribes/${token}?locale=en`)
  await expect(page.getByRole("heading", { name: "Unsubscribe from SMS", exact: true })).toBeVisible()
  expect(fixture("state", data).events).toBe(0)
  await expect(page.getByRole("navigation", { name: "SMS workspace", exact: true })).toHaveCount(0)
  await noViewportOverflow(page)
  await page.getByRole("button", { name: "Confirm unsubscribe", exact: true }).click()
  await expect(page.getByRole("heading", { name: "You have unsubscribed", exact: true })).toBeVisible()
  expect(fixture("state", data)).toMatchObject({ contacts: [[source.name, "revoked"]], events: 1, messages: 0 })
  await page.reload()
  expect(fixture("state", data).events).toBe(1)
})
