import { test as base, expect } from "@playwright/test"
import { randomUUID } from "node:crypto"
import { existsSync } from "node:fs"
import { isolatedEnvironment, runRails } from "./rails_runner.js"

const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN1cAAAAASUVORK5CYII=", "base64")

function fixtureCall(method, token, name = "gallery") {
  const env = isolatedEnvironment()
  if (!existsSync(env.E2E_DATABASE_PATH)) throw new Error("Website E2E requires an already prepared isolated database")
  const output = runRails(`
    require Rails.root.join("spec/e2e/helpers/website_fixtures")
    result = WebsiteBrowserFixtures.${method}(${JSON.stringify(token)}${method === "snapshot" ? `, ${JSON.stringify(name)}` : ""})
    puts "WEBSITE_FIXTURE=" + result.to_json
  `, { env, timeout: 60000 })
  const result = output.split("\n").find(line => line.startsWith("WEBSITE_FIXTURE="))
  if (!result) throw new Error(`Website fixture ${method} did not report a result`)
  return JSON.parse(result.slice("WEBSITE_FIXTURE=".length))
}

export const test = base.extend({
  websiteFixture: async ({ request }, use) => {
    const response = await request.get(`${process.env.APP_BASE_URL}/81721200/admin/modules/website`, { timeout: 15000 })
    expect(response.ok(), `Website fixture prerequisite: HTTP ${response.status()} from the isolated application`).toBe(true)
    const token = randomUUID().replaceAll("-", "")
    const fixture = fixtureCall("create", token)
    fixture.snapshot = (name = "gallery") => fixtureCall("snapshot", token, name)
    try {
      await use(fixture)
    } finally {
      fixtureCall("cleanup", token)
    }
  },
  page: async ({ page }, use) => {
    // Keep image loading deterministic and local. Specific per-test broken-image
    // and mocked-upload routes registered later take priority over this handler.
    await page.route("**/*", route => {
      const request = route.request()
      if (request.resourceType() === "image" && new URL(request.url()).origin !== new URL(process.env.APP_BASE_URL).origin) {
        return route.fulfill({ contentType: "image/png", body: PNG })
      }
      return route.fallback()
    })
    await use(page)
  }
})

export { expect }
