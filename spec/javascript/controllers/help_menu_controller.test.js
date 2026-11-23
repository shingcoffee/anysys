import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/help_menu_controller"
import { mountController, click, tick, controllerFor } from "../support/stimulus.js"

const html = `
  <div data-controller="help-menu">
    <button data-help-menu-target="trigger" data-action="click->help-menu#toggle" data-role="toggle" aria-expanded="false">?</button>
    <div data-help-menu-target="panel" class="hidden" data-role="panel">
      <button data-action="click->help-menu#openNotify" data-role="notify">Notify</button>
      <button data-action="click->help-menu#openEmail" data-role="email">Email</button>
      <a href="https://docs.anysys.com" data-action="click->help-menu#close" data-role="docs">Docs</a>
    </div>
    <div data-help-menu-target="notifyDialog" class="hidden" data-role="notify-dialog">
      <form data-role="notify-form">
        <input data-role="notify-subject" value="draft" />
        <ul data-help-attachments-target="list"><li>chip</li></ul>
        <p class="" data-help-attachments-target="error">too big</p>
        <button type="submit" data-help-attachments-target="submit" disabled data-role="notify-submit">Send</button>
      </form>
      <button type="button" data-action="click->help-menu#closeDialogs" data-role="close-dialog">Close</button>
    </div>
    <div data-help-menu-target="emailDialog" class="hidden" data-role="email-dialog">Email dialog</div>
  </div>`

const isHidden = (el, role) => el.querySelector(`[data-role='${role}']`).classList.contains("hidden")

describe("help-menu controller", () => {
  let element
  beforeEach(async () => {
    document.documentElement.classList.remove("overflow-hidden")
    ;({ element } = await mountController("help-menu", Controller, html))
  })

  afterEach(() => {
    document.documentElement.classList.remove("overflow-hidden")
  })

  it("panel starts hidden and toggles open/closed", () => {
    const trigger = element.querySelector("[data-role='toggle']")
    expect(isHidden(element, "panel")).toBe(true)
    click(trigger)
    expect(isHidden(element, "panel")).toBe(false)
    expect(trigger.getAttribute("aria-expanded")).toBe("true")
    click(trigger)
    expect(isHidden(element, "panel")).toBe(true)
    expect(trigger.getAttribute("aria-expanded")).toBe("false")
  })

  it("openNotify closes the panel, reveals the notify dialog, and focuses the first field", () => {
    const subject = element.querySelector("[data-role='notify-subject']")
    const focus = vi.spyOn(subject, "focus")
    click(element.querySelector("[data-role='toggle']"))
    click(element.querySelector("[data-role='notify']"))
    expect(isHidden(element, "panel")).toBe(true)
    expect(isHidden(element, "notify-dialog")).toBe(false)
    expect(document.documentElement.classList.contains("overflow-hidden")).toBe(true)
    expect(focus).toHaveBeenCalled()
  })

  it("openEmail closes the panel and reveals the email dialog", () => {
    click(element.querySelector("[data-role='toggle']"))
    click(element.querySelector("[data-role='email']"))
    expect(isHidden(element, "panel")).toBe(true)
    expect(isHidden(element, "email-dialog")).toBe(false)
    expect(document.documentElement.classList.contains("overflow-hidden")).toBe(true)
  })

  it("closes the panel on an outside click", () => {
    click(element.querySelector("[data-role='toggle']"))
    document.body.dispatchEvent(new Event("click", { bubbles: true }))
    expect(isHidden(element, "panel")).toBe(true)
  })

  it("Escape closes panel and dialogs and unlocks scroll", () => {
    click(element.querySelector("[data-role='toggle']"))
    click(element.querySelector("[data-role='notify']"))
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }))
    expect(isHidden(element, "panel")).toBe(true)
    expect(isHidden(element, "notify-dialog")).toBe(true)
    expect(document.documentElement.classList.contains("overflow-hidden")).toBe(false)
  })

  it("closeDialogs resets the form, chips, error, and submit", () => {
    click(element.querySelector("[data-role='notify']"))
    element.querySelector("[data-role='notify-subject']").value = "changed"
    click(element.querySelector("[data-role='close-dialog']"))
    expect(isHidden(element, "notify-dialog")).toBe(true)
    expect(element.querySelector("[data-role='notify-subject']").value).toBe("draft")
    expect(element.querySelector("[data-help-attachments-target='list']").children).toHaveLength(0)
    expect(element.querySelector("[data-help-attachments-target='error']").textContent).toBe("")
    expect(element.querySelector("[data-help-attachments-target='error']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-role='notify-submit']").disabled).toBe(false)
    expect(document.documentElement.classList.contains("overflow-hidden")).toBe(false)
    expect(document.activeElement).toBe(element.querySelector("[data-role='toggle']"))
  })

  it("openNotify is a no-op past closing the panel when there is no notify dialog", async () => {
    const noDialogHtml = `
      <div data-controller="help-menu">
        <button data-action="click->help-menu#toggle" data-role="toggle">?</button>
        <div data-help-menu-target="panel" class="hidden" data-role="panel">
          <button data-action="click->help-menu#openNotify" data-role="notify">Notify</button>
          <button data-action="click->help-menu#openEmail" data-role="email">Email</button>
        </div>
      </div>`
    const { element: el } = await mountController("help-menu", Controller, noDialogHtml)
    click(el.querySelector("[data-role='toggle']"))
    expect(() => click(el.querySelector("[data-role='notify']"))).not.toThrow()
    expect(() => click(el.querySelector("[data-role='email']"))).not.toThrow()
    expect(isHidden(el, "panel")).toBe(true)
    expect(document.documentElement.classList.contains("overflow-hidden")).toBe(false)
  })

  it("disconnect removes the document click/keydown listeners and unlocks scroll", async () => {
    click(element.querySelector("[data-role='notify']"))
    expect(document.documentElement.classList.contains("overflow-hidden")).toBe(true)
    const removeSpy = vi.spyOn(document, "removeEventListener")
    element.remove()
    await tick()
    expect(removeSpy).toHaveBeenCalledWith("click", expect.any(Function))
    expect(removeSpy).toHaveBeenCalledWith("keydown", expect.any(Function))
    expect(removeSpy).toHaveBeenCalledWith("anysys:topbar-menu-open", expect.any(Function))
    expect(document.documentElement.classList.contains("overflow-hidden")).toBe(false)
  })

  it("closes panel and dialogs when a peer top-bar menu opens", () => {
    click(element.querySelector("[data-role='toggle']"))
    click(element.querySelector("[data-role='notify']"))
    document.dispatchEvent(new CustomEvent("anysys:topbar-menu-open", {
      detail: { source: document.createElement("div") }
    }))
    expect(isHidden(element, "panel")).toBe(true)
    expect(isHidden(element, "notify-dialog")).toBe(true)
  })

  it("closeDialogs is a no-op when only one dialog target exists", async () => {
    const one = `
      <div data-controller="help-menu">
        <div data-help-menu-target="panel" class="hidden" data-role="panel"></div>
        <div data-help-menu-target="notifyDialog" class="hidden" data-role="notify-dialog"></div>
      </div>`
    const mounted = await mountController("help-menu", Controller, one)
    const controller = controllerFor(mounted.application, mounted.element, "help-menu")
    expect(() => controller.closeDialogs()).not.toThrow()
    expect(isHidden(mounted.element, "notify-dialog")).toBe(true)
  })

  it("closeDialogs does not restore focus when the trigger is absent", async () => {
    const one = `
      <div data-controller="help-menu">
        <div data-help-menu-target="panel" class="hidden" data-role="panel"></div>
        <div data-help-menu-target="notifyDialog" data-role="notify-dialog">open</div>
      </div>`
    const mounted = await mountController("help-menu", Controller, one)
    const controller = controllerFor(mounted.application, mounted.element, "help-menu")
    expect(() => controller.closeDialogs()).not.toThrow()
    expect(isHidden(mounted.element, "notify-dialog")).toBe(true)
  })
})
