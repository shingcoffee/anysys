import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/user_role_dialog_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const flush = () => new Promise((r) => setTimeout(r, 0))

const html = `
  <div data-controller="user-role-dialog"
       data-user-role-dialog-user-id-value="7"
       data-user-role-dialog-user-name-value="Ann &amp; Co"
       data-user-role-dialog-current-role-ids-value="[2]"
       data-user-role-dialog-roles-value='[
         {"id":1,"name":"Admin","key":"admin","description":"Full access","system":true},
         {"id":2,"name":"Member","key":"member","description":"","system":false}
       ]'
       data-user-role-dialog-submit-url-value="/1/admin/roles">
    <button data-action="click->user-role-dialog#open">Edit</button>
  </div>`

const overlay = () => document.body.querySelector('[role="dialog"]')

describe("user-role-dialog controller", () => {
  let application, element, ctrl
  beforeEach(async () => {
    ;({ application, element } = await mountController("user-role-dialog", Controller, html))
    ctrl = controllerFor(application, element, "user-role-dialog")
  })
  afterEach(() => { overlay()?.remove() })

  it("esc() escapes HTML-significant characters", () => {
    expect(ctrl.esc('a & b < c > "d" \'e\'')).toBe("a &amp; b &lt; c &gt; &quot;d&quot; &#39;e&#39;")
    expect(ctrl.esc(null)).toBe("")
  })

  it("open() appends a modal dialog with one checkbox per role", () => {
    ctrl.open()
    expect(overlay()).not.toBeNull()
    const checks = overlay().querySelectorAll('input[type="checkbox"]')
    expect(checks.length).toBe(2)
    // current role id 2 is pre-checked, role 1 is not
    const byValue = (v) => [...checks].find((c) => c.value === String(v))
    expect(byValue(2).checked).toBe(true)
    expect(byValue(1).checked).toBe(false)
  })

  it("renders the escaped user name and a System badge for system roles", () => {
    ctrl.open()
    expect(overlay().innerHTML).toContain("Ann &amp; Co")
    expect(overlay().innerHTML).toContain("System")
  })

  it("uses readable role names in a labelled, height-constrained dialog without internal keys", () => {
    ctrl.rolesValue = [{ id: 2, name: "Support team", key: "internal_support_key", description: "Customer records", system: false }]
    ctrl.open()
    expect(overlay().textContent).toContain("Support team")
    expect(overlay().textContent).not.toContain("internal_support_key")
    expect(overlay().getAttribute("aria-labelledby")).toBe("user-access-dialog-title")
    expect(overlay().querySelector(".max-h-\\[85vh\\]")).not.toBeNull()
    expect(overlay().querySelector("[style]")).toBeNull()
    expect(overlay().querySelector("input").value).toBe("2")
  })

  it("Cancel removes the overlay", () => {
    ctrl.open()
    overlay().querySelector('[data-action="cancel"]').click()
    expect(overlay()).toBeNull()
  })

  it("clicking the backdrop (overlay itself) closes it", () => {
    ctrl.open()
    const ov = overlay()
    ov.dispatchEvent(new MouseEvent("click", { bubbles: true }))
    // event.target === overlay path
    ov.click()
    expect(document.body.querySelector('[role="dialog"]')).toBeNull()
  })

  it("Escape key closes the overlay and detaches its listener", () => {
    ctrl.open()
    // a non-Escape key is ignored
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "a" }))
    expect(overlay()).not.toBeNull()
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }))
    expect(overlay()).toBeNull()
  })

  it("renders a placeholder when no roles are defined", async () => {
    const noRoles = html.replace(/data-user-role-dialog-roles-value='[^']*'/, "data-user-role-dialog-roles-value='[]'")
    const m = await mountController("user-role-dialog", Controller, noRoles)
    const c = controllerFor(m.application, m.element, "user-role-dialog")
    c.open()
    expect(overlay().innerHTML).toContain("No roles defined.")
    expect(overlay().querySelectorAll('input[type="checkbox"]').length).toBe(0)
  })

  describe("Save", () => {
    let meta, originalLocation
    beforeEach(() => {
      meta = document.createElement("meta")
      meta.setAttribute("name", "csrf-token")
      meta.setAttribute("content", "tok-123")
      document.head.appendChild(meta)
      originalLocation = Object.getOwnPropertyDescriptor(window, "location")
      Object.defineProperty(window, "location", { configurable: true, value: { reload: vi.fn() } })
    })
    afterEach(() => {
      meta.remove()
      if (originalLocation) Object.defineProperty(window, "location", originalLocation)
      vi.restoreAllMocks()
    })

    it("POSTs the checked role ids and reloads on success", async () => {
      global.fetch = vi.fn().mockResolvedValue({ ok: true })
      ctrl.open()
      overlay().querySelector('[data-action="save"]').click()
      await flush()
      expect(global.fetch).toHaveBeenCalledWith("/1/admin/roles", expect.objectContaining({
        method: "POST",
        body: JSON.stringify({ user_id: 7, role_ids: [2] })
      }))
      expect(window.location.reload).toHaveBeenCalled()
    })

    it("alerts with the server errors on a failed save", async () => {
      const alertSpy = vi.spyOn(window, "alert").mockImplementation(() => {})
      global.fetch = vi.fn().mockResolvedValue({ ok: false, json: async () => ({ errors: ["nope"] }) })
      ctrl.open()
      overlay().querySelector('[data-action="save"]').click()
      await flush()
      expect(alertSpy).toHaveBeenCalledWith('Save failed: ["nope"]')
      expect(window.location.reload).not.toHaveBeenCalled()
    })

    it("falls back to an empty error object when the error body is unparseable", async () => {
      const alertSpy = vi.spyOn(window, "alert").mockImplementation(() => {})
      global.fetch = vi.fn().mockResolvedValue({ ok: false, json: async () => { throw new Error("bad json") } })
      ctrl.open()
      overlay().querySelector('[data-action="save"]').click()
      await flush()
      expect(alertSpy).toHaveBeenCalledWith("Save failed: {}")
    })
  })
})
