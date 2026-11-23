import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/platform_announcement_audience_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const PREVIEW_URL = "/81721200/admin/maintenance/platform/announcements/audience_preview"

const html = `
  <div data-controller="platform-announcement-audience"
       data-platform-announcement-audience-preview-url-value="${PREVIEW_URL}"
       data-platform-announcement-audience-loading-text-value="Checking..."
       data-platform-announcement-audience-error-text-value="Could not size this audience."
       data-platform-announcement-audience-count-text-value="{count} customers match these conditions."
       data-platform-announcement-audience-empty-text-value="No customers match these conditions.">
    <input type="radio" name="audience" value="all"
           data-action="change->platform-announcement-audience#toggleAudience">
    <input type="radio" name="audience" value="selected" checked
           data-action="change->platform-announcement-audience#toggleAudience">
    <div data-platform-announcement-audience-target="panel"></div>
    <input type="hidden" data-platform-announcement-audience-target="rules" value='{"joins":[]}'>
    <p data-platform-announcement-audience-target="output"></p>
  </div>
`

const noPanelHtml = `
  <div data-controller="platform-announcement-audience">
    <input type="radio" name="audience" value="all">
  </div>
`

const noPreviewUrlHtml = `
  <div data-controller="platform-announcement-audience">
    <p data-platform-announcement-audience-target="output"></p>
  </div>
`

const bareHtml = `
  <div data-controller="platform-announcement-audience"
       data-platform-announcement-audience-preview-url-value="${PREVIEW_URL}">
  </div>
`

async function mount(markup = html) {
  const { application, element } = await mountController(
    "platform-announcement-audience",
    Controller,
    markup
  )
  return {
    element,
    ctrl: controllerFor(application, element, "platform-announcement-audience"),
    output: element.querySelector('[data-platform-announcement-audience-target="output"]')
  }
}

function jsonResponse(payload, ok = true) {
  return { ok, json: async () => payload }
}

describe("platform-announcement-audience controller", () => {
  beforeEach(() => {
    document.head.innerHTML = ""
  })

  afterEach(() => {
    vi.unstubAllGlobals()
    document.head.innerHTML = ""
  })

  describe("toggleAudience", () => {
    it("hides the panel when the radio value is all", async () => {
      const { ctrl, element } = await mount()
      const panel = element.querySelector('[data-platform-announcement-audience-target="panel"]')

      ctrl.toggleAudience({ target: element.querySelector('input[value="all"]') })
      expect(panel.classList.contains("hidden")).toBe(true)
    })

    it("shows the panel when the radio value is selected", async () => {
      const { ctrl, element } = await mount()
      const panel = element.querySelector('[data-platform-announcement-audience-target="panel"]')

      panel.classList.add("hidden")
      ctrl.toggleAudience({ target: element.querySelector('input[value="selected"]') })
      expect(panel.classList.contains("hidden")).toBe(false)
    })

    it("is a no-op when there is no panel target", async () => {
      const { ctrl } = await mount(noPanelHtml)

      expect(() => ctrl.toggleAudience({ target: { value: "all" } })).not.toThrow()
    })
  })

  describe("preview", () => {
    it("renders the translated match count", async () => {
      const fetchMock = vi.fn().mockResolvedValue(jsonResponse({ count: 3 }))
      vi.stubGlobal("fetch", fetchMock)

      const { ctrl, output } = await mount()
      await ctrl.preview()

      expect(output.textContent).toBe("3 customers match these conditions.")
      expect(fetchMock).toHaveBeenCalledTimes(1)
      const [url, init] = fetchMock.mock.calls[0]
      expect(url).toBe(PREVIEW_URL)
      expect(init.method).toBe("POST")
      expect(JSON.parse(init.body)).toEqual({ target_rules_json: '{"joins":[]}' })
    })

    it("renders the empty message when nothing matches", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse({ count: 0 })))

      const { ctrl, output } = await mount()
      await ctrl.preview()

      expect(output.textContent).toBe("No customers match these conditions.")
    })

    it("treats a non-numeric count as zero", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse({ count: "many" })))

      const { ctrl, output } = await mount()
      await ctrl.preview()

      expect(output.textContent).toBe("No customers match these conditions.")
    })

    it("shows the loading text while the request is in flight", async () => {
      let release
      const pending = new Promise((resolve) => { release = resolve })
      vi.stubGlobal("fetch", vi.fn().mockReturnValue(pending))

      const { ctrl, output } = await mount()
      const running = ctrl.preview()
      expect(output.textContent).toBe("Checking...")

      release(jsonResponse({ count: 1 }))
      await running
    })

    it("shows the error text on a failed response", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse({}, false)))

      const { ctrl, output } = await mount()
      await ctrl.preview()

      expect(output.textContent).toBe("Could not size this audience.")
    })

    it("shows the error text when the request throws", async () => {
      vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("offline")))

      const { ctrl, output } = await mount()
      await ctrl.preview()

      expect(output.textContent).toBe("Could not size this audience.")
    })

    it("sends the CSRF token when the meta tag is present", async () => {
      document.head.innerHTML = '<meta name="csrf-token" content="tok-123">'
      const fetchMock = vi.fn().mockResolvedValue(jsonResponse({ count: 1 }))
      vi.stubGlobal("fetch", fetchMock)

      const { ctrl } = await mount()
      await ctrl.preview()

      expect(fetchMock.mock.calls[0][1].headers["X-CSRF-Token"]).toBe("tok-123")
    })

    it("sends an empty CSRF token when the meta tag is missing", async () => {
      const fetchMock = vi.fn().mockResolvedValue(jsonResponse({ count: 1 }))
      vi.stubGlobal("fetch", fetchMock)

      const { ctrl } = await mount()
      await ctrl.preview()

      expect(fetchMock.mock.calls[0][1].headers["X-CSRF-Token"]).toBe("")
    })

    it("falls back to empty rules when there is no rules target", async () => {
      const fetchMock = vi.fn().mockResolvedValue(jsonResponse({ count: 0 }))
      vi.stubGlobal("fetch", fetchMock)

      const { ctrl } = await mount(noPreviewUrlHtml.replace(
        'data-controller="platform-announcement-audience"',
        `data-controller="platform-announcement-audience" data-platform-announcement-audience-preview-url-value="${PREVIEW_URL}"`
      ))
      await ctrl.preview()

      expect(JSON.parse(fetchMock.mock.calls[0][1].body)).toEqual({ target_rules_json: "{}" })
    })

    it("does nothing without an output target", async () => {
      const fetchMock = vi.fn()
      vi.stubGlobal("fetch", fetchMock)

      const { ctrl } = await mount(bareHtml)
      await ctrl.preview()

      expect(fetchMock).not.toHaveBeenCalled()
    })

    it("does nothing without a preview url", async () => {
      const fetchMock = vi.fn()
      vi.stubGlobal("fetch", fetchMock)

      const { ctrl, output } = await mount(noPreviewUrlHtml)
      await ctrl.preview()

      expect(fetchMock).not.toHaveBeenCalled()
      expect(output.textContent).toBe("")
    })
  })
})
