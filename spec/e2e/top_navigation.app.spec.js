import { test, expect } from "@playwright/test"
import { BASE, screenshot } from "./customer_settings_support.js"

const ROOT = "/81721200/admin"

test.describe("tenant-aware top navigation", () => {
  test.skip(!BASE, "Set APP_BASE_URL to the SKIP_AUTH=1 development server")
  test.describe.configure({ timeout: 90000 })

  for (const locale of ["en", "zh-CN"]) {
    for (const width of [768, 1440]) {
      test(`desktop links and Communication popup at ${width}px ${locale}`, async ({ page }) => {
        await page.setViewportSize({ width, height: 900 })
        const response = await page.goto(`${BASE}${ROOT}/dashboard?locale=${locale}`)
        expect(response?.status()).toBe(200)
        await page.waitForLoadState("networkidle")

        const nav = page.locator("nav[data-menu-bar]")
        expect(await nav.locator("[data-menu-item-key]").evaluateAll(items => items.slice(0, 5).map(item => item.dataset.menuItemKey)))
          .toEqual(["home", "assistant", "users", "payments", "communication"])
        await expect(nav.locator("a[data-menu-item-key='users']"))
          .toHaveAttribute("href", `${ROOT}/modules/authentication/users`)
        await expect(nav.locator("a[data-menu-item-key='payments']"))
          .toHaveAttribute("href", `${ROOT}/modules/payments/transactions`)

        const communication = nav.locator("details[data-menu-item-key='communication']")
        await page.waitForFunction(() => window.Stimulus?.getControllerForElementAndIdentifier(
          document.querySelector("details[data-menu-item-key='communication']"), "menu-placement"
        ))
        await page.evaluate(() => document.fonts.ready)
        const summary = communication.locator("summary")
        await expect(summary).toHaveText(locale === "en" ? "Communication" : "通信")
        await summary.focus()
        await summary.press("Enter")
        await expect(communication).toHaveAttribute("open", "")
        const panel = communication.locator("[data-menu-placement-target='panel']")
        await expect(panel).toHaveCSS("position", "fixed")
        await expect(panel.locator("a")).toHaveCount(2)
        await expect(panel.locator("a").first()).toHaveAttribute("href", `${ROOT}/modules/emails/send_activities`)
        await expect(panel.locator("a").last()).toHaveAttribute("href", `${ROOT}/modules/sms/campaigns`)
        const box = await panel.boundingBox()
        const trigger = await summary.boundingBox()
        expect(box.width).toBeGreaterThanOrEqual(160)
        expect(box.y).toBeGreaterThanOrEqual(trigger.y + trigger.height)
        expect(box.x).toBeGreaterThanOrEqual(0)
        expect(box.x + box.width).toBeLessThanOrEqual(width)
        await screenshot(page, `top-navigation-${locale}-${width}`)

        const destination = `${ROOT}/modules/emails/send_activities`
        const [navigation] = await Promise.all([
          page.waitForResponse(response => response.request().method() === "GET" &&
            new URL(response.url()).origin === new URL(BASE).origin && new URL(response.url()).pathname === destination),
          panel.locator("a").first().click()
        ])
        expect(navigation.status()).toBe(200)
        expect(await navigation.finished()).toBeNull()
        await page.waitForURL(url => url.pathname === destination)
        await expect(page.locator("html")).not.toHaveAttribute("aria-busy", "true")
        await expect(page.locator("html")).not.toHaveAttribute("data-turbo-preview", "")
        await expect(page).toHaveURL(new RegExp(`/modules/emails/send_activities`))
        await expect(nav.locator("details[data-menu-item-key='communication'] summary"))
          .toHaveAttribute("aria-current", "page")
        await expect(nav.locator("details[data-menu-item-key='communication'] a[aria-current='page']"))
          .toHaveAttribute("href", `${ROOT}/modules/emails/send_activities`)
        await expect(nav.locator("a[data-menu-item-key='modules']")).not.toHaveAttribute("aria-current", "page")
      })
    }

    test(`mobile drawer links at 390px ${locale}`, async ({ page }) => {
      await page.setViewportSize({ width: 390, height: 844 })
      const response = await page.goto(`${BASE}${ROOT}/dashboard?locale=${locale}`)
      expect(response?.status()).toBe(200)
      await page.waitForLoadState("networkidle")
      await page.locator("button[data-action='click->drawer#open']").click()
      const drawer = page.locator("[data-drawer-target='panel']")
      await expect(drawer.locator("a[data-menu-item='users']")).toHaveAttribute("href", `${ROOT}/modules/authentication/users`)
      await expect(drawer.locator("a[data-menu-item='payments']")).toHaveAttribute("href", `${ROOT}/modules/payments/transactions`)
      const communication = drawer.locator("details[data-menu-item='communication']")
      await communication.locator("summary").click()
      await expect(communication.locator("a")).toHaveCount(2)
      await screenshot(page, `top-navigation-${locale}-mobile`)
      await communication.locator("a").last().click()
      await expect(page).toHaveURL(new RegExp(`/modules/sms/campaigns`))
      await expect(page.locator("[data-drawer-target='panel'] details[data-menu-item='communication'] a[aria-current='page']"))
        .toHaveAttribute("href", `${ROOT}/modules/sms/campaigns`)
    })
  }
})
