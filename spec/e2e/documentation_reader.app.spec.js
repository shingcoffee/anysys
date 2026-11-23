import { test, expect } from "@playwright/test"
import { mkdirSync } from "node:fs"
import { fileURLToPath } from "node:url"

const BASE = process.env.APP_BASE_URL
const CID = "81721200"
const SHOTS = fileURLToPath(new URL("../../tmp/playwright-docs/", import.meta.url))
const WIDTHS = [320, 390, 768, 1024, 1440]
const DRAWER = "[data-developer-docs-nav-target='drawer']"
const TRIGGER = "button[data-action='click->developer-docs-nav#openDrawer']"
const CENTER = "[data-docs-reader-center]"
const FOOTER_SEQUENCE = "[data-docs-footer-sequence]"
const AUDIENCES = {
  customer: { root: `/${CID}/admin/help/docs`, prose: ".customer-doc", directory: "customer-doc-guides-title", articles: ["getting-started", "records"] },
  developer: { root: `/${CID}/admin/maintenance/platform/developer_docs`, prose: ".developer-doc", directory: "developer-doc-guides-title", articles: ["system-map"] }
}
const LABELS = {
  en: { contents: "Contents", toc: "On this page", home: { customer: "All guides", developer: "Reference home" }, docSet: { customer: "Customer guide", developer: "Developer reference" }, section: "More in this section", sequence: "Previous / Next", empty: "No pages match that search.", clear: "Clear search" },
  "zh-CN": { contents: "目录", toc: "本页内容", home: { customer: "全部指南", developer: "文档首页" }, docSet: { customer: "客户指南", developer: "开发文档" }, section: { customer: "本节其他指南", developer: "本节其他页面" }, sequence: { customer: "上一篇 / 下一篇", developer: "上一页 / 下一页" }, empty: "没有匹配的页面。", clear: "清除搜索" }
}

function navLabel(locale, key, audience) {
  const value = LABELS[locale][key]
  return typeof value === "string" ? value : value[audience]
}

async function visit(page, audience, locale, slug = "", query) {
  const url = new URL(`${AUDIENCES[audience].root}${slug ? `/${slug}` : ""}`, BASE)
  url.searchParams.set("locale", locale)
  if (query) url.searchParams.set("q", query)
  const response = await page.goto(url.href)
  expect(response?.status()).toBe(200)
  // The shell preloads the full importmap. Finish that startup burst before
  // exercising a new GET or lazy image on the shared development server.
  await page.waitForLoadState("networkidle")
  await expect(page.locator("html")).toHaveAttribute("lang", locale)
  await page.evaluate(() => document.fonts.ready)
  await expect(page.locator(CENTER)).toBeVisible()
  await readerReady(page)
}

async function sidebarState(page, collapsed) {
  await page.context().addCookies([
    { name: "sidebar_state_maintenance", value: collapsed ? "collapsed" : "expanded", url: BASE }
  ])
}

async function openDrawer(page) {
  await readerReady(page)
  await page.locator(TRIGGER).click()
  await expect.poll(() => page.locator(DRAWER).evaluate((el) => el.getBoundingClientRect().left)).toBeCloseTo(0, 0)
  await expect(page.locator("[data-developer-docs-nav-target='backdrop']")).toBeVisible()
}

async function closeDrawer(page) {
  await page.locator(`${DRAWER} button[data-action='click->developer-docs-nav#closeDrawer']`).click()
  await expect.poll(() => page.locator(DRAWER).evaluate((el) => el.getBoundingClientRect().right)).toBeLessThanOrEqual(1)
  await expect(page.locator("[data-developer-docs-nav-target='backdrop']")).toBeHidden()
}

async function visibleContents(page, locale) {
  const desktop = page.locator(`.docs-page aside nav[aria-label='${LABELS[locale].contents}']`)
  if (await page.locator(TRIGGER).isVisible()) {
    await openDrawer(page)
    return page.locator(`${DRAWER} nav[aria-label='${LABELS[locale].contents}']`)
  }
  return desktop
}

async function visibleToc(page, locale) {
  const inline = page.locator("[data-docs-inline-toc]")
  if (await inline.isVisible()) {
    if (!(await inline.locator("details").evaluate((el) => el.open))) await inline.locator("summary").click()
    return inline.locator("nav")
  }
  return page.locator(`.docs-page nav[aria-label='${LABELS[locale].toc}']:visible`)
}

async function assertReaderGeometry(page, audience, locale, hub) {
  await readerReady(page)
  // Let layout/container queries settle after the shell's restored sidebar state.
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))))
  const metrics = await page.locator(".docs-page").evaluate((reader, proseSelector) => {
    const rect = (el) => { const r = el.getBoundingClientRect(); return { left: r.left, right: r.right, width: r.width } }
    const type = (el) => { const s = getComputedStyle(el); return { size: parseFloat(s.fontSize), leading: parseFloat(s.lineHeight) } }
    const family = (el) => el ? getComputedStyle(el).fontFamily : null
    const center = reader.querySelector("[data-docs-reader-center]")
    const prose = reader.querySelector(proseSelector)
    const main = document.querySelector("#main-content")
    const paragraph = prose.querySelector("p:not(aside > p):not(figcaption p)")
    const parent = getComputedStyle(reader.parentElement)
    const available = reader.parentElement.clientWidth - parseFloat(parent.paddingLeft) - parseFloat(parent.paddingRight)
    return {
      available,
      reader: rect(reader), center: rect(center), prose: rect(prose), h1: rect(reader.querySelector("h1")),
      main: { ...rect(main), client: main.clientWidth, scroll: main.scrollWidth },
      document: { client: document.documentElement.clientWidth, scroll: document.documentElement.scrollWidth },
      families: {
        body: family(document.body),
        h1: family(reader.querySelector("h1")),
        prose: family(prose),
        paragraph: family(paragraph),
        pre: family(prose.querySelector("pre"))
      },
      typography: {
        h1: type(reader.querySelector("h1")), summary: type(center.querySelector("header p")),
        h2: type(prose.querySelector("h2")), paragraph: type(paragraph),
        h3: prose.querySelector("h3") && type(prose.querySelector("h3")),
        list: prose.querySelector("li") && type(prose.querySelector("li")),
        callout: prose.querySelector("aside p:not(:first-child)") && type(prose.querySelector("aside p:not(:first-child)")),
        cell: prose.querySelector("td") && type(prose.querySelector("td")),
        code: prose.querySelector("pre") && type(prose.querySelector("pre"))
      }
    }
  }, AUDIENCES[audience].prose)
  // The reader fills the admin content area like every other admin page.
  expect(metrics.reader.width).toBeCloseTo(metrics.available, 0)
  // Hubs give the topic grid the full column; prose keeps the 832px measure.
  if (!hub) expect(metrics.center.width).toBeLessThanOrEqual(833)
  expect(metrics.center.left).toBeGreaterThanOrEqual(metrics.reader.left - 1)
  expect(metrics.center.right).toBeLessThanOrEqual(metrics.reader.right + 1)
  expect(Math.abs(metrics.h1.left - metrics.prose.left)).toBeLessThanOrEqual(1)
  expect(metrics.prose.width).toBeCloseTo(Math.min(metrics.center.width, 832), 0)
  expect(metrics.document.scroll).toBeLessThanOrEqual(metrics.document.client + 1)
  expect(metrics.main.scroll).toBeLessThanOrEqual(metrics.main.client + 1)
  await expect(page.locator("h1")).toHaveCount(1)
  expect(metrics.families.h1).toBe(metrics.families.body)
  expect(metrics.families.prose).toBe(metrics.families.body)
  expect(metrics.families.paragraph).toBe(metrics.families.body)
  if (metrics.families.pre) expect(metrics.families.pre).not.toBe(metrics.families.body)
  expect(metrics.typography.h1).toEqual({ size: 20, leading: 27.5 })
  expect(metrics.typography.h2).toEqual({ size: 20, leading: 25 })
  const bodyType = { size: 14, leading: 21 }
  expect(metrics.typography.paragraph).toEqual(bodyType)
  expect(metrics.typography.summary).toEqual({ size: 13, leading: 19.5 })
  if (metrics.typography.list) expect(metrics.typography.list).toEqual(bodyType)
  if (metrics.typography.callout) expect(metrics.typography.callout).toEqual(bodyType)
  if (metrics.typography.h3) expect(metrics.typography.h3).toEqual({ size: 18, leading: 24.75 })
  if (metrics.typography.cell) expect(metrics.typography.cell).toEqual(bodyType)
  if (metrics.typography.code) expect(metrics.typography.code).toEqual({ size: 13, leading: 21.125 })
  const short = page.viewportSize().height < 640
  const leftRail = page.locator(".docs-page aside").first()
  await expect(leftRail).toBeVisible({ visible: !short && metrics.reader.width >= 832 })
  await expect(page.locator(TRIGGER)).toBeVisible({ visible: short || metrics.reader.width < 832 })
  if (hub) {
    await expect(page.locator(`.docs-page nav[aria-label='${LABELS[locale].toc}']`)).toHaveCount(0)
    const panels = await page.locator(`section[aria-labelledby='${AUDIENCES[audience].directory}'] .card`).evaluateAll((els) => els.map((el) => { const r = el.getBoundingClientRect(); return { left: r.left, top: r.top, right: r.right } }))
    expect(panels.length).toBeGreaterThan(1)
    if (metrics.center.width >= 576) {
      expect(panels[1].top).toBeCloseTo(panels[0].top, 0)
      expect(panels[1].left).toBeGreaterThan(panels[0].right)
    } else {
      expect(panels[1].left).toBeCloseTo(panels[0].left, 0)
      expect(panels[1].top).toBeGreaterThan(panels[0].top)
    }
    const title = page.locator(`section[aria-labelledby='${AUDIENCES[audience].directory}'] h4`).first()
    expect(await title.evaluate((el) => parseFloat(getComputedStyle(el).fontSize))).toBe(14)
  } else {
    const toc = await visibleToc(page, locale)
    await expect(page.locator(`.docs-page nav[aria-label='${LABELS[locale].toc}']:visible`)).toHaveCount(1)
    expect(await toc.locator("a").first().evaluate((el) => parseFloat(getComputedStyle(el).fontSize))).toBe(13)
    await expect(page.locator("[data-docs-inline-toc]")).toBeVisible({ visible: short || metrics.reader.width < 1216 })
  }
  const overflow = await page.locator(CENTER).evaluate((center) => {
    const bounds = center.getBoundingClientRect()
    return [...center.querySelectorAll("h1,h2,h3,p,figure,table,pre,nav,section,.card")]
      .filter((el) => !el.closest("table,pre") || el.matches("table,pre"))
      .filter((el) => el.getClientRects().length)
      .filter((el) => { const r = el.getBoundingClientRect(); return r.left < bounds.left - 1 || r.right > bounds.right + 1 })
      .map((el) => `${el.tagName}#${el.id}`)
  })
  expect(overflow).toEqual([])
  return metrics
}

async function assertRichContent(page, audience) {
  const prose = page.locator(AUDIENCES[audience].prose)
  for (const scroller of await prose.locator("table,pre").all()) {
    const result = await scroller.evaluate((el) => {
      el.scrollLeft = el.scrollWidth
      return { overflow: getComputedStyle(el).overflowX, scrollable: el.scrollWidth > el.clientWidth + 1, moved: el.scrollLeft > 0 }
    })
    expect(result.overflow).toBe("auto")
    if (result.scrollable) expect(result.moved).toBe(true)
  }
  for (const image of await prose.locator("figure img").all()) {
    await image.scrollIntoViewIfNeeded()
    // Decode the real lazy-loaded response before measuring. A missing/invalid
    // image rejects here; an in-flight response is not a zero-width image bug.
    await image.evaluate((el) => el.decode())
    expect(await image.evaluate((el) => el.complete && el.naturalWidth > 0)).toBe(true)
    const ratio = await image.evaluate((el) => ({ rendered: el.getBoundingClientRect().width / el.getBoundingClientRect().height, natural: el.naturalWidth / el.naturalHeight }))
    expect(ratio.rendered).toBeCloseTo(ratio.natural, 2)
    const figure = image.locator("xpath=ancestor::figure")
    const src = await image.getAttribute("src")
    await expect(figure.locator("a")).toHaveCount(2)
    for (const link of await figure.locator("a").all()) await expect(link).toHaveAttribute("href", src)
  }
}

async function shot(page, name) {
  mkdirSync(SHOTS, { recursive: true })
  await page.evaluate(() => document.fonts.ready)
  await page.screenshot({ path: `${SHOTS}/${name}.png`, animations: "disabled", fullPage: false })
}

async function navigationSurface(page) {
  await readerReady(page)
  if (await page.locator(TRIGGER).isVisible()) {
    if (await page.locator(DRAWER).getAttribute("aria-hidden") === "true") await openDrawer(page)
    return page.locator(DRAWER)
  }
  return page.locator("aside[data-developer-docs-nav-target='desktop']")
}

async function readerReady(page) {
  // A Turbo cached preview is visible before the final response/controller is ready.
  await page.waitForFunction(() => {
    const reader = document.querySelector(".docs-page")
    const sidebar = document.querySelector("[data-controller~='sidebar-collapsible']")
    return !document.documentElement.hasAttribute("data-turbo-preview") &&
      document.documentElement.getAttribute("aria-busy") !== "true" &&
      !!reader && !!window.Stimulus?.getControllerForElementAndIdentifier(reader, "developer-docs-nav") &&
      (!sidebar || !!window.Stimulus.getControllerForElementAndIdentifier(sidebar, "sidebar-collapsible"))
  })
}

async function submitContentsSearch(page, input, query, locale) {
  await readerReady(page)
  const form = input.locator("xpath=ancestor::form")
  await expect(form).toHaveAttribute("method", "get")
  await expect(form.locator("input[name='locale']")).toHaveValue(locale)
  const path = new URL(await form.getAttribute("action"), BASE).pathname
  const [response] = await Promise.all([
    page.waitForResponse((response) => {
      const url = new URL(response.url())
      return response.request().method() === "GET" && url.origin === new URL(BASE).origin &&
        url.pathname === path && url.searchParams.get("q") === query && url.searchParams.get("locale") === locale
    }),
    input.press("Enter")
  ])
  expect(response.status()).toBe(200)
  expect(await response.finished()).toBeNull()
  await page.waitForURL((url) => url.pathname === path && url.searchParams.get("q") === query && url.searchParams.get("locale") === locale)
  await readerReady(page)
}

async function linkHrefs(locator) {
  return locator.evaluateAll((els) => els.map((el) => el.getAttribute("href")))
}

async function assertDescriptions(page, scope) {
  for (const link of await scope.locator("a[aria-describedby]").all()) {
    const id = await link.getAttribute("aria-describedby")
    await expect(page.locator(`[id='${id}']`)).toHaveCount(1)
    expect((await page.locator(`[id='${id}']`).textContent()).trim()).not.toBe("")
    await expect(link).toHaveAccessibleDescription((await page.locator(`[id='${id}']`).textContent()).trim())
    expect(await link.getAttribute("aria-label")).toBeNull()
    expect((await link.textContent()).trim()).not.toBe("")
  }
  const ids = await page.locator(".docs-page [id]").evaluateAll((els) => els.map((el) => el.id))
  expect(new Set(ids).size).toBe(ids.length)
}

async function assertPinnedScroll(page, scope) {
  const read = () => scope.evaluate((el) => {
    const list = el.querySelector("[data-docs-nav-list]")
    const header = el.querySelector("[data-docs-nav-header]")
    return {
      controls: [...header.querySelectorAll("a,input,button")].map((node) => ({ top: node.getBoundingClientRect().top, left: node.getBoundingClientRect().left })),
      headerTop: header.getBoundingClientRect().top,
      scroll: list.scrollTop, client: list.clientHeight, height: list.scrollHeight,
      main: document.querySelector("#main-content").scrollTop
    }
  })
  const before = await read()
  expect(before.client).toBeGreaterThan(0)
  expect(before.height).toBeGreaterThan(before.client + 10)
  await scope.locator("[data-docs-nav-list]").evaluate((el) => { el.scrollTop = el.scrollHeight })
  const after = await read()
  expect(after.scroll).toBeGreaterThan(before.scroll + 10)
  expect(after.main).toBe(before.main)
  expect(after.headerTop).toBeCloseTo(before.headerTop, 0)
  after.controls.forEach((control, index) => {
    expect(Math.abs(control.top - before.controls[index].top)).toBeLessThanOrEqual(1)
    expect(Math.abs(control.left - before.controls[index].left)).toBeLessThanOrEqual(1)
  })
}

test.describe("documentation readers", () => {
  test.skip(!BASE, "Set APP_BASE_URL to the SKIP_AUTH=1 development server")
  test.describe.configure({ timeout: 90000 })

  test("customer guide home and section navigation", async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1100 })
    const response = await page.goto(`${BASE}/${CID}/admin/help/docs?locale=en`)
    expect(response?.status()).toBe(200)
    await page.waitForLoadState("networkidle")
    await expect(page.locator("html")).toHaveAttribute("lang", "en")
    await expect(page.locator("#customer-doc-guides-title")).toHaveText("Browse guides by topic")
    await expect(page.locator(".customer-doc")).toBeVisible()
    await expect(page.locator("nav[aria-label='Contents'] section").first()).toBeVisible()
    await expect(page.locator("nav[aria-label='Contents'] details")).toHaveCount(0)
    await expect(page.locator(".docs-page aside").getByRole("link", { name: "All guides" })).toHaveCount(0)
    await expect(page.locator("nav[aria-label='On this page']")).toHaveCount(0)
    await shot(page, "customer-home-en")

    await page.getByRole("link", { name: "Get started in your workspace" }).first().click()
    await expect(page).toHaveURL(new RegExp(`/${CID}/admin/help/docs/getting-started`))
    await expect(page.locator("h1")).toContainText("Get started in your workspace")
    await expect(page.locator("nav[aria-label='More in this section']")).toBeVisible()
    await expect(page.locator(FOOTER_SEQUENCE)).toBeVisible()
    await visibleToc(page, "en")
    await expect(page.locator("nav[aria-label='On this page']:visible")).toHaveCount(1)
    await shot(page, "customer-getting-started-en")

    await page.setViewportSize({ width: 390, height: 844 })
    await page.goto(`${BASE}/${CID}/admin/help/docs/records?locale=en`)
    await openDrawer(page)
    await expect(page.locator("[data-developer-docs-nav-target='drawer']")).toBeVisible()
    await expect(page.locator("[data-developer-docs-nav-target='drawer'] nav[aria-label='Contents']")).toBeVisible()
    await shot(page, "customer-records-mobile-en")
    await closeDrawer(page)
  })

  test("developer reference home and topic cards", async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1100 })
    const response = await page.goto(`${BASE}/${CID}/admin/maintenance/platform/developer_docs`)
    expect(response?.status()).toBe(200)
    await page.waitForLoadState("networkidle")
    await expect(page.locator("#developer-doc-guides-title")).toHaveText("Browse by topic")
    await expect(page.locator(".developer-doc")).toBeVisible()
    await expect(page.getByRole("link", { name: "System map" }).first()).toBeVisible()
    await expect(page.locator("nav[aria-label='On this page']")).toHaveCount(0)
    await shot(page, "developer-home-en")

    await page.getByRole("link", { name: "System map" }).first().click()
    await expect(page).toHaveURL(new RegExp(`/${CID}/admin/maintenance/platform/developer_docs/system-map`))
    await expect(page.locator("#developer-doc-guides-title")).toHaveCount(0)
    await expect(page.locator(".docs-page").getByRole("link", { name: "Reference home" })).toHaveCount(0)
    await expect(page.locator("nav[aria-label='More in this section']")).toBeVisible()
    await shot(page, "developer-system-map-en")
  })

  test("customer Chinese home keeps grouped cards", async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1100 })
    const response = await page.goto(`${BASE}/${CID}/admin/help/docs?locale=zh-CN`)
    expect(response?.status()).toBe(200)
    await page.waitForLoadState("networkidle")
    await expect(page.locator("html")).toHaveAttribute("lang", "zh-CN")
    await expect(page.locator("#customer-doc-guides-title")).toHaveText("按主题浏览指南")
    await expect(page.locator(".docs-page aside").getByRole("link", { name: "全部指南" })).toHaveCount(0)
    await shot(page, "customer-home-zh-CN")
  })

  for (const width of [390, 1440]) {
    test(`customer overview URL renders the same hub as the docs root at ${width}px`, async ({ page }) => {
      await page.setViewportSize({ width, height: 1100 })
      await visit(page, "customer", "en")
      const root = await assertReaderGeometry(page, "customer", "en", true)
      const rootTitle = await page.locator("h1").textContent()
      const rootCards = await page.locator("section[aria-labelledby='customer-doc-guides-title'] a").evaluateAll((els) => els.map((el) => el.getAttribute("href")))

      await visit(page, "customer", "en", "overview")
      const overview = await assertReaderGeometry(page, "customer", "en", true)
      await expect(page.locator("h1")).toHaveText(rootTitle)
      expect(await page.locator("section[aria-labelledby='customer-doc-guides-title'] a").evaluateAll((els) => els.map((el) => el.getAttribute("href")))).toEqual(rootCards)
      expect(overview.reader).toEqual(root.reader)
      expect(overview.center).toEqual(root.center)
      expect(overview.prose).toEqual(root.prose)
      await expect(page.locator("nav[aria-label='Dashboard menu'] a[aria-current='page']")).toHaveCount(0)
      const contents = await visibleContents(page, "en")
      await expect(contents.locator("a[aria-current='page']")).toHaveAttribute("href", `${AUDIENCES.customer.root}/overview?locale=en`)
      if (await page.locator(TRIGGER).isVisible()) await closeDrawer(page)
      await shot(page, `customer-overview-en-${width}`)
    })
  }

  test("wide screens give the hub grid the full width and keep the article measure", async ({ page }) => {
    await page.setViewportSize({ width: 1920, height: 1100 })
    await visit(page, "customer", "en")
    await assertReaderGeometry(page, "customer", "en", true)
    const tops = await page.locator("section[aria-labelledby='customer-doc-guides-title'] .card").evaluateAll((els) => els.map((el) => Math.round(el.getBoundingClientRect().top)))
    expect(tops.filter((top) => top === tops[0])).toHaveLength(4)
    await shot(page, "customer-hub-en-1920")

    await visit(page, "customer", "en", "getting-started")
    const metrics = await assertReaderGeometry(page, "customer", "en", false)
    expect(metrics.reader.width).toBeGreaterThan(1800)
    expect(metrics.prose.width).toBeCloseTo(832, 0)
    await shot(page, "customer-getting-started-en-1920")
  })

  for (const audience of Object.keys(AUDIENCES)) {
    for (const locale of ["en", "zh-CN"]) {
      for (const width of WIDTHS) {
        for (const collapsed of audience === "developer" && width >= 768 ? [false, true] : [false]) {
          const state = audience === "developer" ? (collapsed ? "collapsed" : "expanded") : "no-sidebar"
          test(`${audience} ${locale} ${width}px ${state}: readable complete hub and articles`, async ({ page }, testInfo) => {
            test.setTimeout(90000)
            await page.setViewportSize({ width, height: 1100 })
            if (audience === "developer") await sidebarState(page, collapsed)
            await visit(page, audience, locale)
            const hub = page.locator(`section[aria-labelledby='${AUDIENCES[audience].directory}']`)
            const hrefs = await hub.locator("a").evaluateAll((els) => els.map((el) => el.getAttribute("href")))
            expect(new Set(hrefs).size).toBe(hrefs.length)
            expect(hrefs.length).toBe(audience === "customer" ? 12 : 36)
            const evidence = [{ slug: "hub", ...await assertReaderGeometry(page, audience, locale, true) }]
            await shot(page, `${audience}-hub-${locale}-${width}-${state}`)
            for (const slug of AUDIENCES[audience].articles) {
              await visit(page, audience, locale, slug)
              await expect(page.locator(`#${AUDIENCES[audience].directory}`)).toHaveCount(0)
              evidence.push({ slug, ...await assertReaderGeometry(page, audience, locale, false) })
              await assertRichContent(page, audience)
              const contents = await visibleContents(page, locale)
              const active = contents.locator("a[aria-current='page']")
              await expect(active).toHaveCount(1)
              expect(new URL(await active.getAttribute("href"), BASE).pathname).toBe(`${AUDIENCES[audience].root}/${slug}`)
              await expect(contents.locator("details,summary")).toHaveCount(0)
              expect(await active.evaluate((el) => parseFloat(getComputedStyle(el).fontSize))).toBe(13)
              if (await page.locator(TRIGGER).isVisible()) await closeDrawer(page)
              await page.locator("#main-content").evaluate((el) => { el.scrollTop = 0 })
              await shot(page, `${audience}-${slug}-${locale}-${width}-${state}`)
            }
            await testInfo.attach("computed-reader-metrics", { body: JSON.stringify(evidence, null, 2), contentType: "application/json" })
          })
        }
      }
    }
  }

  for (const audience of Object.keys(AUDIENCES)) {
    for (const locale of ["en", "zh-CN"]) {
      for (const width of [390, 1440]) {
        test(`${audience} ${locale} ${width}px: contents search preserves the complete directory`, async ({ page }) => {
          await page.setViewportSize({ width, height: 1100 })
          if (audience === "developer") await sidebarState(page, true)
          await visit(page, audience, locale)
          const directory = `section[aria-labelledby='${AUDIENCES[audience].directory}'] a`
          const hrefs = await page.locator(directory).evaluateAll((els) => els.map((el) => el.getAttribute("href")))
          const matching = audience === "customer" ? (locale === "en" ? "approved sender" : "经批准的发送方") : "Kramdown"
          for (const query of [matching, "no-guide-matches-this-qa-query"]) {
            if (await page.locator(TRIGGER).isVisible()) await openDrawer(page)
            const input = page.locator("input[name='q']:visible")
            await expect(input).toHaveCount(1)
            await input.fill(query)
            await submitContentsSearch(page, input, query, locale)
            await expect(page).toHaveURL((url) => url.searchParams.get("q") === query && url.searchParams.get("locale") === locale)
            await expect(page.locator("html")).toHaveAttribute("lang", locale)
            await expect(page.locator(".docs-page input[name='q']").first()).toHaveValue(query)
            await expect(page.locator(".docs-page input[name='q']").last()).toHaveValue(query)
            expect(await page.locator(directory).evaluateAll((els) => els.map((el) => el.getAttribute("href")))).toEqual(hrefs)
            const effectiveLocale = await page.locator("html").getAttribute("lang")
            const contentsLinks = page.locator("[data-docs-nav-list] li > a")
            if (query === matching) {
              expect(await contentsLinks.count()).toBeGreaterThan(0)
              expect(await contentsLinks.count()).toBeLessThan((hrefs.length + 1) * 2)
              for (const details of await page.locator("[data-docs-nav-list] details").all()) expect(await details.evaluate((el) => el.open)).toBe(true)
            } else {
              await expect(contentsLinks).toHaveCount(0)
              await expect(page.locator(".docs-page")).toContainText(LABELS[effectiveLocale].empty)
            }
            await expect(page.locator("html")).toHaveAttribute("lang", locale)
          }
          // Both pinned control regions expose native Clear search recovery.
          const effectiveLocale = await page.locator("html").getAttribute("lang")
          if (await page.locator(TRIGGER).isVisible()) {
            await openDrawer(page)
            await page.locator(`${DRAWER} [data-docs-nav-header]`).getByRole("link", { name: LABELS[effectiveLocale].clear, exact: true }).click()
          } else {
            await page.locator("[data-docs-nav-header='desktop']").getByRole("link", { name: LABELS[effectiveLocale].clear, exact: true }).click()
          }
          await expect(page.locator(".docs-page input[name='q']").first()).toHaveValue("")
          await expect(page).toHaveURL((url) => !url.searchParams.has("q") && url.searchParams.get("locale") === locale)
          await expect(page.locator("html")).toHaveAttribute("lang", locale)
          expect(await page.locator(directory).evaluateAll((els) => els.map((el) => el.getAttribute("href")))).toEqual(hrefs)
        })
      }
    }
  }

  for (const audience of Object.keys(AUDIENCES)) {
    for (const locale of ["en", "zh-CN"]) {
      test(`${audience} ${locale}: TOC, section, sequence, and home are native navigation`, async ({ page }) => {
        await page.setViewportSize({ width: 1024, height: 1100 })
        if (audience === "developer") await sidebarState(page, false)
        const slug = AUDIENCES[audience].articles[0]
        await visit(page, audience, locale, slug)
        const toc = await visibleToc(page, locale)
        const headingLink = toc.locator("a").nth(1)
        const fragment = await headingLink.getAttribute("href")
        await headingLink.click()
        await expect(page).toHaveURL((url) => decodeURIComponent(url.hash) === fragment)
        const heading = page.locator(AUDIENCES[audience].prose).locator(`[id='${decodeURIComponent(fragment.slice(1))}']`)
        await expect.poll(() => heading.evaluate((el) => {
          const r = el.getBoundingClientRect(); const main = document.querySelector("#main-content").getBoundingClientRect()
          return r.top >= main.top && r.top < main.bottom
        })).toBe(true)
        const sequence = page.locator(FOOTER_SEQUENCE)
        await expect(sequence.locator("a")).toHaveCount(2)
        const section = page.locator(`nav[aria-label='${navLabel(locale, "section", audience)}']`)
        await expect(section).toBeVisible()
        const related = section.locator("a").first()
        const relatedPath = new URL(await related.getAttribute("href"), BASE).pathname
        await related.click()
        await expect(page).toHaveURL((url) => url.pathname === relatedPath)
        await visit(page, audience, locale, slug)
        const next = page.locator(`${FOOTER_SEQUENCE} a`).last()
        const nextPath = new URL(await next.getAttribute("href"), BASE).pathname
        await next.click()
        await expect(page).toHaveURL((url) => url.pathname === nextPath)
        await expect(page.locator(CENTER)).toBeVisible()
        await expect(page.locator(CENTER).locator("nav").last().locator("a").first()).toHaveAttribute("href", new RegExp(`/${slug}(?:\\?|$)`))
        await expect(page.locator("html")).toHaveAttribute("lang", locale)
        const effectiveLocale = await page.locator("html").getAttribute("lang")
        const previous = page.locator(`${FOOTER_SEQUENCE} a`).first()
        expect(new URL(await previous.getAttribute("href"), BASE).pathname).toBe(`${AUDIENCES[audience].root}/${slug}`)
        await previous.click()
        await expect(page).toHaveURL((url) => url.pathname === `${AUDIENCES[audience].root}/${slug}`)
        await visit(page, audience, locale, slug)
        const contents = await visibleContents(page, locale)
        await expect(contents.locator("a[aria-current='page']")).toHaveCount(1)
        await contents.locator("a[href*='/overview']").first().click()
        await expect(page.locator(`#${AUDIENCES[audience].directory}`)).toBeVisible()
        const endpoints = page.locator(FOOTER_SEQUENCE)
        // Every reader navigation link retains the explicit document locale.
        expect(await page.locator("[data-docs-reader-center] nav").last().locator(":scope > *").evaluateAll((els) => els.map((el) => el.tagName))).toEqual(["A"])
        if (audience === "customer") await expect(endpoints.locator("a")).toHaveCount(1)
        await visit(page, audience, locale, slug, "no-guide-matches-this-qa-query")
        await expect(page.locator(`nav[aria-label='${navLabel(locale, "section", audience)}']`)).toHaveCount(1)
        await expect(page.locator(`${FOOTER_SEQUENCE} a`)).toHaveCount(2)
      })
    }
  }

  test("drawer keyboard access, dismissal, and navigation", async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 844 })
    await visit(page, "customer", "en", "records")
    await page.locator(TRIGGER).focus()
    await page.keyboard.press("Enter")
    await expect.poll(() => page.locator(DRAWER).evaluate((el) => el.getBoundingClientRect().left)).toBeCloseTo(0, 0)
    const drawer = page.locator(DRAWER)
    expect(await drawer.evaluate((el) => el.getBoundingClientRect().width)).toBeLessThanOrEqual(320 * 0.85 + 1)
    for (const control of await drawer.locator("input[type='search']:visible,button:visible,summary:visible,a:visible").all()) {
      expect(await control.evaluate((el) => el.getBoundingClientRect().height)).toBeGreaterThanOrEqual(44)
    }
    await expect(drawer.locator("details,summary")).toHaveCount(0)
    for (const control of [drawer.locator("input[type='search']"), drawer.locator("button[type='submit']"), drawer.locator("li > a").first()]) {
      await control.focus()
      expect(await control.evaluate((el) => getComputedStyle(el).boxShadow)).not.toBe("none")
    }
    await closeDrawer(page)
    await expect(page.locator(TRIGGER)).toBeFocused()
    await page.locator(TRIGGER).focus()
    for (let tab = 0; tab < 12; tab++) {
      await page.keyboard.press("Tab")
      expect(await page.evaluate(() => !!document.activeElement.closest("[data-developer-docs-nav-target='drawer']"))).toBe(false)
    }
    await openDrawer(page)
    // Tab and Shift+Tab wrap within the modal, including native details visibility.
    const focusable = drawer.locator("a:visible,button:visible,input:visible,summary:visible")
    await focusable.last().focus()
    await page.keyboard.press("Tab")
    await expect(focusable.first()).toBeFocused()
    await page.keyboard.press("Shift+Tab")
    await expect(focusable.last()).toBeFocused()
    await page.keyboard.press("Escape")
    await expect.poll(() => drawer.evaluate((el) => el.getBoundingClientRect().right)).toBeLessThanOrEqual(1)
    await expect(page.locator(TRIGGER)).toBeFocused()
    await openDrawer(page)
    await page.locator("[data-developer-docs-nav-target='backdrop']").click({ position: { x: 310, y: 400 } })
    await expect.poll(() => drawer.evaluate((el) => el.getBoundingClientRect().right)).toBeLessThanOrEqual(1)
    await openDrawer(page)
    await drawer.locator("a[href*='/overview']").first().click()
    await expect(page.locator("#customer-doc-guides-title")).toBeVisible()
    await expect.poll(() => drawer.evaluate((el) => el.getBoundingClientRect().right)).toBeLessThanOrEqual(1)
  })

  test("developer sidebar toggle and resize switch modes at measured container thresholds", async ({ page }) => {
    await sidebarState(page, true)
    await page.setViewportSize({ width: 1440, height: 1100 })
    await visit(page, "developer", "en", "system-map")
    let metrics = await assertReaderGeometry(page, "developer", "en", false)
    expect(metrics.reader.width).toBeGreaterThanOrEqual(1152)
    await page.locator("[data-sidebar-collapsible-target='rail'] [data-sidebar-collapsible-toggle]:visible").click()
    await expect.poll(() => page.locator(".docs-page").evaluate((el) => el.getBoundingClientRect().width)).toBeLessThan(1152)
    await assertReaderGeometry(page, "developer", "en", false)
    await page.locator("[data-sidebar-collapsible-target='full'] [data-sidebar-collapsible-toggle]:visible").click()
    for (const width of [980, 1024, 1200, 1264, 1440]) {
      await page.setViewportSize({ width, height: 1100 })
      metrics = await assertReaderGeometry(page, "developer", "en", false)
    }
    await page.setViewportSize({ width: 768, height: 1100 })
    await openDrawer(page)
    await page.setViewportSize({ width: 1440, height: 1100 })
    await expect(page.locator(DRAWER)).toHaveAttribute("aria-hidden", "true")
    await expect(page.locator("[data-developer-docs-nav-target='backdrop']")).toBeHidden()
    await shot(page, "developer-container-threshold-reflow")
  })

  for (const locale of ["en", "zh-CN"]) {
    for (const width of [1440, 390]) {
      test(`customer ${locale} ${width}px: direct task navigation and searched article retain reading context`, async ({ page }) => {
        test.setTimeout(90000)
        await page.setViewportSize({ width, height: 844 })
        await visit(page, "customer", locale, "forms")
        let surface = await navigationSurface(page)
        await expect(surface.locator("details,summary")).toHaveCount(0)
        await expect(surface.locator("[data-docs-nav-list] section > h3")).toHaveCount(8)
        await expect(surface.locator("[data-docs-nav-list] li > a")).toHaveCount(13)
        await assertDescriptions(page, surface)
        if (width === 1440) await shot(page, `customer-navigation-rail-${locale}`)
        // Cross-group destinations are ordinary visible links, with no disclosure step.
        await surface.locator("li > a[href*='/docs/email?']").click()
        await expect(page).toHaveURL((url) => url.pathname.endsWith("/docs/email") && url.searchParams.get("locale") === locale)
        surface = await navigationSurface(page)
        await surface.locator("li > a[href*='/docs/forms?']").click()
        await expect(page).toHaveURL((url) => url.pathname.endsWith("/docs/forms") && url.searchParams.get("locale") === locale)

        const title = await page.locator("h1").textContent()
        const prose = await page.locator(".customer-doc").innerText()
        const neighbors = await linkHrefs(page.locator(`${FOOTER_SEQUENCE} a`))
        expect(neighbors.map((href) => new URL(href, BASE).pathname.split("/").pop())).toEqual(["records", "websites"])
        const sectionSelector = `nav[aria-label='${navLabel(locale, "section", "customer")}']`
        const siblings = await linkHrefs(page.locator(`${sectionSelector} a`))
        const siblingTitles = await page.locator(sectionSelector).innerText()
        const exclusion = locale === "en" ? "approved sender" : "经批准的发送方"
        for (const [query, submit] of [[exclusion, "click"], ["no-guide-matches-this-qa-query", "click"], [title, "Enter"]]) {
          surface = await navigationSurface(page)
          await surface.locator("input[name='q']").fill(query)
          if (submit === "click") await surface.locator("button[type='submit']").click()
          else await surface.locator("input[name='q']").press("Enter")
          await expect(page).toHaveURL((url) => url.pathname.endsWith("/docs/forms") && url.searchParams.get("q") === query && url.searchParams.get("locale") === locale)
          await expect(page.locator("h1")).toHaveText(title)
          expect(await page.locator(".customer-doc").innerText()).toBe(prose)
          expect(await linkHrefs(page.locator(`${FOOTER_SEQUENCE} a`))).toEqual(neighbors)
          expect(await linkHrefs(page.locator(`${sectionSelector} a`))).toEqual(siblings)
          expect(await page.locator(sectionSelector).innerText()).toBe(siblingTitles)
          for (const href of [...neighbors, ...siblings]) {
            const url = new URL(href, BASE)
            expect(url.pathname).toContain(`/${CID}/admin/help/docs/`)
            expect(url.searchParams.get("locale")).toBe(locale)
            expect(url.searchParams.has("q")).toBe(false)
          }
          await expect(page.locator(`${CENTER} > header a[href*='#customer-doc-guide-group-content']`)).toHaveCount(1)
          if (width === 390) await expect(page.locator(DRAWER)).toHaveAttribute("aria-hidden", "true")
          surface = await navigationSurface(page)
          const current = surface.locator("a[aria-current='page']")
          await expect(current).toHaveCount(1)
          await expect(surface.locator("[data-docs-nav-header] [data-docs-current-guide]")).toHaveCount(1)
          await expect(current).toHaveAttribute("href", `${AUDIENCES.customer.root}/forms?locale=${locale}`)
          await expect(surface.locator("[data-docs-nav-list] a[aria-current], [data-docs-nav-list] [data-docs-current-guide]")).toHaveCount(0)
          const results = surface.locator("[data-docs-nav-list] li > a")
          if (query === exclusion) {
            await expect(results).toHaveCount(1)
            await expect(results).toHaveAttribute("href", `${AUDIENCES.customer.root}/sms?locale=${locale}`)
          } else if (query === title) {
            await expect(surface.locator("[data-docs-nav-list] li > a[href*='/docs/forms?']")).toHaveCount(1)
          } else {
            await expect(results).toHaveCount(0)
            await expect(surface.locator("[data-docs-nav-list]")).toContainText(LABELS[locale].empty)
            await expect(surface.locator("[data-docs-nav-list] [role='alert']")).toHaveCount(0)
            await expect(surface.locator("[data-docs-nav-list]").getByRole("link", { name: LABELS[locale].clear, exact: true })).toBeVisible()
            if (width === 390) await shot(page, `customer-navigation-context-mobile-${locale}`)
            else await shot(page, `customer-navigation-search-${locale}`)
          }
          await assertDescriptions(page, surface)
        }
        await surface.locator("[data-docs-nav-header]").getByRole("link", { name: LABELS[locale].clear, exact: true }).click()
        await expect(page).toHaveURL((url) => url.pathname.endsWith("/docs/forms") && !url.searchParams.has("q") && url.searchParams.get("locale") === locale)
        surface = await navigationSurface(page)
        await expect(surface.locator("[data-docs-nav-list] li > a")).toHaveCount(13)
        await expect(surface.locator("[data-docs-nav-list] a[aria-current='page']")).toHaveCount(1)
        if (width === 390) await closeDrawer(page)
        const nextTitle = await page.locator(`${FOOTER_SEQUENCE} a`).last().locator("span").last().textContent()
        await page.locator(`${FOOTER_SEQUENCE} a`).last().click()
        await expect(page).toHaveURL((url) => url.pathname.endsWith("/docs/websites") && !url.searchParams.has("q") && url.searchParams.get("locale") === locale)
        await expect(page.locator("h1")).toHaveText(nextTitle)
        await readerReady(page)
        await page.locator(`${FOOTER_SEQUENCE} a`).first().click()
        await expect(page).toHaveURL((url) => url.pathname.endsWith("/docs/forms") && !url.searchParams.has("q") && url.searchParams.get("locale") === locale)
        await expect(page.locator("h1")).toHaveText(title)
        await page.locator(`${CENTER} > header a[href*='#customer-doc-guide-group-content']`).click()
        await expect(page).toHaveURL((url) => url.pathname === AUDIENCES.customer.root && url.hash === "#customer-doc-guide-group-content" && url.searchParams.get("locale") === locale)
        await expect(page.locator("#customer-doc-guide-group-content")).toBeInViewport()
        await expect(page.locator("#customer-doc-guides-title").locator("xpath=ancestor::section").locator("li > a")).toHaveCount(12)
        surface = await navigationSurface(page)
        await expect(page.locator(`${CENTER} > header`).getByRole("link", { name: LABELS[locale].home.customer, exact: true })).toHaveCount(0)
        await surface.locator("[data-docs-nav-header]").getByRole("link", { name: LABELS[locale].docSet.customer, exact: true }).click()
        await expect(page).toHaveURL((url) => url.pathname === AUDIENCES.customer.root && !url.hash && url.searchParams.get("locale") === locale)
      })
    }

    test(`customer ${locale}: desktop current guide reveal preserves user scroll and reading focus`, async ({ page }) => {
      test.setTimeout(90000)
      const desktop = page.locator("aside[data-developer-docs-nav-target='desktop']")
      const list = desktop.locator("[data-docs-nav-list]")
      const main = page.locator("#main-content")
      const settleLayout = () => page.evaluate(async () => {
        // Flush resize, ResizeObserver and scheduled reveal frames before measuring.
        for (let frame = 0; frame < 3; frame++) await new Promise(requestAnimationFrame)
      })
      const headerPositions = () => desktop.locator("[data-docs-nav-header]").evaluate((el) =>
        [el, ...el.querySelectorAll("a,input,button")].map((node) => {
          const bounds = node.getBoundingClientRect()
          return { top: bounds.top, left: bounds.left }
        }))
      const expectHeaderPositions = async (expected) => {
        const actual = await headerPositions()
        expect(actual).toHaveLength(expected.length)
        actual.forEach((position, index) => {
          expect(Math.abs(position.top - expected[index].top)).toBeLessThanOrEqual(1)
          expect(Math.abs(position.left - expected[index].left)).toBeLessThanOrEqual(1)
        })
      }
      const expectWholeCurrentRow = async () => {
        const current = list.locator("[data-docs-current-guide]")
        await expect(current).toHaveCount(1)
        await expect.poll(() => current.evaluate((el) => {
          const row = el.getBoundingClientRect()
          const listBounds = el.closest("[data-docs-nav-list]").getBoundingClientRect()
          return row.top >= listBounds.top - 1 && row.bottom <= listBounds.bottom + 1 &&
            row.left >= listBounds.left - 1 && row.right <= listBounds.right + 1
        })).toBe(true)
      }
      const expectMainAtTop = async () => {
        expect(await main.evaluate((el) => el.scrollTop)).toBe(0)
        expect(await page.evaluate(() => document.scrollingElement.scrollTop)).toBe(0)
      }

      for (const slug of ["forms", "support"]) {
        await page.setViewportSize({ width: 1440, height: 844 })
        await visit(page, "customer", locale, slug)
        await settleLayout()
        await expect(desktop).toBeVisible()
        await expect(page.locator(TRIGGER)).toBeHidden()
        await expectWholeCurrentRow()
        expect(await list.evaluate((el) => el.scrollTop)).toBeGreaterThan(0)
        await expectMainAtTop()
        // Revealing navigation must not move focus from the document into the rail/drawer.
        expect(await page.evaluate(() => !!document.activeElement.closest("aside[data-developer-docs-nav-target='desktop'], [data-developer-docs-nav-target='drawer']"))).toBe(false)
        await expect(page.locator(DRAWER)).toHaveAttribute("aria-hidden", "true")
        const pinnedHeader = await headerPositions()
        const readingFocus = page.locator(`${FOOTER_SEQUENCE} a`).first()
        await readingFocus.evaluate((el) => el.focus({ preventScroll: true }))

        await list.evaluate((el) => { el.scrollTop = 0 })
        await settleLayout()
        await expectHeaderPositions(pinnedHeader)
        for (const viewport of [{ width: 1200, height: 820 }, { width: 1440, height: 844 }]) {
          await page.setViewportSize(viewport)
          await settleLayout()
          await expect(desktop).toBeVisible()
          await expect(page.locator(TRIGGER)).toBeHidden()
          // Both window resize and reader-width observation stay in desktop mode.
          expect(await list.evaluate((el) => el.scrollTop)).toBe(0)
          await expect(readingFocus).toBeFocused()
          await expectMainAtTop()
        }
        await expectHeaderPositions(pinnedHeader)

        await page.setViewportSize({ width: 1440, height: 550 })
        await settleLayout()
        await expect(desktop).toBeHidden()
        await expect(page.locator(TRIGGER)).toBeVisible()
        await expect(readingFocus).toBeFocused()
        await expectMainAtTop()
        await openDrawer(page)
        await expect(page.locator(`${DRAWER} button[data-action='click->developer-docs-nav#closeDrawer']`)).toBeFocused()
        await expectMainAtTop()
        await closeDrawer(page)
        await expect(page.locator(TRIGGER)).toBeFocused()
        await readingFocus.evaluate((el) => el.focus({ preventScroll: true }))
        await page.setViewportSize({ width: 1440, height: 844 })
        await settleLayout()
        await expect(desktop).toBeVisible()
        await expectWholeCurrentRow()
        expect(await list.evaluate((el) => el.scrollTop)).toBeGreaterThan(0)
        await expectHeaderPositions(pinnedHeader)
        await expect(readingFocus).toBeFocused()
        await expectMainAtTop()
        await shot(page, `customer-navigation-desktop-reveal-${slug}-${locale}`)

        const query = locale === "en" ? "approved sender" : "经批准的发送方"
        await visit(page, "customer", locale, slug, query)
        await settleLayout()
        const context = desktop.locator("[data-docs-nav-header] [data-docs-current-guide]")
        await expect(desktop.locator("a[aria-current='page']")).toHaveCount(1)
        await expect(context).toHaveAttribute("href", `${AUDIENCES.customer.root}/${slug}?locale=${locale}`)
        await expect(context).toBeInViewport({ ratio: 1 })
        await expect(list.locator("li > a")).toHaveCount(1)
        await expect(list.locator("li > a")).toHaveAttribute("href", `${AUDIENCES.customer.root}/sms?locale=${locale}`)
        await expect(list.locator("[data-docs-current-guide], a[aria-current]")).toHaveCount(0)
        expect(await list.evaluate((el) => el.scrollTop)).toBe(0)
        await expectMainAtTop()
        const searchHeader = await headerPositions()
        await page.setViewportSize({ width: 1440, height: 550 })
        await settleLayout()
        await expect(desktop).toBeHidden()
        await page.setViewportSize({ width: 1440, height: 844 })
        await settleLayout()
        await expect(desktop).toBeVisible()
        await expect(context).toBeInViewport({ ratio: 1 })
        expect(await list.evaluate((el) => el.scrollTop)).toBe(0)
        await expectHeaderPositions(searchHeader)
        await expectMainAtTop()
      }
    })

    test(`customer ${locale}: fixed header survives real desktop and mobile list scrolling`, async ({ page }) => {
      for (const viewport of [{ width: 1440, height: 640 }, { width: 390, height: 640 }]) {
        await page.setViewportSize(viewport)
        await visit(page, "customer", locale, "forms", locale === "en" ? "a" : "。")
        const surface = await navigationSurface(page)
        await assertPinnedScroll(page, surface)
        const support = surface.locator("li > a[href*='/docs/support?']")
        await expect(support).toBeInViewport()
        if (viewport.width === 390) await closeDrawer(page)
      }
    })

    test(`customer ${locale} 320px: late active guide reveal preserves close focus and main scroll`, async ({ page }) => {
      await page.setViewportSize({ width: 320, height: 844 })
      await visit(page, "customer", locale, "support")
      const main = page.locator("#main-content")
      await main.evaluate((el) => { el.scrollTop = 180 })
      const before = await main.evaluate((el) => ({ scroll: el.scrollTop, proseTop: el.querySelector(".customer-doc").getBoundingClientRect().top }))
      await openDrawer(page)
      const drawer = page.locator(DRAWER)
      await expect(drawer.locator("button[data-action='click->developer-docs-nav#closeDrawer']")).toBeFocused()
      const active = drawer.locator("[data-docs-nav-list] [data-docs-current-guide]")
      const contained = () => active.evaluate((el) => { const row = el.getBoundingClientRect(); const list = el.closest("[data-docs-nav-list]").getBoundingClientRect(); return row.top >= list.top - 1 && row.bottom <= list.bottom + 1 })
      await expect.poll(contained).toBe(true)
      expect(await drawer.locator("[data-docs-nav-list]").evaluate((el) => el.scrollTop)).toBeGreaterThan(0)
      expect(await main.evaluate((el) => ({ scroll: el.scrollTop, proseTop: el.querySelector(".customer-doc").getBoundingClientRect().top }))).toEqual(before)
      await closeDrawer(page)
      await expect(page.locator(TRIGGER)).toBeFocused()
      await expect(page.locator(`${FOOTER_SEQUENCE} a`)).toHaveCount(1)
      await assertReaderGeometry(page, "customer", locale, false)
      const wrap = await page.locator(`${FOOTER_SEQUENCE} a span`).last().evaluate((el) => ({ scroll: el.scrollWidth, width: el.clientWidth }))
      expect(wrap.scroll).toBeLessThanOrEqual(wrap.width + 1)
      await visit(page, "customer", locale, "support", locale === "en" ? "approved sender" : "经批准的发送方")
      await openDrawer(page)
      await expect(drawer.locator("[data-docs-nav-header] [data-docs-current-guide]")).toBeInViewport()
      await expect(drawer.locator("button[data-action='click->developer-docs-nav#closeDrawer']")).toBeFocused()
      expect(await drawer.locator("[data-docs-nav-list]").evaluate((el) => el.scrollTop)).toBe(0)
      await closeDrawer(page)
      await openDrawer(page)
      expect(await drawer.locator("[data-docs-nav-list]").evaluate((el) => el.scrollTop)).toBe(0)
      await closeDrawer(page)
      await page.setViewportSize({ width: 320, height: 550 })
      await openDrawer(page)
      await expect(drawer.locator("[data-docs-nav-header] [data-docs-current-guide]")).toBeInViewport()
      const bounds = await drawer.evaluate((el) => {
        const r = el.getBoundingClientRect()
        const list = el.querySelector("[data-docs-nav-list]")
        return {
          listHeight: list.clientHeight, bottom: list.getBoundingClientRect().bottom,
          overflow: [...el.querySelectorAll("[data-docs-nav-header] a,input,button")].filter((node) => { const b = node.getBoundingClientRect(); return b.left < r.left - 1 || b.right > r.right + 1 || b.bottom > r.bottom + 1 }).length
        }
      })
      expect(bounds.listHeight).toBeGreaterThanOrEqual(64)
      expect(bounds.bottom).toBeLessThanOrEqual(551)
      expect(bounds.overflow).toBe(0)
      await shot(page, `customer-navigation-short-mobile-${locale}`)
      await closeDrawer(page)
    })
  }

  test("developer drawer lists every group and reveals a late current page with list-only scroll", async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 844 })
    await visit(page, "developer", "en", "internationalization")
    const before = await page.locator("#main-content").evaluate((el) => el.scrollTop)
    await openDrawer(page)
    const drawer = page.locator(DRAWER)
    await expect(drawer.locator("details,summary")).toHaveCount(0)
    await expect(drawer.locator("[data-docs-nav-list] section > h3")).toHaveCount(6)
    await expect(drawer.locator("button[data-action='click->developer-docs-nav#closeDrawer']")).toBeFocused()
    const active = drawer.locator("[data-docs-current-guide]")
    await expect.poll(() => active.evaluate((el) => { const row = el.getBoundingClientRect(); const list = el.closest("[data-docs-nav-list]").getBoundingClientRect(); return row.top >= list.top - 1 && row.bottom <= list.bottom + 1 })).toBe(true)
    expect(await drawer.locator("[data-docs-nav-list]").evaluate((el) => el.scrollTop)).toBeGreaterThan(0)
    expect(await page.locator("#main-content").evaluate((el) => el.scrollTop)).toBe(before)
    await shot(page, "developer-navigation-drawer-reveal")
    await closeDrawer(page)
    await page.setViewportSize({ width: 1440, height: 1100 })
    await sidebarState(page, true)
    await visit(page, "developer", "en", "system-map", "a")
    await assertPinnedScroll(page, await navigationSurface(page))
  })

  test("reading aids: full-height rails, scroll-spy, search shortcut, back to top and code copy", async ({ page, context }) => {
    await context.grantPermissions(["clipboard-read", "clipboard-write"])
    await sidebarState(page, true)
    await page.setViewportSize({ width: 1440, height: 900 })
    await visit(page, "developer", "en", "system-map")
    const main = page.locator("#main-content")
    const rail = page.locator("aside[data-developer-docs-nav-target='desktop'] > div")
    const bounds = async () => ({
      main: await main.evaluate((el) => el.getBoundingClientRect().bottom),
      rail: await rail.evaluate((el) => el.getBoundingClientRect().bottom)
    })
    await main.evaluate((el) => { el.scrollTop = 600 })
    await expect.poll(async () => { const b = await bounds(); return b.main - b.rail }).toBeLessThanOrEqual(32)
    expect((await bounds()).rail).toBeLessThanOrEqual((await bounds()).main)

    const toc = page.locator(".docs-page > div > nav[aria-label='On this page']")
    await expect(toc).toBeVisible()
    await main.evaluate((el) => { el.scrollTop = 0 })
    await expect(toc.locator("a[aria-current='location']")).toHaveCount(1)
    const target = toc.locator("[data-docs-reader-target='tocLink']").nth(2)
    await target.click()
    await expect(target).toHaveAttribute("aria-current", "location")
    await main.evaluate((el) => { el.scrollTop = el.scrollHeight })
    await expect(toc.locator("[data-docs-reader-target='tocLink']").last()).toHaveAttribute("aria-current", "location")
    await toc.getByRole("link", { name: "Back to top" }).click()
    await expect.poll(() => main.evaluate((el) => el.scrollTop)).toBeLessThan(80)

    await page.locator(".developer-doc").click({ position: { x: 5, y: 5 } })
    await page.keyboard.press("/")
    await expect(page.locator("#developer-docs-q")).toBeFocused()
    await page.keyboard.press("Escape")

    const block = page.locator(".developer-doc [data-docs-code]").first()
    await block.scrollIntoViewIfNeeded()
    await block.hover()
    const copy = block.getByRole("button", { name: "Copy" })
    await expect(copy).toBeVisible()
    await copy.click()
    await expect(block.getByRole("button", { name: "Copied" })).toBeVisible()
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(await block.locator("pre").textContent())
    await shot(page, "developer-reading-aids")
  })

  for (const audience of Object.keys(AUDIENCES)) {
    for (const locale of ["en", "zh-CN"]) {
      test(`${audience} ${locale}: wide short-height fallback returns to desktop at 640px`, async ({ page }) => {
        if (audience === "developer") await sidebarState(page, true)
        await page.setViewportSize({ width: 1440, height: 550 })
        await visit(page, audience, locale, AUDIENCES[audience].articles[0])
        await assertReaderGeometry(page, audience, locale, false)
        await openDrawer(page)
        await expect(page.locator(`${DRAWER} [data-docs-nav-list]`)).toBeVisible()
        expect(await page.locator(`${DRAWER} [data-docs-nav-list]`).evaluate((el) => el.clientHeight)).toBeGreaterThan(64)
        await shot(page, `${audience}-navigation-short-height-${locale}`)
        await page.setViewportSize({ width: 1440, height: 640 })
        await expect(page.locator(DRAWER)).toHaveAttribute("aria-hidden", "true")
        await expect(page.locator("[data-developer-docs-nav-target='backdrop']")).toBeHidden()
        await assertReaderGeometry(page, audience, locale, false)
      })
    }
  }

  for (const audience of Object.keys(AUDIENCES)) {
    for (const locale of ["en", "zh-CN"]) {
      test(`${audience} ${locale}: 200% effective desktop zoom reflows without horizontal loss`, async ({ browser }) => {
        // At 200% desktop zoom, a 1440x1100 physical window exposes 720x550 CSS pixels.
        // A DPR-2 context reproduces that layout budget rather than applying non-reflowing pinch zoom.
        const context = await browser.newContext({ viewport: { width: 720, height: 550 }, deviceScaleFactor: 2 })
        try {
          const page = await context.newPage()
          if (audience === "developer") await sidebarState(page, false)
          await visit(page, audience, locale, AUDIENCES[audience].articles[0])
          await assertReaderGeometry(page, audience, locale, false)
          await assertRichContent(page, audience)
          await page.locator("#main-content").evaluate((el) => { el.scrollTop = 0 })
          await shot(page, `${audience}-${locale}-200-percent-reflow`)
        } finally {
          await context.close()
        }
      })
    }
  }
})
