import { describe, it, expect, vi, afterEach } from "vitest"
import Controller from "controllers/template_token_checkbox_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = `
  <div data-controller="template-token-checkbox"
       data-template-token-checkbox-url-value="/81721200/admin/maintenance/platform/module_settings/1"
       data-template-token-checkbox-token-model-value="User"
       data-template-token-checkbox-token-attribute-value="email"
       data-template-token-checkbox-active-value="false">
    <label>
      <input type="checkbox"
             data-template-token-checkbox-target="checkbox"
             data-action="change->template-token-checkbox#toggle" />
    </label>
  </div>`

// The badge is optional in the markup, so it gets its own fixture: without it
// every renderState call returns at the guard and nothing is rendered.
const badgeHtml = `
  <div data-controller="template-token-checkbox"
       data-template-token-checkbox-url-value="/81721200/admin/maintenance/platform/module_settings/1"
       data-template-token-checkbox-token-model-value="User"
       data-template-token-checkbox-token-attribute-value="email"
       data-template-token-checkbox-active-value="false">
    <label>
      <input type="checkbox"
             data-template-token-checkbox-target="checkbox"
             data-action="change->template-token-checkbox#toggle" />
    </label>
    <span data-template-token-checkbox-target="badge"></span>
  </div>`

const flush = () => new Promise((r) => setTimeout(r, 10))

describe("template-token-checkbox controller", () => {
  afterEach(() => {
    vi.restoreAllMocks()
    vi.useRealTimers()
  })

  // mountController awaits a real setTimeout, so it has to run before fake
  // timers are installed.
  const mount = async (markup = html) => {
    const { application, element } = await mountController("template-token-checkbox", Controller, markup)
    return {
      element,
      controller: controllerFor(application, element, "template-token-checkbox"),
      checkbox: element.querySelector('input[type="checkbox"]'),
      badge: element.querySelector("[data-template-token-checkbox-target='badge']")
    }
  }

  it("sends AJAX PATCH request on toggle change", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue({
      ok: true,
      json: async () => ({ success: true, enabled: true })
    })

    const { element } = await mountController("template-token-checkbox", Controller, html)
    const checkbox = element.querySelector('input[type="checkbox"]')

    checkbox.checked = true
    checkbox.dispatchEvent(new Event("change"))

    await flush()

    expect(fetchSpy).toHaveBeenCalledWith(
      "/81721200/admin/maintenance/platform/module_settings/1",
      expect.objectContaining({
        method: "PATCH",
        headers: expect.objectContaining({
          "Content-Type": "application/json",
          "Accept": "application/json"
        }),
        body: JSON.stringify({
          token_model: "User",
          token_attribute: "email",
          token_enabled: "1"
        })
      })
    )

    expect(checkbox.checked).toBe(true)
  })

  it("handles fetch failure gracefully and reverts checkbox state", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue({
      ok: false,
      json: async () => ({ success: false, error: "Failed" })
    })

    const { element } = await mountController("template-token-checkbox", Controller, html)
    const checkbox = element.querySelector('input[type="checkbox"]')

    checkbox.checked = true
    checkbox.dispatchEvent(new Event("change"))

    await flush()

    expect(checkbox.checked).toBe(false)
  })

  it("handles network exception during fetch", async () => {
    vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("Network error"))

    const { element } = await mountController("template-token-checkbox", Controller, html)
    const checkbox = element.querySelector('input[type="checkbox"]')

    checkbox.checked = true
    checkbox.dispatchEvent(new Event("change"))

    await flush()

    expect(checkbox.checked).toBe(false)
  })

  it("sends the CSRF token from the page meta tag", async () => {
    const meta = document.createElement("meta")
    meta.name = "csrf-token"
    meta.content = "tok-123"
    document.head.appendChild(meta)

    try {
      const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: true, json: async () => ({}) })
      const { element } = await mountController("template-token-checkbox", Controller, html)

      element.querySelector('input[type="checkbox"]').dispatchEvent(new Event("change"))
      await flush()

      expect(fetchSpy).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({ headers: expect.objectContaining({ "X-CSRF-Token": "tok-123" }) })
      )
    } finally {
      meta.remove()
    }
  })

  // A double-fired change event must not mint a second PATCH for the same box.
  it("ignores a toggle while a save is already in flight", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: true, json: async () => ({}) })
    const { element } = await mountController("template-token-checkbox", Controller, html)
    const checkbox = element.querySelector('input[type="checkbox"]')

    checkbox.dispatchEvent(new Event("change"))
    checkbox.dispatchEvent(new Event("change"))
    await flush()

    expect(fetchSpy).toHaveBeenCalledTimes(1)
  })

  it("toggles when called without an event", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: true, json: async () => ({}) })
    const { controller } = await mount()

    await controller.toggle()

    expect(fetchSpy).toHaveBeenCalledOnce()
  })

  describe("badge", () => {
    it("shows the saving badge and then the available one", async () => {
      let resolveFetch
      vi.spyOn(globalThis, "fetch").mockReturnValue(new Promise((r) => { resolveFetch = r }))
      const { checkbox, badge } = await mount(badgeHtml)

      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change"))
      await Promise.resolve()
      expect(badge.textContent).toBe("Saving…")
      expect(badge.innerHTML).toContain("animate-pulse")

      resolveFetch({ ok: true, json: async () => ({}) })
      await flush()

      expect(badge.textContent).toBe("Token Available")
      expect(badge.innerHTML).toContain("badge-success")
    })

    it("shows the not-tokenized badge when the box is cleared", async () => {
      vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: true, json: async () => ({}) })
      const { checkbox, badge } = await mount(badgeHtml)

      checkbox.dispatchEvent(new Event("change"))
      await flush()

      expect(badge.textContent).toBe("Not Tokenized")
      expect(badge.innerHTML).toContain("badge-default")
    })

    // The failure badge is transient: it reverts to the persisted state so the
    // row does not sit on "Failed" for the rest of the session.
    it("shows the failure badge and reverts to the saved state", async () => {
      vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("Network error"))
      vi.spyOn(console, "error").mockImplementation(() => {})
      const { checkbox, badge } = await mount(badgeHtml)
      vi.useFakeTimers()

      checkbox.dispatchEvent(new Event("change"))
      await vi.advanceTimersByTimeAsync(0)
      expect(badge.textContent).toBe("Failed")
      expect(badge.innerHTML).toContain("badge-danger")

      await vi.advanceTimersByTimeAsync(2000)
      expect(badge.textContent).toBe("Not Tokenized")
    })

    it("escapes markup in a label instead of rendering it", async () => {
      vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: true, json: async () => ({}) })
      const { checkbox, badge, controller } = await mount(
        badgeHtml.replace(
          "data-template-token-checkbox-active-value=\"false\"",
          "data-template-token-checkbox-active-value=\"false\" data-template-token-checkbox-not-available-label-value=\"&lt;img src=x onerror=alert(1)&gt;\""
        )
      )

      checkbox.dispatchEvent(new Event("change"))
      await flush()

      expect(badge.querySelector("img")).toBeNull()
      expect(badge.textContent).toBe("<img src=x onerror=alert(1)>")
      expect(controller.escapeHtml(null)).toBe("")
    })

    it("does nothing for an unknown state", async () => {
      const { badge, controller } = await mount(badgeHtml)

      controller.renderState("nonsense")

      expect(badge.innerHTML).toBe("")
    })
  })
})
