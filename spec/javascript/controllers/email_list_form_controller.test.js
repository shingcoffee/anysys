import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/email_list_form_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

// Mounted on a <div> rather than <form> — happy-dom's HTMLFormElement.contains()
// breaks Stimulus action binding inside form roots (same pattern as
// email_credential_form_controller.test.js).
const html = (listType = "dynamic", options = {}) => `
  <div data-controller="email-list-form"
       data-email-list-form-list-type-value="${listType}"
       data-email-list-form-preview-url-value="${options.previewUrl ?? "/cid/admin/modules/emails/lists/preview"}"
       data-email-list-form-loading-label-value="Loading…">
    <select data-action="change->email-list-form#toggle" data-role="list-type">
      <option value="static" ${listType === "static" ? "selected" : ""}>Static</option>
      <option value="dynamic" ${listType === "dynamic" ? "selected" : ""}>Dynamic</option>
    </select>
    <div data-email-list-form-target="panel" data-list-type="static" class="${listType === "static" ? "" : "hidden"}">static</div>
    <div data-email-list-form-target="panel" data-list-type="dynamic" class="${listType === "dynamic" ? "" : "hidden"}">
      ${options.liveRules === false ? "" : `<input type="hidden" name="email_list[segment_rules_json]" value='{"type":"group","joins":[],"conditions":[]}' data-role="rules">`}
      ${options.previewRules ? `<input type="hidden" value='{"type":"stale"}' data-email-list-form-target="previewRules">` : ""}
      ${options.button === false ? "" : `<button type="button" data-email-list-form-target="previewButton" data-action="email-list-form#preview">Preview</button>`}
    </div>
    ${options.modal === false ? "" : `
      <div data-email-list-form-target="previewModal" class="hidden" data-role="preview-modal">
        ${options.frame === false ? "" : `<turbo-frame id="email_list_preview" data-email-list-form-target="previewFrame"><p data-role="hint">hint</p></turbo-frame>`}
      </div>`}
  </div>`

const panel = (element, type) =>
  element.querySelector(`[data-email-list-form-target="panel"][data-list-type="${type}"]`)

const response = (html, ok = true) => ({ ok, status: ok ? 200 : 422, text: async () => html })

const previewCalls = (fetchMock) =>
  fetchMock.mock.calls.filter(([url]) => String(url).includes("/lists/preview"))

describe("email-list-form controller", () => {
  let application, element, ctrl

  beforeEach(async () => {
    ;({ application, element } = await mountController("email-list-form", Controller, html()))
    ctrl = controllerFor(application, element, "email-list-form")
  })

  afterEach(() => {
    vi.restoreAllMocks()
    document.head.innerHTML = ""
  })

  it("shows only the dynamic panel on connect by default", () => {
    expect(panel(element, "static").classList.contains("hidden")).toBe(true)
    expect(panel(element, "dynamic").classList.contains("hidden")).toBe(false)
  })

  it("shows only the static panel when listType value is static", async () => {
    ;({ application, element } = await mountController("email-list-form", Controller, html("static")))
    expect(panel(element, "static").classList.contains("hidden")).toBe(false)
    expect(panel(element, "dynamic").classList.contains("hidden")).toBe(true)
  })

  it("toggles panels when toggle is invoked with a select change", () => {
    const select = element.querySelector('[data-role="list-type"]')
    select.value = "static"
    ctrl.toggle({ target: select })

    expect(panel(element, "static").classList.contains("hidden")).toBe(false)
    expect(panel(element, "dynamic").classList.contains("hidden")).toBe(true)
  })

  it("toggles back to dynamic", () => {
    ctrl.toggle({ target: { value: "static" } })
    ctrl.toggle({ target: { value: "dynamic" } })

    expect(panel(element, "static").classList.contains("hidden")).toBe(true)
    expect(panel(element, "dynamic").classList.contains("hidden")).toBe(false)
  })

  it("POSTs live segment rules to previewUrl and opens the preview modal", async () => {
    const fetchMock = vi.fn().mockResolvedValue(response(
      `<turbo-frame id="email_list_preview"><p>matched</p></turbo-frame>`
    ))
    vi.stubGlobal("fetch", fetchMock)
    document.head.innerHTML = `<meta name="csrf-token" content="token">`
    const frame = element.querySelector("#email_list_preview")
    const modal = element.querySelector('[data-role="preview-modal"]')

    await ctrl.preview({ preventDefault: vi.fn() })

    const calls = previewCalls(fetchMock)
    expect(calls).toHaveLength(1)
    const [url, options] = calls[0]
    expect(url).toContain("/lists/preview")
    expect(options.method).toBe("POST")
    expect(options.headers["Turbo-Frame"]).toBe("email_list_preview")
    expect(options.headers["X-CSRF-Token"]).toBe("token")
    expect(options.body.get("segment_rules_json")).toContain("group")
    expect(options.body.get("page")).toBe("1")
    expect(element.querySelector("#email_list_preview")).toBe(frame)
    expect(frame.innerHTML).toContain("matched")
    expect(modal.classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-email-list-form-target='previewButton']").disabled).toBe(false)
    expect(element.querySelector("[data-email-list-form-target='previewButton']").textContent).toBe("Preview")
  })

  it("closes the preview modal", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(response(
      `<turbo-frame id="email_list_preview"><p>matched</p></turbo-frame>`
    )))
    await ctrl.preview()
    const modal = element.querySelector('[data-role="preview-modal"]')
    expect(modal.classList.contains("hidden")).toBe(false)

    ctrl.closePreview({ preventDefault: vi.fn() })

    expect(modal.classList.contains("hidden")).toBe(true)
  })

  it("prefers live builder rules over a previewRules target", async () => {
    ;({ application, element } = await mountController("email-list-form", Controller, html("dynamic", { previewRules: true })))
    ctrl = controllerFor(application, element, "email-list-form")
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(response(
      `<turbo-frame id="email_list_preview"><p>matched</p></turbo-frame>`
    )))

    await ctrl.preview()

    expect(previewCalls(fetch)[0][1].body.get("segment_rules_json")).toContain("group")
  })

  it("POSTs the selected page from previewPage with an empty CSRF token", async () => {
    const fetchMock = vi.fn().mockResolvedValue(response(
      `<turbo-frame id="email_list_preview"><p>page 2</p></turbo-frame>`
    ))
    vi.stubGlobal("fetch", fetchMock)

    await ctrl.previewPage({ preventDefault: vi.fn(), params: { page: "2" }, target: { dataset: { page: "3" } } })

    const options = previewCalls(fetchMock)[0][1]
    expect(options.body.get("page")).toBe("2")
    expect(options.headers["X-CSRF-Token"]).toBe("")
    expect(element.querySelector("#email_list_preview").innerHTML).toContain("page 2")
  })

  it("uses the target page when previewPage receives no action params", async () => {
    const fetchMock = vi.fn().mockResolvedValue(response(
      `<turbo-frame id="email_list_preview"><p>page 4</p></turbo-frame>`
    ))
    vi.stubGlobal("fetch", fetchMock)

    await ctrl.previewPage({ target: { dataset: { page: "4" } } })

    expect(previewCalls(fetchMock)[0][1].body.get("page")).toBe("4")
  })

  it("defaults previewPage to the first page when no event is provided", async () => {
    const fetchMock = vi.fn().mockResolvedValue(response(
      `<turbo-frame id="email_list_preview"><p>page 1</p></turbo-frame>`
    ))
    vi.stubGlobal("fetch", fetchMock)

    await ctrl.previewPage()

    expect(previewCalls(fetchMock)[0][1].body.get("page")).toBe("1")
  })

  it("uses the pagination link page and POSTs it into the preview frame", async () => {
    const fetchMock = vi.fn().mockResolvedValue(response(
      `<turbo-frame id="email_list_preview"><p>page 3</p></turbo-frame>`
    ))
    vi.stubGlobal("fetch", fetchMock)
    const link = document.createElement("a")
    link.href = "https://example.test/lists/preview?page=3"
    element.querySelector("#email_list_preview").append(link)
    const preventDefault = vi.fn()

    await ctrl.interceptPreviewNav({ target: link, preventDefault })

    expect(preventDefault).toHaveBeenCalled()
    expect(previewCalls(fetchMock)[0][1].body.get("page")).toBe("3")
  })

  it("does not intercept links outside the preview frame", () => {
    const link = document.createElement("a")
    link.href = "https://example.test/lists/preview?page=3"
    element.append(link)
    const preventDefault = vi.fn()

    ctrl.interceptPreviewNav({ target: link, preventDefault })

    expect(preventDefault).not.toHaveBeenCalled()
  })

  it("does not intercept events that do not originate from a link", () => {
    const preventDefault = vi.fn()

    ctrl.interceptPreviewNav({ target: {}, preventDefault })

    expect(preventDefault).not.toHaveBeenCalled()
  })

  it("uses page one when pagination link omits page", async () => {
    const fetchMock = vi.fn().mockResolvedValue(response(
      `<turbo-frame id="email_list_preview"><p>first page</p></turbo-frame>`
    ))
    vi.stubGlobal("fetch", fetchMock)
    const link = document.createElement("a")
    link.href = "https://example.test/lists/preview"
    element.querySelector("#email_list_preview").append(link)

    await ctrl.interceptPreviewNav({ target: link, preventDefault: vi.fn() })

    expect(previewCalls(fetchMock)[0][1].body.get("page")).toBe("1")
  })

  it("replaces the frame with returned non-OK response HTML", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(response(
      `<turbo-frame id="email_list_preview"><p>malformed</p></turbo-frame>`, false
    )))

    await ctrl.preview()

    expect(element.querySelector("#email_list_preview").innerHTML).toContain("malformed")
  })

  it("loads a preview when the optional preview button is absent", async () => {
    const fetchMock = vi.fn().mockResolvedValue(response(
      `<turbo-frame id="email_list_preview"><p>matched</p></turbo-frame>`
    ))
    vi.stubGlobal("fetch", fetchMock)
    const mounted = await mountController("email-list-form", Controller, html("dynamic", { button: false }))

    await controllerFor(mounted.application, mounted.element, "email-list-form").preview()

    expect(previewCalls(fetchMock)).toHaveLength(1)
    expect(mounted.element.querySelector("#email_list_preview").innerHTML).toContain("matched")
  })

  it("does not fetch when the preview URL or frame is unavailable", async () => {
    const fetchMock = vi.fn()
    vi.stubGlobal("fetch", fetchMock)
    const first = await mountController("email-list-form", Controller, html("dynamic", { previewUrl: "" }))
    const second = await mountController("email-list-form", Controller, html("dynamic", { frame: false }))

    await controllerFor(first.application, first.element, "email-list-form").preview()
    await controllerFor(second.application, second.element, "email-list-form").preview()

    expect(previewCalls(fetchMock)).toHaveLength(0)
  })

  it("uses preview rules or an empty object when no live builder input exists", async () => {
    const fetchMock = vi.fn().mockResolvedValue(response(
      `<turbo-frame id="email_list_preview"><p>matched</p></turbo-frame>`
    ))
    vi.stubGlobal("fetch", fetchMock)
    const withPreviewRules = await mountController(
      "email-list-form", Controller, html("dynamic", { liveRules: false, previewRules: true })
    )
    const withoutRules = await mountController(
      "email-list-form", Controller, html("dynamic", { liveRules: false })
    )

    await controllerFor(withPreviewRules.application, withPreviewRules.element, "email-list-form").preview()
    await controllerFor(withoutRules.application, withoutRules.element, "email-list-form").preview()

    const calls = previewCalls(fetchMock)
    expect(calls[0][1].body.get("segment_rules_json")).toContain("stale")
    expect(calls[1][1].body.get("segment_rules_json")).toBe("{}")
  })

  it("leaves the frame unchanged when response omits its turbo frame", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(response("<p>not a frame</p>")))

    await ctrl.preview()

    expect(element.querySelector("#email_list_preview").innerHTML).toContain("hint")
  })

  it("closePreview is a no-op when the modal target is absent", async () => {
    const mounted = await mountController("email-list-form", Controller, html("dynamic", { modal: false, frame: false }))
    expect(() => {
      controllerFor(mounted.application, mounted.element, "email-list-form").closePreview()
    }).not.toThrow()
  })

  it("closes the modal on Escape and cleans up on disconnect", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(response(
      `<turbo-frame id="email_list_preview"><p>matched</p></turbo-frame>`
    )))
    await ctrl.preview()
    const modal = element.querySelector('[data-role="preview-modal"]')
    expect(modal.classList.contains("hidden")).toBe(false)

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }))
    expect(modal.classList.contains("hidden")).toBe(true)

    await ctrl.preview()
    expect(modal.classList.contains("hidden")).toBe(false)
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" }))
    expect(modal.classList.contains("hidden")).toBe(false)
    ctrl.disconnect()
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }))
    // After disconnect, Escape listener is removed — modal stays open
    expect(modal.classList.contains("hidden")).toBe(false)
  })

  it("opens preview with a frame but no modal shell", async () => {
    const markup = `
      <div data-controller="email-list-form"
           data-email-list-form-list-type-value="dynamic"
           data-email-list-form-preview-url-value="/cid/admin/modules/emails/lists/preview">
        <input type="hidden" name="email_list[segment_rules_json]" value='{}'>
        <turbo-frame id="email_list_preview" data-email-list-form-target="previewFrame"><p>hint</p></turbo-frame>
      </div>`
    const fetchMock = vi.fn().mockResolvedValue(response(
      `<turbo-frame id="email_list_preview"><p>matched</p></turbo-frame>`
    ))
    vi.stubGlobal("fetch", fetchMock)
    const mounted = await mountController("email-list-form", Controller, markup)

    await controllerFor(mounted.application, mounted.element, "email-list-form").preview()

    expect(previewCalls(fetchMock)).toHaveLength(1)
    expect(mounted.element.querySelector("#email_list_preview").innerHTML).toContain("matched")
  })
})
