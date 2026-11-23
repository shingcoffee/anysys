import { describe, it, expect, beforeEach, vi } from "vitest"
import Controller from "controllers/page_visibility_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const lastAudience = "A form needs at least one audience."

const html = `
  <form data-controller="page-visibility"
        data-page-visibility-saving-value="Saving…"
        data-page-visibility-last-audience-value="${lastAudience}">
    <span data-page-visibility-target="status" class="hidden"></span>
    <input type="hidden" name="page[visible_audiences][]" value="stale">
    <label class="cursor-pointer">
      <input type="checkbox" value="admin" checked
             data-page-visibility-target="admin"
             data-action="change->page-visibility#sync"
             aria-label="Admin">
    </label>
    <label class="cursor-pointer">
      <input type="checkbox" value="member"
             data-page-visibility-target="member"
             data-action="change->page-visibility#sync"
             aria-label="Member">
    </label>
    <label class="cursor-pointer">
      <input type="checkbox" value="public"
             data-page-visibility-target="public"
             data-action="change->page-visibility#sync"
             aria-label="Public">
    </label>
  </form>`

const htmlWithoutStatus = `
  <form data-controller="page-visibility">
    <label>
      <input type="checkbox" value="admin" checked data-page-visibility-target="admin" aria-label="Admin">
    </label>
    <input type="checkbox" value="member" data-page-visibility-target="member">
    <input type="checkbox" value="public" data-page-visibility-target="public">
  </form>`

const htmlMissingMember = `
  <form data-controller="page-visibility">
    <label>
      <input type="checkbox" value="admin" checked data-page-visibility-target="admin" aria-label="Admin">
    </label>
    <label>
      <input type="checkbox" value="public" data-page-visibility-target="public" aria-label="Public">
    </label>
  </form>`

function hiddenValues(form) {
  return [...form.querySelectorAll('input[type="hidden"][name="page[visible_audiences][]"]')]
    .map((input) => input.value)
}

function switchFor(element, key) {
  return element.querySelector(`[data-page-visibility-target="${key}"]`)
}

describe("page-visibility controller — independent switches", () => {
  let ctrl, admin, member, pub, element

  beforeEach(async () => {
    const mounted = await mountController("page-visibility", Controller, html)
    element = mounted.element
    ctrl = controllerFor(mounted.application, element, "page-visibility")
    admin = switchFor(element, "admin")
    member = switchFor(element, "member")
    pub = switchFor(element, "public")
    element.requestSubmit = vi.fn()
  })

  it("locks the last remaining audience on connect and drops stale hidden inputs", () => {
    expect(admin.disabled).toBe(true)
    expect(admin.getAttribute("aria-label")).toBe(lastAudience)
    expect(admin.closest("label").classList.contains("opacity-60")).toBe(true)
    expect(admin.closest("label").classList.contains("cursor-not-allowed")).toBe(true)
    expect(admin.closest("label").dataset.tooltip).toBe(lastAudience)
    expect(member.disabled).toBe(false)
    expect(pub.disabled).toBe(false)
    expect(hiddenValues(element)).toEqual(["admin"])
  })

  it("toggles member independently without touching public", () => {
    member.checked = true
    ctrl.sync({ target: member })
    expect(admin.checked).toBe(true)
    expect(member.checked).toBe(true)
    expect(pub.checked).toBe(false)
    expect(hiddenValues(element)).toEqual(["admin", "member"])
  })

  it("toggles public independently without auto-checking member", () => {
    pub.checked = true
    ctrl.sync({ target: pub })
    expect(admin.checked).toBe(true)
    expect(member.checked).toBe(false)
    expect(pub.checked).toBe(true)
    expect(hiddenValues(element)).toEqual(["admin", "public"])
  })

  it("toggles admin independently once another audience is on", () => {
    member.checked = true
    ctrl.sync({ target: member })
    admin.checked = false
    ctrl.sync({ target: admin })
    expect(admin.checked).toBe(false)
    expect(member.checked).toBe(true)
    expect(pub.checked).toBe(false)
    expect(hiddenValues(element)).toEqual(["member"])
  })

  it("unlocks the last switch when a second audience is turned on", () => {
    member.checked = true
    ctrl.sync({ target: member })
    expect(admin.disabled).toBe(false)
    expect(admin.getAttribute("aria-label")).toBe("Admin")
    expect(admin.closest("label").classList.contains("opacity-60")).toBe(false)
    expect(admin.closest("label").classList.contains("cursor-pointer")).toBe(true)
    expect(admin.closest("label").dataset.tooltip).toBeUndefined()
    expect(member.disabled).toBe(false)
  })

  it("locks again when the set returns to one audience", () => {
    member.checked = true
    ctrl.sync({ target: member })
    member.checked = false
    ctrl.sync({ target: member })
    expect(admin.disabled).toBe(true)
    expect(admin.getAttribute("aria-label")).toBe(lastAudience)
    expect(admin.closest("label").dataset.tooltip).toBe(lastAudience)
    expect(hiddenValues(element)).toEqual(["admin"])
  })

  it("keeps a disabled last switch in the hidden payload", () => {
    expect(admin.disabled).toBe(true)
    expect(hiddenValues(element)).toEqual(["admin"])
    ctrl.sync()
    expect(hiddenValues(element)).toEqual(["admin"])
  })

  it("does not re-store aria-label when the last switch is locked twice", () => {
    expect(admin.dataset.unlockedAria).toBe("Admin")
    ctrl.sync()
    expect(admin.dataset.unlockedAria).toBe("Admin")
    expect(admin.getAttribute("aria-label")).toBe(lastAudience)
  })
})

describe("page-visibility controller — lastAudience default", () => {
  it("reads the English default when the last-audience value is missing", async () => {
    const { application, element } = await mountController("page-visibility", Controller, htmlWithoutStatus)
    const ctrl = controllerFor(application, element, "page-visibility")
    const admin = switchFor(element, "admin")

    expect(ctrl.lastAudienceValue).toBe(lastAudience)
    expect(ctrl.savingValue).toBe("Saving…")
    expect(admin.disabled).toBe(true)
    expect(admin.getAttribute("aria-label")).toBe(lastAudience)
    expect(admin.closest("label").dataset.tooltip).toBe(lastAudience)
  })

  it("locks an input that has no aria-label without storing a restore value", async () => {
    const { application, element } = await mountController("page-visibility", Controller, htmlWithoutStatus)
    const ctrl = controllerFor(application, element, "page-visibility")
    const member = switchFor(element, "member")
    element.requestSubmit = vi.fn()

    member.checked = true
    ctrl.sync({ target: member })
    expect(member.dataset.unlockedAria).toBeUndefined()

    const admin = switchFor(element, "admin")
    admin.checked = false
    ctrl.sync({ target: admin })
    expect(member.disabled).toBe(true)
    expect(member.dataset.unlockedAria).toBeUndefined()
    expect(member.getAttribute("aria-label")).toBe(lastAudience)
  })
})

describe("page-visibility controller — missing targets and wrappers", () => {
  it("ignores a missing audience target when locking and posting", async () => {
    const { application, element } = await mountController("page-visibility", Controller, htmlMissingMember)
    const ctrl = controllerFor(application, element, "page-visibility")
    const admin = switchFor(element, "admin")
    const pub = switchFor(element, "public")
    element.requestSubmit = vi.fn()

    expect(switchFor(element, "member")).toBeNull()
    expect(hiddenValues(element)).toEqual(["admin"])

    pub.checked = true
    ctrl.sync({ target: pub })
    expect(admin.checked).toBe(true)
    expect(pub.checked).toBe(true)
    expect(hiddenValues(element)).toEqual(["admin", "public"])
  })

  it("locks and unlocks an input that is not wrapped in a label", async () => {
    const { application, element } = await mountController("page-visibility", Controller, htmlWithoutStatus)
    const ctrl = controllerFor(application, element, "page-visibility")
    const member = switchFor(element, "member")
    const pub = switchFor(element, "public")
    element.requestSubmit = vi.fn()

    expect(member.closest("label")).toBeNull()
    member.checked = true
    ctrl.sync({ target: member })
    expect(member.disabled).toBe(false)

    const admin = switchFor(element, "admin")
    admin.checked = false
    ctrl.sync({ target: admin })
    expect(member.disabled).toBe(true)
    expect(member.getAttribute("aria-label")).toBe(lastAudience)

    pub.checked = true
    ctrl.sync({ target: pub })
    expect(member.disabled).toBe(false)
  })
})

describe("page-visibility controller — auto-submit", () => {
  it("sync() calls requestSubmit after applying the lock", async () => {
    const { application, element } = await mountController("page-visibility", Controller, html)
    const ctrl = controllerFor(application, element, "page-visibility")
    const member = switchFor(element, "member")
    element.requestSubmit = vi.fn()

    member.checked = true
    ctrl.sync({ target: member })

    expect(element.requestSubmit).toHaveBeenCalledOnce()
  })

  it("submit() falls back to submit() when requestSubmit is unavailable", async () => {
    const { application, element } = await mountController("page-visibility", Controller, html)
    const ctrl = controllerFor(application, element, "page-visibility")
    element.requestSubmit = undefined
    element.submit = vi.fn()

    ctrl.submit()

    expect(element.submit).toHaveBeenCalledOnce()
  })

  it("shows saving status text when a status target is present", async () => {
    const { application, element } = await mountController("page-visibility", Controller, html)
    const ctrl = controllerFor(application, element, "page-visibility")
    element.requestSubmit = vi.fn()
    const status = element.querySelector('[data-page-visibility-target="status"]')

    ctrl.submit()

    expect(status.textContent).toBe("Saving…")
    expect(status.classList.contains("hidden")).toBe(false)
  })

  it("submit() works without a status target", async () => {
    const { application, element } = await mountController("page-visibility", Controller, htmlWithoutStatus)
    const ctrl = controllerFor(application, element, "page-visibility")
    element.requestSubmit = vi.fn()

    expect(() => ctrl.submit()).not.toThrow()
    expect(element.requestSubmit).toHaveBeenCalledOnce()
  })
})
