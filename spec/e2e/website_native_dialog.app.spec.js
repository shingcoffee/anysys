import { test, expect } from "@playwright/test"

const BASE = process.env.APP_BASE_URL
const PATH = "/81721200/site"
const WIDTHS = [320, 390, 768]

async function openMenu(page, width, locale = "en") {
  await page.setViewportSize({ width, height: 844 })
  const response = await page.goto(`${BASE}${PATH}?locale=${locale}`)
  expect(response?.ok()).toBeTruthy()
  await page.waitForFunction(() => window.Stimulus?.getControllerForElementAndIdentifier(
    document.querySelector("[data-controller='website-nav']"), "website-nav"
  ))
  const trigger = page.locator("[data-website-nav-target='trigger']")
  const panel = page.locator("dialog#website-nav-panel[data-website-nav-target='panel']")
  const close = panel.locator("button[data-action='click->website-nav#close']")
  const signup = panel.locator("a[href^='/auth/sign_up']")
  const openLabel = await trigger.getAttribute("aria-label")
  const overflow = await page.locator("html").evaluate((root) => root.style.overflow)
  await expect(panel).toHaveCount(1)
  await expect(panel).not.toHaveAttribute("open")
  await trigger.focus()
  await trigger.press("Enter")
  await expect(panel).toBeVisible()
  await expect(panel).toHaveAttribute("open", "")
  expect(await panel.evaluate((dialog) => dialog.matches(":modal"))).toBe(true)
  await expect(trigger).toHaveAttribute("aria-expanded", "true")
  await expect(close).toBeFocused()
  expect(await page.locator("html").evaluate((root) => root.style.overflow)).toBe("hidden")
  return { panel, trigger, close, signup, openLabel, overflow }
}

async function expectClosed(page, { panel, trigger, openLabel, overflow }, restoreFocus = true) {
  await expect(panel).not.toHaveAttribute("open")
  await expect(panel).toBeHidden()
  expect(await panel.evaluate((dialog) => dialog.matches(":modal"))).toBe(false)
  await expect(trigger).toHaveAttribute("aria-expanded", "false")
  await expect(trigger).toHaveAttribute("aria-label", openLabel)
  expect(await page.locator("html").evaluate((root) => root.style.overflow)).toBe(overflow)
  if (restoreFocus) await expect(trigger).toBeFocused()
}

test.describe("scoped home-site browser-native mobile modal", () => {
  test.skip(!BASE, "set APP_BASE_URL to the rebuilt running Rails fixture")

  test.beforeEach(async ({ page }) => {
    await page.route("**/*", (route) => ["GET", "HEAD"].includes(route.request().method())
      ? route.continue() : route.abort("blockedbyclient"))
  })

  for (const locale of ["en", "zh-CN"]) {
    for (const width of WIDTHS) {
      test(`native focus, Tab confinement, inert background and Escape at ${width}px in ${locale}`, async ({ page }) => {
        const menu = await openMenu(page, width, locale)
        const { panel, trigger, close, signup } = menu
        const backgroundHero = page.locator("#site-main a[href]").first()
        await expect(backgroundHero).toHaveCount(1)

        // The transparent dialog fills the viewport; only its inner sheet is narrow.
        const dialogBox = await panel.boundingBox()
        const sheetBox = await panel.locator(":scope > div").boundingBox()
        expect(dialogBox.x).toBe(0)
        expect(dialogBox.y).toBe(0)
        expect(dialogBox.width).toBe(width)
        expect(dialogBox.height).toBe(844)
        expect(sheetBox.x).toBeGreaterThan(0)
        expect(sheetBox.x + sheetBox.width).toBeCloseTo(width, 0)
        expect(sheetBox.y).toBe(0)
        expect(sheetBox.height).toBe(844)

        // Native modal inertness must reject programmatic background focus too.
        await backgroundHero.evaluate((link) => link.focus())
        await expect(close).toBeFocused()
        await expect(backgroundHero).not.toBeFocused()
        await expect(trigger).not.toBeFocused()

        // Check the real sequential order through the final signup link.
        const controls = panel.locator("button, a[href]")
        for (let index = 1; index < await controls.count(); index++) {
          await page.keyboard.press("Tab")
          await expect(controls.nth(index)).toBeFocused()
          expect(await panel.evaluate((dialog) => dialog.contains(document.activeElement))).toBe(true)
        }
        await expect(signup).toBeFocused()
        for (const [key, destination] of [["Tab", close], ["Shift+Tab", signup]]) {
          await page.keyboard.press(key)
          // Native dialogs allow browser chrome at the Tab boundary. Chromium
          // reports BODY then; it must never focus an inert background control.
          const focus = await panel.evaluate((dialog) => ({
            inside: dialog.contains(document.activeElement),
            browserChrome: document.activeElement === document.body
          }))
          expect(focus.inside || focus.browserChrome).toBe(true)
          await expect(backgroundHero).not.toBeFocused()
          await expect(trigger).not.toBeFocused()
          if (focus.browserChrome) await page.keyboard.press(key)
          await expect(destination).toBeFocused()
        }
        await page.keyboard.press("Escape")
        await expectClosed(page, menu)
      })
    }
  }

  for (const width of WIDTHS) {
    test(`sheet content stays open; backdrop, close button and desktop resize dismiss at ${width}px`, async ({ page }) => {
      const menu = await openMenu(page, width)
      const { panel, trigger, close } = menu
      const sheet = panel.locator(":scope > div")
      const sheetBox = await sheet.boundingBox()
      // Click actual sheet chrome, not the self-only transparent dialog hit area.
      await page.mouse.click(sheetBox.x + sheetBox.width / 2, sheetBox.y + 75)
      await expect(panel).toHaveAttribute("open", "")
      const backdropPoint = { x: sheetBox.x / 2, y: 500 }
      expect(await page.evaluate(({ x, y }) => document.elementFromPoint(x, y)?.tagName, backdropPoint)).toBe("DIALOG")
      await page.mouse.click(backdropPoint.x, backdropPoint.y)
      await expectClosed(page, menu)

      await trigger.click()
      await expect(close).toBeFocused()
      await close.click()
      await expectClosed(page, menu)

      await trigger.click()
      await page.setViewportSize({ width: 900, height: 844 })
      await expect(panel).toHaveAttribute("open", "")
      await page.setViewportSize({ width: 1280, height: 844 })
      // The trigger is intentionally hidden on desktop, so focus cannot land on it.
      await expectClosed(page, menu, false)
    })
  }

  test("disconnect closes the native top-layer modal and releases the inert background", async ({ page }) => {
    const { panel, trigger, overflow } = await openMenu(page, 390)
    await trigger.evaluate((button) => button.closest("[data-controller='website-nav']").removeAttribute("data-controller"))
    await expect(panel).not.toHaveAttribute("open")
    expect(await panel.evaluate((dialog) => dialog.matches(":modal"))).toBe(false)
    expect(await page.locator("html").evaluate((root) => root.style.overflow)).toBe(overflow)
    await expect(trigger).toBeFocused()
    const backgroundHero = page.locator("#site-main a[href]").first()
    await backgroundHero.focus()
    await expect(backgroundHero).toBeFocused()
  })
})
