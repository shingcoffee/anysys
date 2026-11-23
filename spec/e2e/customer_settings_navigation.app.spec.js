import { test, expect } from "@playwright/test"
import { writeFileSync } from "node:fs"
import { BASE, ROOT, MAIN, HEADING, SHOTS, DESTINATIONS, DESKTOP_SETTINGS_SIDEBAR, protect, visit, fixture, shell, fits, screenshot, connected } from "./customer_settings_support.js"

test.describe("customer settings destination and responsive inventory", () => {
  test.skip(!BASE, "Set APP_BASE_URL to the SKIP_AUTH=1 development server")
  test.setTimeout(90000)

  for (const locale of ["en", "zh-CN"]) {
    for (const width of [390, 1440]) {
      test(`module aliases retain one canonical active task at ${width}px ${locale}`, async ({ page, context }) => {
        const guard = await protect(context)
        await page.setViewportSize({ width, height: width === 390 ? 844 : 1000 })
        for (const suffix of ["", "/modules/email", "/modules/emails", "/modules/sms", "/modules/ai_assistants", "/modules/authentications", "/modules/captcha/status"]) {
          const path = await visit(page, suffix, locale)
          await shell(page, path, locale)
          await fits(page, path)
        }
        expect(guard.writes).toEqual([])
        expect(guard.unexpected).toEqual([])
      })
    }

    for (const width of [320, 390, 768, 1440]) {
      test(`every registered destination and nested GET at ${width}px ${locale}`, async ({ page, context }) => {
        test.setTimeout(600000)
        const guard = await protect(context)
        await page.setViewportSize({ width, height: width <= 390 ? 844 : 1000 })
        const queue = [ROOT, ...["/modules/email", "/modules/emails", "/modules/sms", "/modules/ai_assistants", "/modules/authentications", "/modules/captcha/status"].map(p => ROOT + p)]
        const seen = new Set()
        const inventory = []
        while (queue.length) {
          const path = queue.shift()
          if (seen.has(path)) continue
          seen.add(path)
          await test.step(path.replace(ROOT, "") || "overview", async () => {
            await visit(page, path, locale)
            await shell(page, path, locale)
            await fits(page, path)
            const title = await page.locator(HEADING).innerText()
            inventory.push({ path, title })
            // Check controls hidden in Advanced, member sections, and starter
            // disclosures too. Opening a native disclosure is nonpersisting.
            await page.locator("main details").evaluateAll(nodes => nodes.forEach(n => { n.open = true }))
            await fits(page, `${path} expanded`)
            const links = await page.locator("main a[href]").evaluateAll(nodes => nodes
              .filter(a => !a.dataset.turboMethod && !a.dataset.method)
              .map(a => {
                const url = new URL(a.href)
                // Locale is the matrix parameter, while plan_code and other
                // route inputs are part of the actual authorized GET surface.
                url.searchParams.delete("locale")
                return url.pathname + url.search
              }))
            queue.push(...links.filter(p => p.startsWith(ROOT) && !seen.has(p)))
            if ([390, 1440].includes(width) && !/entity_(?!student_profile$|assoc_)/.test(path)) {
              await page.locator(MAIN).evaluate(n => { n.scrollTop = 0 })
              await screenshot(page, `inventory-${locale}-${width}-${path.replace(ROOT, "overview").replaceAll("/", "-")}`)
            }
          })
        }
        expect([...seen]).toEqual(expect.arrayContaining(DESTINATIONS.map(([p]) => ROOT + p)))
        expect([...seen].filter(p => p.includes("/member/sources/")).length).toBeGreaterThanOrEqual(5)
        // Populated controls are current, authorized responses from the separate
        // exporter DB; the running tenant may legitimately have no providers or public pages.
        for (const name of ["payment-providers", "payment-sandbox", "payment-production", "public-protection"]) {
          const data = await fixture(page, guard, name, locale)
          await shell(page, data.path, locale)
          await fits(page, `exported ${name}`)
          await page.locator(`${MAIN} details`).evaluateAll(nodes => nodes.forEach(n => { n.open = true }))
          await fits(page, `exported ${name} expanded`)
          inventory.push({ path: data.path, title: await page.locator(HEADING).innerText(), source: data.source })
          if ([390, 1440].includes(width)) await screenshot(page, `inventory-fixture-${name}-${locale}-${width}`)
        }
        expect(inventory.filter(item => /merchant_accounts\/\d+\/edit$/.test(item.path)).length).toBeGreaterThanOrEqual(2)
        expect([...seen].filter(p => /roles\/\d+\/grants$/.test(p))).toHaveLength(3)
        expect(guard.writes).toEqual([])
        expect(guard.unexpected).toEqual([])
        writeFileSync(`${SHOTS}/inventory-${locale}-${width}.json`, JSON.stringify(inventory, null, 2))
      })
    }

    test(`overview has exact task links and one searchable desktop navigation ${locale}`, async ({ page, context }) => {
      await protect(context)
      await page.setViewportSize({ width: 1440, height: 1000 })
      await visit(page, "", locale)
      const aside = page.locator(DESKTOP_SETTINGS_SIDEBAR)
      await connected(page, `${DESKTOP_SETTINGS_SIDEBAR} [data-controller='list-filter']`, "list-filter")
      for (const [path, en, zh] of DESTINATIONS) {
        await expect(page.locator(`main a[href='${ROOT + path}']`)).toHaveCount(1)
        await expect(aside.locator(`a[href='${ROOT + path}']`)).toHaveText(locale === "en" ? en : zh)
      }
      await expect(page.locator("input[type=search]:visible")).toHaveCount(1)
      const search = aside.getByRole("searchbox")
      await search.fill(locale === "en" ? "password" : "密码重置")
      await expect(aside.locator(`a[href='${ROOT}/modules/authentication/forget_password']`)).toBeVisible()
      await expect(aside.locator(`a[href='${ROOT}/modules/authentication/roles']`)).toBeHidden()
      await search.fill("qa-no-such-settings-987")
      await expect(aside.locator("[role=status]")).toBeVisible()
      await expect(aside.locator("a:visible")).toHaveCount(0)
      await search.fill("")
      await expect(aside.locator("a[href]")).toHaveCount(DESTINATIONS.length + 1)
      await expect(aside.locator("a:visible")).toHaveCount(1)
      await expect(aside.locator("[role=status]")).toBeHidden()
    })

    for (const width of [320, 390, 768]) {
      test(`native settings menu keyboard, search, active parent and focus at ${width}px ${locale}`, async ({ page, context, browser }) => {
        await protect(context)
        await page.setViewportSize({ width, height: 844 })
        await visit(page, "/modules/authentication/roles/3/grants", locale)
        expect(Number(browser.version().split(".")[0]), "commandfor requires modern Chromium").toBeGreaterThanOrEqual(135)
        const trigger = page.locator("button[commandfor='settings-navigation-dialog'][command='show-modal']")
        const dialog = page.locator("#settings-navigation-dialog")
        await connected(page, "#settings-navigation-dialog [data-controller='list-filter']", "list-filter")
        await expect(trigger).toHaveAccessibleName(locale === "en" ? "Settings menu" : "设置菜单")
        await trigger.focus()
        await trigger.press("Enter")
        await expect(dialog).toBeVisible()
        expect(await dialog.evaluate(d => d.matches(":modal"))).toBe(true)
        await expect(dialog.locator("a[aria-current=page]")).toHaveAttribute("href", ROOT + "/modules/authentication/roles")
        for (let i = 0; i < 24; i++) {
          await page.keyboard.press("Tab")
          // Chromium permits Tab to browser chrome (activeElement becomes BODY).
          // It must never focus an underlying, inert application control.
          expect(await dialog.evaluate(d => document.activeElement === document.body || d.contains(document.activeElement)), "no focus escapes into the underlying page").toBe(true)
        }
        await dialog.getByRole("searchbox").fill(locale === "en" ? "password reset" : "密码重置")
        await expect(dialog.locator("a:visible")).toHaveCount(1)
        await screenshot(page, `navigation-dialog-${locale}-${width}`)
        // Chromium's first Escape clears a populated type=search field.
        await page.keyboard.press("Escape")
        await expect(dialog.getByRole("searchbox")).toHaveValue("")
        await page.keyboard.press("Escape")
        await expect(dialog).toBeHidden()
        await expect(trigger).toBeFocused()
        await trigger.press("Enter")
        await dialog.getByRole("searchbox").fill(locale === "en" ? "password reset" : "密码重置")
        await expect(dialog.locator("a:visible")).toHaveCount(1)
        await dialog.locator("a:visible").click()
        await page.waitForURL(/authentication\/forget_password/, { waitUntil: "domcontentloaded" })
        await expect(dialog).toBeHidden()
      })
    }
  }
})
