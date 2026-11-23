import { test, expect } from "@playwright/test"

const BASE = process.env.APP_BASE_URL
const PATH = "/81721200/site"
const LABELS = ["English", "简体中文"]

test.describe("scoped language popup at narrow CSS viewports", () => {
  test.skip(!BASE, "set APP_BASE_URL to the rebuilt running Rails fixture")

  for (const locale of ["en", "zh-CN"]) {
    for (const width of [150, 160, 195]) {
      test(`full language labels and keyboard GET fit ${width} CSS px in ${locale}`, async ({ page }) => {
        const writes = []
        await page.route("**/*", (route) => {
          if (["GET", "HEAD"].includes(route.request().method())) return route.continue()
          writes.push(`${route.request().method()} ${route.request().url()}`)
          return route.abort("blockedbyclient")
        })
        await page.setViewportSize({ width, height: 900 })
        const response = await page.goto(`${BASE}${PATH}?locale=${locale}`)
        expect(response?.ok()).toBeTruthy()
        await expect(page.locator("#site-main")).toHaveCount(1)
        await page.evaluate(() => document.fonts.ready)

        const switcher = page.locator("header details").filter({ has: page.locator("[role='menu']") })
        const summary = switcher.locator(":scope > summary")
        const panel = switcher.getByRole("menu")
        await summary.focus()
        await summary.press("Enter")
        await expect(switcher).toHaveAttribute("open", "")
        await expect(panel).toBeVisible()
        const links = panel.getByRole("menuitem")
        await expect(links).toHaveText(LABELS)

        // Check the actual opened popup and every rendered line of each label,
        // not just its anchor box: an offscreen or clipped label must fail.
        const panelBox = await panel.boundingBox()
        expect(panelBox.x).toBeGreaterThanOrEqual(19)
        expect(panelBox.x + panelBox.width).toBeLessThanOrEqual(width - 19)
        for (const [index, label] of LABELS.entries()) {
          const link = links.nth(index)
          await expect(link).toHaveAccessibleName(label)
          await expect(link).toBeInViewport({ ratio: 1 })
          const box = await link.boundingBox()
          expect(box.x).toBeGreaterThanOrEqual(0)
          expect(box.x + box.width).toBeLessThanOrEqual(width)
          const text = await link.locator("span").evaluate((span) => {
            const range = document.createRange()
            range.selectNodeContents(span)
            const css = getComputedStyle(span)
            return {
              label: span.textContent,
              visibility: css.visibility,
              opacity: css.opacity,
              lines: [...range.getClientRects()].map(({ left, right, top, bottom }) => ({ left, right, top, bottom }))
            }
          })
          expect(text.label).toBe(label)
          expect(text.visibility).toBe("visible")
          expect(Number(text.opacity)).toBeGreaterThan(0)
          expect(text.lines.length).toBeGreaterThan(0)
          for (const line of text.lines) {
            expect(line.left).toBeGreaterThanOrEqual(box.x - 1)
            expect(line.right).toBeLessThanOrEqual(box.x + box.width + 1)
            expect(line.top).toBeGreaterThanOrEqual(box.y - 1)
            expect(line.bottom).toBeLessThanOrEqual(box.y + box.height + 1)
            expect(line.right).toBeGreaterThan(line.left)
          }
        }
        expect(await page.locator("html").evaluate((root) => root.scrollWidth)).toBeLessThanOrEqual(width + 1)

        // The native summary opens with Enter; Tab reaches the ordinary GET links.
        await summary.press("Tab")
        await expect(links.first()).toBeFocused()
        const nextLocale = locale === "en" ? "zh-CN" : "en"
        const destination = panel.locator(`a[lang='${nextLocale}']`)
        if (nextLocale === "zh-CN") await page.keyboard.press("Tab")
        await expect(destination).toBeFocused()
        const [navigation] = await Promise.all([
          page.waitForResponse((result) => result.request().method() === "GET" &&
            new URL(result.url()).pathname === PATH && new URL(result.url()).searchParams.get("locale") === nextLocale),
          destination.press("Enter")
        ])
        expect(navigation.ok()).toBeTruthy()
        await expect(page.locator("html")).toHaveAttribute("lang", nextLocale)
        expect(new URL(page.url()).pathname).toBe(PATH)
        expect(new URL(page.url()).searchParams.get("locale")).toBe(nextLocale)
        expect(writes).toEqual([])
      })
    }
  }
})
