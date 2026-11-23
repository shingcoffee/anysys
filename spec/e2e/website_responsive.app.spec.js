import { test, expect } from "./helpers/website_fixtures.js"
import { writeFileSync } from "node:fs"

const BASE = process.env.APP_BASE_URL
const PUBLIC_PATHS = [
  "/81721200/site",
  "/81721200/site/about",
  "/81721200/site/shing-test"
]
const adminPaths = (fixture) => [
  "/81721200/admin/modules/website",
  "/81721200/admin/modules/website/pages/new",
  fixture.pages.gallery.edit,
  "/81721200/admin/settings/modules/website",
  "/81721200/admin/maintenance/platform/module_settings/website/layouts",
  "/81721200/admin/maintenance/platform/module_settings/website/skeletons"
]
const VIEWPORTS = [
  { name: "desktop", width: 1440, height: 900 },
  { name: "tablet", width: 768, height: 1024 },
  { name: "mobile", width: 390, height: 844 }
]
const COMPOSER_WIDTHS = [320, 390, 768, 1024, 1280, 1440]
const LOCALES = {
  en: { settings: "Page settings", sections: "Sections on this page", save: "Save" },
  "zh-CN": { settings: "页面设置", sections: "本页区块", save: "保存" }
}

const savedForm = (page) => page.locator("[data-website-workspace]").evaluate((form) => Object.fromEntries(
  [...new FormData(form)].filter(([key]) => key.startsWith("website_page[")).map(([key, value]) => [
    key, key === "website_page[sections_json]" ? JSON.parse(value) : value
  ])
))

async function waitForComposer(page, locale) {
  await expect(page.locator("[data-website-workspace]")).toBeVisible()
  await page.waitForFunction(() => {
    const mount = document.querySelector("[data-website-workspace]")
    const controller = mount && window.Stimulus?.getControllerForElementAndIdentifier(mount, "website-builder")
    return typeof controller?.toggleHrefPicker === "function" && typeof controller?.persist === "function"
  }, null, { timeout: 30000 })
  const outline = page.locator("[data-workspace-outline]")
  const selected = page.locator("[data-website-builder-target='sectionNav'][aria-selected='true']")
  if (await outline.isVisible()) {
    await expect(selected).toBeVisible()
    await expect(selected).toBeEnabled()
  } else {
    await expect(page.locator("[data-website-builder-target='row']:visible").getByRole("textbox").first()).toBeEnabled()
  }
  const save = page.getByRole("button", { name: LOCALES[locale].save, exact: true })
  await expect(save).toBeVisible()
  await expect(save).toBeEnabled()
}

async function waitForWebsiteNav(page) {
  await expect(page.locator("[data-controller='website-nav'] header")).toBeVisible()
  await page.waitForFunction(() => {
    const mount = document.querySelector("[data-controller='website-nav']")
    return mount && window.Stimulus?.getControllerForElementAndIdentifier(mount, "website-nav")
  }, null, { timeout: 30000 })
  await expect(page.locator("[data-website-nav-target='trigger']")).toBeEnabled()
  await expect(page.getByRole("main")).toBeVisible()
}

const expectNoHorizontalOverflow = async (page) => {
  const geometry = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth
  }))
  expect(geometry.scrollWidth).toBeLessThanOrEqual(geometry.clientWidth + 1)
}

// Bare shared classes are the reference, so editor-specific overrides cannot
// make this pass merely by agreeing with another overridden editor field.
async function sharedTypography(page) {
  return page.evaluate(() => {
    const host = document.createElement("div")
    host.hidden = true
    host.innerHTML = '<input class="input-field"><label class="form-label"></label><h3 class="text-heading"></h3><h4 class="section-header"></h4><span class="text-caption"></span>'
    document.body.append(host)
    const styles = Object.fromEntries([...host.children].map((element) => {
      const css = getComputedStyle(element)
      return [element.className, { fontSize: css.fontSize, fontFamily: css.fontFamily, fontWeight: css.fontWeight }]
    }))
    host.remove()
    return { ...styles, bodyFamily: getComputedStyle(document.body).fontFamily }
  })
}

async function expectSharedTypography(scope, reference) {
  for (const [selector, key] of [
    ["input:not([type=hidden]):not([type=radio]):not([type=checkbox]):not([type=file]), textarea, select", "input-field"],
    [".form-label", "form-label"], [".text-heading", "text-heading"],
    [".section-header", "section-header"], [".text-caption", "text-caption"]
  ]) {
    const styles = await scope.locator(selector).evaluateAll((elements) => elements.map((element) => {
      const css = getComputedStyle(element)
      return { id: element.id, prop: element.dataset.prop, fontSize: css.fontSize, fontFamily: css.fontFamily, fontWeight: css.fontWeight }
    }))
    for (const { id, prop, ...style } of styles) expect.soft(style, `${selector}: ${id || prop || key}`).toEqual(reference[key])
  }
  for (const control of await scope.locator("input:not([type=hidden]), textarea, select, button").all()) {
    await expect(control).toHaveAccessibleName(/\S/)
  }
}

// Register before the first request; only the nonpersisting preview may POST.
// Compare the real saved values after reload even when an assertion fails.
async function withSettingsDraft(page, path, locale, exercise) {
  const writes = []
  await page.route("**/*", (route) => {
    const request = route.request()
    if (["GET", "HEAD"].includes(request.method())) return route.fallback()
    if (request.method() === "POST" && new URL(request.url()).pathname === path.replace(/\/edit$/, "/preview")) return route.continue()
    writes.push(`${request.method()} ${new URL(request.url()).pathname}`)
    return route.abort("blockedbyclient")
  })
  const response = await page.goto(`${BASE}${path}?locale=${locale}`, { waitUntil: "domcontentloaded", timeout: 30000 })
  expect(response?.ok()).toBe(true)
  await waitForComposer(page, locale)
  await expect(page.locator("#website_page_title")).toHaveCSS("font-size", "14px")
  expect((await page.locator("[data-workspace-identity-nav]").boundingBox()).height).toBeGreaterThanOrEqual(40)
  const original = await savedForm(page)
  try {
    await exercise(original)
  } finally {
    await page.reload({ waitUntil: "domcontentloaded" })
    await waitForComposer(page, locale)
    expect.soft(await savedForm(page), "reload must restore all saved identity and content values").toEqual(original)
    expect.soft(writes, "no save, upload or other persistence request may reach Rails").toEqual([])
  }
}

test.describe("website public pages and composer are responsive", () => {
  test.skip(!BASE, "set APP_BASE_URL to run app-backed e2e (see spec/e2e/README.md)")

  for (const [locale, labels] of Object.entries(LOCALES)) {
    for (const width of [1440, 390, 320]) {
      test(`Page settings native preferences and draft retention at ${width}px in ${locale}`, async ({ page, websiteFixture }, testInfo) => {
        test.setTimeout(150000)
        await page.setViewportSize({ width, height: width === 320 ? 568 : width === 390 ? 844 : 900 })
        await withSettingsDraft(page, websiteFixture.pages.gallery.edit, locale, async (original) => {
          const identityNav = page.locator("[data-workspace-identity-nav]")
          const identity = page.locator("[data-identity-panel]")
          await expect(page.locator("html")).toHaveAttribute("lang", locale)
          await expect(identityNav).toContainText(labels.settings)
          await expect(identity).toBeHidden()
          await expect(page.locator("[name='website_page[slug]'], #website_page_slug, label[for='website_page_slug']")).toHaveCount(0)
          expect(original).not.toHaveProperty("website_page[slug]")
          await identityNav.click()
          await expect(identity).toBeVisible()
          const reference = await sharedTypography(page)
          expect(reference["input-field"].fontSize).toBe("14px")
          expect(reference["form-label"].fontSize).toBe("13px")
          expect(reference["input-field"].fontFamily).toBe(reference.bodyFamily)
          await expectSharedTypography(identity, reference)
          expect(await savedForm(page)).toEqual(original)
          await expect(page.locator("[data-website-builder-target='unsaved']:visible")).toHaveCount(0)
          expect(await identity.textContent()).not.toMatch(/slug|路径|Lowercase letters|仅限小写/)
          const title = identity.getByRole("textbox", { name: locale === "en" ? "Title *" : "标题 *", exact: true })
          await title.focus()
          await expect(title).toBeFocused()
          await title.fill(`QA settings ${locale} ${width}`)
          await expect(page.locator("[data-website-builder-target='unsaved']:visible").first()).toBeVisible()
          const names = locale === "en" ? ["Show in navigation", "Published", "Home page"] : ["显示在导航中", "已发布", "首页"]
          const fields = ["nav_visible", "published", "home"]
          for (const [index, field] of fields.entries()) {
            const checkbox = identity.getByRole("switch", { name: names[index], exact: true })
            await expect(checkbox).toHaveAccessibleName(names[index])
            await expect(checkbox).toHaveAttribute("type", "checkbox")
            await expect(checkbox.locator("+ span")).toHaveCSS("width", "44px")
            await expect(checkbox.locator("+ span")).toHaveCSS("height", "24px")
            const label = identity.locator(`label[for='website_page_${field}']`)
            await label.scrollIntoViewIfNeeded()
            const box = await label.boundingBox()
            expect(box.height).toBeGreaterThanOrEqual(44)
            expect(box.x).toBeGreaterThanOrEqual(0)
            expect(box.x + box.width).toBeLessThanOrEqual(width)
            if (field === "home") {
              await expect(checkbox).toBeEnabled()
              page.once("dialog", (dialog) => dialog.dismiss())
              await label.click()
              await expect(checkbox).not.toBeChecked()
              page.once("dialog", (dialog) => dialog.accept())
              await checkbox.focus()
              await checkbox.press("Space")
              await expect(checkbox).toBeChecked()
            } else {
              const checked = await checkbox.isChecked()
              // Tab proves visually hidden controls remain in the native focus order.
              await page.keyboard.press("Tab")
              await expect(checkbox).toBeFocused()
              await checkbox.press("Space")
              await expect(checkbox).toBeChecked({ checked: !checked })
              await label.click()
              await expect(checkbox).toBeChecked({ checked })
              await checkbox.press("Space")
              await expect(checkbox).toBeChecked({ checked: !checked })
              await expect(checkbox.locator("+ span")).not.toHaveCSS("box-shadow", "none")
            }
          }
          const draft = await savedForm(page)
          expect(draft["website_page[title]"]).toBe(`QA settings ${locale} ${width}`)
          expect(draft["website_page[home]"]).toBe("1")
          expect(draft["website_page[sections_json]"]).toEqual(original["website_page[sections_json]"])
          await page.locator("[data-workspace-detail]:not(.hidden) [data-action*='showOutline']:visible").first().click()
          await expect(identity).toBeHidden()
          await expect(identityNav).toContainText(labels.settings)
          const tabs = page.locator("[data-website-builder-target='sectionNav']")
          await tabs.last().click()
          await page.locator("[data-workspace-detail]:not(.hidden) [data-action*='showOutline']:visible").first().click()
          await tabs.first().click()
          await page.locator("[data-workspace-detail]:not(.hidden) [data-action*='showOutline']:visible").first().click()
          if (width < 1280) {
            const panes = page.locator("[data-website-builder-target='paneBtn']")
            await panes.last().click()
            await panes.first().click()
          }
          await identityNav.click()
          expect(await savedForm(page)).toEqual(draft)
          await expectNoHorizontalOverflow(page)
          const body = identity.locator(":scope > div")
          expect(await body.evaluate((element) => element.scrollWidth <= element.clientWidth + 1)).toBe(true)
          for (const [slice, control] of [["title", title], ["preferences", identity.locator("label[for='website_page_home']")]]) {
            await control.scrollIntoViewIfNeeded()
            const path = testInfo.outputPath(`settings-${locale}-${width}-${slice}.png`)
            await page.screenshot({ path, fullPage: false })
            await testInfo.attach(`${locale}-${width}-${slice}`, { path, contentType: "image/png" })
          }
        })
      })
    }

    test(`Page settings homepage remains natively locked in ${locale}`, async ({ page, websiteFixture }) => {
      test.setTimeout(150000)
      await page.setViewportSize({ width: 390, height: 844 })
      await withSettingsDraft(page, websiteFixture.home_edit, locale, async (original) => {
        const identity = page.locator("[data-identity-panel]")
        await page.locator("[data-workspace-identity-nav]").click()
        const home = identity.locator("#website_page_home")
        await expect(home).toHaveAttribute("role", "switch")
        await expect(home).toBeChecked()
        await expect(home).toBeDisabled()
        await expect(home).toHaveAccessibleDescription(locale === "en" ? "This is the home page (/site)." : "这是首页（/site）。")
        const label = identity.locator("label[for='website_page_home']")
        await label.scrollIntoViewIfNeeded()
        const box = await label.boundingBox()
        // Locator.click waits for the associated disabled input to be enabled.
        // A real pointer click on its label must leave the native lock intact.
        await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2)
        await expect(home).toBeChecked()
        expect(await identity.evaluate((element) => new FormData(element.closest("form")).getAll("website_page[home]"))).toEqual(["1"])
        await expect(identity.locator("[name='website_page[slug]']")).toHaveCount(0)
        expect(await savedForm(page)).toEqual(original)
      })
    })
  }

  for (const viewport of VIEWPORTS) {
    test(`public marketing pages fit ${viewport.name}`, async ({ page }, testInfo) => {
      test.setTimeout(120000)
      await page.setViewportSize({ width: viewport.width, height: viewport.height })

      for (const path of PUBLIC_PATHS) {
        const response = await page.goto(`${BASE}${path}`, { waitUntil: "domcontentloaded" })
        expect(response?.ok()).toBeTruthy()
        await waitForWebsiteNav(page)
        await expectNoHorizontalOverflow(page)

        const hamburger = page.locator("[data-website-nav-target='trigger']")
        const desktopNav = page.locator("header nav.hidden")
        if (viewport.width < 1024) {
          await expect(hamburger).toBeVisible()
          await expect(desktopNav).toBeHidden()
        } else {
          await expect(hamburger).toBeHidden()
          await expect(page.locator("header nav").first()).toBeVisible()
        }

        const shotName = `${path.replaceAll("/", "-").replace(/^-/, "")}-${viewport.name}.png`
        const shotPath = testInfo.outputPath(shotName)
        await page.screenshot({ path: shotPath, fullPage: false })
        await testInfo.attach(shotName, { path: shotPath, contentType: "image/png" })
      }
    })
  }

  for (const [locale, labels] of Object.entries(LOCALES)) {
    for (const width of COMPOSER_WIDTHS) {
      test(`composer geometry and keyboard panes at ${width}px in ${locale}`, async ({ page, websiteFixture }, testInfo) => {
        test.setTimeout(180000)
        const height = width === 320 ? 568 : width === 768 ? 1024 : width < 768 ? 844 : width === 1280 ? 800 : 900
        await page.setViewportSize({ width, height })
        const writes = []
        await page.route("**/*", (route) => {
          if (["GET", "HEAD"].includes(route.request().method())) return route.fallback()
          writes.push(`${route.request().method()} ${route.request().url()}`)
          return route.abort("blockedbyclient")
        })
        const response = await page.goto(`${BASE}${websiteFixture.pages.gallery.edit}?locale=${locale}`, { waitUntil: "domcontentloaded", timeout: 30000 })
        expect(response?.ok()).toBe(true)
        await waitForComposer(page, locale)
        const original = await savedForm(page)
        try {
        const reference = await sharedTypography(page)
        expect(reference["input-field"].fontSize).toBe("14px")
        expect(reference["form-label"].fontSize).toBe("13px")
        expect(reference["input-field"].fontFamily).toBe(reference.bodyFamily)
        await expect(page.locator("html")).toHaveAttribute("lang", locale)
        const editor = page.locator("[data-website-builder-target='editorPane']")
        const preview = page.locator("[data-website-builder-target='previewPane']")
        const identityNav = page.locator("[data-workspace-identity-nav]")
        const identity = page.locator("[data-identity-panel]")
        const tabs = page.locator("[data-workspace-section-nav]").getByRole("tab")
        const paneTabs = page.locator("[data-website-builder-target='paneBtn']")
        await expect(page.locator("[data-array-item] [data-prop='body']").first()).toHaveAttribute("rows", "2")
        await expect(page.locator("[data-array-item] > div").first()).toHaveCSS("row-gap", "8px")
        await expect(page.locator("[data-website-builder-target='previewFrame']")).toHaveCSS("min-height", "0px")
        await expect(editor).toBeVisible()
        await expect(identityNav).toContainText(labels.settings)
        await expect(page.getByRole("tablist", { name: labels.sections, exact: true })).toBeVisible()
        await expect(identity).toBeHidden()
        await expect(page.getByRole("button", { name: labels.save, exact: true })).toBeInViewport({ ratio: 1 })
        await expectNoHorizontalOverflow(page)

        const editorBox = await editor.boundingBox()
        const identityBox = await identityNav.boundingBox()
        expect(identityBox.height).toBeLessThan(88)
        expect(editorBox.x).toBeGreaterThanOrEqual(0)
        expect(editorBox.x + editorBox.width).toBeLessThanOrEqual(width + 1)
        expect(editorBox.y + editorBox.height).toBeLessThanOrEqual(height + 1)
        await tabs.first().click()
        const headline = editor.locator("[data-prop='headline']").first()
        await headline.scrollIntoViewIfNeeded()
        await expect(headline).toBeInViewport({ ratio: 1 })
        const fieldBox = await headline.boundingBox()
        expect(fieldBox.width).toBeGreaterThan(Math.min(editorBox.width, 768) - 80)
        expect(fieldBox.x + fieldBox.width).toBeLessThanOrEqual(editorBox.x + editorBox.width)
        await page.locator("[data-workspace-detail]:not(.hidden) [data-action*='showOutline']:visible").first().click()
        const tabBoxes = await tabs.evaluateAll((buttons) => buttons.map((button) => {
          const { x, y, width, height } = button.getBoundingClientRect()
          return { x, y, width, height }
        }))
        for (let index = 1; index < tabBoxes.length; index++) {
          expect(Math.abs(tabBoxes[index].x - tabBoxes[0].x)).toBeLessThan(2)
          expect(tabBoxes[index].y).toBeGreaterThanOrEqual(tabBoxes[index - 1].y + tabBoxes[index - 1].height - 1)
        }

        if (width >= 1280) {
          await expect(preview).toBeVisible()
          await expect(paneTabs.first()).toBeHidden()
          const previewBox = await preview.boundingBox()
          expect(editorBox.width).toBeLessThanOrEqual(38 * 16 + 1)
          expect(editorBox.width / (editorBox.width + previewBox.width)).toBeLessThanOrEqual(0.461)
          expect(previewBox.width).toBeGreaterThan(editorBox.width)
          expect(Math.abs(previewBox.x - (editorBox.x + editorBox.width))).toBeLessThan(2)
          expect(Math.abs(previewBox.y - editorBox.y)).toBeLessThan(2)
          expect(previewBox.x + previewBox.width).toBeLessThanOrEqual(width + 1)
        } else {
          await expect(preview).toBeHidden()
          await expect(paneTabs.first()).toBeVisible()
          expect(editorBox.width).toBeGreaterThan(width * 0.9)
        }

        const screenshot = async (pane) => {
          const path = testInfo.outputPath(`composer-${locale}-${width}-${pane}.png`)
          await page.screenshot({ path, fullPage: false })
          await testInfo.attach(`${locale}-${width}-${pane}`, { path, contentType: "image/png" })
        }
        await expect(page.locator("[data-website-builder-target='previewLoading']")).toBeHidden({ timeout: 15000 })
        await screenshot("editor")
        await tabs.first().click()

        // Counts reserve their space while idle; focus reveals only the count
        // belonging to that field, without moving any neighboring controls.
        const copy = editor.locator("[data-section-type='hero_cinematic']")
        const copyFields = copy.locator("[data-count-field]").filter({ has: page.locator("[data-prop='kicker'], [data-prop='headline'], [data-prop='subhead']") })
        const counts = copyFields.locator("[data-char-count]")
        const countFor = (prop) => copy.locator("[data-count-field]").filter({
          has: page.locator(`[data-prop='${prop}']`)
        }).locator("[data-char-count]")
        const fieldGeometry = () => copyFields.evaluateAll((elements) => elements.map((element) => {
          const { x, y, width, height } = element.getBoundingClientRect()
          const row = element.closest("[data-section-type]").getBoundingClientRect()
          return { x: x - row.x, y: y - row.y, width, height }
        }))
        await expect(counts).toHaveCount(3)
        await expect(copy.locator("[data-char-count]:visible")).toHaveCount(0)
        for (const count of await counts.all()) {
          await expect(count).toHaveCSS("visibility", "hidden")
        }
        // Keep the next textarea in view too so native focus scrolling is not
        // mistaken for a character-counter layout shift on short phones.
        await copy.locator("[data-prop='subhead']").scrollIntoViewIfNeeded()
        const idleGeometry = await fieldGeometry()

        await headline.click()
        await expect(headline).toBeFocused()
        await expect(countFor("headline")).toBeVisible()
        await expect(copy.locator("[data-char-count]:visible")).toHaveCount(1)
        expect(await fieldGeometry(), "headline focus must not shift fields").toEqual(idleGeometry)
        await screenshot("focused-headline")

        // Tab past the subhead's Design trigger into the textarea to prove
        // focus-within is scoped per wrapper.
        const subheadField = copy.locator("[data-count-field]").filter({ has: page.locator("[data-prop='subhead']") })
        await headline.press("Tab")
        await expect(subheadField.locator("[data-field-header] [data-style-trigger]")).toBeFocused()
        await page.keyboard.press("Tab")
        await expect(copy.locator("[data-prop='subhead']")).toBeFocused()
        await expect(countFor("headline")).toBeHidden()
        await expect(countFor("subhead")).toBeVisible()
        await expect(copy.locator("[data-char-count]:visible")).toHaveCount(1)
        expect(await fieldGeometry(), "textarea focus must not shift fields").toEqual(idleGeometry)

        await page.locator("[data-workspace-detail]:not(.hidden) [data-action*='showOutline']:visible").first().click()
        await expect(copy.locator("[data-char-count]:visible")).toHaveCount(0)
        await tabs.first().click()
        expect(await fieldGeometry(), "blur must not shift fields").toEqual(idleGeometry)

        await page.locator("[data-workspace-detail]:not(.hidden) [data-action*='showOutline']:visible").first().click()
        await tabs.first().click()
        await page.locator("[data-workspace-detail]:not(.hidden) [data-action*='showOutline']:visible").first().click()
        await tabs.first().press("End")
        await expect(tabs.last()).toBeFocused()
        await expect(tabs.last()).toHaveAttribute("tabindex", "0")
        await expect(page.locator("[data-workspace-outline]")).toBeVisible()
        await expect(tabs.last()).toBeInViewport({ ratio: 0.99 })
        const navBox = await page.locator("[data-workspace-section-nav]").boundingBox()
        const lastBox = await tabs.last().boundingBox()
        expect(lastBox.y).toBeGreaterThanOrEqual(navBox.y - 1)
        expect(lastBox.y + lastBox.height).toBeLessThanOrEqual(navBox.y + navBox.height + 1)
        await tabs.last().press("Home")
        await expect(tabs.first()).toBeFocused()

        // Exercise every real tab, every card and every auxiliary control. Capture
        // scroll slices so tall bodies are inspected rather than clipped offscreen.
        const inspector = page.locator("[data-workspace-inspector]")
        const measurements = []
        const types = ["hero_cinematic", "card_grid", "quote", "cta_band"]
        for (const [index, type] of types.entries()) {
          if (await page.locator("[data-workspace-outline]").isHidden()) {
            await page.locator("[data-workspace-detail]:not(.hidden) [data-action*='showOutline']:visible").first().click()
          }
          await tabs.nth(index).click()
          const row = editor.locator(`[data-section-type='${type}']`)
          await expect(row).toBeVisible()
          await expect(row.locator("details[data-field-group]")).toHaveCount(0)
          // Design panels sit hidden beside their elements, so content budgets
          // measure content only; every trigger shares one visible size.
          for (const details of await row.locator("details:not([data-style-target])").all()) {
            if (!(await details.evaluate((element) => element.open))) await details.locator(":scope > summary").click()
          }
          await expect(row.locator("[data-style-panel]:visible")).toHaveCount(0)
          await expect(row.locator("[data-field-section='style']")).toHaveCount(0)
          const bodyHeight = (await row.boundingBox()).height
          for (const toggle of await row.locator("[data-href-toggle]").all()) {
            await toggle.click()
            await expect(toggle).toHaveAttribute("aria-expanded", "true")
          }
          const expandedHeight = (await row.boundingBox()).height
          const triggerBoxes = await row.locator("[data-style-trigger]").evaluateAll((elements) => elements.map((element) => {
            const rect = element.getBoundingClientRect()
            return `${Math.round(rect.width)}x${Math.round(rect.height)}`
          }))
          expect(new Set(triggerBoxes).size, `${type} Design triggers share one size: ${triggerBoxes}`).toBe(1)
          const sectionTrigger = row.locator("header [data-style-trigger]")
          await expect(sectionTrigger).toHaveCount(1)
          expect(await sectionTrigger.evaluate((element) => getComputedStyle(element).opacity)).toBe("1")
          const fieldTrigger = row.locator("[data-field-header] [data-style-trigger]:not([data-edited])").first()
          if (await fieldTrigger.count()) {
            await page.mouse.move(0, 0)
            await expect.poll(() => fieldTrigger.evaluate((element) => getComputedStyle(element).opacity)).toBe("0")
            await fieldTrigger.locator("xpath=ancestor::*[contains(@class, 'group/design')][1]").hover()
            await expect.poll(() => fieldTrigger.evaluate((element) => getComputedStyle(element).opacity)).toBe("1")
          }
          const sectionPanel = row.locator("[data-style-panel][id$='-section']")
          await sectionTrigger.click()
          await expect(sectionPanel).toBeVisible()
          await expect(sectionTrigger).toHaveAttribute("aria-expanded", "true")
          const sectionPanelHeight = (await sectionPanel.boundingBox()).height
          expect.soft(sectionPanelHeight, `${type} section Design panel height at ${width}px`).toBeLessThanOrEqual(900)
          for (const trigger of await row.locator("[data-style-trigger][aria-expanded='false']").all()) await trigger.click()
          for (const details of await row.locator("details[data-style-target]").all()) {
            if (!(await details.evaluate((element) => element.open))) await details.locator(":scope > summary").click()
          }
          await expectSharedTypography(row, reference)
          for (const picker of await row.locator("[data-href-picker] select").all()) {
            const options = await picker.locator("option").evaluateAll((elements) => elements.filter((option) => option.value).map((option) => ({ title: option.textContent.trim(), slug: option.value })))
            expect(options.length).toBeGreaterThan(0)
            for (const { title, slug } of options) {
              expect(title).not.toBe("")
              expect(title).not.toContain(` — ${slug}`)
            }
          }
          const geometry = await row.evaluate((element) => {
            const parent = element.closest("[data-workspace-inspector]")
            const box = parent.getBoundingClientRect()
            return {
              clientWidth: parent.clientWidth, scrollWidth: parent.scrollWidth,
              overflow: [...element.querySelectorAll("input:not([type=file]):not([type=radio]), textarea, select, button, summary")]
                .filter((control) => control.getClientRects().length && getComputedStyle(control).visibility !== "hidden")
                .filter((control) => { const rect = control.getBoundingClientRect(); return rect.left < box.left - 1 || rect.right > box.right + 1 })
                .map((control) => ({ tag: control.tagName, prop: control.dataset.prop, text: control.textContent.trim() }))
            }
          })
          expect.soft(geometry.overflow, `${type} expanded controls must fit at ${width}px`).toEqual([])
          expect.soft(geometry.scrollWidth).toBeLessThanOrEqual(geometry.clientWidth + 1)
          await expectNoHorizontalOverflow(page)
          const baseline = type === "card_grid" ? (width < 768 ? 3219 : 3471) : { hero_cinematic: width < 768 ? 1551 : 1635, quote: 511, cta_band: 745 }[type]
          measurements.push({ locale, width, type, bodyHeight, expandedHeight, baseline, reduction: Math.round(100 * (1 - expandedHeight / baseline)) })
          const scroll = await inspector.evaluate((element) => ({ height: element.clientHeight, max: element.scrollHeight - element.clientHeight }))
          for (let position = 0, slice = 0; position < scroll.max + scroll.height; position += Math.max(1, scroll.height - 60), slice++) {
            await inspector.evaluate((element, top) => { element.scrollTop = top }, Math.min(position, scroll.max))
            await screenshot(`${type}-expanded-${slice}`)
            if (position >= scroll.max) break
          }
          // The UX defines desktop targets for all four sections; its only
          // explicit mobile height target is the three-card body.
          // card_grid budgets include one extra single-line field row for its kicker.
          // Appearance selects live in the hidden section Design panel, outside content budgets.
          if (width === 1440 || (width === 390 && type === "card_grid")) {
            const fieldRow = type === "card_grid" ? 100 : 0
            const limit = type === "card_grid" ? (width === 390 ? 1800 : 1900) + fieldRow : { hero_cinematic: 1050, quote: 400, cta_band: 550 }[type]
            expect.soft(bodyHeight, `${type} fully open content height at ${width}px`).toBeLessThanOrEqual(limit)
            if (type === "card_grid") expect.soft(expandedHeight, "all cards, image URLs and pickers must be at least 40% shorter").toBeLessThanOrEqual(baseline * 0.6 + fieldRow)
          }
        }
        const reportPath = testInfo.outputPath(`measurements-${locale}-${width}.json`)
        writeFileSync(reportPath, JSON.stringify(measurements, null, 2))
        await testInfo.attach("expanded-body-measurements", { path: reportPath, contentType: "application/json" })
        // UI-only expansion must neither change serialization nor request a preview.
        await page.waitForTimeout(700)
        expect(await savedForm(page)).toEqual(original)
        expect(writes).toEqual([])
        await expect(page.locator("aside [data-website-builder-target='unsaved']")).toBeHidden()

        if (width < 1280) {
          await paneTabs.first().click()
          await paneTabs.first().press("ArrowRight")
          await expect(paneTabs.last()).toBeFocused()
          await expect(paneTabs.last()).toHaveAttribute("aria-selected", "true")
          await expect(paneTabs.first()).toHaveAttribute("tabindex", "-1")
          await expect(preview).toBeVisible()
          await expect(editor).toBeHidden()
        }
        const frame = page.locator("[data-website-builder-target='previewFrame']")
        const stage = page.locator("[data-website-builder-target='previewStage']")
        const previewGeometry = []
        const expectFrameFillsStage = async (viewport) => {
          await expect(frame).toBeInViewport({ ratio: 1 })
          const frameBox = await frame.boundingBox()
          const stageBox = await stage.boundingBox()
          expect(stageBox.height, "preview must have available space").toBeGreaterThan(0)
          for (const dimension of ["x", "y", "width", "height"]) {
            expect(Math.abs(frameBox[dimension] - stageBox[dimension]), `iframe must fill stage ${dimension}`).toBeLessThanOrEqual(1)
          }
          previewGeometry.push({ viewport, frame: frameBox, stage: stageBox })
        }
        await screenshot("preview-initial")
        await expectFrameFillsStage("initial")
        for (const viewport of ["mobile", "tablet", "desktop"]) {
          const button = page.locator(`[data-website-builder-target='viewportBtn'][data-viewport='${viewport}']`)
          await expect(button).toBeInViewport({ ratio: 1 })
          await button.click()
          await expect(button).toHaveAttribute("aria-pressed", "true")
          await expectFrameFillsStage(viewport)
        }
        const previewReportPath = testInfo.outputPath(`preview-geometry-${locale}-${width}.json`)
        writeFileSync(previewReportPath, JSON.stringify(previewGeometry, null, 2))
        await testInfo.attach("preview-stage-geometry", { path: previewReportPath, contentType: "application/json" })
        await expectNoHorizontalOverflow(page)
        await screenshot("preview")
        if (width < 1280) {
          await paneTabs.last().click()
          await paneTabs.last().press("Home")
          await expect(paneTabs.first()).toBeFocused()
          await expect(paneTabs.first()).toHaveAttribute("aria-selected", "true")
          await expect(editor).toBeVisible()
          await expect(preview).toBeHidden()
        }
        } finally {
          await page.reload({ waitUntil: "domcontentloaded" })
          await waitForComposer(page, locale)
          expect.soft(await savedForm(page), "saved fixture must remain unchanged after all UI toggles").toEqual(original)
          expect.soft(writes, "read-only UI toggles must not dirty, preview or persist").toEqual([])
        }
      })
    }
  }

  test("public hamburger opens a sheet on tablet and closes after growing to desktop", async ({ page }) => {
    test.setTimeout(60000)
    await page.setViewportSize({ width: 768, height: 1024 })
    const response = await page.goto(`${BASE}/81721200/site`, { waitUntil: "domcontentloaded" })
    expect(response?.ok()).toBeTruthy()
    await waitForWebsiteNav(page)
    await page.evaluate(() => window.scrollTo(0, 400))
    const trigger = page.locator("[data-website-nav-target='trigger']")
    const triggerBox = await trigger.boundingBox()
    await trigger.click()
    const panel = page.locator("[data-website-nav-target='panel']")
    await expect(panel).toBeVisible()
    // The blurred sticky header must not become the sheet's containing block.
    const overlayTargets = [panel, ...await page.locator("[data-website-nav-target='backdrop']").all()]
    for (const overlay of overlayTargets) {
      const target = await overlay.getAttribute("data-website-nav-target")
      const box = await overlay.boundingBox()
      expect(box.y, `${target} top`).toBe(0)
      expect(box.height, `${target} height`).toBe(1024)
    }
    expect((await page.locator("header").boundingBox()).y, "sticky header stays pinned").toBe(0)
    const closeBox = await panel.getByRole("button", { name: "Close menu" }).boundingBox()
    const centerY = (box) => box.y + box.height / 2
    expect(Math.abs(centerY(closeBox) - centerY(triggerBox)), "close sits where the trigger was").toBeLessThanOrEqual(1)
    expect(Math.abs(closeBox.x + closeBox.width - (triggerBox.x + triggerBox.width))).toBeLessThanOrEqual(1)
    await page.mouse.move(40, 900)
    await page.mouse.wheel(0, 600)
    await page.waitForTimeout(300)
    expect(await page.evaluate(() => window.scrollY), "page behind the sheet stays locked").toBe(400)
    await page.setViewportSize({ width: 1280, height: 800 })
    await expect(panel).toBeHidden()
  })

  for (const viewport of VIEWPORTS) {
    test(`unpublished previews, form pages, and website admin surfaces fit ${viewport.name}`, async ({ page, websiteFixture }, testInfo) => {
      test.setTimeout(240000)
      const failures = []
      await page.setViewportSize({ width: viewport.width, height: viewport.height })

      for (const path of [websiteFixture.pages.gallery.preview, websiteFixture.pages.split.preview, ...adminPaths(websiteFixture)]) {
        const response = await page.goto(`${BASE}${path}?locale=en`, { waitUntil: "domcontentloaded" })
        const status = response?.status() ?? 0
        if (status >= 400) {
          failures.push({ path, viewport: viewport.name, status })
          continue
        }
        await expect(page.locator("#main-content, [data-controller='website-nav'] header").first()).toBeVisible()
        if (await page.locator("[data-website-workspace]").count()) await waitForComposer(page, "en")
        if (await page.locator("[data-controller='website-nav']").count()) await waitForWebsiteNav(page)
        const geometry = await page.evaluate(() => ({
          clientWidth: document.documentElement.clientWidth,
          scrollWidth: document.documentElement.scrollWidth
        }))
        if (geometry.scrollWidth > geometry.clientWidth + 1) {
          failures.push({ path, viewport: viewport.name, ...geometry })
        }
        const shotName = `admin-${path.replaceAll("/", "-").replace(/^-/, "")}-${viewport.name}.png`
        const shotPath = testInfo.outputPath(shotName)
        await page.screenshot({ path: shotPath, fullPage: false })
        await testInfo.attach(shotName, { path: shotPath, contentType: "image/png" })
      }
      expect(failures, JSON.stringify(failures, null, 2)).toEqual([])
    })
  }
})
