import { describe, it, expect, beforeEach } from "vitest"
import Controller from "controllers/flowchart_list_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const row = (name, description) =>
  `<tr data-flowchart-list-target="row" data-name="${name}" data-description="${description}"><td>${name}</td></tr>`

const html = `
  <div data-controller="flowchart-list">
    <input data-flowchart-list-target="searchInput" data-action="input->flowchart-list#search">
    <table><tbody data-flowchart-list-target="tableBody">
      ${row("Order Approval", "handles order signoff")}
      ${row("Invoice Sync", "syncs invoices nightly")}
      ${row("User Onboarding", "welcome new users")}
    </tbody></table>
    <div data-flowchart-list-target="emptyState" class="hidden">No results</div>
  </div>`

const rows = (el) => [...el.querySelectorAll("[data-flowchart-list-target='row']")]
const visibleNames = (el) => rows(el).filter(r => !r.classList.contains("hidden")).map(r => r.dataset.name)
const emptyState = (el) => el.querySelector("[data-flowchart-list-target='emptyState']")
const input = (el) => el.querySelector("[data-flowchart-list-target='searchInput']")

const search = (el, term) => {
  const i = input(el)
  i.value = term
  i.dispatchEvent(new Event("input", { bubbles: true }))
}

describe("flowchart-list controller", () => {
  let element, application
  beforeEach(async () => {
    ;({ application, element } = await mountController("flowchart-list", Controller, html))
  })

  it("shows all rows for an empty query", () => {
    search(element, "")
    expect(visibleNames(element).length).toBe(3)
    expect(emptyState(element).classList.contains("hidden")).toBe(true)
  })

  it("substring-matches on the name", () => {
    search(element, "invoice")
    expect(visibleNames(element)).toEqual(["Invoice Sync"])
  })

  it("matches on the description too", () => {
    search(element, "nightly")
    expect(visibleNames(element)).toEqual(["Invoice Sync"])
  })

  it("fuzzy-matches non-contiguous characters", () => {
    // 'ordr' is not a substring but its chars appear in order in 'order approval'
    search(element, "ordr")
    expect(visibleNames(element)).toContain("Order Approval")
  })

  it("shows the empty state when nothing matches a non-empty query", () => {
    search(element, "zzzznope")
    expect(visibleNames(element).length).toBe(0)
    expect(emptyState(element).classList.contains("hidden")).toBe(false)
  })

  it("clearSearch restores all rows and hides the empty state", () => {
    search(element, "zzzznope")
    expect(emptyState(element).classList.contains("hidden")).toBe(false)
    controllerFor(application, element, "flowchart-list").clearSearch()
    expect(input(element).value).toBe("")
    expect(visibleNames(element).length).toBe(3)
    expect(emptyState(element).classList.contains("hidden")).toBe(true)
  })

  it("connect() caches an empty row list when there are no row targets", async () => {
    const noRowsHtml = `
      <div data-controller="flowchart-list">
        <input data-flowchart-list-target="searchInput" data-action="input->flowchart-list#search">
        <table><tbody data-flowchart-list-target="tableBody"></tbody></table>
        <div data-flowchart-list-target="emptyState" class="hidden">No results</div>
      </div>`
    const { application: app, element: el } = await mountController("flowchart-list", Controller, noRowsHtml)
    const ctrl = controllerFor(app, el, "flowchart-list")
    expect(ctrl.cachedRows).toEqual([])
  })

  it("clearSearch is a no-op when there is no search-input target", async () => {
    const noInputHtml = `
      <div data-controller="flowchart-list">
        <table><tbody data-flowchart-list-target="tableBody">
          ${row("Order Approval", "handles order signoff")}
        </tbody></table>
        <div data-flowchart-list-target="emptyState" class="hidden">No results</div>
      </div>`
    const { application: app, element: el } = await mountController("flowchart-list", Controller, noInputHtml)
    const ctrl = controllerFor(app, el, "flowchart-list")
    expect(() => ctrl.clearSearch()).not.toThrow()
  })

  it("matches rows missing data-name/data-description via the empty-string fallback", async () => {
    const bareRowHtml = `
      <div data-controller="flowchart-list">
        <input data-flowchart-list-target="searchInput" data-action="input->flowchart-list#search">
        <table><tbody data-flowchart-list-target="tableBody">
          <tr data-flowchart-list-target="row"><td>bare</td></tr>
        </tbody></table>
        <div data-flowchart-list-target="emptyState" class="hidden">No results</div>
      </div>`
    const { element: el } = await mountController("flowchart-list", Controller, bareRowHtml)
    // A non-empty query against a row with neither dataset attribute falls through
    // to the `""` fallback on both name and description and simply doesn't match.
    search(el, "anything")
    expect(rows(el)[0].classList.contains("hidden")).toBe(true)
  })

  it("toggleEmptyState is a no-op when there is no empty-state target", async () => {
    const noEmptyStateHtml = `
      <div data-controller="flowchart-list">
        <input data-flowchart-list-target="searchInput" data-action="input->flowchart-list#search">
        <table><tbody data-flowchart-list-target="tableBody">
          ${row("Order Approval", "handles order signoff")}
        </tbody></table>
      </div>`
    const { element: el } = await mountController("flowchart-list", Controller, noEmptyStateHtml)
    expect(() => search(el, "zzzznope")).not.toThrow()
  })
})
