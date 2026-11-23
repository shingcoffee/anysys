import { describe, it, expect, vi, afterEach } from "vitest"
import Controller from "controllers/template_workspace_layout_controller"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

const html = () => `
  <div data-controller="template-workspace-layout" data-template-workspace-layout-current-value="split">
    <div class="flex">
      <button data-template-workspace-layout-target="btnSplit" data-action="click->template-workspace-layout#switchToSplit">Split</button>
      <button data-template-workspace-layout-target="btnCompose" data-action="click->template-workspace-layout#switchToCompose">Compose</button>
      <button data-template-workspace-layout-target="btnPreview" data-action="click->template-workspace-layout#switchToPreview">Preview</button>
    </div>
    <div data-template-workspace-layout-target="container">
      <div data-template-workspace-layout-target="composer">Composer</div>
      <div data-template-workspace-layout-target="preview">Preview</div>
    </div>
  </div>
`

describe("template-workspace-layout controller", () => {
  it("defaults to split view and updates elements", async () => {
    const { application, element } = await mountController("template-workspace-layout", Controller, html())
    const ctrl = controllerFor(application, element, "template-workspace-layout")

    const composer = element.querySelector("[data-template-workspace-layout-target='composer']")
    const preview = element.querySelector("[data-template-workspace-layout-target='preview']")

    expect(composer.classList.contains("hidden")).toBe(false)
    expect(preview.classList.contains("hidden")).toBe(false)
  })

  it("toggles compose focus on click", async () => {
    const { application, element } = await mountController("template-workspace-layout", Controller, html())
    const btnCompose = element.querySelector("[data-template-workspace-layout-target='btnCompose']")

    btnCompose.click()
    await tick()

    const composer = element.querySelector("[data-template-workspace-layout-target='composer']")
    const preview = element.querySelector("[data-template-workspace-layout-target='preview']")

    expect(composer.classList.contains("hidden")).toBe(false)
    expect(preview.classList.contains("hidden")).toBe(true)
  })

  it("toggles preview focus on click", async () => {
    const { application, element } = await mountController("template-workspace-layout", Controller, html())
    const btnPreview = element.querySelector("[data-template-workspace-layout-target='btnPreview']")

    btnPreview.click()
    await tick()

    const composer = element.querySelector("[data-template-workspace-layout-target='composer']")
    const preview = element.querySelector("[data-template-workspace-layout-target='preview']")

    expect(composer.classList.contains("hidden")).toBe(true)
    expect(preview.classList.contains("hidden")).toBe(false)
  })

  it("toggles split focus on click", async () => {
    // Start with compose view to verify that switching back to split view works
    const htmlWithCompose = `
      <div data-controller="template-workspace-layout" data-template-workspace-layout-current-value="compose">
        <div class="flex">
          <button data-template-workspace-layout-target="btnSplit" data-action="click->template-workspace-layout#switchToSplit">Split</button>
          <button data-template-workspace-layout-target="btnCompose" data-action="click->template-workspace-layout#switchToCompose">Compose</button>
          <button data-template-workspace-layout-target="btnPreview" data-action="click->template-workspace-layout#switchToPreview">Preview</button>
        </div>
        <div data-template-workspace-layout-target="container">
          <div data-template-workspace-layout-target="composer">Composer</div>
          <div data-template-workspace-layout-target="preview">Preview</div>
        </div>
      </div>
    `
    const { application, element } = await mountController("template-workspace-layout", Controller, htmlWithCompose)
    const btnSplit = element.querySelector("[data-template-workspace-layout-target='btnSplit']")

    btnSplit.click()
    await tick()

    const composer = element.querySelector("[data-template-workspace-layout-target='composer']")
    const preview = element.querySelector("[data-template-workspace-layout-target='preview']")

    expect(composer.classList.contains("hidden")).toBe(false)
    expect(preview.classList.contains("hidden")).toBe(false)
  })

  it("handles events without preventDefault and methods without events", async () => {
    const { application, element } = await mountController("template-workspace-layout", Controller, html())
    const ctrl = controllerFor(application, element, "template-workspace-layout")

    // Call methods without event object
    ctrl.switchToCompose()
    await tick()
    expect(ctrl.currentValue).toBe("compose")

    ctrl.switchToSplit()
    await tick()
    expect(ctrl.currentValue).toBe("split")

    ctrl.switchToPreview()
    await tick()
    expect(ctrl.currentValue).toBe("preview")

    // Call with event object containing preventDefault
    const mockEvent = { preventDefault: vi.fn() }
    ctrl.switchToCompose(mockEvent)
    expect(mockEvent.preventDefault).toHaveBeenCalled()
  })

  it("returns early from updateLayout if targets are missing", async () => {
    // HTML with missing container target
    const partialHtml = `
      <div data-controller="template-workspace-layout" data-template-workspace-layout-current-value="split">
        <div data-template-workspace-layout-target="composer">Composer</div>
        <div data-template-workspace-layout-target="preview">Preview</div>
      </div>
    `
    const { application, element } = await mountController("template-workspace-layout", Controller, partialHtml)
    const ctrl = controllerFor(application, element, "template-workspace-layout")

    // This should run the early return without throwing
    expect(() => ctrl.updateLayout()).not.toThrow()
  })

  it("handles activateButton and deactivateButton with null", async () => {
    const { application, element } = await mountController("template-workspace-layout", Controller, html())
    const ctrl = controllerFor(application, element, "template-workspace-layout")

    expect(() => ctrl.activateButton(null)).not.toThrow()
    expect(() => ctrl.deactivateButton(null)).not.toThrow()
  })
})
