import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/remote_template_preview_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = (extra = "") => `
<form data-controller="remote-template-preview" 
      data-remote-template-preview-url-value="/preview"
      data-remote-template-preview-test-send-url-value="/test_send">
  <input name="email_template[name]" value="Test Name" />
  <input id="email_template_subject" name="email_template[subject]" value="Hello {{first_name}}" />
  <select name="email_template[editor_type]"><option value="code" selected>Code</option></select>
  <textarea name="email_template[body]">HiBody</textarea>
  <textarea name="email_template[body_html]">HiBodyHtml</textarea>
  <textarea name="email_template[body_text]">Hi plain</textarea>
  <select name="email_template[status]"><option value="draft" selected>Draft</option></select>

  <button type="button" data-remote-template-preview-target="button" data-action="click->remote-template-preview#loadPreview">Load</button>
  <div data-remote-template-preview-target="subjectPane"></div>
  <div data-remote-template-preview-target="htmlPane">
    <iframe data-remote-template-preview-target="iframe"></iframe>
  </div>
  <div data-remote-template-preview-target="textPane"></div>

  <button type="button" data-remote-template-preview-target="tabSubject" data-action="click->remote-template-preview#showTab" data-tab="subject">Subject</button>
  <button type="button" data-remote-template-preview-target="tabHtml" data-action="click->remote-template-preview#showTab" data-tab="html">HTML</button>
  <button type="button" data-remote-template-preview-target="tabText" data-action="click->remote-template-preview#showTab" data-tab="text">Text</button>

  <input data-remote-template-preview-target="testEmailInput" value="test@example.com" />
  <button type="button" data-remote-template-preview-target="testSendButton" data-action="click->remote-template-preview#sendTestEmail">Send Test</button>
  <div data-remote-template-preview-target="testStatus" class="hidden"></div>
  ${extra}
</form>
`

describe("remote-template-preview controller", () => {
  let consoleErrorSpy

  beforeEach(() => {
    globalThis.alert = vi.fn()
    consoleErrorSpy = vi.spyOn(console, "error").mockImplementation(() => {})
    
    // Default fetch mock to prevent connect() loadPreview from failing
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        subject: "Default Subject",
        body_html: "<div>Default HTML</div>",
        body_text: "Default Text"
      })
    }))
  })

  afterEach(() => {
    vi.restoreAllMocks()
    vi.useRealTimers()
  })

  it("gathers only supported form inputs into the getFormData hash", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const data = ctrl.getFormData()
    expect(data.email_template).toEqual({
      name: "Test Name",
      subject: "Hello {{first_name}}",
      editor_type: "code",
      body: "HiBody",
      body_html: "HiBodyHtml",
      body_text: "Hi plain",
      status: "draft"
    })
  })

  it("handles missing form inputs in getFormData gracefully", async () => {
    // Mount with no form inputs whatsoever
    const { application, element } = await mountController("remote-template-preview", Controller, `
      <div data-controller="remote-template-preview">
        <button type="button" data-remote-template-preview-target="button">Load</button>
      </div>
    `)
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const data = ctrl.getFormData()
    expect(data.email_template).toEqual({
      name: "",
      subject: "",
      editor_type: "code",
      body: "",
      body_html: "",
      body_text: "",
      status: "draft"
    })
  })

  it("prefers live Lexxy content and handles unchecked controls without hidden fallbacks", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, `
      <form data-controller="remote-template-preview">
        <input name="email_template[name]" value="" />
        <input name="email_template[subject]" type="hidden" value="Hidden subject" />
        <textarea name="email_template[body]">Fallback body</textarea>
        <lexxy-editor></lexxy-editor>
        <input name="email_template[status]" type="checkbox" value="active" />
      </form>
    `)
    const ctrl = controllerFor(application, element, "remote-template-preview")
    const editor = element.querySelector("lexxy-editor")

    editor.value = "<p>Live body</p>"
    expect(ctrl.getFormData().email_template).toMatchObject({
      name: "",
      subject: "Hidden subject",
      body: "<p>Live body</p>",
      status: "draft"
    })

    editor.value = null
    expect(ctrl.getFormData().email_template.body).toBe("Fallback body")
  })

  it("loads the preview successfully and populates pane and iframe contents", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const fakeFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        subject: "Hello Alice",
        body_html: "<h1>Hi Alice</h1>",
        body_text: "Hi Alice plain"
      })
    })
    vi.stubGlobal("fetch", fakeFetch)

    await ctrl.loadPreview()

    expect(fakeFetch).toHaveBeenCalledWith("/preview", expect.any(Object))
    expect(element.querySelector("[data-remote-template-preview-target='subjectPane']").textContent).toBe("Hello Alice")
    expect(element.querySelector("[data-remote-template-preview-target='iframe']").srcdoc).toContain("<h1>Hi Alice</h1>")
    expect(element.querySelector("[data-remote-template-preview-target='textPane']").textContent).toBe("Hi Alice plain")
  })

  it("prefers server-provided body_srcdoc over client wrapping of body_html", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const fakeFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        subject: "Hello",
        body_html: "<h1>fragment</h1>",
        body_srcdoc: "<!DOCTYPE html><html><body><h1>from-server</h1></body></html>",
        body_text: "plain"
      })
    })
    vi.stubGlobal("fetch", fakeFetch)

    await ctrl.loadPreview()

    const srcdoc = element.querySelector("[data-remote-template-preview-target='iframe']").srcdoc
    expect(srcdoc).toContain("from-server")
    expect(srcdoc).not.toContain("fragment")
  })

  it("supports empty or missing properties in preview response", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const fakeFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        subject: "",
        body_html: "",
        body_text: ""
      })
    })
    vi.stubGlobal("fetch", fakeFetch)

    await ctrl.loadPreview()

    expect(element.querySelector("[data-remote-template-preview-target='subjectPane']").textContent).toBe("(Empty Subject)")
    expect(element.querySelector("[data-remote-template-preview-target='iframe']").srcdoc).toContain("<body></body>")
    expect(element.querySelector("[data-remote-template-preview-target='textPane']").textContent).toBe("(Empty Text)")
  })

  it("handles missing pane targets during preview populate without throwing", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, `
      <div data-controller="remote-template-preview" data-remote-template-preview-url-value="/preview">
        <button type="button" data-remote-template-preview-target="button">Load</button>
      </div>
    `)
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const fakeFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        subject: "Subject",
        body_html: "HTML",
        body_text: "Text"
      })
    })
    vi.stubGlobal("fetch", fakeFetch)

    await expect(ctrl.loadPreview()).resolves.not.toThrow()
  })

  it("handles preview fetch error gracefully and shows alert", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const fakeFetch = vi.fn().mockResolvedValue({ ok: false })
    vi.stubGlobal("fetch", fakeFetch)
    const alertSpy = vi.spyOn(globalThis, "alert")

    await ctrl.loadPreview()

    expect(alertSpy).toHaveBeenCalledWith("Error loading preview")
    expect(consoleErrorSpy).toHaveBeenCalled()
  })

  it("handles preview fetch network error gracefully", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const fakeFetch = vi.fn().mockRejectedValue(new Error("Network Failure"))
    vi.stubGlobal("fetch", fakeFetch)
    const alertSpy = vi.spyOn(globalThis, "alert")

    await ctrl.loadPreview()

    expect(alertSpy).toHaveBeenCalledWith("Error loading preview")
    expect(consoleErrorSpy).toHaveBeenCalled()
  })

  it("uses the CSRF token from meta tags if present", async () => {
    // Inject CSRF meta
    const meta = document.createElement("meta")
    meta.name = "csrf-token"
    meta.content = "my-special-csrf-token"
    document.head.appendChild(meta)

    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const fakeFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({})
    })
    vi.stubGlobal("fetch", fakeFetch)

    await ctrl.loadPreview()

    expect(fakeFetch).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({
        headers: expect.objectContaining({
          "X-CSRF-Token": "my-special-csrf-token"
        })
      })
    )

    meta.remove()
  })

  it("calls preventDefault if event is passed to loadPreview", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const fakeEvent = { preventDefault: vi.fn() }
    await ctrl.loadPreview(fakeEvent)

    expect(fakeEvent.preventDefault).toHaveBeenCalled()
  })

  it("debounces preview requests when autoRefresh is enabled", async () => {
    const { application, element } = await mountController(
      "remote-template-preview", 
      Controller, 
      html(`<input type="checkbox" data-remote-template-preview-target="autoRefresh" checked />`)
    )
    const ctrl = controllerFor(application, element, "remote-template-preview")

    vi.useFakeTimers()

    const loadPreviewSpy = vi.spyOn(ctrl, "loadPreview").mockImplementation(async () => {})

    // Call debounced multiple times
    ctrl.debouncedLoadPreview()
    ctrl.debouncedLoadPreview()
    ctrl.debouncedLoadPreview()

    // No immediate call
    expect(loadPreviewSpy).not.toHaveBeenCalled()

    // Advance 500ms
    vi.advanceTimersByTime(500)
    expect(loadPreviewSpy).not.toHaveBeenCalled()

    // Advance remaining 500ms
    vi.advanceTimersByTime(500)
    expect(loadPreviewSpy).toHaveBeenCalledTimes(1)
  })

  it("does not trigger preview if autoRefresh is unchecked", async () => {
    const { application, element } = await mountController(
      "remote-template-preview", 
      Controller, 
      html(`<input type="checkbox" data-remote-template-preview-target="autoRefresh" />`) // unchecked
    )
    const ctrl = controllerFor(application, element, "remote-template-preview")

    vi.useFakeTimers()

    const loadPreviewSpy = vi.spyOn(ctrl, "loadPreview").mockImplementation(async () => {})

    ctrl.debouncedLoadPreview()
    vi.advanceTimersByTime(2000)

    expect(loadPreviewSpy).not.toHaveBeenCalled()
  })

  it("triggers debounced preview if autoRefresh is missing entirely", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    vi.useFakeTimers()

    const loadPreviewSpy = vi.spyOn(ctrl, "loadPreview").mockImplementation(async () => {})

    ctrl.debouncedLoadPreview()
    vi.advanceTimersByTime(1000)

    expect(loadPreviewSpy).toHaveBeenCalled()
  })

  it("switches tabs successfully on showTab", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const preventDefault = vi.fn()

    // Show HTML tab — subject header stays visible
    ctrl.showTab({ currentTarget: element.querySelector("[data-tab='html']"), preventDefault })
    expect(preventDefault).toHaveBeenCalled()
    expect(element.querySelector("[data-remote-template-preview-target='htmlPane']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-remote-template-preview-target='subjectPane']").classList.contains("hidden")).toBe(false)

    // Show text tab
    ctrl.showTab({ currentTarget: element.querySelector("[data-tab='text']"), preventDefault })
    expect(element.querySelector("[data-remote-template-preview-target='textPane']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-remote-template-preview-target='htmlPane']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-remote-template-preview-target='subjectPane']").classList.contains("hidden")).toBe(false)

    // Show subject tab (legacy) — keep HTML pane as fallback, subject still visible
    ctrl.showTab({ currentTarget: element.querySelector("[data-tab='subject']"), preventDefault })
    expect(element.querySelector("[data-remote-template-preview-target='subjectPane']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-remote-template-preview-target='htmlPane']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-remote-template-preview-target='textPane']").classList.contains("hidden")).toBe(true)
  })

  it("handles missing pane and tab targets gracefully in showTab", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, `
      <div data-controller="remote-template-preview">
        <button type="button" data-remote-template-preview-target="tabSubject" data-action="click->remote-template-preview#showTab" data-tab="subject">Subject</button>
      </div>
    `)
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const mockEvent = {
      currentTarget: element.querySelector("[data-tab='subject']"),
      preventDefault: vi.fn()
    }

    expect(() => ctrl.showTab(mockEvent)).not.toThrow()
  })

  it("handles unknown tab dataset values gracefully in showTab", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const mockEvent = {
      currentTarget: { dataset: { tab: "unknown-tab-name" } },
      preventDefault: vi.fn()
    }

    expect(() => ctrl.showTab(mockEvent)).not.toThrow()
  })

  it("validates empty email input when sending test email", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    element.querySelector("[data-remote-template-preview-target='testEmailInput']").value = "  "
    const fakeFetch = vi.fn()
    vi.stubGlobal("fetch", fakeFetch)

    await ctrl.sendTestEmail()

    expect(fakeFetch).not.toHaveBeenCalled()
    const statusEl = element.querySelector("[data-remote-template-preview-target='testStatus']")
    expect(statusEl.textContent).toContain("Please enter an email address")
    expect(statusEl.classList.contains("hidden")).toBe(false)
  })

  it("sends a test email successfully and displays the success alert with icon", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const fakeFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ success: true, message: "Email sent successfully!" })
    })
    vi.stubGlobal("fetch", fakeFetch)

    const preventDefault = vi.fn()
    await ctrl.sendTestEmail({ preventDefault })

    expect(preventDefault).toHaveBeenCalled()
    expect(fakeFetch).toHaveBeenCalledWith("/test_send", expect.any(Object))
    
    const statusEl = element.querySelector("[data-remote-template-preview-target='testStatus']")
    expect(statusEl.textContent).toContain("Email sent successfully!")
    expect(statusEl.classList.contains("bg-green-50")).toBe(true)
    expect(statusEl.classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-remote-template-preview-target='testEmailInput']").value).toBe("")
  })

  it("displays an error message when server-side test-send fails with explicit error", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const fakeFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ success: false, error: "Invalid email domain" })
    })
    vi.stubGlobal("fetch", fakeFetch)

    await ctrl.sendTestEmail()

    const statusEl = element.querySelector("[data-remote-template-preview-target='testStatus']")
    expect(statusEl.textContent).toContain("Invalid email domain")
    expect(statusEl.classList.contains("bg-red-50")).toBe(true)
  })

  it("escapes HTML in the loading label while preview is in flight", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")
    ctrl.loadingLabelValue = `<img src=x onerror=alert(1)>Loading`

    let resolveFetch
    vi.stubGlobal("fetch", vi.fn().mockReturnValue(new Promise((resolve) => { resolveFetch = resolve })))

    const pending = ctrl.loadPreview()
    const button = element.querySelector("[data-remote-template-preview-target='button']")
    expect(button.querySelector("img")).toBeNull()
    expect(button.innerHTML).toContain("&lt;img src=x onerror=alert(1)&gt;")

    resolveFetch({ ok: true, json: async () => ({ subject: "", body_html: "", body_text: "" }) })
    await pending
  })

  it("escapes HTML in the sending label while a test email is in flight", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")
    ctrl.sendingLabelValue = `<img src=x onerror=alert(1)>Sending`

    let resolveFetch
    vi.stubGlobal("fetch", vi.fn().mockReturnValue(new Promise((resolve) => { resolveFetch = resolve })))

    const pending = ctrl.sendTestEmail({ preventDefault() {} })
    const button = element.querySelector("[data-remote-template-preview-target='testSendButton']")
    expect(button.querySelector("img")).toBeNull()
    expect(button.innerHTML).toContain("&lt;img src=x onerror=alert(1)&gt;")

    resolveFetch({ ok: true, json: async () => ({ success: true, message: "ok" }) })
    await pending
  })

  it("escapes HTML in server test-send error messages", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const payload = `<img src=x onerror=alert(1)> is not a valid email address.`
    const fakeFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ success: false, error: payload })
    })
    vi.stubGlobal("fetch", fakeFetch)

    await ctrl.sendTestEmail()

    const statusEl = element.querySelector("[data-remote-template-preview-target='testStatus']")
    expect(statusEl.querySelector("img")).toBeNull()
    expect(statusEl.innerHTML).toContain("&lt;img src=x onerror=alert(1)&gt;")
  })

  it("displays a default error message when server-side test-send fails without explicit error", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const fakeFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ success: false })
    })
    vi.stubGlobal("fetch", fakeFetch)

    await ctrl.sendTestEmail()

    const statusEl = element.querySelector("[data-remote-template-preview-target='testStatus']")
    expect(statusEl.textContent).toContain("Failed to send test email")
    expect(statusEl.classList.contains("bg-red-50")).toBe(true)
  })

  it("displays network error sending test email on fetch exception", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const fakeFetch = vi.fn().mockRejectedValue(new Error("Timeout"))
    vi.stubGlobal("fetch", fakeFetch)

    await ctrl.sendTestEmail()

    const statusEl = element.querySelector("[data-remote-template-preview-target='testStatus']")
    expect(statusEl.textContent).toContain("Network error sending test email")
    expect(statusEl.classList.contains("bg-red-50")).toBe(true)
    expect(consoleErrorSpy).toHaveBeenCalled()
  })

  it("handles missing testStatus target when showing or clearing status", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, `
      <div data-controller="remote-template-preview">
        <input data-remote-template-preview-target="testEmailInput" value="test@test.com" />
        <button type="button" data-remote-template-preview-target="testSendButton">Send</button>
      </div>
    `)
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const fakeFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ success: true, message: "OK" })
    })
    vi.stubGlobal("fetch", fakeFetch)

    await expect(ctrl.sendTestEmail()).resolves.not.toThrow()
  })

  it("early exits in loadPreview if buttonTarget is missing", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, `
      <div data-controller="remote-template-preview"></div>
    `)
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const fakeFetch = vi.fn()
    vi.stubGlobal("fetch", fakeFetch)

    await ctrl.loadPreview()
    expect(fakeFetch).not.toHaveBeenCalled()
  })

  it("uses the CSRF token from meta tags if present on sendTestEmail", async () => {
    const meta = document.createElement("meta")
    meta.name = "csrf-token"
    meta.content = "my-special-csrf-token"
    document.head.appendChild(meta)

    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const fakeFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ success: true })
    })
    vi.stubGlobal("fetch", fakeFetch)

    await ctrl.sendTestEmail()

    expect(fakeFetch).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({
        headers: expect.objectContaining({
          "X-CSRF-Token": "my-special-csrf-token"
        })
      })
    )

    meta.remove()
  })

  it("reads activate-immediately checkbox status (not the Rails unchecked hidden field)", async () => {
    const checkboxHtml = `
<form data-controller="remote-template-preview"
      data-remote-template-preview-url-value="/preview"
      data-remote-template-preview-test-send-url-value="/test_send">
  <input name="email_template[status]" type="hidden" value="draft" />
  <input name="email_template[status]" type="checkbox" value="active" checked />
  <button type="button" data-remote-template-preview-target="button">Load</button>
</form>`
    const { application, element } = await mountController("remote-template-preview", Controller, checkboxHtml)
    const ctrl = controllerFor(application, element, "remote-template-preview")
    expect(ctrl.getFormData().email_template.status).toBe("active")

    element.querySelector('input[type="checkbox"]').checked = false
    expect(ctrl.getFormData().email_template.status).toBe("draft")
  })

  it("keeps the subject header visible when switching HTML/Text preview tabs", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")
    const subjectPane = element.querySelector("[data-remote-template-preview-target='subjectPane']")
    subjectPane.textContent = "Hello Alice"
    subjectPane.classList.remove("hidden")

    ctrl.showTab({
      preventDefault() {},
      currentTarget: element.querySelector("[data-remote-template-preview-target='tabText']")
    })

    expect(subjectPane.classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-remote-template-preview-target='htmlPane']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-remote-template-preview-target='textPane']").classList.contains("hidden")).toBe(false)
  })

  it("opens a full-page preview via POST without Rails _method override", async () => {
    const formHtml = `
<form method="post" action="/templates/1" data-controller="remote-template-preview"
      data-remote-template-preview-url-value="/templates/1/preview"
      data-remote-template-preview-test-send-url-value="/test_send">
  <input type="hidden" name="_method" value="patch" />
  <input name="email_template[subject]" value="Hi" />
  <select name="email_template[editor_type]"><option value="code" selected>Code</option></select>
  <textarea name="email_template[body_html]">&lt;p&gt;Hi&lt;/p&gt;</textarea>
  <button type="button" data-remote-template-preview-target="button">Load</button>
  <button type="button" data-action="click->remote-template-preview#openFullPagePreview">New Tab</button>
</form>`
    const { application, element } = await mountController("remote-template-preview", Controller, formHtml)
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const fakeFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ body_srcdoc: "<html><body>Preview</body></html>" })
    })
    vi.stubGlobal("fetch", fakeFetch)

    const iframe = { srcdoc: "" }
    const fakeDoc = {
      open: vi.fn(),
      write: vi.fn(),
      close: vi.fn(),
      querySelector: vi.fn().mockReturnValue(iframe)
    }
    const openSpy = vi.spyOn(window, "open").mockReturnValue({ document: fakeDoc })

    await ctrl.openFullPagePreview({ preventDefault() {} })

    expect(fakeFetch).toHaveBeenCalledWith(
      "/templates/1/preview?preview_mode=full_page",
      expect.objectContaining({
        method: "POST",
        headers: expect.objectContaining({ Accept: "application/json" })
      })
    )
    const body = JSON.parse(fakeFetch.mock.calls[0][1].body)
    expect(body._method).toBeUndefined()
    expect(body.email_template.subject).toBe("Hi")
    expect(openSpy).toHaveBeenCalled()
    expect(fakeDoc.write).toHaveBeenCalled()
    expect(fakeDoc.write.mock.calls[0][0]).toContain('sandbox=""')
    expect(fakeDoc.write.mock.calls[0][0]).not.toContain("Preview")
    expect(iframe.srcdoc).toBe("<html><body>Preview</body></html>")
  })

  it("wraps body_html when full-page preview JSON omits body_srcdoc", async () => {
    const formHtml = `
<form data-controller="remote-template-preview"
      data-remote-template-preview-url-value="/preview">
  <button type="button" data-remote-template-preview-target="button">Load</button>
</form>`
    const { application, element } = await mountController("remote-template-preview", Controller, formHtml)
    const ctrl = controllerFor(application, element, "remote-template-preview")
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ body_html: "<p>Fallback</p>" })
    }))
    const iframe = { srcdoc: "" }
    vi.spyOn(window, "open").mockReturnValue({
      document: {
        open: vi.fn(),
        write: vi.fn(),
        close: vi.fn(),
        querySelector: vi.fn().mockReturnValue(iframe)
      }
    })

    await ctrl.openFullPagePreview({ preventDefault() {} })

    expect(iframe.srcdoc).toContain("<p>Fallback</p>")
    expect(iframe.srcdoc).toContain("<!DOCTYPE html>")
  })

  it("wraps an empty document when full-page preview JSON has no HTML", async () => {
    const formHtml = `
<form data-controller="remote-template-preview"
      data-remote-template-preview-url-value="/preview">
  <button type="button" data-remote-template-preview-target="button">Load</button>
</form>`
    const { application, element } = await mountController("remote-template-preview", Controller, formHtml)
    const ctrl = controllerFor(application, element, "remote-template-preview")
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({})
    }))
    const iframe = { srcdoc: "" }
    vi.spyOn(window, "open").mockReturnValue({
      document: {
        open: vi.fn(),
        write: vi.fn(),
        close: vi.fn(),
        querySelector: vi.fn().mockReturnValue(iframe)
      }
    })

    await ctrl.openFullPagePreview({ preventDefault() {} })

    expect(iframe.srcdoc).toContain("<!DOCTYPE html>")
  })

  it("reports a blocked full-page preview popup and preserves existing query parameters", async () => {
    const meta = document.createElement("meta")
    meta.name = "csrf-token"
    meta.content = "full-page-token"
    document.head.appendChild(meta)

    const formHtml = `
      <form data-controller="remote-template-preview"
            data-remote-template-preview-url-value="/preview?draft=1">
        <button type="button" data-remote-template-preview-target="button">Load</button>
      </form>`
    const { application, element } = await mountController("remote-template-preview", Controller, formHtml)
    const ctrl = controllerFor(application, element, "remote-template-preview")
    const fakeFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ body_srcdoc: "<html></html>" })
    })
    vi.stubGlobal("fetch", fakeFetch)
    vi.spyOn(window, "open").mockReturnValue(null)

    await ctrl.openFullPagePreview()

    expect(fakeFetch).toHaveBeenCalledWith(
      "/preview?draft=1&preview_mode=full_page",
      expect.objectContaining({
        headers: expect.objectContaining({ "X-CSRF-Token": "full-page-token" })
      })
    )
    expect(globalThis.alert).toHaveBeenCalledWith("Unable to open preview tab (popup blocked?)")
    meta.remove()
  })

  it("reports full-page preview request failures, including an empty preview URL", async () => {
    const { application, element } = await mountController(
      "remote-template-preview",
      Controller,
      `<form data-controller="remote-template-preview"></form>`
    )
    const ctrl = controllerFor(application, element, "remote-template-preview")
    const fakeFetch = vi.fn().mockResolvedValue({ ok: false })
    vi.stubGlobal("fetch", fakeFetch)

    await ctrl.openFullPagePreview()

    expect(fakeFetch).toHaveBeenCalledWith("", expect.any(Object))
    expect(consoleErrorSpy).toHaveBeenCalled()
    expect(globalThis.alert).toHaveBeenCalledWith("Error loading preview")
  })
})
