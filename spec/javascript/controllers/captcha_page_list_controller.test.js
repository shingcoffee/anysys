import { describe, it, expect } from "vitest"
import Controller from "controllers/captcha_page_list_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const row = ({ name, path }) =>
  `<li data-captcha-page-list-target="row" data-name="${name}" data-path="${path}">${name}</li>`

const group = (label, rows) =>
  `<div data-captcha-page-list-target="group"><h3>${label}</h3><ul>${rows}</ul></div>`

const listHtml = `
<div data-controller="captcha-page-list">
  <input type="search" data-captcha-page-list-target="search" data-action="input->captcha-page-list#search">
  <div data-captcha-page-list-target="directory">
    ${group("Authentication", row({ name: "Sign in", path: "/auth/sign_in" }) + row({ name: "Sign up", path: "/auth/sign_up" }))}
    ${group("Payments", row({ name: "Checkout", path: "/:customer_id/payments/checkout" }))}
  </div>
  <div data-captcha-page-list-target="emptyFilter" class="hidden">empty</div>
</div>
`

const visibleNames = (el) =>
  [...el.querySelectorAll("[data-captcha-page-list-target='row']")]
    .filter((r) => !r.classList.contains("hidden"))
    .map((r) => r.textContent)

const hiddenGroups = (el) =>
  [...el.querySelectorAll("[data-captcha-page-list-target='group']")]
    .filter((g) => g.classList.contains("hidden"))
    .map((g) => g.querySelector("h3").textContent)

describe("captcha-page-list controller", () => {
  it("shows every row on connect", async () => {
    const { element } = await mountController("captcha-page-list", Controller, listHtml)
    expect(visibleNames(element)).toEqual(["Sign in", "Sign up", "Checkout"])
    expect(element.querySelector("[data-captcha-page-list-target='emptyFilter']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-captcha-page-list-target='directory']").classList.contains("hidden")).toBe(false)
  })

  it("filters by a case-insensitive name substring", async () => {
    const { application, element } = await mountController("captcha-page-list", Controller, listHtml)
    const controller = controllerFor(application, element, "captcha-page-list")
    element.querySelector("input").value = "sign in"
    controller.search()
    expect(visibleNames(element)).toEqual(["Sign in"])
    expect(hiddenGroups(element)).toEqual(["Payments"])
  })

  it("filters by path and shows the empty state when nothing matches", async () => {
    const { application, element } = await mountController("captcha-page-list", Controller, listHtml)
    const controller = controllerFor(application, element, "captcha-page-list")
    const input = element.querySelector("input")
    input.value = "/auth/sign_up"
    controller.search()
    expect(visibleNames(element)).toEqual(["Sign up"])

    input.value = "no-such-url"
    controller.search()
    expect(visibleNames(element)).toEqual([])
    expect(hiddenGroups(element)).toEqual(["Authentication", "Payments"])
    expect(element.querySelector("[data-captcha-page-list-target='emptyFilter']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-captcha-page-list-target='directory']").classList.contains("hidden")).toBe(true)
  })

  it("restores every row when the query is cleared", async () => {
    const { application, element } = await mountController("captcha-page-list", Controller, listHtml)
    const controller = controllerFor(application, element, "captcha-page-list")
    const input = element.querySelector("input")
    input.value = "checkout"
    controller.search()
    expect(visibleNames(element)).toEqual(["Checkout"])
    input.value = "  "
    controller.search()
    expect(visibleNames(element)).toEqual(["Sign in", "Sign up", "Checkout"])
    expect(hiddenGroups(element)).toEqual([])
  })
})

describe("captcha-page-list controller without optional targets", () => {
  it("applies when search, emptyFilter, directory, and groups are absent", async () => {
    const html =
      `<div data-controller="captcha-page-list">` +
      row({ name: "Sign in", path: "/auth/sign_in" }) +
      `</div>`
    const { application, element } = await mountController("captcha-page-list", Controller, html)
    const controller = controllerFor(application, element, "captcha-page-list")
    expect(visibleNames(element)).toEqual(["Sign in"])
    expect(controller.searchQuery()).toBe("")
    controller.apply()
    expect(visibleNames(element)).toEqual(["Sign in"])
  })

  it("keeps an empty group visible when it has no rows", async () => {
    const html = `
      <div data-controller="captcha-page-list">
        <div data-captcha-page-list-target="group"><h3>Empty</h3><ul></ul></div>
      </div>
    `
    const { element } = await mountController("captcha-page-list", Controller, html)
    expect(element.querySelector("[data-captcha-page-list-target='group']").classList.contains("hidden")).toBe(false)
  })

  it("applies when there are no row targets", async () => {
    const html = `<div data-controller="captcha-page-list"></div>`
    const { application, element } = await mountController("captcha-page-list", Controller, html)
    const controller = controllerFor(application, element, "captcha-page-list")
    controller.apply()
    expect(element.querySelectorAll("[data-captcha-page-list-target='row']").length).toBe(0)
  })
})
