import { test, expect } from "@playwright/test"
import { BASE, protect, fixture, connected, shell, fits, screenshot, payload, interceptedSubmit, visit } from "./customer_settings_support.js"

// First export authorized HTML from rolled-back test DB records:
// SETTINGS_BROWSER_FIXTURES=1 bundle exec rspec spec/system/admin/settings/customer_settings_browser_fixtures_spec.rb
// Then APP_BASE_URL=http://127.0.0.1:3000 npx playwright test --config config/javascript/playwright.config.js spec/e2e/customer_settings*.app.spec.js
test.describe("customer settings conditional states from isolated Rails test responses", () => {
  test.skip(!BASE, "Set APP_BASE_URL and generate the test-database fixtures")
  test.setTimeout(120000)

  for (const locale of ["en", "zh-CN"]) {
    for (const width of [320, 390, 768, 1440]) {
      test(`role edit grants review, token edit, populated footer and invoices fit ${locale} ${width}`, async ({ page, context }) => {
        const guard = await protect(context)
        await page.setViewportSize({ width, height: 900 })
        for (const name of ["role-edit", "role-grants", "token-edit", "website-footer", "invoice-list", "invoice-detail", "invoice-download"]) {
          const data = await fixture(page, guard, name, locale)
          await shell(page, data.path, locale)
          await fits(page, `${name} ${locale} ${width}`)
          await page.locator("main details").evaluateAll(nodes => nodes.forEach(n => { n.open = true }))
          await fits(page, `${name} expanded ${locale} ${width}`)
          if ([390, 1440].includes(width)) await screenshot(page, `fixture-${name}-${locale}-${width}`)
          if (name === "invoice-detail") {
            await expect(page.locator("main")).toContainText("INV-QA-SETTINGS")
            await expect(page.locator("main form")).toHaveCount(0)
            await expect(page.locator("main a[href$='/download']")).toHaveCount(1)
          }
          if (name === "invoice-download") {
            await page.emulateMedia({ media: "print" })
            const styles = await page.locator("main").evaluate(n => ({ overflow: getComputedStyle(n).overflowY, height: n.clientHeight, scroll: n.scrollHeight }))
            expect(styles.overflow).toBe("visible")
            expect(styles.height).toBeGreaterThanOrEqual(styles.scroll - 2)
            await expect(page.locator("[data-shell-workspace] > aside")).toBeHidden()
            await page.emulateMedia({ media: "screen" })
          }
        }
        await visit(page, "/modules/authentication/sign_up", locale)
        await page.emulateMedia({ media: "print" })
        // Print expansion is opt-in for invoice downloads, not every settings page.
        expect(await page.locator("main").evaluate(n => getComputedStyle(n).overflowY)).toBe("auto")
        expect(guard.writes).toEqual([])
        expect(guard.unexpected).toEqual([])
      })
    }

    for (const width of [390, 1440]) {
      test(`reserved member grants remain read-only through label and action filters ${locale} ${width}`, async ({ page, context }) => {
        const guard = await protect(context)
        await page.setViewportSize({ width, height: 900 })
        await fixture(page, guard, "role-grants", locale)
        await connected(page, "[data-controller='grants-editor']", "grants-editor")
        const editor = page.locator("[data-controller='grants-editor']")
        await expect(editor).toHaveAttribute("data-grants-editor-locked-value", "true")
        await editor.locator("details").evaluateAll(nodes => nodes.forEach(n => { n.open = true }))
        const boxes = editor.getByRole("checkbox")
        const original = await boxes.evaluateAll(nodes => nodes.map(node => ({ checked: node.checked, disabled: node.disabled })))
        expect(original.length).toBeGreaterThan(0)
        expect(original.every(node => node.disabled)).toBe(true)
        await expect(editor.locator("[data-grants-editor-target='saveButton'],[data-grants-editor-target='saveBar']")).toHaveCount(0)
        await expect(editor).toContainText(locale === "en" ? "Permissions are read-only" : "权限只读")
        const row = editor.locator("[data-grants-editor-target='row']").first()
        const label = await row.getAttribute("data-display-label")
        const search = editor.locator("[data-grants-editor-target='search']")
        await search.fill("no-such-capability-qa")
        await expect(editor.locator("[data-grants-editor-target='emptyState']")).toBeVisible()
        await search.fill(label)
        await expect(row).toBeVisible()
        await expect(row).toContainText(label)
        await search.fill("")
        const actionFilter = editor.locator("[data-grants-editor-target='actionFilter']").first()
        const action = await actionFilter.getAttribute("data-action-name")
        await expect(actionFilter).toHaveAccessibleName(/\S/)
        await actionFilter.click()
        expect(await editor.locator("[data-grants-editor-target='row']:not(.hidden)").evaluateAll(nodes => nodes.map(node => node.dataset.actions.split(" ")))).toEqual(expect.arrayContaining([expect.arrayContaining([action])]))
        expect(await editor.locator("[data-grants-editor-target='row']:not(.hidden)").evaluateAll((nodes, action) => nodes.every(node => node.dataset.actions.split(" ").includes(action)), action)).toBe(true)
        await actionFilter.click()
        const grantedFilter = editor.locator("[data-grants-editor-target='onlyGrantedFilter']")
        await grantedFilter.click()
        expect(await editor.locator("[data-grants-editor-target='row']:not(.hidden)").evaluateAll(nodes => nodes.every(node => node.dataset.rowGranted === "true"))).toBe(true)
        await grantedFilter.click()
        await page.keyboard.press("Control+s")
        expect(await boxes.evaluateAll(nodes => nodes.map(node => ({ checked: node.checked, disabled: node.disabled })))).toEqual(original)
        await fits(page, `locked member grants ${locale} ${width}`)
        await screenshot(page, `grants-readonly-${locale}-${width}`)
        expect(guard.writes).toEqual([])
        expect(guard.unexpected).toEqual([])
      })

      test(`populated footer reorder add edit and blank removal serialize separately from replacement ${locale} ${width}`, async ({ page, context }) => {
        const guard = await protect(context)
        await page.setViewportSize({ width, height: 900 })
        await fixture(page, guard, "website-footer", locale)
        await connected(page, "[data-controller='countable-items-reorder']", "countable-items-reorder")
        const form = page.locator("form").filter({ has: page.locator("#website_name") })
        const rows = form.locator("[data-footer-columns] > li")
        await expect(rows).toHaveCount(2)
        await rows.first().locator("button[data-countable-items-reorder-target='downButton']").click()
        await expect(rows.first().locator("input[id$='_heading']")).toHaveValue("Help")
        await expect(rows.last().locator("input[id$='_heading']")).toHaveValue("Visit")
        expect(await rows.locator("input[data-countable-items-reorder-target='positionInput']").evaluateAll(nodes => nodes.map(n => n.value))).toEqual(["0", "1"])
        await rows.first().locator("input[id$='_heading']").fill("QA edited heading")
        await rows.last().locator("input[type=text]").evaluateAll(nodes => nodes.forEach(n => { n.value = ""; n.dispatchEvent(new Event("input", { bubbles: true })) }))
        await form.locator("#website_footer_column_new_heading").fill("QA new column")
        await form.locator("#website_footer_column_new_link_label").fill("QA added link")
        await form.locator("#website_footer_column_new_link_url").fill("/qa")
        expect(guard.writes).toEqual([])
        await page.locator("#website-settings-footer").scrollIntoViewIfNeeded()
        await fits(page, "populated edited footer")
        await screenshot(page, `website-populated-footer-${locale}-${width}`)
        const data = await payload(page, form)
        const save = page.locator(`button[form='${await form.getAttribute("id")}']`)
        const entry = await interceptedSubmit(page, guard, form, save)
        const sent = new URLSearchParams(entry.body)
        for (const [name, value] of data.filter(([key]) => key.startsWith("website[footer]"))) expect(sent.get(name)).toBe(value)
        expect(sent.has("skeleton_key")).toBe(false)
        expect(guard.unexpected).toEqual([])
      })

      test(`role and personalization edits submit persisted identity without live writes ${locale} ${width}`, async ({ page, context }) => {
        const guard = await protect(context)
        await page.setViewportSize({ width, height: 900 })
        for (const [name, field, value] of [["role-edit", "role[name]", "QA edited role"], ["token-edit", "emails_template_token[label]", "QA edited field"]]) {
          const data = await fixture(page, guard, name, locale)
          const form = page.locator("main form")
          await form.locator(`[name='${field}']`).fill(value)
          const entry = await interceptedSubmit(page, guard, form, form.locator("input[type=submit],button[type=submit]"))
          expect(entry.path).toBe(data.path.replace(/\/edit$/, ""))
          expect(new URLSearchParams(entry.body).get("_method")).toBe("patch")
          expect(new URLSearchParams(entry.body).get(field)).toBe(value)
        }
        expect(guard.unexpected).toEqual([])
      })
    }
  }
})
