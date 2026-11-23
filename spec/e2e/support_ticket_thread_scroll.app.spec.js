import { test, expect } from "@playwright/test"

// Viewport-locked shell: html/body stay overflow-hidden. The conversation
// pane (not the document, not <main>) is the scroll container — same as the
// dashboard AI assistant thread.
const BASE = process.env.APP_BASE_URL
const PATH = process.env.SUPPORT_TICKET_PATH || "/81721200/admin/maintenance/platform/support_tickets/2"

test.describe("support ticket thread scroll", () => {
  test.skip(!BASE, "set APP_BASE_URL to run app-backed e2e (see spec/e2e/README.md)")

  test("wheeling over the conversation scrolls the thread, not the document", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 720 })
    const response = await page.goto(`${BASE}${PATH}`)
    expect(response?.ok()).toBeTruthy()
    await page.waitForSelector("[data-help-thread-target='thread']")

    const thread = page.locator("[data-help-thread-target='thread']")
    await expect(thread).toBeVisible()
    await expect(page.locator("#help-reply-body")).toBeVisible()

    const before = await page.evaluate(() => {
      const main = document.querySelector("main")
      const list = document.querySelector("[data-help-thread-target='thread']")
      const html = document.documentElement
      const body = document.body
      return {
        mainTop: main.scrollTop,
        mainScrollable: main.scrollHeight > main.clientHeight + 1,
        listOverflowY: getComputedStyle(list).overflowY,
        listScrollable: list.scrollHeight > list.clientHeight + 1,
        htmlOverflowY: getComputedStyle(html).overflowY,
        bodyOverflowY: getComputedStyle(body).overflowY
      }
    })

    expect(["auto", "scroll"]).toContain(before.listOverflowY)
    expect(before.htmlOverflowY).toBe("hidden")
    expect(before.bodyOverflowY).toBe("hidden")

    await thread.hover()
    await page.mouse.wheel(0, 900)

    const after = await page.evaluate(() => {
      const main = document.querySelector("main")
      const list = document.querySelector("[data-help-thread-target='thread']")
      return {
        mainTop: main.scrollTop,
        listTop: list.scrollTop,
        htmlTop: document.documentElement.scrollTop,
        windowY: window.scrollY
      }
    })

    expect(after.htmlTop).toBe(0)
    expect(after.windowY).toBe(0)
    if (before.listScrollable) {
      expect(after.listTop).toBeGreaterThan(before.listTop)
    }
  })
})
