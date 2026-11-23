import { test, expect } from "@playwright/test"
import { mkdirSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { randomUUID } from "node:crypto"
import { runRails } from "./helpers/rails_runner.js"

const BASE = process.env.APP_BASE_URL
const ROOT = "/81721200/admin/maintenance/platform/module_settings"
const SHOT_DIR = process.env.MODULE_SETTINGS_BROWSER_ARTIFACTS || fileURLToPath(new URL("../../tmp/playwright-module-settings", import.meta.url))
const READY_TIMEOUT = 15_000
const RUN_ID = randomUUID().replaceAll("-", "")
const SMS_KEY = `task4_e2e_template_${RUN_ID}`
const WEBHOOK_ID = `task4-e2e-webhook-${RUN_ID}`
const SEEDED_TEST = "catalog and module workspaces keep responsive geometry and active navigation"

const NESTED = [
  `${ROOT}/ai_assistant/settings`,
  `${ROOT}/captcha/settings`,
  `${ROOT}/captcha/pages`,
  `${ROOT}/email/credentials`,
  `${ROOT}/email/credentials/new`,
  `${ROOT}/sms/credentials`,
  `${ROOT}/sms/credentials/new`,
  `${ROOT}/sms/templates`,
  `${ROOT}/sms/templates/new`,
  `${ROOT}/payment/gateways`,
  `${ROOT}/payment/webhook_events`
]

const SHOTS = [
  { path: ROOT, name: "catalog" },
  { path: `${ROOT}/ai_assistant/settings`, name: "ai-assistant-settings" },
  { path: `${ROOT}/captcha/settings`, name: "captcha-settings" },
  { path: `${ROOT}/email/credentials`, name: "email-credentials" },
  { path: `${ROOT}/email/credentials/new`, name: "email-credential-new" },
  { path: `${ROOT}/sms/credentials/new`, name: "sms-credential-new" },
  { path: `${ROOT}/sms/templates/new`, name: "sms-template-new" },
  { path: `${ROOT}/payment/gateways`, name: "payment-gateways" },
  { path: `${ROOT}/payment/webhook_events`, name: "payment-webhooks" }
]

const expectNoPageOverflow = async (page) => {
  const geometry = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth
  }))
  expect(geometry.scrollWidth).toBeLessThanOrEqual(geometry.clientWidth)
}

const waitForController = async (mount, identifier) => {
  await expect.poll(() => mount.evaluate((element, name) =>
    !!window.Stimulus?.getControllerForElementAndIdentifier(element, name), identifier
  ), { timeout: READY_TIMEOUT, message: `${identifier} connected on the current DOM` }).toBe(true)
}

const waitForAppReady = async (page) => {
  await page.waitForLoadState("domcontentloaded")
  // The importmap's module graph and eager Stimulus imports finish asynchronously.
  // Await real startup and the current shell mount before a click or geometry read.
  await page.evaluate(async () => {
    await import("application")
    await document.fonts.ready
  })
  await waitForController(page.locator("[data-controller~='sidebar-collapsible']"), "sidebar-collapsible")
}

const visitModuleSettings = async (page, path) => {
  const target = new URL(path, BASE)
  const response = await page.goto(target.href, { waitUntil: "domcontentloaded" })
  expect(response?.status(), `module settings page ${path}`).toBe(200)
  expect(new URL(page.url()).pathname).toBe(target.pathname)
  await waitForAppReady(page)
  await expect(page.locator("h1")).toBeVisible()
  return response
}

const openDeveloper = async (page, href) => {
  const target = new URL(`${href}/developer`, BASE)
  const tab = page.locator("[data-section-nav-tab='developer']")
  await waitForAppReady(page)
  await expect(tab).toBeVisible()
  await expect(tab).toHaveAttribute("href", target.pathname)

  const timing = { clickedAt: new Date().toISOString() }
  // Register the exact GET before clicking: Turbo can return before its new DOM
  // is rendered, so the five-second assertion must not time the whole navigation.
  const [response] = await Promise.all([
    page.waitForResponse((result) => {
      const url = new URL(result.url())
      return result.request().method() === "GET" && result.status() === 200 &&
        url.origin === target.origin && url.pathname === target.pathname
    }, { timeout: READY_TIMEOUT }).then((result) => {
      timing.responseAt = new Date().toISOString()
      return result
    }),
    page.waitForURL((url) => url.origin === target.origin && url.pathname === target.pathname,
      { waitUntil: "domcontentloaded", timeout: READY_TIMEOUT }),
    tab.click()
  ])
  await page.waitForLoadState("domcontentloaded")
  timing.domContentLoadedAt = new Date().toISOString()
  // This is a scoped render-readiness budget for the headed Developer context,
  // not a longer default for the layout, filtering, or geometry assertions.
  const shell = page.locator("[data-module-settings-shell='true']")
  await expect(shell.locator("h1")).toBeVisible()
  await expect(shell.locator("[data-section-nav-tab='developer'][aria-current='page']")).toBeVisible({ timeout: READY_TIMEOUT })
  await expect(shell.locator("[data-module-settings-pane='developer'][data-developer-reference='true']")).toBeVisible({ timeout: READY_TIMEOUT })
  timing.developerVisibleAt = new Date().toISOString()
  await waitForAppReady(page)
  timing.appReadyAt = new Date().toISOString()

  const markup = await response.text()
  return {
    path: target.pathname, method: response.request().method(), status: response.status(),
    contentType: response.headers()["content-type"],
    developerMarkup: /data-module-settings-pane="developer"/.test(markup) && /data-developer-reference="true"/.test(markup),
    ...timing
  }
}

const seedFixtures = () => {
  runRails(`
    Sms::Template.find_or_create_by!(key: "${SMS_KEY}") do |template|
      template.status = "active"
      template.variables = ["code"]
      template.provider_template_codes = { "aliyun" => "SMS_TASK4" }
    end
    Payments::WebhookEvent.find_or_create_by!(provider: "stripe", psp_event_id: "${WEBHOOK_ID}") do |event|
      event.event_type = "payment_intent.succeeded"
      event.signing_merchant_id = "acct_task4"
      event.status = "failed"
    end
  `)
}

const cleanupFixtures = () => {
  runRails(`
    Sms::Template.where(key: "${SMS_KEY}").delete_all
    Payments::WebhookEvent.where(provider: "stripe", psp_event_id: "${WEBHOOK_ID}").delete_all
  `)
}

const assertFixturesRemoved = () => {
  const output = runRails(`
    sms = Sms::Template.where(key: "${SMS_KEY}").count
    webhook = Payments::WebhookEvent.where(provider: "stripe", psp_event_id: "${WEBHOOK_ID}").count
    abort "task4 fixtures remain: sms=#{sms} webhook=#{webhook}" unless sms.zero? && webhook.zero?
    puts "MODULE_SETTINGS_CLEANUP=" + { database: expected, sms_key: "${SMS_KEY}", webhook_id: "${WEBHOOK_ID}", sms_templates: sms, webhook_events: webhook }.to_json
  `)
  process.stdout.write(output)
}

const expectOrderedProviderStages = async (page) => {
  const stages = await page.locator("[data-provider-workspace-section]").evaluateAll((nodes) =>
    nodes.map((node) => node.dataset.providerWorkspaceSection)
  )
  const expected = ["assignment", "provider", "health", "credentials", "advanced-options"]
  const indexes = expected.map((stage) => stages.indexOf(stage)).filter((index) => index >= 0)
  expect(indexes).toEqual([...indexes].sort((a, b) => a - b))
  expect(stages).toContain("assignment")
  expect(stages).toContain("credentials")
}

const expectProviderPage = async (page, path, { form = false } = {}) => {
  const response = await visitModuleSettings(page, path)
  expect(response?.ok(), `provider page ${path}`).toBeTruthy()
  await expect(page.locator("[data-module-settings-shell='true']")).toBeVisible()
  await expect(page.locator("[data-section-nav-tab='providers'][aria-current='page']")).toBeVisible()
  await expect(page.locator("[data-provider-workspace='true']")).toBeVisible()
  await expectOrderedProviderStages(page)
  await expectNoPageOverflow(page)

  if (form) {
    const providerForm = page.locator("[data-module-settings-shell='true'] main form.w-full").first()
    await expect(providerForm).toBeVisible()
    const formBox = await providerForm.boundingBox()
    const shellBox = await page.locator("[data-module-settings-shell='true'] main").boundingBox()
    expect(formBox.width).toBeGreaterThanOrEqual(shellBox.width - 2)
    await expect(page.locator("[data-module-settings-form-actions]")).toBeVisible()
  }
}

test.describe("platform module settings layout", () => {
  test.describe.configure({ mode: "serial" })
  test.skip(!BASE, "set APP_BASE_URL to run app-backed e2e (see spec/e2e/README.md)")

  test.beforeEach(({}, testInfo) => {
    if (testInfo.title !== SEEDED_TEST) return

    cleanupFixtures()
    seedFixtures()
  })

  test.afterEach(({}, testInfo) => {
    if (testInfo.title !== SEEDED_TEST) return

    try {
      cleanupFixtures()
    } finally {
      assertFixturesRemoved()
    }
  })

  test.afterAll(() => {
    try {
      cleanupFixtures()
    } finally {
      assertFixturesRemoved()
    }
  })

  test("catalog and module workspaces keep responsive geometry and active navigation", async ({ page }, testInfo) => {
    test.setTimeout(180_000)
    await page.setViewportSize({ width: 1280, height: 900 })
    mkdirSync(SHOT_DIR, { recursive: true })

    const index = await visitModuleSettings(page, ROOT)
    expect(index?.ok()).toBeTruthy()
    await expect(page.locator("h1")).toContainText(/Module Settings|模块设置/)
    await expect(page.locator("[data-controller='module-settings-catalog']")).toBeVisible()
    await expect(page.locator("[data-module-card]")).not.toHaveCount(0)
    await expect(page.locator("[data-controller='tabs']")).toHaveCount(0)
    await expect(page.locator("[data-module-settings-nav]")).toHaveCount(0)
    await expectNoPageOverflow(page)

    const moduleLinks = await page.locator("[data-module-settings-catalog-target='row']").evaluateAll((rows) =>
      Object.fromEntries(rows.map((row) => [row.dataset.key, row.querySelector("a")?.getAttribute("href")]).filter(([, href]) => href))
    )
    const hrefs = Object.values(moduleLinks)
    expect(hrefs.length).toBeGreaterThan(0)

    const developerNavigation = []
    for (const href of hrefs) {
      const response = await visitModuleSettings(page, href)
      expect(response?.ok(), `landing ${href}`).toBeTruthy()
      await expect(page.locator("[data-controller='tabs']")).toHaveCount(0)
      await expect(page.locator("[data-module-settings-shell='true']")).toBeVisible()
      await expectNoPageOverflow(page)
      await expect(page.locator("[data-module-settings-pane='overview']")).toBeVisible()
      await expect(page.locator("[data-module-settings-section='availability']")).toBeVisible()
      await expect(page.locator("[data-module-settings-section='details']")).toBeVisible()
      await expect(page.locator("[data-developer-reference]")).toHaveCount(0)
      await expect(page.locator("[data-module-settings-nav]")).toBeVisible()
      await expect(page.locator("[data-section-nav-tab='overview'][aria-current='page']")).toBeVisible()
      await expect(page.locator("[data-section-nav-tab='developer']")).toBeVisible()
      developerNavigation.push(await openDeveloper(page, href))
      await expect(page.locator("[data-module-settings-pane='developer'][data-developer-reference='true']")).toBeVisible()
      await expect(page.locator("[data-module-settings-section='availability']")).toHaveCount(0)
      await expect(page.locator("[data-section-nav-tab='developer'][aria-current='page']")).toBeVisible()
      await expectNoPageOverflow(page)
      const key = href.split("/").pop()
      await page.screenshot({ path: `${SHOT_DIR}/landing-${key}.png` })
    }
    await testInfo.attach("developer-navigation-readiness", {
      body: JSON.stringify(developerNavigation, null, 2), contentType: "application/json"
    })

    await page.setViewportSize({ width: 390, height: 844 })
    await visitModuleSettings(page, ROOT)
    const mobileCard = page.locator("[data-module-card]").first()
    await expect(mobileCard).toBeVisible()
    const mobileCardBox = await mobileCard.boundingBox()
    expect(mobileCardBox).not.toBeNull()
    expect(mobileCardBox.width).toBeGreaterThan(300)
    expect(mobileCardBox.x).toBeGreaterThanOrEqual(0)
    expect(mobileCardBox.x + mobileCardBox.width).toBeLessThanOrEqual(390)

    await visitModuleSettings(page, hrefs[0])
    await expect(page.locator("[data-module-settings-shell='true']")).toBeVisible()
    await expect(page.locator("[data-module-settings-nav]")).toBeVisible()
    await expect(page.locator("[data-section-nav-tab='overview'][aria-current='page']")).toBeVisible()
    await expectNoPageOverflow(page)

    const mobileRows = page.locator("[data-module-settings-section='availability'] [data-module-settings-setting-row]")
    await expect(mobileRows).toHaveCount(2)
    for (const row of await mobileRows.all()) {
      await expect(row).toHaveCSS("flex-direction", "column")
      const rowBox = await row.boundingBox()
      expect(rowBox.x).toBeGreaterThanOrEqual(0)
      expect(rowBox.x + rowBox.width).toBeLessThanOrEqual(390)
    }

    if (moduleLinks.authentication) {
      await visitModuleSettings(page, `${moduleLinks.authentication}/configuration`)
      await expect(page.locator("[data-module-settings-pane='configuration']")).toBeVisible()
      await expect(page.locator("[data-section-nav-tab='configuration'][aria-current='page']")).toBeVisible()
      await expectNoPageOverflow(page)
    }

    if (moduleLinks.payment) {
      await visitModuleSettings(page, `${ROOT}/payment/gateways`)
      const nav = page.locator("[data-module-settings-nav] > div")
      await expect(page.locator("[data-section-nav-tab='providers'][aria-current='page']")).toBeVisible()
      await expect(page.locator("[data-payment-gateway-list='true']")).toBeVisible()
      await expect(page.locator("[data-module-settings-pane='overview']")).toHaveCount(0)
      await expect(page.locator("[data-module-settings-section='availability']")).toHaveCount(0)
      await expect(page.locator("[data-module-settings-section='next-actions']")).toHaveCount(0)
      const navGeometry = await nav.evaluate((element) => ({
        clientWidth: element.clientWidth,
        scrollWidth: element.scrollWidth,
        overflowX: getComputedStyle(element).overflowX
      }))
      expect(navGeometry.overflowX).toBe("auto")
      expect(navGeometry.scrollWidth).toBeGreaterThanOrEqual(navGeometry.clientWidth)
      await expectNoPageOverflow(page)

      await visitModuleSettings(page, `${ROOT}/payment/webhook_events`)
      await expect(page.locator("[data-section-nav-tab='operations'][aria-current='page']")).toBeVisible()
      await expect(page.locator("[data-module-settings-pane='overview']")).toHaveCount(0)
      await expect(page.locator("[data-module-settings-pane='operations']")).toHaveCount(0)
    }

    if (moduleLinks.captcha) {
      await visitModuleSettings(page, `${ROOT}/captcha/pages`)
      await expect(page.locator("[data-section-nav-tab='resources'][aria-current='page']")).toBeVisible()
      // The resources pane renders two independent lists: protected URLs and skipped URLs.
      await expect(page.locator("[data-controller='captcha-page-list']")).toHaveCount(2)
      await expect(page.locator("[data-controller='captcha-page-list']").first()).toBeVisible()
      await expect(page.locator("[data-module-settings-pane='overview']")).toHaveCount(0)
      await expect(page.locator("[data-module-settings-section='availability']")).toHaveCount(0)
      await expect(page.locator("[data-module-settings-section='next-actions']")).toHaveCount(0)
      await expectNoPageOverflow(page)
    }

    await page.setViewportSize({ width: 1280, height: 900 })
    await visitModuleSettings(page, `${hrefs[0]}/developer`)
    await expect(page.locator("[data-developer-reference]")).toBeVisible()
    for (const scroller of await page.locator("[data-developer-reference] .overflow-x-auto").all()) {
      const scrollerBox = await scroller.boundingBox()
      expect(scrollerBox.x).toBeGreaterThanOrEqual(0)
      expect(scrollerBox.x + scrollerBox.width).toBeLessThanOrEqual(1280)
    }
    await expectNoPageOverflow(page)

    for (const path of NESTED) {
      const response = await visitModuleSettings(page, path)
      expect(response?.ok(), `nested ${path}`).toBeTruthy()
      await expect(page.locator("h1")).toBeVisible()
      await expect(page.locator("[data-controller='tabs']")).toHaveCount(0)
      await expect(page.locator("[data-module-settings-nav]")).toBeVisible()
    }

    for (const path of [`${ROOT}/sms/templates`, `${ROOT}/payment/webhook_events`]) {
      await visitModuleSettings(page, path)
      await expect(page.locator("[data-module-settings-shell='true']")).toBeVisible()
      await expect(
        page.locator("[data-responsive-collection='true'], [data-module-settings-empty-section='true']")
      ).toBeVisible()
      const table = page.locator("[data-responsive-collection='true']")
      if (await table.count()) {
        await expect(table).toHaveAttribute("role", "table")
        await expect(table.locator("[role='columnheader']")).not.toHaveCount(0)
        await expect(table.locator("[data-responsive-collection-record][role='row']").first()).toBeVisible()
        await expect(table.locator("[data-responsive-collection-record][role='row']").first().locator(":scope > [role='cell']")).not.toHaveCount(0)
      }
      await expect(page.locator(path.includes("/sms/")
        ? "[data-section-nav-tab='resources'][aria-current='page']"
        : "[data-section-nav-tab='operations'][aria-current='page']"
      )).toBeVisible()
      await expectNoPageOverflow(page)
    }

    await page.setViewportSize({ width: 768, height: 1024 })
    for (const path of [`${ROOT}/sms/templates`, `${ROOT}/payment/webhook_events`]) {
      await visitModuleSettings(page, path)
      const collection = page.locator("[data-responsive-collection='true']")
      if (await collection.count()) {
        await expect(page.locator("[data-responsive-collection-record]").first()).toBeVisible()
        await expect(page.locator("[data-responsive-collection-record]").first().locator("a, button").first()).toBeVisible()
      } else {
        await expect(page.locator("[data-module-settings-empty-section='true']")).toBeVisible()
      }
      await expectNoPageOverflow(page)
    }

    await page.setViewportSize({ width: 1280, height: 900 })
    await visitModuleSettings(page, `${ROOT}/sms/templates?q=task4&sort=key&dir=asc`)
    await expect(page.locator("[role='columnheader'][aria-sort='ascending'] a[data-sms-template-sort='key']")).toBeVisible()
    await expect(page.locator("[role='columnheader'][aria-sort='none'] a[data-sms-template-sort='status']")).toBeVisible()

    await page.setViewportSize({ width: 390, height: 844 })
    await visitModuleSettings(page, `${ROOT}/sms/templates?q=task4&sort=key&dir=asc`)
    const mobileSort = page.locator("[data-responsive-collection-mobile-sort='true']")
    await expect(mobileSort).toBeVisible()
    await expect(mobileSort).toContainText(/Sorted by Key, ascending|当前按键名升序排列/)
    await expectNoPageOverflow(page)

    await page.setViewportSize({ width: 390, height: 844 })
    for (const path of [`${ROOT}/sms/templates`, `${ROOT}/payment/webhook_events`]) {
      await visitModuleSettings(page, path)
      const collection = page.locator("[data-responsive-collection='true']")
      if (await collection.count()) {
        await expect(page.locator("[data-responsive-collection-record]").first()).toBeVisible()
        await expect(page.locator("[data-responsive-collection-mobile-label]").first()).toBeVisible()
        await expect(page.locator("[data-responsive-collection-desktop-header]")).toBeHidden()
      } else {
        await expect(page.locator("[data-module-settings-empty-section='true']")).toBeVisible()
      }
      await expectNoPageOverflow(page)
    }

    const providerShows = [
      `${ROOT}/ai_assistant/settings`,
      `${ROOT}/captcha/settings`,
      `${ROOT}/email/credentials`,
      `${ROOT}/sms/credentials`
    ]
    for (const path of providerShows) {
      await expectProviderPage(page, path)
    }

    const providerForms = [
      `${ROOT}/ai_assistant/settings/edit?section=vendor`,
      `${ROOT}/captcha/settings/edit?section=vendor`,
      `${ROOT}/email/credentials/new`,
      `${ROOT}/sms/credentials/new`
    ]
    for (const path of providerForms) {
      await expectProviderPage(page, path, { form: true })
    }

    await page.setViewportSize({ width: 390, height: 844 })
    await expectProviderPage(page, `${ROOT}/email/credentials/new`, { form: true })
    const mobileActions = page.locator("[data-module-settings-form-actions] a, [data-module-settings-form-actions] button")
    for (const action of await mobileActions.all()) {
      const actionBox = await action.boundingBox()
      const groupBox = await page.locator("[data-module-settings-form-actions]").boundingBox()
      expect(actionBox.width).toBeGreaterThan(groupBox.width * 0.8)
    }

    await page.setViewportSize({ width: 1280, height: 900 })
    await expectProviderPage(page, `${ROOT}/email/credentials/new`, { form: true })
    const desktopGroupBox = await page.locator("[data-module-settings-form-actions]").boundingBox()
    for (const action of await page.locator("[data-module-settings-form-actions] a, [data-module-settings-form-actions] button").all()) {
      const actionBox = await action.boundingBox()
      expect(actionBox.width).toBeLessThan(desktopGroupBox.width * 0.5)
    }

    for (const shot of SHOTS) {
      await visitModuleSettings(page, shot.path)
      await page.screenshot({ path: `${SHOT_DIR}/${shot.name}.png` })
    }
  })

  test("leaves no scoped SMS or webhook fixtures after the layout test", () => {
    assertFixturesRemoved()
  })

  test("catalog and captcha resource filtering work from the keyboard", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 900 })

    const catalogResponse = await visitModuleSettings(page, ROOT)
    expect(catalogResponse?.ok()).toBeTruthy()

    const catalog = page.locator("[data-controller='module-settings-catalog']")
    await waitForController(catalog, "module-settings-catalog")
    const catalogSearch = catalog.locator("[data-module-settings-catalog-target='search']")
    const catalogRows = catalog.locator("[data-module-settings-catalog-target='row']")
    const catalogDirectory = catalog.locator("[data-module-settings-catalog-target='directory']")
    const catalogEmpty = catalog.locator("[data-module-settings-catalog-target='emptyFilter']")
    const firstCatalogKey = await catalogRows.first().getAttribute("data-key")
    const captchaHref = await catalogRows.filter({ has: page.locator("a") }).evaluateAll((rows) =>
      rows.find((row) => row.dataset.key === "captcha")?.querySelector("a")?.getAttribute("href")
    )
    const initialCatalogCount = await catalogRows.count()

    expect(firstCatalogKey).toBeTruthy()
    expect(captchaHref).toBeTruthy()
    expect(initialCatalogCount).toBeGreaterThan(1)

    await catalogSearch.focus()
    await page.keyboard.type(firstCatalogKey)
    await expect(catalog.locator("[data-module-settings-catalog-target='row']:visible")).toHaveCount(1)

    await catalogSearch.fill("task-5-no-such-module")
    await expect(catalogEmpty).toBeVisible()
    await expect(catalogDirectory).toBeHidden()

    await catalogSearch.fill("")
    const inactiveFilter = catalog.locator("[data-module-settings-catalog-target='filter'][data-filter='inactive']")
    await inactiveFilter.focus()
    await page.keyboard.press("Enter")
    await expect(inactiveFilter).toHaveAttribute("aria-pressed", "true")
    await expect(catalog.locator("[data-module-settings-catalog-target='filter'][data-filter='all']")).toHaveAttribute(
      "aria-pressed",
      "false"
    )
    await expectNoPageOverflow(page)

    await page.setViewportSize({ width: 390, height: 844 })
    const captchaResponse = await visitModuleSettings(page, `${ROOT}/captcha/pages`)
    expect(captchaResponse?.ok()).toBeTruthy()

    const captchaList = page.locator("[data-controller='captcha-page-list']").filter({
      has: page.locator("[data-captcha-page-list-target='row']")
    }).first()
    await expect(captchaList).toBeVisible()
    await waitForController(captchaList, "captcha-page-list")

    const captchaSearch = captchaList.locator("[data-captcha-page-list-target='search']")
    const captchaRows = captchaList.locator("[data-captcha-page-list-target='row']")
    const captchaDirectory = captchaList.locator("[data-captcha-page-list-target='directory']")
    const captchaEmpty = captchaList.locator("[data-captcha-page-list-target='emptyFilter']")
    const firstCaptchaPath = await captchaRows.first().getAttribute("data-path")

    expect(firstCaptchaPath).toBeTruthy()

    await captchaSearch.focus()
    await page.keyboard.type(firstCaptchaPath)
    await expect(captchaList.locator("[data-captcha-page-list-target='row']:visible")).not.toHaveCount(0)

    await captchaSearch.fill("task-5-no-such-resource")
    await expect(captchaEmpty).toBeVisible()
    await expect(captchaDirectory).toBeHidden()

    await captchaSearch.fill("")
    await expect(captchaDirectory).toBeVisible()
    await expect(captchaEmpty).toBeHidden()
    await expectNoPageOverflow(page)
  })
})
