import { test, expect } from "@playwright/test"

const BASE = process.env.APP_BASE_URL

test.describe("Sapphire brand across site and app", () => {
  test.skip(!BASE, "set APP_BASE_URL to run app-backed e2e")

  for (const locale of ["en", "zh-CN"]) for (const width of [1440, 390]) {
    test(`accessible Sapphire branding at ${width}px ${locale}`, async ({ page }, testInfo) => {
      await page.setViewportSize({ width, height: width === 390 ? 844 : 900 })
      const site = await page.goto(`${BASE}/?locale=${locale}`)
      expect(site.status()).toBe(200)
      await expect(page.locator("html")).toHaveAttribute("lang", locale)
      await expect(page.locator("#site-main h1")).toBeVisible()

      const siteName = await page.locator("header nav").getAttribute("aria-label")
      expect(siteName).toMatch(/\S/)
      const siteBrand = page.locator("header").getByRole("link", { name: siteName, exact: true })
      await expect(siteBrand).toBeVisible()
      const home = new URL(await siteBrand.getAttribute("href"), BASE)
      expect(home.pathname).toBe("/")
      expect(home.searchParams.get("locale")).toBe(locale)
      const siteLogo = siteBrand.locator("svg[aria-hidden='true']")
      await expect(siteLogo).toBeVisible()
      const facets = await siteLogo.locator("path[d]").evaluateAll(paths => paths.map(path => path.getAttribute("d")))
      expect(facets.length).toBeGreaterThan(0)
      await page.screenshot({ path: testInfo.outputPath(`site-${width}.png`) })

      const dashboard = await page.goto(`${BASE}/81721200/admin/dashboard?locale=${locale}`)
      expect(dashboard.status()).toBe(200)
      await expect(page.locator("html")).toHaveAttribute("lang", locale)
      const brandLink = page.locator("header").getByRole("link", {
        name: locale === "en" ? "Sapphire — Dashboard" : "Sapphire — 仪表板", exact: true
      })
      await expect(brandLink).toBeVisible()
      expect(new URL(await brandLink.getAttribute("href"), BASE).pathname).toBe("/81721200/admin/dashboard")
      const logo = brandLink.getByRole("img", { name: "Sapphire", exact: true })
      await expect(logo).toBeVisible()
      expect(await logo.locator("path[d]").evaluateAll(paths => paths.map(path => path.getAttribute("d")))).toEqual(facets)
      expect(await logo.evaluate((mark) => mark.getBoundingClientRect().height)).toBeGreaterThan(20)
      expect(await brandLink.evaluate((link) => ({ text: link.textContent.trim(), children: link.children.length,
        borderWidth: getComputedStyle(link).borderTopWidth }))).toEqual({ text: "", children: 1, borderWidth: "0px" })
      await page.screenshot({ path: testInfo.outputPath(`dashboard-${width}.png`) })

      if (width === 390) {
        await page.locator("header").getByRole("button", {
          name: locale === "en" ? "Open menu" : "打开菜单", exact: true
        }).click()
        await expect(page.locator("aside[data-drawer-target='panel']").getByRole("img", { name: "Sapphire", exact: true })).toBeVisible()
        await expect(page.locator("aside > div:first-child span")).toHaveCount(0)
        await expect(page.locator("aside[data-drawer-target='panel']")).toHaveCSS("transform", "none")
        await expect.poll(() => page.locator("aside[data-drawer-target='panel']").evaluate(
          (panel) => Math.round(panel.getBoundingClientRect().left)
        )).toBe(0)
        await page.screenshot({ path: testInfo.outputPath("drawer-390.png"), animations: "disabled" })
      }

      const icon = await page.request.get(`${BASE}/icon.png`)
      expect(icon.ok()).toBe(true)
      expect(icon.headers()["content-type"]).toContain("image/png")
      const faviconFacet = await page.evaluate(async () => {
        const image = new Image()
        image.src = "/icon.png"
        await image.decode()
        const canvas = document.createElement("canvas")
        canvas.width = image.width
        canvas.height = image.height
        const context = canvas.getContext("2d")
        context.drawImage(image, 0, 0)
        return [...context.getImageData(256, 160, 1, 1).data].slice(0, 3)
      })
      expect(faviconFacet[0]).toBeGreaterThan(faviconFacet[1])
      expect(faviconFacet[2]).toBeGreaterThan(faviconFacet[1])
      const svg = await page.request.get(`${BASE}/icon.svg`)
      expect(svg.ok()).toBe(true)
      expect(await svg.text()).toContain('filter="url(#violet-fav)"')
    })
  }
})
