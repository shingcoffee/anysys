import { expect } from "@playwright/test"
import { mkdirSync, readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"

export const BASE = process.env.APP_BASE_URL
export const ROOT = `/${process.env.SETTINGS_CUSTOMER_ID || "81721200"}/admin/settings`
export const MAIN = "#main-content"
// The settings header precedes the content slot; embedded website previews may
// contain their own document headings inside that slot.
export const HEADING = `${MAIN} h1:not([data-settings-page] h1)`
export const DESKTOP_SETTINGS_SIDEBAR = "[data-shell-workspace] > [data-controller='sidebar-collapsible'] aside"
export const SHOTS = process.env.SETTINGS_BROWSER_ARTIFACTS || fileURLToPath(new URL("../../tmp/playwright-customer-settings/", import.meta.url))
export const DESTINATIONS = [
  ["/member", "Member portal", "会员中心"],
  ["/modules/authentication/sign_up", "Member registration", "会员注册"],
  ["/modules/authentication/forget_password", "Password reset", "密码重置"],
  ["/modules/authentication", "Account security", "账户安全"],
  ["/modules/authentication/roles", "Roles & permissions", "角色与权限"],
  ["/modules/authentication/user_role_assignments", "User access", "用户访问权限"],
  ["/modules/captcha", "Public page protection", "公开页面防护"],
  ["/modules/website", "Website", "网站"],
  ["/modules/ai_assistant", "AI assistant", "AI 助手"],
  ["/modules/emails/daily_cap", "Email limit", "邮件限额"],
  ["/modules/emails/template_tokens", "Email personalization", "邮件个性化"],
  ["/modules/sms/daily_cap", "Text message limit", "短信限额"],
  ["/modules/payments/merchant_accounts", "Payment providers", "收款服务商"],
  ["/billing/subscription", "Plan", "套餐"],
  ["/billing/payment_methods", "Payment methods", "付款方式"],
  ["/billing/invoices", "Invoices", "账单明细"]
]

// Install at context level: popups, fetches, Turbo and ordinary form submissions
// are all guarded. Even unexpected mutation attempts can never reach Rails.
export async function protect(context) {
  const guard = { writes: [], unexpected: [], fixtures: new Map(), handlers: new Map() }
  await context.route("**/*", async (route) => {
    const request = route.request()
    const url = new URL(request.url())
    if (url.origin !== new URL(BASE).origin) return route.abort("blockedbyclient")
    if (!["GET", "HEAD"].includes(request.method())) {
      const entry = { method: request.method(), path: url.pathname, body: request.postData(), headers: request.headers() }
      guard.writes.push(entry)
      const handler = guard.handlers.get(url.pathname)
      if (handler) return route.fulfill(await handler(entry))
      guard.unexpected.push(entry)
      return route.abort("blockedbyclient")
    }
    const fixture = guard.fixtures.get(`${url.pathname}?locale=${url.searchParams.get("locale") || guard.locale || "en"}`)
    if (fixture) return route.fulfill({ contentType: "text/html; charset=utf-8", body: fixture.html })
    // Fixture IDs are from a rolled-back test database; never resolve them live.
    if (/^\/\d+\/admin\/settings/.test(url.pathname) && !url.pathname.startsWith(ROOT)) {
      guard.unexpected.push({ method: request.method(), path: url.pathname })
      return route.abort("blockedbyclient")
    }
    return route.continue()
  })
  return guard
}

export async function visit(page, suffix, locale = "en") {
  const path = suffix.startsWith(ROOT) ? suffix : ROOT + suffix
  const url = new URL(path, BASE)
  url.searchParams.set("locale", locale)
  const response = await page.goto(url.href, { waitUntil: "domcontentloaded" })
  expect(response.status(), path).toBe(200)
  await expect(page.locator("html")).toHaveAttribute("lang", locale)
  await page.evaluate(() => document.fonts.ready)
  return path
}

export function registerFixture(guard, name, locale) {
  const directory = process.env.EXPORT_CUSTOMER_SETTINGS_FIXTURES || fileURLToPath(new URL("../../tmp/playwright-customer-settings/fixtures/", import.meta.url))
  const data = JSON.parse(readFileSync(`${directory}/${name}-${locale}.json`, "utf8"))
  expect(data.source, "Re-export current Rails responses with helpers/bootstrap.js export").toBe("spec/system/admin/settings/customer_settings_browser_fixtures_spec.rb")
  expect(data.schema_version).toBe(1)
  expect(data.locale).toBe(locale)
  guard.locale = locale
  guard.fixtures.set(`${data.path}?locale=${locale}`, data)
  return data
}

export async function fixture(page, guard, name, locale) {
  const data = registerFixture(guard, name, locale)
  const response = await page.goto(`${BASE}${data.path}?locale=${locale}`, { waitUntil: "domcontentloaded" })
  expect(response.status()).toBe(200)
  await expect(page.locator("html")).toHaveAttribute("lang", locale)
  expect(await page.evaluate(() => document.characterSet)).toBe("UTF-8")
  // Rails disables forgery protection in the test environment, so exported
  // pages lack this meta tag. Supply a dummy token for intercepted fetches only.
  await page.evaluate(() => {
    if (!document.querySelector("meta[name=csrf-token]")) {
      const token = document.createElement("meta")
      token.name = "csrf-token"
      token.content = "isolated-test-response"
      document.head.append(token)
    }
  })
  await page.evaluate(() => document.fonts.ready)
  return data
}

export async function connected(page, selector, identifier) {
  await page.waitForFunction(({ selector, identifier }) => window.Stimulus?.getControllerForElementAndIdentifier(
    document.querySelector(selector), identifier
  ), { selector, identifier })
}

export function activeDestination(path) {
  const suffix = path.split("?")[0].replace(/^\/\d+\/admin\/settings/, "")
  const aliases = {
    "/modules/email": "/modules/emails/daily_cap", "/modules/emails": "/modules/emails/daily_cap",
    "/modules/sms": "/modules/sms/daily_cap", "/modules/ai_assistants": "/modules/ai_assistant",
    "/modules/authentications": "/modules/authentication"
  }
  return aliases[suffix] || DESTINATIONS.map(([p]) => p).sort((a, b) => b.length - a.length)
    .find(p => suffix === p || (p !== "/modules/authentication" && suffix.startsWith(p + "/"))) || ""
}

export async function shell(page, path, locale) {
  const root = path.match(/^\/\d+\/admin\/settings/)[0]
  const main = page.locator(MAIN)
  await expect.soft(main, path).toHaveCount(1)
  expect.soft(await main.evaluate(node => node.tagName), path).toBe("MAIN")
  await expect.soft(page.locator("[data-settings-page]"), path).toHaveCount(1)
  await expect.soft(page.locator(HEADING), path).toHaveCount(1)
  const breadcrumbs = main.getByRole("navigation", {
    name: locale === "en" ? "Breadcrumb" : "面包屑导航", exact: true
  })
  if (path === root) {
    await expect.soft(breadcrumbs, path).toContainText(locale === "en" ? "Settings" : "设置")
  } else {
    await expect.soft(breadcrumbs.locator(`a[href='${root}']`).first(), path).toHaveText(locale === "en" ? "Settings" : "设置")
  }
  for (const scope of [DESKTOP_SETTINGS_SIDEBAR, "#settings-navigation-dialog"]) {
    const active = page.locator(`${scope} a[aria-current='page']`)
    expect.soft(await active.evaluateAll(nodes => nodes.map(a => a.getAttribute("href"))), `${path}: ${scope} active destination`)
      .toEqual([root + activeDestination(path)])
  }
  const text = await main.innerText()
  expect.soft(text, path).not.toMatch(/Translation missing|translation missing|\{"kind"\s*:|Surface key:|admin\/assistants|entity_assoc_/)
}

export async function fits(page, label) {
  const failures = await page.evaluate(() => {
    const main = document.querySelector("#main-content")
    const bounds = main.getBoundingClientRect()
    const failures = []
    for (const node of [document.documentElement, main]) {
      if (node.scrollWidth > node.clientWidth + 2) failures.push(`${node.tagName}: ${node.scrollWidth} > ${node.clientWidth}`)
    }
    for (const node of main.querySelectorAll("input:not([type=hidden]),select,textarea,button,summary")) {
      const rect = node.getBoundingClientRect()
      const style = getComputedStyle(node)
      if (!node.checkVisibility() || rect.width <= 2 || rect.height <= 2 || style.clipPath === "inset(50%)") continue
      if (rect.left < bounds.left - 2 || rect.right > bounds.right + 2) failures.push(`${node.id || node.name || node.textContent.trim()}: ${Math.round(rect.left)}..${Math.round(rect.right)}`)
    }
    return failures
  })
  expect.soft(failures, `${label}: document/main and form controls fit horizontally`).toEqual([])
}

export async function screenshot(page, name) {
  mkdirSync(SHOTS, { recursive: true })
  // The shell scrolls internally: capture the viewport, and selected lower
  // sections separately rather than producing an apparently full-page image.
  await page.screenshot({ path: `${SHOTS}/${name}.png`, animations: "disabled" })
}

export async function payload(page, form) {
  return form.evaluate(el => [...new FormData(el)].filter(([key]) => !["authenticity_token", "commit", "utf8"].includes(key)))
}

export async function interceptedSubmit(page, guard, form, button) {
  const action = new URL(await form.getAttribute("action"), BASE).pathname
  guard.handlers.set(action, () => ({ status: 204, body: "" }))
  const request = page.waitForRequest(r => new URL(r.url()).pathname === action && r.method() !== "GET")
  await button.click()
  await request
  await expect.poll(() => guard.writes.filter(w => w.path === action).length).toBeGreaterThan(0)
  return guard.writes.filter(w => w.path === action).at(-1)
}

export async function handleDialog(page, action, decision = "dismiss") {
  const result = page.waitForEvent("dialog").then(async dialog => {
    const details = { type: dialog.type(), message: dialog.message() }
    await dialog[decision]()
    return details
  })
  await action()
  return result
}
