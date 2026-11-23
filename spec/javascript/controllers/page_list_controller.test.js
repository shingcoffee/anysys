import { describe, it, expect, beforeEach } from "vitest"
import Controller from "controllers/page_list_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = `
  <div data-controller="page-list">
    <input data-page-list-target="searchInput" data-action="input->page-list#search" data-role="search" />
    <button data-page-list-target="clearButton" class="hidden" data-role="clear" data-action="click->page-list#clearSearch">x</button>
    <table>
      <tbody data-page-list-target="tableBody" data-role="tbody">
        <tr data-page-list-target="row" data-name="contact form" data-description="reach us" data-role="row1"><td>a</td></tr>
        <tr data-page-list-target="row" data-name="pricing" data-description="plans" data-role="row2"><td>b</td></tr>
      </tbody>
    </table>
    <div data-page-list-target="emptyState" class="hidden" data-role="empty">no results</div>
  </div>`

const q = (el, role) => el.querySelector(`[data-role='${role}']`)

describe("page-list controller", () => {
  let element, controller
  beforeEach(async () => {
    const m = await mountController("page-list", Controller, html)
    element = m.element
    controller = controllerFor(m.application, element, "page-list")
  })

  it("search filters rows by name/description and toggles the clear button", () => {
    const input = q(element, "search")
    input.value = "pricing"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    expect(q(element, "row1").style.display).toBe("none")
    expect(q(element, "row2").style.display).toBe("")
    expect(q(element, "clear").classList.contains("hidden")).toBe(false)
  })

  it("matches on description text too", () => {
    const input = q(element, "search")
    input.value = "reach"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    expect(q(element, "row1").style.display).toBe("")
    expect(q(element, "row2").style.display).toBe("none")
  })

  it("shows the empty state and hides the tbody when nothing matches", () => {
    const input = q(element, "search")
    input.value = "zzz"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    expect(q(element, "empty").classList.contains("hidden")).toBe(false)
    expect(q(element, "tbody").classList.contains("hidden")).toBe(true)
  })

  it("treats rows missing name/description data attributes as empty strings", async () => {
    const bareHtml = `
      <div data-controller="page-list">
        <input data-page-list-target="searchInput" data-action="input->page-list#search" data-role="search" />
        <table>
          <tbody data-page-list-target="tableBody">
            <tr data-page-list-target="row" data-role="row-bare"><td>a</td></tr>
          </tbody>
        </table>
      </div>`
    const m = await mountController("page-list", Controller, bareHtml)
    const input = q(m.element, "search")
    input.value = "anything"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    expect(q(m.element, "row-bare").style.display).toBe("none")
  })

  it("clearSearch empties the field and restores all rows", () => {
    const input = q(element, "search")
    input.value = "zzz"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    controller.clearSearch()
    expect(input.value).toBe("")
    expect(q(element, "row1").style.display).toBe("")
    expect(q(element, "row2").style.display).toBe("")
    expect(q(element, "clear").classList.contains("hidden")).toBe(true)
  })
})
