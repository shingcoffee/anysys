import { test, expect } from "@playwright/test"
import { writeFileSync } from "node:fs"

const BASE = process.env.APP_BASE_URL
const RUN = Date.now()
const PREFIX = process.env.MARKETING_POLISH_PREFIX || `/tmp/opencode/marketing-polish-spec-${RUN}`
const PAGES = { home: { sections: 11, images: 2 }, platform: { sections: 9, images: 2 }, pricing: { sections: 5, images: 0 }, about: { sections: 6, images: 2 }, contact: { sections: 3, images: 1 } }
const VIEWPORTS = [
  { name: "320", width: 320, height: 844 }, { name: "390", width: 390, height: 844 },
  { name: "768", width: 768, height: 1024 }, { name: "1024", width: 1024, height: 900 },
  { name: "1440", width: 1440, height: 900 },
  // Browser page-zoom-equivalent reflow: 1440×900 physical pixels at 200%.
  // DPR provides screenshot density; the 720 CSS viewport causes real reflow.
  { name: "1440-200pct", width: 720, height: 450, deviceScaleFactor: 2 }
]
const COPY = {
  en: {
    reference: "Start free and upgrade only when you're ready to grow. Reference monthly prices in USD — plans, trials, currency and charges are confirmed in workspace billing.",
    plans: ["Free", "Starter", "Pro", "Enterprise"], cadence: "USD / month", recommended: "Most popular", foundation: "More than a plan. A complete, connected workspace.",
    channel: "Talk to us from inside your workspace.",
    availability: "Already building? Open the Help menu in your workspace to start a support conversation — our team replies right in the thread, with the full context of your setup.",
    routes: ["See how records, forms and websites work together.", "Compare plans and find the perfect fit.", "Create a workspace and start shaping your idea."],
    quotas: [["Up to 10 pages", "Up to 5 custom record types", "1 member seat"], ["Up to 50 pages", "Up to 25 custom record types", "5 member seats", "14-day free trial"], ["Up to 500 pages", "Up to 200 custom record types", "25 member seats", "14-day free trial"], ["Unlimited pages", "Unlimited custom record types", "Unlimited member seats", "14-day free trial"]],
    faqAnswers: [
      "In the standard plan guide, Free is $0 per month, with up to 10 pages, 5 custom record types and 1 member seat.",
      "In the standard plan guide, Starter, Pro and Enterprise each include a 14-day trial. Your workspace shows available trial offers.",
      "Pages are pages created in the page builder, including form pages—not the marketing pages in the website builder. Custom record types are the kinds of data you define, not individual records. Member seats count registered workspace accounts, including administrators.",
      "This guide shows reference monthly prices in USD. Your workspace billing settings show available plans and offers, your billing currency and any applicable usage charges."
    ]
  },
  "zh-CN": {
    reference: "免费起步，准备好增长时再升级。以下为美元月度参考价格，具体方案、试用、币种与费用以工作空间账单为准。",
    plans: ["免费版", "入门版", "专业版", "企业版"], cadence: "美元 / 月", recommended: "最受欢迎", foundation: "不止一个方案，更是完整贯通的工作空间。",
    channel: "在工作空间内直接联系我们。",
    availability: "已经在使用？在工作空间中打开“帮助”菜单即可发起支持对话，我们的团队会在对话中直接回复，并全面了解你的配置。",
    routes: ["了解记录、表单与网站如何相互贯通。", "比较各个方案，找到最合适的选择。", "创建工作空间，让构想开始落地。"],
    quotas: [["最多 10 个页面", "最多 5 种自定义记录类型", "1 个会员席位"], ["最多 50 个页面", "最多 25 种自定义记录类型", "5 个会员席位", "14 天免费试用"], ["最多 500 个页面", "最多 200 种自定义记录类型", "25 个会员席位", "14 天免费试用"], ["页面数不限", "自定义记录类型不限", "会员席位不限", "14 天免费试用"]],
    faqAnswers: [
      "按标准方案说明，免费版每月 $0，最多 10 个页面、5 种自定义记录类型和 1 个会员席位。",
      "按标准方案说明，入门版、专业版和企业版均提供 14 天试用。可用试用优惠以工作空间中显示为准。",
      "页面指在页面构建器中创建的页面，包括表单页面，不含网站构建器中的营销页面。自定义记录类型指你定义的数据类型，而非单条记录。会员席位按工作空间中的注册账户计算，包括管理员。",
      "本页列出美元月度参考价格。可用方案和优惠、账单币种及适用的用量费用，以工作空间的账单设置为准。"
    ]
  }
}
const pathFor = slug => slug === "home" ? "/" : `/${slug}`
const marker = (page, role) => {
  const sections = page.locator("#site-main [data-site-section]")
  // Existing saved sections can retain opaque section IDs.
  // Identify these by their semantics rather than assuming integration renames IDs.
  if (role.endsWith("_hero")) return sections.filter({ has: page.locator("h1") })
  if (role.endsWith("_plans")) return sections.filter({ has: page.locator("article ul") })
  if (role.endsWith("_faq")) return sections.filter({ has: page.locator("details") })
  if (role.endsWith("_cta")) return sections.filter({ has: page.locator("h2") }).filter({ has: page.locator("a[href]") })
  if (role === "pricing_foundation") return sections.filter({ has: page.locator("h2") }).filter({ has: page.locator("article h3") }).filter({ hasNot: page.locator("article ul") })
  if (role === "contact_availability") return sections.filter({ has: page.locator("h2") }).filter({ has: page.locator("p") }).filter({ hasNot: page.locator("h1,h3,a[href],details") })
  throw new Error(`No structural section selector for ${role}`)
}

// Text ranges reveal cropping even when overflow-x:hidden masks document overflow.
// Closed native details, inert hidden menus and decorative SVG text are excluded.
async function expectReadableGeometry(page) {
  const result = await page.evaluate(() => {
    const violations = []
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT)
    while (walker.nextNode()) {
      const node = walker.currentNode, element = node.parentElement
      if (!node.textContent.trim() || element.closest("script,style,svg,[aria-hidden='true']")) continue
      if (!element.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true })) continue
      if (element.closest("details:not([open])") && !element.closest("summary")) continue
      if (element.closest(".sr-only") && !element.closest(":focus")) continue
      const range = document.createRange()
      range.selectNodeContents(node)
      for (const box of range.getClientRects()) {
        if (box.width < 1 || box.height < 1) continue
        if (box.left < -1 || box.right > innerWidth + 1) violations.push({ kind: "text outside viewport", text: node.textContent.trim() })
        for (let parent = element; parent && parent !== document.body; parent = parent.parentElement) {
          const css = getComputedStyle(parent), clip = parent.getBoundingClientRect()
          if ((["hidden", "clip"].includes(css.overflowX) && (box.left < clip.left - 2 || box.right > clip.right + 2)) ||
              (["hidden", "clip"].includes(css.overflowY) && (box.top < clip.top - 3 || box.bottom > clip.bottom + 3))) {
            violations.push({ kind: "clipped text", text: node.textContent.trim(), ancestor: parent.tagName })
            break
          }
        }
      }
    }
    // Localized illustration labels are visually meaningful even though their
    // SVG overlay is hidden from accessibility (the image already has alt text).
    for (const text of document.querySelectorAll("#site-main svg text")) {
      const box = text.getBoundingClientRect(), frame = text.closest("svg").getBoundingClientRect()
      if (box.width < 1 || box.height < 1) continue
      if (box.left < frame.left - 1 || box.right > frame.right + 1 || box.top < frame.top - 1 || box.bottom > frame.bottom + 1) {
        violations.push({ kind: "cropped illustration label", text: text.textContent.trim() })
      }
    }
    return { width: innerWidth, scrollWidth: document.documentElement.scrollWidth, violations }
  })
  expect.soft(result.scrollWidth, "document must fit its CSS viewport").toBeLessThanOrEqual(result.width + 1)
  expect.soft(result.violations, "visible text ranges must fit viewport and clipping ancestors").toEqual([])
}

async function settleImages(page) {
  // Trigger real lazy loading, preserving the existing loading policy.
  await page.evaluate(async () => {
    await document.fonts.ready
    for (let y = 0; y < document.documentElement.scrollHeight; y += 600) {
      scrollTo(0, y)
      await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))
    }
    await Promise.all([...document.images].map(image => image.decode().catch(() => {})))
    scrollTo(0, 0)
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))
  })
}

async function expectKeyboardFocus(locator) {
  await expect(locator).toBeFocused()
  const focus = await locator.evaluate(element => {
    const css = getComputedStyle(element)
    return { visible: element.matches(":focus-visible"), shadow: css.boxShadow, outline: css.outlineStyle, width: parseFloat(css.outlineWidth) }
  })
  expect(focus.visible).toBe(true)
  expect(focus.shadow !== "none" || (focus.outline !== "none" && focus.width > 0), "keyboard focus must have a visible indicator").toBe(true)
}

// Use browser-parsed colors, including Tailwind's OKLCH colors. Evaluate every
// text run against BOTH gradient stops (conservative worst-case), compositing
// badge/button surfaces separately. Never assume a transparent gradient is dark.
async function expectFeaturedContrast(card) {
  const metrics = await card.evaluate(card => {
    const canvas = document.createElement("canvas")
    canvas.width = canvas.height = 1
    const ctx = canvas.getContext("2d", { willReadFrequently: true })
    const rgba = color => {
      ctx.clearRect(0, 0, 1, 1)
      ctx.fillStyle = color
      ctx.fillRect(0, 0, 1, 1)
      return [...ctx.getImageData(0, 0, 1, 1).data].map((value, index) => index === 3 ? value / 255 : value)
    }
    const blend = (fg, bg) => [...fg.slice(0, 3).map((value, index) => value * fg[3] + bg[index] * (1 - fg[3])), 1]
    const luminance = color => color.slice(0, 3).map(value => {
      const scaled = value / 255
      return scaled <= 0.04045 ? scaled / 12.92 : ((scaled + 0.055) / 1.055) ** 2.4
    }).reduce((sum, value, index) => sum + value * [0.2126, 0.7152, 0.0722][index], 0)
    const css = getComputedStyle(card)
    const stops = [css.getPropertyValue("--tw-gradient-from").trim(), css.getPropertyValue("--tw-gradient-to").trim()]
    const validStops = css.backgroundImage !== "none" && stops.every(color => CSS.supports("color", color))
    const backgrounds = validStops ? stops.map(color => blend(rgba(color), [255, 255, 255, 1])) : [blend(rgba(css.backgroundColor), [255, 255, 255, 1])]
    const contrast = (fg, bg) => (Math.max(luminance(fg), luminance(bg)) + 0.05) / (Math.min(luminance(fg), luminance(bg)) + 0.05)
    const runs = []
    const walker = document.createTreeWalker(card, NodeFilter.SHOW_TEXT)
    while (walker.nextNode()) {
      const node = walker.currentNode, element = node.parentElement
      if (!node.textContent.trim() || element.closest("[aria-hidden='true']")) continue
      const surfaces = []
      for (let parent = element; parent && parent !== card; parent = parent.parentElement) surfaces.push(rgba(getComputedStyle(parent).backgroundColor))
      const ratios = backgrounds.map(background => {
        let bg = background
        for (const surface of [...surfaces].reverse()) bg = blend(surface, bg)
        return contrast(blend(rgba(getComputedStyle(element).color), bg), bg)
      })
      runs.push({ text: node.textContent.trim(), minimum: Math.min(...ratios) })
    }
    const checkmarks = [...card.querySelectorAll("li svg")].map(icon => ({ minimum: Math.min(...backgrounds.map(bg => contrast(rgba(getComputedStyle(icon).color), bg))) }))
    return { stops, dark: backgrounds.every(bg => luminance(bg) < 0.12), runs, checkmarks }
  })
  expect.soft(metrics.dark, `Starter must remain dark across its entire background: ${metrics.stops}`).toBe(true)
  for (const run of metrics.runs) expect.soft(run.minimum, `Starter contrast: ${run.text}`).toBeGreaterThanOrEqual(4.5)
  for (const icon of metrics.checkmarks) expect.soft(icon.minimum, "Starter checkmark contrast").toBeGreaterThanOrEqual(3)
}

async function checkPricing(page, locale, viewport) {
  const copy = COPY[locale], hero = marker(page, "pricing_hero"), plans = marker(page, "pricing_plans")
  await expect(hero.getByText(copy.reference, { exact: true })).toBeVisible()
  await expect(hero.locator("a,img")).toHaveCount(0)
  const cards = plans.locator("article")
  await expect(cards).toHaveCount(4)
  await expect(cards.locator("h3")).toHaveText(copy.plans)
  for (const [index, amount] of ["$0", "$29", "$99", "$499"].entries()) {
    const card = cards.nth(index)
    await expect(card.getByText(amount, { exact: true })).toBeVisible()
    await expect(card.getByText(copy.cadence, { exact: true })).toBeVisible()
    await expect(card.locator("ul li")).toHaveText(copy.quotas[index])
    await expect(card.getByRole("checkbox")).toHaveCount(0)
    await expect(card.locator("li svg")).toHaveCount(copy.quotas[index].length)
    for (const icon of await card.locator("li svg").all()) await expect(icon).toHaveAttribute("aria-hidden", "true")
    const link = card.getByRole("link")
    await expect(link).toHaveCount(1)
    const href = new URL(await link.getAttribute("href"), BASE)
    expect(href.pathname).toBe("/auth/sign_up")
    expect(href.searchParams.get("locale")).toBe(locale)
    expect((await link.boundingBox()).height).toBeGreaterThanOrEqual(44)
  }
  await expect(cards.nth(1).getByText(copy.recommended, { exact: true })).toBeVisible()
  await expectFeaturedContrast(cards.nth(1))
  const foundation = marker(page, "pricing_foundation")
  await expect(foundation).toHaveCount(1)
  await expect(foundation.getByRole("heading", { name: copy.foundation, exact: true })).toBeVisible()
  await expect(foundation.locator("h3")).toHaveCount(3)
  expect(await foundation.evaluate(element => ({
    followsPlans: element.previousElementSibling?.querySelectorAll("article ul").length === 4,
    precedesFAQ: element.nextElementSibling?.querySelectorAll("details").length === 4
  }))).toEqual({ followsPlans: true, precedesFAQ: true })
  // Measure the grid cells: the featured card's gradient frame is lifted on desktop.
  const boxes = await cards.evaluateAll(elements => elements.map(element => element.parentElement.getBoundingClientRect().toJSON()))
  if (viewport.width >= 1024) {
    const standard = boxes.filter((_, index) => index !== 1)
    for (const box of standard) {
      expect(Math.abs(box.y - standard[0].y)).toBeLessThanOrEqual(1)
      expect(Math.abs(box.height - standard[0].height)).toBeLessThanOrEqual(1)
    }
    expect(boxes[1].y).toBeLessThan(standard[0].y)
    expect(Math.abs(boxes[1].height - standard[0].height)).toBeLessThanOrEqual(1)
  } else if (viewport.width < 768) {
    for (let index = 1; index < boxes.length; index++) expect(boxes[index].y).toBeGreaterThanOrEqual(boxes[index - 1].bottom)
  }
  // Reference framing precedes prices and both are discoverable immediately.
  if ([390, 1440].includes(viewport.width)) {
    await expect(hero.getByText(copy.reference, { exact: true })).toBeInViewport({ ratio: 1 })
    await expect(cards.first().getByText("$0", { exact: true })).toBeInViewport({ ratio: 1 })
  }
  await expect(marker(page, "pricing_faq").locator("details")).toHaveCount(4)
  await expect(marker(page, "pricing_faq").locator("details > p")).toHaveText(copy.faqAnswers)
}

async function checkAbout(page, locale, viewport) {
  const hero = marker(page, "about_hero"), image = hero.locator("img"), heading = hero.locator("h1")
  await expect(image).toHaveCount(1)
  expect(new URL(await image.getAttribute("src"), BASE).pathname).toBe("/site-images/anysys/anysys-photo-about-team.webp")
  await expect(image).toHaveAttribute("loading", "eager")
  const actions = await hero.locator("a").evaluateAll(links => links.map(link => link.getAttribute("href")))
  expect(actions.map(href => new URL(href, BASE).pathname)).toEqual(["/auth/sign_up", pathFor("platform")])
  for (const href of actions) expect(new URL(href, BASE).searchParams.get("locale")).toBe(locale)
  // The saved order places Mission and Craft as the two editorial prose
  // sections. Distinguish these from the hero, principles cards and closing
  // action by their structure, retaining opaque IDs and edited headings.
  // Do not exclude images here: Craft is a photo-led story.
  const editorials = page.locator("#site-main [data-site-section]")
    .filter({ has: page.locator("h2") }).filter({ has: page.locator("p") })
    .filter({ hasNot: page.locator("h1,h3,a[href],details,article") })
  await expect(editorials).toHaveCount(2)
  const mission = editorials.first(), craft = editorials.last()
  await expect(mission).toHaveCount(1)
  await expect(craft).toHaveCount(1)
  await expect(craft.locator("h2")).toHaveCount(1)
  await expect(craft.locator("h2")).toBeVisible()
  await expect(craft.locator("h2")).toHaveText(/\S/)
  await expect(craft.locator("p")).toHaveCount(2)
  for (const paragraph of await craft.locator("p").all()) await expect(paragraph).toHaveText(/\S/)
  await expect(craft.locator("img")).toHaveCount(1)
  expect(new URL(await craft.locator("img").getAttribute("src"), BASE).pathname).toBe("/site-images/anysys/anysys-photo-craft.webp")
  await expect(mission.locator("p")).toHaveCount(2)
  const art = await image.boundingBox(), text = await heading.boundingBox()
  if (viewport.width >= 1024) {
    expect(art.x).toBeGreaterThanOrEqual(text.x + text.width)
    expect(art.y).toBeLessThan(text.y + text.height + 100)
    expect(art.y + art.height).toBeGreaterThan(text.y)
  } else {
    expect(art.y).toBeGreaterThan(text.y + text.height)
  }
  // Meaningful artwork keeps its native landscape ratio rather than cropping.
  const ratio = await image.evaluate(element => ({ natural: element.naturalWidth / element.naturalHeight, rendered: element.width / element.height }))
  expect(Math.abs(ratio.natural - ratio.rendered)).toBeLessThanOrEqual(0.03)
}

async function checkContact(page, locale, viewport, context) {
  const copy = COPY[locale], availability = marker(page, "contact_availability"), routes = marker(page, "contact_cta").getByRole("link")
  await expect(availability.getByRole("heading", { name: copy.channel, exact: true })).toBeVisible()
  const honestNote = availability.getByText(copy.availability, { exact: true })
  await expect(honestNote).toBeVisible()
  expect(await availability.evaluate(element => element.previousElementSibling?.querySelectorAll("h1").length === 1)).toBe(true)
  await expect(page.locator("#site-main form, #site-main input, #site-main textarea, #site-main a[href^='mailto:'], #site-main a[href^='tel:']")).toHaveCount(0)
  await expect(routes).toHaveCount(3)
  const expectedPaths = [pathFor("platform"), pathFor("pricing"), "/auth/sign_up"]
  for (const [index, path] of expectedPaths.entries()) {
    const card = routes.nth(index)
    await expect(card.locator("h3")).toHaveText(/\S/)
    await expect(card.locator("p")).toHaveText(copy.routes[index])
    await expect(card.locator("a,button")).toHaveCount(0)
    const href = new URL(await card.getAttribute("href"), BASE)
    expect(href.origin).toBe(new URL(BASE).origin)
    expect(href.pathname).toBe(path)
    expect(href.searchParams.get("locale")).toBe(locale)
    // Check actual existing destinations with GET. Signup may redirect under
    // SKIP_AUTH; stop at that redirect rather than visiting authenticated areas.
    if (viewport.width === 1440) {
      const response = await context.request.get(href.href, { maxRedirects: 0 })
      expect(response.status(), href.href).toBeLessThan(400)
      if (index < 2) {
        expect(response.status()).toBe(200)
        expect(await response.text()).toContain(`lang="${locale}"`)
        // Route titles come from the same localized published navigation.
        const nav = page.locator(`header nav a[href='${await card.getAttribute("href")}']`)
        await expect(card.locator("h3")).toHaveText(await nav.innerText())
      }
    }
  }
  const boxes = await routes.evaluateAll(elements => elements.map(element => element.getBoundingClientRect().toJSON()))
  if (viewport.width >= 1024) for (const box of boxes) expect(Math.abs(box.y - boxes[0].y)).toBeLessThanOrEqual(1)
  if (viewport.width < 768) for (let index = 1; index < boxes.length; index++) expect(boxes[index].y).toBeGreaterThanOrEqual(boxes[index - 1].bottom)
}

async function checkFAQ(page, slug) {
  const faq = marker(page, `${slug}_faq`), details = faq.locator("details"), summaries = details.locator(":scope > summary")
  await expect(details).toHaveCount(4)
  for (const item of await details.all()) await expect(item).not.toHaveAttribute("open")
  await summaries.first().focus()
  await summaries.first().press("Enter")
  await expectKeyboardFocus(summaries.first())
  await expect(details.first()).toHaveAttribute("open", "")
  await expect(details.first().locator("p")).toBeVisible()
  await summaries.nth(1).focus()
  await summaries.nth(1).press("Space")
  await expect(details.first()).toHaveAttribute("open", "")
  await expect(details.nth(1)).toHaveAttribute("open", "")
  await expect(details.nth(1).locator("p")).toBeVisible()
  await expectReadableGeometry(page)
  await summaries.nth(1).press("Space")
  await expect(details.nth(1)).not.toHaveAttribute("open")
  await expect(details.first()).toHaveAttribute("open", "")
  await summaries.first().press("Enter")
  await expect(details.first()).not.toHaveAttribute("open")
}

async function checkNavigation(page, slug, locale, viewport) {
  await page.evaluate(() => scrollTo(0, 0))
  await page.waitForFunction(() => window.Stimulus?.getControllerForElementAndIdentifier(document.querySelector("[data-controller='website-nav']"), "website-nav"))
  const trigger = page.locator("[data-website-nav-target='trigger']"), panel = page.locator("dialog#website-nav-panel")
  if (viewport.width < 1024) {
    await expect(trigger).toBeVisible()
    await trigger.focus()
    await trigger.press("Enter")
    await expect(panel).toBeVisible()
    expect(await panel.evaluate(element => element.matches(":modal"))).toBe(true)
    await expect(trigger).toHaveAttribute("aria-expanded", "true")
    const close = panel.locator("button").first()
    await expectKeyboardFocus(close)
    await expect(panel.locator("nav a")).toHaveCount(5)
    const hrefs = await panel.locator("nav a").evaluateAll(elements => elements.map(element => element.href))
    expect(hrefs.map(href => new URL(href).pathname)).toEqual(Object.keys(PAGES).map(pathFor))
    for (const href of hrefs) expect(new URL(href).searchParams.get("locale")).toBe(locale)
    await expectReadableGeometry(page)
    await page.keyboard.press("Escape")
    await expect(panel).toBeHidden()
    await expect(trigger).toHaveAttribute("aria-expanded", "false")
    await expectKeyboardFocus(trigger)
  } else {
    await expect(trigger).toBeHidden()
    await expect(page.locator("header nav")).toBeVisible()
    const hrefs = await page.locator("header nav a").evaluateAll(elements => elements.map(element => element.href))
    expect(hrefs.map(href => new URL(href).pathname)).toEqual(Object.keys(PAGES).map(pathFor))
    for (const href of hrefs) expect(new URL(href).searchParams.get("locale")).toBe(locale)
  }
  const switcher = page.locator("header details").filter({ has: page.locator("[role='menu']") })
  const summary = switcher.locator(":scope > summary"), menu = switcher.getByRole("menu")
  await summary.focus()
  await summary.press("Enter")
  await expectKeyboardFocus(summary)
  await expect(menu.getByRole("menuitem")).toHaveText(["English", "简体中文"])
  await expectReadableGeometry(page)
  const nextLocale = locale === "en" ? "zh-CN" : "en", destination = menu.locator(`a[lang='${nextLocale}']`)
  await summary.press("Tab")
  if (nextLocale === "zh-CN") await page.keyboard.press("Tab")
  await expect(destination).toBeFocused()
  const target = new URL(await destination.getAttribute("href"), page.url())
  expect(target.origin).toBe(new URL(BASE).origin)
  expect(target.pathname).toBe(pathFor(slug))
  expect(target.searchParams.get("locale")).toBe(nextLocale)
  const [response] = await Promise.all([
    // Turbo performs the same locale GET as fetch rather than a document
    // navigation. Match the exact chosen URL and GET, allowing either transport.
    page.waitForResponse(response => response.url() === target.href && response.request().method() === "GET" &&
      (response.request().isNavigationRequest() || response.request().resourceType() === "fetch")),
    destination.press("Enter")
  ])
  expect(response.request().method()).toBe("GET")
  expect(response.status()).toBe(200)
  const rendered = await page.evaluate(html => {
    const document = new DOMParser().parseFromString(html, "text/html")
    return { locale: document.documentElement.lang, h1Count: document.querySelectorAll("#site-main h1").length,
      heading: document.querySelector("#site-main h1")?.textContent }
  }, await response.text())
  expect(rendered.locale).toBe(nextLocale)
  expect(rendered.h1Count).toBe(1)
  expect(rendered.heading).toMatch(/\S/)
  await page.waitForURL(url => url.href === target.href)
  await expect(page.locator("html")).toHaveAttribute("lang", nextLocale)
  expect(new URL(page.url()).pathname).toBe(pathFor(slug))
  expect(new URL(page.url()).searchParams.get("locale")).toBe(nextLocale)
  await expect(page.locator("#site-main h1")).toHaveCount(1)
  await expect(page.locator("#site-main h1")).toBeVisible()
  await expect(page.locator("#site-main h1")).toHaveText(rendered.heading)
}

test.describe("customer 81721200 marketing polish — public GET-only browser acceptance", () => {
  test.skip(!BASE, "set APP_BASE_URL to the integrated existing server")
  for (const locale of Object.keys(COPY)) for (const viewport of VIEWPORTS) {
    test.describe(`${locale} / ${viewport.name}`, () => {
      // reducedMotion is a browser-context option, not a top-level test option.
      test.use({ viewport: { width: viewport.width, height: viewport.height }, deviceScaleFactor: viewport.deviceScaleFactor || 1, contextOptions: { reducedMotion: "reduce" }, serviceWorkers: "block" })
      for (const [slug, counts] of Object.entries(PAGES)) {
        test(`${slug}: content, geometry, artwork and keyboard routes`, async ({ page, context }, testInfo) => {
          test.setTimeout(90000)
          expect(PREFIX.startsWith("/tmp/opencode/marketing-polish-")).toBe(true)
          const writes = [], errors = []
          await context.route("**/*", route => {
            const request = route.request()
            if (["GET", "HEAD"].includes(request.method())) return route.continue()
            writes.push(`${request.method()} ${request.url()}`)
            return route.abort("blockedbyclient")
          })
          page.on("pageerror", error => errors.push(error.message))
          page.on("requestfailed", request => errors.push(`${request.failure()?.errorText} ${request.url()}`))
          page.on("response", response => { if (response.status() >= 400) errors.push(`HTTP ${response.status()} ${response.url()}`) })
          try {
            const response = await page.goto(`${BASE}${pathFor(slug)}?locale=${locale}`, { waitUntil: "load" })
            expect(response?.status()).toBe(200)
            expect(new URL(page.url()).pathname).toBe(pathFor(slug))
            await expect(page.locator("a[href^='/81721200/site']")).toHaveCount(0)
            await expect(page.locator("html")).toHaveAttribute("lang", locale)
            const main = page.locator("#site-main")
            await expect(page.getByRole("main")).toHaveCount(1)
            await expect(main).toHaveAttribute("tabindex", "-1")
            await expect(main.locator("h1")).toHaveCount(1)
            await expect(main.locator("h1")).toHaveText(/\S/)
            await expect(main.locator("h1")).toBeVisible()
            await expect(main.locator("[data-site-section]")).toHaveCount(counts.sections)
            await settleImages(page)
            await expect(main.locator("img")).toHaveCount(counts.images)
            for (const image of await main.locator("img").all()) {
              await expect(image).toBeVisible()
              await expect(image).toHaveAttribute("alt", /\S/)
              expect(await image.evaluate(element => element.complete && element.naturalWidth > 0 && element.naturalHeight > 0)).toBe(true)
              const ratios = await image.evaluate(element => {
                const box = element.getBoundingClientRect()
                return { native: element.naturalWidth / element.naturalHeight, rendered: box.width / box.height }
              })
              expect(Math.abs(ratios.native - ratios.rendered), "default meaningful artwork must keep its native ratio").toBeLessThanOrEqual(0.03)
            }
            await expectReadableGeometry(page)
            const timing = await page.evaluate(() => {
              const navigation = performance.getEntriesByType("navigation")[0]
              return { ttfbMs: navigation.responseStart - navigation.requestStart, domContentLoadedMs: navigation.domContentLoadedEventEnd, loadMs: navigation.loadEventEnd,
                fcpMs: performance.getEntriesByName("first-contentful-paint")[0]?.startTime ?? null,
                resources: performance.getEntriesByType("resource").length }
            })
            await testInfo.attach("local-browser-navigation-timing", { body: JSON.stringify({ slug, locale, viewport, timing, method: "Unthrottled existing local server; concurrent workers. Diagnostic, not production CWV." }, null, 2), contentType: "application/json" })
            if ([390, 1440].includes(viewport.width)) {
              for (const slice of ["top", "full"]) {
                const shot = `${PREFIX}-${slug}-${locale}-${viewport.name}-${slice}.png`
                writeFileSync(shot, await page.screenshot({ fullPage: slice === "full", animations: "disabled" }), { flag: "wx" })
                await testInfo.attach(`${slug}-${locale}-${viewport.name}-${slice}`, { path: shot, contentType: "image/png" })
              }
            }
            if (slug === "pricing") await checkPricing(page, locale, viewport)
            if (slug === "about") await checkAbout(page, locale, viewport)
            if (slug === "contact") await checkContact(page, locale, viewport, context)
            if (["home", "pricing"].includes(slug)) await checkFAQ(page, slug)
            await checkNavigation(page, slug, locale, viewport)
          } finally {
            expect.soft(writes, "no persistence requests may reach Rails").toEqual([])
            expect.soft(errors, "no failed resources or uncaught browser errors").toEqual([])
          }
        })
      }
    })
  }
})
