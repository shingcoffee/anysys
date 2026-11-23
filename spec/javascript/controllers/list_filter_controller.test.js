import { describe, it, expect, beforeEach, vi } from "vitest"
import Controller from "controllers/list_filter_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const item = ({ text, searchText, name }) => {
  const attrs = ['data-list-filter-target="item"']
  if (searchText !== undefined) attrs.push(`data-search-text="${searchText}"`)
  if (name !== undefined) attrs.push(`data-name="${name}"`)
  return `<li ${attrs.join(" ")}>${text}</li>`
}

const catalogHtml = `
<div data-controller="list-filter">
  <input type="search" data-list-filter-target="search" data-action="input->list-filter#search">
  <div data-list-filter-target="directory">
    <section data-list-filter-target="group" data-group="org">
      ${item({ text: "Member", searchText: "Member surfaces" })}
    </section>
    <section data-list-filter-target="group" data-group="billing">
      ${item({ text: "Invoices", searchText: "Invoices billing" })}
    </section>
    <section data-list-filter-target="group" data-group="empty"></section>
  </div>
  <div data-list-filter-target="empty" class="hidden">empty</div>
</div>
`

const visibleText = (el) =>
  [...el.querySelectorAll("[data-list-filter-target='item']")]
    .filter((row) => !row.classList.contains("hidden"))
    .map((row) => row.textContent)

const groupHidden = (el, name) =>
  el.querySelector(`[data-group="${name}"]`).classList.contains("hidden")

describe("list-filter controller", () => {
  let application, element, controller

  beforeEach(async () => {
    ;({ application, element } = await mountController("list-filter", Controller, catalogHtml))
    controller = controllerFor(application, element, "list-filter")
  })

  it("shows every item on connect", () => {
    expect(visibleText(element)).toEqual(["Member", "Invoices"])
    expect(element.querySelector("[data-list-filter-target='empty']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-list-filter-target='directory']").classList.contains("hidden")).toBe(false)
    expect(groupHidden(element, "org")).toBe(false)
    expect(groupHidden(element, "empty")).toBe(false)
  })

  it("filters by a case-insensitive search-text substring and hides empty groups", () => {
    const input = element.querySelector("input")
    input.value = "invoice"
    controller.search()
    expect(visibleText(element)).toEqual(["Invoices"])
    expect(groupHidden(element, "org")).toBe(true)
    expect(groupHidden(element, "billing")).toBe(false)
    expect(element.querySelector("[data-list-filter-target='empty']").classList.contains("hidden")).toBe(true)
  })

  it("shows the empty state and hides the directory when nothing matches", () => {
    const input = element.querySelector("input")
    input.value = "nope"
    controller.search()
    expect(visibleText(element)).toEqual([])
    expect(groupHidden(element, "org")).toBe(true)
    expect(groupHidden(element, "billing")).toBe(true)
    expect(element.querySelector("[data-list-filter-target='empty']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-list-filter-target='directory']").classList.contains("hidden")).toBe(true)
  })

  it("restores every item when the query is cleared", () => {
    const input = element.querySelector("input")
    input.value = "member"
    controller.search()
    input.value = "  "
    controller.search()
    expect(visibleText(element)).toEqual(["Member", "Invoices"])
  })

  it("prevents default when search receives an event", () => {
    const preventDefault = vi.fn()
    controller.search({ preventDefault })
    expect(preventDefault).toHaveBeenCalledTimes(1)
  })
})

describe("list-filter haystack fallbacks", () => {
  it("matches data-name when search-text is absent", async () => {
    const html =
      `<div data-controller="list-filter">` +
      `<input data-list-filter-target="search">` +
      item({ text: "Visible", name: "Alpha" }) +
      item({ text: "Other", name: "Beta" }) +
      `</div>`
    const { application, element } = await mountController("list-filter", Controller, html)
    const controller = controllerFor(application, element, "list-filter")
    element.querySelector("input").value = "alp"
    controller.search()
    expect(visibleText(element)).toEqual(["Visible"])
  })

  it("matches text content when search-text and name are absent", async () => {
    const html =
      `<div data-controller="list-filter">` +
      `<input data-list-filter-target="search">` +
      item({ text: "Gamma" }) +
      item({ text: "Delta" }) +
      `</div>`
    const { application, element } = await mountController("list-filter", Controller, html)
    const controller = controllerFor(application, element, "list-filter")
    element.querySelector("input").value = "delt"
    controller.search()
    expect(visibleText(element)).toEqual(["Delta"])
  })

  it("treats an empty haystack as a non-match when a query is present", async () => {
    const html =
      `<div data-controller="list-filter">` +
      `<input data-list-filter-target="search">` +
      `<li data-list-filter-target="item" data-search-text="" data-name=""></li>` +
      `</div>`
    const { application, element } = await mountController("list-filter", Controller, html)
    const controller = controllerFor(application, element, "list-filter")
    element.querySelector("input").value = "x"
    controller.search()
    expect(visibleText(element)).toEqual([])
  })
})

describe("list-filter details targets", () => {
  const detailsHtml = `
<div data-controller="list-filter">
  <input type="search" data-list-filter-target="search" data-action="input->list-filter#search">
  <ul>
    <li data-list-filter-target="group">
      <details data-list-filter-target="details">
        <summary>Email</summary>
        <ul>
          <li data-list-filter-target="item" data-search-text="Templates email content">Templates</li>
          <li data-list-filter-target="item" data-search-text="Audience lists">Audience</li>
        </ul>
      </details>
    </li>
    <li data-list-filter-target="group">
      <details open data-list-filter-target="details">
        <summary>SMS</summary>
        <ul>
          <li data-list-filter-target="item" data-search-text="Messages sms">Messages</li>
        </ul>
      </details>
    </li>
  </ul>
</div>
`
  const detailsAt = (el, i) => el.querySelectorAll("[data-list-filter-target='details']")[i]

  it("opens closed details while a query is active and restores them when cleared", async () => {
    const { application, element } = await mountController("list-filter", Controller, detailsHtml)
    const controller = controllerFor(application, element, "list-filter")
    expect(detailsAt(element, 0).open).toBe(false)
    expect(detailsAt(element, 1).open).toBe(true)

    const input = element.querySelector("input")
    input.value = "template"
    controller.search()
    expect(detailsAt(element, 0).open).toBe(true)
    expect(detailsAt(element, 1).open).toBe(true)

    input.value = ""
    controller.search()
    expect(detailsAt(element, 0).open).toBe(false)
    expect(detailsAt(element, 1).open).toBe(true)
  })

  it("leaves user-opened details open after the query clears", async () => {
    const { application, element } = await mountController("list-filter", Controller, detailsHtml)
    const controller = controllerFor(application, element, "list-filter")

    detailsAt(element, 0).open = true // user opened it before filtering
    const input = element.querySelector("input")
    input.value = "template"
    controller.search()
    input.value = ""
    controller.search()
    expect(detailsAt(element, 0).open).toBe(true)
  })

  it("hides non-matching details items via the item targets", async () => {
    const { application, element } = await mountController("list-filter", Controller, detailsHtml)
    const controller = controllerFor(application, element, "list-filter")

    const input = element.querySelector("input")
    input.value = "audience"
    controller.search()
    expect(visibleText(element)).toEqual(["Audience"])
  })
})

describe("list-filter controller without optional targets", () => {
  it("applies search when search, empty, directory, and group targets are absent", async () => {
    const html =
      `<div data-controller="list-filter">` +
      item({ text: "Solo", searchText: "Solo item" }) +
      `</div>`
    const { application, element } = await mountController("list-filter", Controller, html)
    const controller = controllerFor(application, element, "list-filter")
    expect(visibleText(element)).toEqual(["Solo"])
    controller.search()
    expect(visibleText(element)).toEqual(["Solo"])
  })
})
