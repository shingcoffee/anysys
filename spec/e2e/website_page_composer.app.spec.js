import { test, expect } from "./helpers/website_fixtures.js"

const BASE = process.env.APP_BASE_URL
const target = (name) => `[data-website-builder-target='${name}']`
const sections = async (page) => JSON.parse(await page.locator(target("json")).inputValue())
const rowFor = (page, type) => page.locator(`${target("row")}[data-section-type='${type}']`)
const prop = (row, key) => row.locator(`[data-prop='${key}']`)
const postedForm = (request) => new Response(request.postDataBuffer(), {
  headers: { "content-type": request.headers()["content-type"] }
}).formData()

async function waitForComposer(page, locale = "en") {
  await expect(page.locator("[data-website-workspace]")).toBeVisible()
  await page.waitForFunction(() => {
    const mount = document.querySelector("[data-website-workspace]")
    const controller = mount && window.Stimulus?.getControllerForElementAndIdentifier(mount, "website-builder")
    return typeof controller?.toggleHrefPicker === "function" && typeof controller?.persist === "function"
  }, null, { timeout: 30000 })
  const outline = page.locator("[data-workspace-outline]")
  const selected = page.locator(`${target("sectionNav")}[aria-selected='true']`)
  if (await outline.isVisible()) {
    await expect(selected).toBeVisible()
    await expect(selected).toBeEnabled()
  } else {
    await expect(selected).toBeAttached()
    await expect(page.locator(`${target("row")}:visible`).getByRole("textbox").first()).toBeEnabled()
  }
  const save = page.getByRole("button", { name: locale === "en" ? "Save" : "保存", exact: true })
  await expect(save).toBeVisible()
  await expect(save).toBeEnabled()
}

// Install before navigation: actual fixtures may never receive save or upload
// writes. Only the known nonpersisting preview POST may reach Rails.
async function withDraft(page, path, exercise) {
  const writes = []
  await page.route("**/*", async (route) => {
    const request = route.request()
    if (["GET", "HEAD"].includes(request.method())) return route.fallback()
    if (request.method() === "POST" && new URL(request.url()).pathname === path.replace(/\/edit$/, "/preview")) return route.continue()
    writes.push(`${request.method()} ${new URL(request.url()).pathname}`)
    return route.abort("blockedbyclient")
  })
  const response = await page.goto(`${BASE}${path}?locale=en`, { waitUntil: "domcontentloaded", timeout: 30000 })
  expect(response?.ok()).toBe(true)
  await waitForComposer(page)
  await expect(page.locator(target("previewFrame"))).toHaveCSS("min-height", "0px")
  await expect(page.locator("#website_page_title")).toHaveCSS("font-size", "14px")
  await expect(page.locator("#website_page_nav_visible")).toHaveAttribute("role", "switch")
  const snapshot = () => page.locator("[data-website-workspace]").evaluate((form) => Object.fromEntries(
    [...new FormData(form)].filter(([key]) => key.startsWith("website_page[")).map(([key, value]) => [
      key, key === "website_page[sections_json]" ? JSON.parse(value) : value
    ])
  ))
  const original = await snapshot()
  try {
    await exercise()
  } finally {
    await page.reload({ waitUntil: "domcontentloaded" })
    await waitForComposer(page)
    expect.soft(await snapshot(), "reload must restore every saved content and identity value").toEqual(original)
    expect.soft(writes, "only mocked uploads and nonpersisting draft previews are permitted").toEqual([])
  }
}

async function showOutline(page) {
  const outline = page.locator("[data-workspace-outline]")
  if (await outline.isVisible()) return
  await page.locator("[data-workspace-detail]:not(.hidden) [data-action*='showOutline']:visible").first().click()
  await expect(outline).toBeVisible()
}

async function selectSection(page, type) {
  const row = rowFor(page, type)
  await showOutline(page)
  await page.locator(`#${await row.getAttribute("aria-labelledby")}`).click()
  await expect(row).toBeVisible()
  return row
}

async function expectOutlineFocus(page, tab) {
  await expect(tab).toBeFocused()
  await expect(tab).toHaveAttribute("tabindex", "0")
  await expect(page.locator(`${target("sectionNav")}[tabindex='0']`)).toHaveCount(1)
  await expect(page.locator("[data-workspace-outline]")).toBeVisible()
}

async function expectOpened(page, tab) {
  await expect(tab).toHaveAttribute("aria-selected", "true")
  const panel = page.locator(`#${await tab.getAttribute("aria-controls")}`)
  await expect(panel).toBeVisible()
  await expect(panel).toHaveAttribute("aria-labelledby", await tab.getAttribute("id"))
  await expect(page.locator(`${target("row")}:visible`)).toHaveCount(1)
}

test.describe("website page composer workspace", () => {
  test.skip(!BASE, "set APP_BASE_URL to run app-backed e2e (see spec/e2e/README.md)")
  test.setTimeout(120000)
  test.use({ actionTimeout: 10000 })

  test("all four actual tabs preserve edits and keyboard navigation previews the complete draft", async ({ page, websiteFixture }) => {
    await page.setViewportSize({ width: 1440, height: 900 })
    await withDraft(page, websiteFixture.pages.gallery.edit, async () => {
      const tabs = page.locator(target("sectionNav"))
      await expect(tabs).toHaveCount(4)
      const original = await sections(page)
      expect(original.map(({ type }) => type)).toEqual(["hero_cinematic", "card_grid", "quote", "cta_band"])
      await showOutline(page)
      await tabs.first().focus()
      for (const [key, index] of [["End", 3], ["ArrowDown", 0], ["ArrowUp", 3], ["Home", 0], ["ArrowRight", 1]]) {
        await page.locator(`${target("sectionNav")}[tabindex='0']`).press(key)
        await expectOutlineFocus(page, tabs.nth(index))
      }
      await tabs.nth(1).press("Enter")
      await expectOpened(page, tabs.nth(1))
      await page.locator("[data-workspace-detail]:not(.hidden) [data-action*='showOutline']:visible").first().click()
      await expect(tabs.nth(1)).toBeFocused()
      const changes = [
        ["hero_cinematic", "headline", "Draft headline — keyboard and preview"],
        ["card_grid", "subhead", "Draft card introduction"],
        ["quote", "quote", "Draft quote"],
        ["cta_band", "body", "Draft invitation"]
      ]
      const previewPath = websiteFixture.pages.gallery.preview
      const draftPreview = page.waitForResponse(response => {
        const request = response.request()
        return request.method() === "POST" && new URL(response.url()).pathname === previewPath &&
          changes.every(([, , value]) => request.postData()?.includes(value))
      }, { timeout: 30000 })
      for (const [type, key, value] of changes) await prop(await selectSection(page, type), key).fill(value)
      for (const [type, key, value] of changes) await expect(prop(await selectSection(page, type), key)).toHaveValue(value)
      const expected = structuredClone(original)
      changes.forEach(([, key, value], index) => { expected[index].props[key] = value })
      expect(await sections(page)).toEqual(expected)
      await expect(page.locator(`aside ${target("unsaved")}`)).toBeVisible()
      const previewResponse = await draftPreview
      expect(previewResponse.status()).toBe(200)
      expect(JSON.parse((await postedForm(previewResponse.request())).get("website_page[sections_json]"))).toEqual(expected)
      const preview = page.frameLocator(target("previewFrame"))
      await expect(preview.getByRole("heading", { name: changes[0][2], exact: true })).toBeVisible({ timeout: 30000 })
      for (const [, , value] of changes) await expect(preview.locator("main")).toContainText(value)
      await expect(prop(rowFor(page, "hero_cinematic"), "subhead")).toHaveAttribute("rows", "2")
      await expect(prop(rowFor(page, "quote"), "quote")).toHaveAttribute("rows", "3")
      await expect(prop(rowFor(page, "cta_band"), "body")).toHaveAttribute("rows", "3")
    })
  })

  test("direct primary and CTA actions, optional picker keyboard and secondary disclosure retain values", async ({ page, websiteFixture }) => {
    await page.setViewportSize({ width: 1440, height: 900 })
    await withDraft(page, websiteFixture.pages.gallery.edit, async () => {
      const row = await selectSection(page, "hero_cinematic")
      await expect(row.locator("details[data-field-group]")).toHaveCount(0)
      await expect(row.getByRole("heading", { name: "Copy", exact: true })).toBeVisible()
      const primary = row.locator("[data-button-pair='primary']")
      const href = prop(primary, "primary_href")
      await expect(href).toBeVisible()
      await prop(primary, "primary_label").fill("Meet the team")
      const toggle = primary.locator("[data-href-toggle]")
      const picker = primary.getByRole("combobox")
      await expect(picker).toBeHidden()
      await toggle.click()
      await expect(picker).toBeFocused()
      await picker.press("Escape")
      await expect(picker).toBeHidden()
      await expect(toggle).toBeFocused()
      await toggle.press("Enter")
      const options = await picker.locator("option").evaluateAll((options) => options.filter((option) => option.value).map((option) => ({ text: option.textContent, value: option.value })))
      for (const option of options) expect(option.text).not.toContain(` — ${option.value}`)
      const slug = await picker.locator("option").evaluateAll((options) => options.find((option) => option.value)?.value)
      expect(slug).toBeTruthy()
      await picker.selectOption(slug)
      await expect(href).toHaveValue(slug)
      await expect(href).toBeFocused()
      await expect(picker).toBeHidden()
      await href.fill("https://example.com/team")
      const secondary = row.locator("details[data-button-pair='secondary']")
      await expect(secondary).not.toHaveAttribute("open")
      await secondary.locator("summary").click()
      await prop(secondary, "secondary_label").fill("Read more")
      await prop(secondary, "secondary_href").fill("about")
      await secondary.locator("summary").click()
      await secondary.locator("summary").press("Enter")
      await expect(prop(secondary, "secondary_href")).toHaveValue("about")
      await secondary.locator("summary").press("Space")
      const light = row.getByRole("radio", { name: "Light", exact: true })
      await light.locator("..").click()
      await light.press("ArrowRight")
      await expect(row.getByRole("radio", { name: "Dark", exact: true })).toBeChecked()
      const cta = await selectSection(page, "cta_band")
      await expect(prop(cta, "button_href")).toBeVisible()
      await prop(cta, "button_label").fill("Draft visit")
      await selectSection(page, "hero_cinematic")
      await expect(secondary).not.toHaveAttribute("open")
      await expect(href).toHaveValue("https://example.com/team")
      expect((await sections(page))[0].props).toMatchObject({ primary_label: "Meet the team", primary_href: "https://example.com/team", secondary_label: "Read more", secondary_href: "about", tone: "dark" })
      expect((await sections(page))[3].props.button_label).toBe("Draft visit")
    })
  })

  test("titled cards count, add, duplicate, reorder, remove and max bounds work in mobile drafts", async ({ page, websiteFixture }) => {
    await page.setViewportSize({ width: 390, height: 844 })
    await withDraft(page, websiteFixture.pages.gallery.edit, async () => {
      const row = await selectSection(page, "card_grid")
      const list = row.locator("[data-array='cards']")
      const items = list.locator("details[data-array-item]")
      const original = (await sections(page))[1].props.cards
      const count = original.length
      await expect(items.first()).toHaveAttribute("open")
      for (let index = 0; index < count; index++) {
        await expect(items.nth(index).locator("[data-item-title]")).toHaveText(original[index].title)
        await expect(items.nth(index).locator("[data-item-number]")).toHaveText(`${index + 1}`)
        if (index) {
          await expect(items.nth(index)).not.toHaveAttribute("open")
          await items.nth(index).locator(":scope > summary").click()
        }
        await expect(prop(items.nth(index), "body")).toHaveAttribute("rows", "2")
      }
      await expect(items.first().getByRole("button", { name: /^Move up/ })).toBeDisabled()
      await expect(items.last().getByRole("button", { name: /^Move down/ })).toBeDisabled()
      await list.locator("[data-add-item]").click()
      await expect(items).toHaveCount(count + 1)
      const added = items.nth(count)
      await expect(prop(added, "title")).toBeFocused()
      await prop(added, "title").fill("QA draft card")
      await prop(added, "body").fill("Edited live textarea")
      await prop(added, "href").fill("https://example.com/draft")
      await expect(added.locator("[data-item-title]")).toHaveText("QA draft card")
      await added.locator("[data-duplicate-item]").click()
      const duplicate = items.nth(count + 1)
      await expect(prop(duplicate, "title")).toBeFocused()
      await expect(prop(duplicate, "body")).toHaveValue("Edited live textarea")
      await expect(prop(duplicate, "href")).toHaveValue("https://example.com/draft")
      await prop(duplicate, "title").fill("QA duplicate")
      const duplicateId = await prop(duplicate, "title").getAttribute("id")
      await duplicate.getByRole("button", { name: /^Move up/ }).click()
      await expect(prop(items.nth(count), "title")).toHaveAttribute("id", duplicateId)
      await expect(items.nth(count).getByRole("button", { name: /^Move up/ })).toBeFocused()
      await items.nth(count).locator(":scope > summary").click()
      await selectSection(page, "quote")
      await selectSection(page, "card_grid")
      await expect(items.nth(count)).not.toHaveAttribute("open")
      await items.nth(count).locator(":scope > summary").press("Enter")
      await expect(prop(items.nth(count), "title")).toHaveValue("QA duplicate")
      await items.nth(count + 1).locator("[data-remove-item]").click()
      await expect(items.nth(count).locator(":scope > summary")).toBeFocused()
      await items.nth(count).locator("[data-remove-item]").click()
      await expect(items).toHaveCount(count)
      expect((await sections(page))[1].props.cards).toEqual(original)
      const max = Number(await list.getAttribute("data-max"))
      for (let index = count; index < max; index++) await list.locator("[data-add-item]").click()
      await expect(list.locator("[data-array-count]")).toHaveText(`${max}`)
      await expect(list.locator("[data-add-item]")).toBeDisabled()
      for (const button of await list.locator("[data-duplicate-item]").all()) await expect(button).toBeDisabled()
      await expect(list.locator("[data-array-limit]")).toContainText(`${max}`)
      const ids = await list.locator("[id]").evaluateAll((elements) => elements.map((element) => element.id))
      expect(new Set(ids).size).toBe(ids.length)
    })
  })

  test("native-invalid links reveal an inactive closed card and preserve its draft before save", async ({ page, websiteFixture }) => {
    await page.setViewportSize({ width: 390, height: 844 })
    await withDraft(page, websiteFixture.pages.gallery.edit, async () => {
      const cards = await selectSection(page, "card_grid")
      const item = cards.locator("[data-array-item]").nth(1)
      await item.locator(":scope > summary").click()
      const href = prop(item, "href")
      await href.fill("javascript:alert(1)")
      await expect(href).toHaveAttribute("aria-invalid", "true")
      expect(await href.evaluate((input) => input.validity.customError)).toBe(true)
      await item.locator(":scope > summary").click()
      await selectSection(page, "quote")
      await page.locator(`${target("paneBtn")}[data-pane='preview']`).click()
      await page.getByRole("button", { name: "Save", exact: true }).click()
      await expect(cards).toBeVisible()
      await expect(item).toHaveAttribute("open", "")
      await expect(href).toBeFocused()
      await expect(href).toHaveValue("javascript:alert(1)")
      const status = item.locator("[data-href-status]")
      await expect(status).toBeVisible()
      await expect(href).toHaveAttribute("aria-describedby", await status.getAttribute("id"))
      await href.fill("about")
      await expect(status).toBeHidden()
    })
  })

  test("Page settings reveals and focuses invalid hidden identity on save", async ({ page, websiteFixture }) => {
    await page.setViewportSize({ width: 390, height: 844 })
    await withDraft(page, websiteFixture.pages.gallery.edit, async () => {
      const identity = page.locator("[data-identity-panel]")
      await page.locator("[data-workspace-identity-nav]").click()
      await expect(identity).toBeVisible()
      await expect(identity.locator("#website-page-identity-heading")).toHaveText("Page settings")
      await expect(page.locator("[name='website_page[slug]'], #website_page_slug, label[for='website_page_slug']")).toHaveCount(0)
      expect(await identity.evaluate((element) => new FormData(element.closest("form")).has("website_page[slug]"))).toBe(false)
      const title = identity.getByRole("textbox", { name: "Title *", exact: true })
      await title.fill("")
      await showOutline(page)
      await page.locator(`${target("paneBtn")}[data-pane='preview']`).click()
      await page.getByRole("button", { name: "Save", exact: true }).click()
      await expect(identity).toBeVisible()
      await expect(title).toBeFocused()
      expect(await title.evaluate((input) => input.validity.valueMissing)).toBe(true)
    })
  })

  test("compact image URL, load error, mocked upload success/failure and clear preserve saved media", async ({ page, websiteFixture }) => {
    await page.setViewportSize({ width: 1440, height: 900 })
    await withDraft(page, websiteFixture.pages.gallery.edit, async () => {
      const image = (await selectSection(page, "hero_cinematic")).locator("[data-image-field]")
      const uploadPath = await page.locator("[data-website-workspace]").getAttribute("data-website-builder-upload-url-value")
      expect(uploadPath).toBeTruthy()
      let uploadCount = 0
      let failUpload = false
      const uploaded = "https://example.com/qa-mocked-upload.png"
      const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN1cAAAAASUVORK5CYII=", "base64")
      await page.route(uploaded, (route) => route.fulfill({ contentType: "image/png", body: png }))
      await page.route(`**${new URL(uploadPath, BASE).pathname}`, async (route) => {
        expect(route.request().method()).toBe("POST")
        uploadCount++
        await route.fulfill({ status: failUpload ? 422 : 200, json: failUpload ? { error: "QA mocked upload failure" } : { url: uploaded } })
      })
      await image.locator("summary").click()
      const url = prop(image, "image_url")
      const label = image.locator(":scope > label")
      await expect(label).toHaveText("Photo")
      await expect(label).toHaveAttribute("for", await url.getAttribute("id"))
      await expect(url).toHaveAccessibleName("Photo")
      // The label is visually clipped, but still names the editable URL. Its
      // utility class is an implementation detail, not the accessibility contract.
      const labelStyle = await label.evaluate((element) => {
        const css = getComputedStyle(element)
        return { display: css.display, visibility: css.visibility, width: parseFloat(css.width), height: parseFloat(css.height), clip: css.clip }
      })
      expect(labelStyle.display).not.toBe("none")
      expect(labelStyle.visibility).toBe("visible")
      expect(labelStyle.width).toBeLessThanOrEqual(1)
      expect(labelStyle.height).toBeLessThanOrEqual(1)
      expect(labelStyle.clip).toBe("rect(0px, 0px, 0px, 0px)")
      await page.route("https://example.com/qa-broken-image.png", (route) => route.abort())
      await url.fill("https://example.com/qa-broken-image.png")
      await expect(image.locator("[data-image-failed]")).toBeVisible()
      await expect(url).toHaveValue("https://example.com/qa-broken-image.png")
      await expect(image.locator("[data-image-clear]")).toBeVisible()
      const file = { name: "qa.png", mimeType: "image/png", buffer: png }
      await image.locator("input[type='file']").setInputFiles(file)
      await expect(url).toHaveValue(uploaded)
      await expect(image.locator("[data-image-present]")).toBeVisible()
      failUpload = true
      await image.locator("input[type='file']").setInputFiles(file)
      await expect(image.locator("[data-image-status]")).toHaveText("QA mocked upload failure")
      await expect(url).toHaveValue(uploaded)
      await expect(image.locator("input[type='file']")).toBeEnabled()
      await selectSection(page, "cta_band")
      await selectSection(page, "hero_cinematic")
      await expect(url).toHaveValue(uploaded)
      await image.locator("[data-image-clear]").click()
      await expect(url).toHaveValue("")
      await expect(image.locator("[data-image-empty]")).toBeVisible()
      await expect(image.locator("[data-image-clear]")).toBeHidden()
      await expect(image.locator("[data-image-status]")).toBeHidden()
      expect((await sections(page))[0].props.image_url).toBe("")
      expect(uploadCount).toBe(2)
    })
  })

  test("split image/text fixture uses direct native image-side radios and compact media", async ({ page, websiteFixture }) => {
    await page.setViewportSize({ width: 1440, height: 900 })
    await withDraft(page, websiteFixture.pages.split.edit, async () => {
      const row = await selectSection(page, "split_image_text")
      await expect(row.locator("details[data-field-group]")).toHaveCount(0)
      await row.locator("[data-image-field] summary").click()
      await expect(prop(row, "image_url")).toHaveAccessibleName("Photo")
      await prop(row, "image_url").fill("https://example.com/qa-draft-photo.png")
      await row.getByRole("radio", { name: "Right", exact: true }).locator("..").click()
      await expect(row.getByRole("radio", { name: "Right", exact: true })).toBeChecked()
      expect((await sections(page)).find(({ type }) => type === "split_image_text").props).toMatchObject({ image_url: "https://example.com/qa-draft-photo.png", image_side: "right" })
    })
  })

  test("reset confirmation is preserved: cancel retains edits and accept restores only the active draft", async ({ page, websiteFixture }) => {
    await withDraft(page, websiteFixture.pages.gallery.edit, async () => {
      const row = await selectSection(page, "quote")
      const original = await sections(page)
      await prop(row, "quote").fill("Keep unless confirmed")
      const reset = row.locator("[data-action*='resetSection']")
      page.once("dialog", async (dialog) => { expect(dialog.type()).toBe("confirm"); await dialog.dismiss() })
      await reset.click()
      await expect(prop(row, "quote")).toHaveValue("Keep unless confirmed")
      page.once("dialog", async (dialog) => { expect(dialog.type()).toBe("confirm"); await dialog.accept() })
      await reset.click()
      const defaults = JSON.parse(await row.getAttribute("data-section-defaults"))
      expect((await sections(page))[2].props).toEqual({ quote: "", attribution: "", role: "", ...defaults })
      expect((await sections(page)).filter((_, index) => index !== 2)).toEqual(original.filter((_, index) => index !== 2))
    })
  })

  for (const locale of ["en", "zh-CN"]) {
    test(`real save and publication retain locked content after reload in ${locale}`, async ({ page, websiteFixture }) => {
      test.setTimeout(180000)
      const path = websiteFixture.pages.gallery.edit
      const resource = path.replace(/\/edit$/, "")
      const writes = []
      await page.route("**/*", route => {
        const request = route.request()
        const pathname = new URL(request.url()).pathname
        if (["GET", "HEAD"].includes(request.method())) return route.fallback()
        if (request.method() === "POST" && [resource, `${resource}/preview`].includes(pathname)) return route.continue()
        writes.push(`${request.method()} ${pathname}`)
        return route.abort("blockedbyclient")
      })
      await page.setViewportSize({ width: 1440, height: 900 })
      const response = await page.goto(`${BASE}${path}?locale=${locale}`, { waitUntil: "domcontentloaded" })
      expect(response.ok()).toBe(true)
      await waitForComposer(page, locale)
      const initial = websiteFixture.snapshot()
      const identity = page.locator("[data-identity-panel]")
      await page.locator("[data-workspace-identity-nav]").click()
      const title = identity.locator("#website_page_title")
      // Match the test-owned token before any real persistence request.
      await expect(title).toHaveValue(initial.title)
      const published = identity.locator("#website_page_published")
      await expect(published).not.toBeChecked()
      const original = await sections(page)
      const originalIdentities = original.map(({ id, type }) => ({ id, type }))
      const draftTitle = `Website saved ${locale} ${websiteFixture.token}`
      await title.fill(draftTitle)
      await identity.locator("label[for='website_page_published']").click()
      const quote = await selectSection(page, "quote")
      await prop(quote, "quote").fill(`Saved quote ${locale}`)
      const expected = await sections(page)
      const save = page.getByRole("button", { name: locale === "en" ? "Save" : "保存", exact: true })
      const saved = page.waitForResponse(response => response.request().method() === "POST" && new URL(response.url()).pathname === resource, { timeout: 30000 })
      await save.click()
      const savedResponse = await saved
      const posted = await postedForm(savedResponse.request())
      expect(JSON.parse(posted.get("website_page[sections_json]"))).toEqual(expected)
      expect(posted.get("website_page[title]")).toBe(draftTitle)
      expect(posted.getAll("website_page[published]")).toContain("1")
      expect(savedResponse.status()).toBe(200)
      expect(await savedResponse.json()).toEqual({ ok: true })
      await expect(page.locator(`${target("unsaved")}:visible`)).toHaveCount(0)
      await page.reload({ waitUntil: "domcontentloaded" })
      await waitForComposer(page, locale)
      expect(await sections(page)).toEqual(expected)
      expect((await sections(page)).map(({ id, type }) => ({ id, type }))).toEqual(originalIdentities)
      await page.locator("[data-workspace-identity-nav]").click()
      await expect(title).toHaveValue(draftTitle)
      await expect(published).toBeChecked()
      const persisted = websiteFixture.snapshot()
      expect(persisted).toMatchObject({ id: initial.id, website_id: initial.website_id, slug: initial.slug, layout_key: initial.layout_key, home: false, published: true, title: draftTitle, sections: expected })

      // Taking the page offline must leave all saved content and row identities.
      await identity.locator("label[for='website_page_published']").click()
      const unpublished = page.waitForResponse(response => response.request().method() === "POST" && new URL(response.url()).pathname === resource, { timeout: 30000 })
      await save.click()
      const unpublishedResponse = await unpublished
      expect(unpublishedResponse.status()).toBe(200)
      expect(await unpublishedResponse.json()).toEqual({ ok: true })
      await expect(page.locator(`${target("unsaved")}:visible`)).toHaveCount(0)
      await page.reload({ waitUntil: "domcontentloaded" })
      await waitForComposer(page, locale)
      expect(await sections(page)).toEqual(expected)
      await page.locator("[data-workspace-identity-nav]").click()
      await expect(published).not.toBeChecked()
      expect(websiteFixture.snapshot()).toEqual({ ...persisted, published: false })
      expect(writes).toEqual([])
    })
  }
})
