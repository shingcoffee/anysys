import { describe, it, expect, beforeEach } from "vitest"
import Controller from "controllers/page_settings_controller"
import { mountController, controllerFor, click } from "../support/stimulus.js"

const html = `
  <div data-controller="page-settings">
    <nav>
      <button data-page-settings-target="tab" data-section="general" data-action="click->page-settings#select" data-role="tab-general">General</button>
      <button data-page-settings-target="tab" data-section="seo" data-action="click->page-settings#select" data-role="tab-seo">SEO</button>
    </nav>
    <div data-page-settings-target="panel" data-section="general" data-role="panel-general">g</div>
    <div data-page-settings-target="panel" data-section="seo" class="hidden" data-role="panel-seo">s</div>
  </div>`

const q = (el, role) => el.querySelector(`[data-role='${role}']`)

describe("page-settings controller", () => {
  let element, controller
  beforeEach(async () => {
    const m = await mountController("page-settings", Controller, html)
    element = m.element
    controller = controllerFor(m.application, element, "page-settings")
  })

  it("activates the first visible section on connect", () => {
    expect(q(element, "panel-general").classList.contains("hidden")).toBe(false)
    expect(q(element, "panel-seo").classList.contains("hidden")).toBe(true)
    expect(q(element, "tab-general").classList.contains("bg-indigo-50")).toBe(true)
  })

  it("select switches the visible panel and active tab styling", () => {
    click(q(element, "tab-seo"))
    expect(q(element, "panel-seo").classList.contains("hidden")).toBe(false)
    expect(q(element, "panel-general").classList.contains("hidden")).toBe(true)
    expect(q(element, "tab-seo").classList.contains("text-indigo-700")).toBe(true)
    expect(q(element, "tab-general").classList.contains("text-gray-600")).toBe(true)
  })

  it("show is a no-op for a missing key", () => {
    expect(() => controller.show(undefined)).not.toThrow()
    // still on general
    expect(q(element, "panel-general").classList.contains("hidden")).toBe(false)
  })

  it("falls back to the first tab's section when no panel is already visible", async () => {
    const allHiddenHtml = `
      <div data-controller="page-settings">
        <nav>
          <button data-page-settings-target="tab" data-section="general" data-action="click->page-settings#select" data-role="tab-general">General</button>
          <button data-page-settings-target="tab" data-section="seo" data-action="click->page-settings#select" data-role="tab-seo">SEO</button>
        </nav>
        <div data-page-settings-target="panel" data-section="general" class="hidden" data-role="panel-general">g</div>
        <div data-page-settings-target="panel" data-section="seo" class="hidden" data-role="panel-seo">s</div>
      </div>`
    const { element: el } = await mountController("page-settings", Controller, allHiddenHtml)
    expect(q(el, "panel-general").classList.contains("hidden")).toBe(false)
    expect(q(el, "panel-seo").classList.contains("hidden")).toBe(true)
  })
})
