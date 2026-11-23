import { test, expect } from "@playwright/test"
import { BASE, DESKTOP_SETTINGS_SIDEBAR, screenshot } from "./customer_settings_support.js"

const ROOT = "/81721200/admin"
const desktopSidebar = (page) => page.locator(DESKTOP_SETTINGS_SIDEBAR)
const desktopNav = (page, section) => desktopSidebar(page).locator(`nav[aria-label='${section}']`)
const labels = (nav) => nav.locator(":scope > ul > li > ul > li").evaluateAll(items =>
  items.map(item => item.querySelector(":scope > a, :scope > details > summary")?.textContent.trim())
)
const ORDER = {
  en: ["Overview", "User Authentication", "Payments", "Email", "SMS", "Website", "Captcha", "AI Assistant"],
  "zh-CN": ["概览", "用户认证", "支付", "邮件", "短信", "网站", "验证码", "AI 助手"]
}

test.describe("Settings navigation matches Modules navigation", () => {
  test.skip(!BASE, "Set APP_BASE_URL to the SKIP_AUTH=1 development server")

  for (const locale of ["en", "zh-CN"]) {
    test(`desktop groups, links and filtering ${locale}`, async ({ page }) => {
      await page.setViewportSize({ width: 1440, height: 900 })
      const modules = await page.goto(`${BASE}${ROOT}/modules?locale=${locale}`)
      expect(modules?.status()).toBe(200)

      const moduleNav = desktopNav(page, locale === "en" ? "Modules" : "模块")
      expect(await labels(moduleNav)).toEqual(ORDER[locale])
      const moduleDetails = moduleNav.locator("details").filter({ has: page.locator("summary").filter({ hasText: locale === "en" ? "Email" : "邮件" }) }).first()
      await moduleDetails.locator("summary").click()
      const summaryClass = await moduleDetails.locator("summary").getAttribute("class")
      const linkClass = await moduleDetails.locator("ul a").first().getAttribute("class")
      await screenshot(page, `modules-sidebar-${locale}-desktop`)

      const settings = await page.goto(`${BASE}${ROOT}/settings?locale=${locale}`)
      expect(settings?.status()).toBe(200)
      const nav = desktopNav(page, locale === "en" ? "Settings" : "设置")
      expect(await labels(nav)).toEqual([
        ...ORDER[locale], ...(locale === "en" ? ["Members", "Billing"] : ["会员", "账单"])
      ])
      const details = nav.locator("details").filter({ has: page.locator("summary").filter({ hasText: locale === "en" ? "Email" : "邮件" }) }).first()
      expect(await details.locator("summary").getAttribute("class")).toBe(summaryClass)
      await details.locator("summary").click()
      expect(await details.locator("ul a").first().getAttribute("class")).toBe(linkClass)
      await expect(details.locator("ul a svg")).toHaveCount(await details.locator("ul a").count())
      const gap = await nav.locator("ul").first().evaluate(el => getComputedStyle(el).rowGap)
      expect(Number.parseFloat(gap)).toBeLessThanOrEqual(8)
      await screenshot(page, `settings-sidebar-${locale}-desktop`)

      const search = desktopSidebar(page).getByRole("searchbox")
      await search.fill(locale === "en" ? "password reset" : "密码重置")
      await expect(nav.locator("a:visible")).toHaveCount(1)
      await search.fill("")
      await expect(details).toHaveAttribute("open", "")

      const nested = await page.goto(`${BASE}${ROOT}/settings/modules/emails/template_tokens?locale=${locale}`)
      expect(nested?.status()).toBe(200)
      const selected = desktopNav(page, locale === "en" ? "Settings" : "设置")
        .locator("a[aria-current='page']")
      await expect(selected).toHaveAttribute("href", `${ROOT}/settings/modules/emails/template_tokens`)
      await expect(selected.locator("svg")).toHaveCount(1)
      await expect(selected.locator("xpath=ancestor::details[1]")).toHaveAttribute("open", "")
    })

    for (const width of [390, 768]) {
      test(`mobile and tablet Settings menu at ${width}px ${locale}`, async ({ page }) => {
        await page.setViewportSize({ width, height: 844 })
        const modules = await page.goto(`${BASE}${ROOT}/modules?locale=${locale}`)
        expect(modules?.status()).toBe(200)
        const drawerItems = page.locator("[data-drawer-target='panel'] details[data-menu-item='modules'] > ul > li")
        expect(await drawerItems.evaluateAll(items => items.map(item =>
          item.querySelector(":scope > a, :scope > details > summary")?.textContent.trim()
        ))).toEqual(ORDER[locale])

        const response = await page.goto(`${BASE}${ROOT}/settings?locale=${locale}`)
        expect(response?.status()).toBe(200)
        expect(await labels(page.locator("[data-drawer-target='panel'] details[data-menu-item='settings'] nav"))).toEqual([
          ...ORDER[locale], ...(locale === "en" ? ["Members", "Billing"] : ["会员", "账单"])
        ])
        await page.locator("button[commandfor='settings-navigation-dialog'][command='show-modal']").click()
        const dialog = page.locator("#settings-navigation-dialog")
        await expect(dialog).toBeVisible()
        expect(await labels(dialog.locator("nav"))).toEqual([
          ...ORDER[locale], ...(locale === "en" ? ["Members", "Billing"] : ["会员", "账单"])
        ])
        const summary = dialog.locator("details > summary").filter({ hasText: locale === "en" ? "Email" : "邮件" }).first()
        await summary.click()
        const rows = dialog.locator("details[open] ul a")
        await expect(rows).not.toHaveCount(0)
        for (const row of await rows.all()) {
          await expect(row.locator("svg")).toHaveCount(1)
          expect((await row.boundingBox()).height).toBeGreaterThanOrEqual(44)
        }
        expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width)
        await screenshot(page, `settings-sidebar-${locale}-${width}`)
        await page.keyboard.press("Escape")
        await expect(dialog).toBeHidden()
      })
    }
  }
})
