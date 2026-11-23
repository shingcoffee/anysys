import { describe, it, expect, beforeEach } from "vitest"
import Controller from "controllers/module_settings_catalog_controller"
import { mountController, click, controllerFor, tick } from "../support/stimulus.js"

const row = ({ name, key, description, active, required }) =>
  `<li data-module-settings-catalog-target="row" data-name="${name}" data-key="${key}" data-description="${description}" data-active="${active}" data-required="${required}">${name}</li>`

const catalogHtml = `
<div data-controller="module-settings-catalog" data-module-settings-catalog-filter-value="all">
  <input type="search" data-module-settings-catalog-target="search" data-action="input->module-settings-catalog#search">
  <button type="button" data-module-settings-catalog-target="filter" data-filter="all" data-action="click->module-settings-catalog#setFilter" aria-pressed="true" class="bg-surface text-text-primary shadow-sm ring-1 ring-border-subtle">All</button>
  <button type="button" data-module-settings-catalog-target="filter" data-filter="active" data-action="click->module-settings-catalog#setFilter" aria-pressed="false" class="text-text-muted">Active</button>
  <button type="button" data-module-settings-catalog-target="filter" data-filter="inactive" data-action="click->module-settings-catalog#setFilter" aria-pressed="false" class="text-text-muted">Inactive</button>
  <button type="button" data-module-settings-catalog-target="filter" data-filter="required" data-action="click->module-settings-catalog#setFilter" aria-pressed="false" class="text-text-muted">Required</button>
  <div data-module-settings-catalog-target="directory">
    ${row({ name: "SMS", key: "sms", description: "Send texts", active: "true", required: "false" })}
    ${row({ name: "Captcha", key: "captcha", description: "Bot check", active: "false", required: "true" })}
  </div>
  <div data-module-settings-catalog-target="emptyFilter" class="hidden">empty</div>
</div>
`

const visibleNames = (el) =>
  [...el.querySelectorAll("[data-module-settings-catalog-target='row']")]
    .filter((r) => !r.classList.contains("hidden"))
    .map((r) => r.textContent)

const pill = (el, id) => el.querySelector(`[data-filter="${id}"]`)

describe("module-settings-catalog controller", () => {
  let application, element, controller

  beforeEach(async () => {
    ;({ application, element } = await mountController("module-settings-catalog", Controller, catalogHtml))
    controller = controllerFor(application, element, "module-settings-catalog")
  })

  it("shows every row on connect with the All filter selected", () => {
    expect(visibleNames(element)).toEqual(["SMS", "Captcha"])
    expect(pill(element, "all").getAttribute("aria-pressed")).toBe("true")
    expect(element.querySelector("[data-module-settings-catalog-target='emptyFilter']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-module-settings-catalog-target='directory']").classList.contains("hidden")).toBe(false)
  })

  it("filters by a case-insensitive name/key/description substring", () => {
    const input = element.querySelector("input")
    input.value = "SMS"
    controller.search()
    expect(visibleNames(element)).toEqual(["SMS"])

    input.value = "captcha"
    controller.search()
    expect(visibleNames(element)).toEqual(["Captcha"])

    input.value = "bot"
    controller.search()
    expect(visibleNames(element)).toEqual(["Captcha"])
  })

  it("filters by active, inactive, and required pills", async () => {
    await click(pill(element, "active"))
    expect(visibleNames(element)).toEqual(["SMS"])
    expect(pill(element, "active").getAttribute("aria-pressed")).toBe("true")
    expect(pill(element, "all").getAttribute("aria-pressed")).toBe("false")

    await click(pill(element, "inactive"))
    expect(visibleNames(element)).toEqual(["Captcha"])

    await click(pill(element, "required"))
    expect(visibleNames(element)).toEqual(["Captcha"])

    await click(pill(element, "all"))
    expect(visibleNames(element)).toEqual(["SMS", "Captcha"])
  })

  it("ANDs search with the current filter", async () => {
    await click(pill(element, "required"))
    const input = element.querySelector("input")
    input.value = "sms"
    controller.search()
    expect(visibleNames(element)).toEqual([])
    expect(element.querySelector("[data-module-settings-catalog-target='emptyFilter']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-module-settings-catalog-target='directory']").classList.contains("hidden")).toBe(true)
  })

  it("treats a missing data-filter as All", () => {
    controller.setFilter({ currentTarget: { dataset: {} } })
    expect(controller.filterValue).toBe("all")
    expect(visibleNames(element)).toEqual(["SMS", "Captcha"])
  })

  it("treats an unrecognized filter as All", async () => {
    const input = element.querySelector("input")
    input.value = "captcha"
    controller.search()
    expect(visibleNames(element)).toEqual(["Captcha"])

    controller.filterValue = "bogus"
    await tick()
    expect(visibleNames(element)).toEqual(["Captcha"])
  })
})

describe("module-settings-catalog controller without optional targets", () => {
  it("applies filters when search, emptyFilter, directory, and filter pills are absent", async () => {
    const html =
      `<div data-controller="module-settings-catalog">` +
      row({ name: "SMS", key: "sms", description: "Send", active: "true", required: "false" }) +
      `</div>`
    const { application, element } = await mountController("module-settings-catalog", Controller, html)
    const controller = controllerFor(application, element, "module-settings-catalog")
    expect(visibleNames(element)).toEqual(["SMS"])
    controller.filterValue = "inactive"
    await tick()
    expect(visibleNames(element)).toEqual([])
    controller.filterValue = "all"
    await tick()
    expect(visibleNames(element)).toEqual(["SMS"])
  })
})
