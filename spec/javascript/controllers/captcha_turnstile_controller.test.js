import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/captcha_turnstile_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

// The controller loads a remote SDK script and stores window.turnstile.
// We pre-populate window.turnstile so loadCaptchaSdk() resolves synchronously
// (Promise.resolve path) and never injects a <script> tag — the network path
// is Tier C / Playwright.
const html = (overrides = "") => `
  <form>
    <div data-controller="captcha-turnstile"
         data-captcha-turnstile-site-key-value="site-key-1"
         data-captcha-turnstile-sdk-url-value="about:blank"
         ${overrides}>
      <div data-captcha-turnstile-target="mount"></div>
      <input type="hidden" data-captcha-turnstile-target="input">
    </div>
    <button type="submit">Go</button>
  </form>`

const flush = () => new Promise((r) => setTimeout(r, 0))

describe("captcha-turnstile controller", () => {
  let render
  let remove
  beforeEach(() => {
    render = vi.fn().mockReturnValue("widget-id-1")
    remove = vi.fn()
    window.turnstile = { render, remove }
  })
  afterEach(() => {
    delete window.turnstile
    vi.restoreAllMocks()
  })

  it("renders the widget on connect, disables submit, and passes the sitekey + callbacks", async () => {
    const { element } = await mountController("captcha-turnstile", Controller, html())
    await flush()
    expect(render).toHaveBeenCalledOnce()
    const [mountEl, cfg] = render.mock.calls[0]
    expect(mountEl).toBe(element.querySelector("[data-captcha-turnstile-target='mount']"))
    expect(cfg.sitekey).toBe("site-key-1")
    expect(typeof cfg.callback).toBe("function")
    expect(typeof cfg["error-callback"]).toBe("function")
    expect(typeof cfg["expired-callback"]).toBe("function")
    expect(document.querySelector("button[type='submit']").disabled).toBe(true)
  })

  it("callback writes the token into the input target and re-enables submit", async () => {
    const { element } = await mountController("captcha-turnstile", Controller, html())
    await flush()
    const submit = document.querySelector("button[type='submit']")
    render.mock.calls[0][1].callback("TOKEN-XYZ")
    expect(element.querySelector("[data-captcha-turnstile-target='input']").value).toBe("TOKEN-XYZ")
    expect(submit.disabled).toBe(false)
  })

  it("callback defaults a falsy token to an empty string", async () => {
    const { element } = await mountController("captcha-turnstile", Controller, html())
    await flush()
    render.mock.calls[0][1].callback(undefined)
    expect(element.querySelector("[data-captcha-turnstile-target='input']").value).toBe("")
  })

  it("error-callback clears the input and disables submit", async () => {
    const { element } = await mountController("captcha-turnstile", Controller, html())
    await flush()
    const submit = document.querySelector("button[type='submit']")
    // First succeed so we can observe the failure path actually clears state.
    render.mock.calls[0][1].callback("TOKEN-XYZ")
    expect(submit.disabled).toBe(false)

    render.mock.calls[0][1]["error-callback"]()
    expect(element.querySelector("[data-captcha-turnstile-target='input']").value).toBe("")
    expect(submit.disabled).toBe(true)
  })

  it("expired-callback clears the input and disables submit", async () => {
    const { element } = await mountController("captcha-turnstile", Controller, html())
    await flush()
    render.mock.calls[0][1]["expired-callback"]()
    expect(element.querySelector("[data-captcha-turnstile-target='input']").value).toBe("")
    expect(document.querySelector("button[type='submit']").disabled).toBe(true)
  })

  it("tolerates a missing submit button (no wrapping form) for render and callbacks", async () => {
    const htmlNoForm = `
      <div data-controller="captcha-turnstile"
           data-captcha-turnstile-site-key-value="site-key-1"
           data-captcha-turnstile-sdk-url-value="about:blank">
        <div data-captcha-turnstile-target="mount"></div>
        <input type="hidden" data-captcha-turnstile-target="input">
      </div>`
    const { element } = await mountController("captcha-turnstile", Controller, htmlNoForm)
    await flush()
    expect(render).toHaveBeenCalledOnce()
    expect(() => render.mock.calls[0][1].callback("TOKEN")).not.toThrow()
    expect(element.querySelector("[data-captcha-turnstile-target='input']").value).toBe("TOKEN")
    expect(() => render.mock.calls[0][1]["error-callback"]()).not.toThrow()
  })

  it("tolerates a missing input target", async () => {
    const htmlNoInput = `
      <form>
        <div data-controller="captcha-turnstile"
             data-captcha-turnstile-site-key-value="site-key-1"
             data-captcha-turnstile-sdk-url-value="about:blank">
          <div data-captcha-turnstile-target="mount"></div>
        </div>
        <button type="submit">Go</button>
      </form>`
    await mountController("captcha-turnstile", Controller, htmlNoInput)
    await flush()
    const submit = document.querySelector("button[type='submit']")
    expect(() => render.mock.calls[0][1].callback("TOKEN")).not.toThrow()
    expect(submit.disabled).toBe(false)
  })

  it("falls back to the default Cloudflare SDK URL when sdk-url value is blank", async () => {
    const htmlNoUrl = `
      <div data-controller="captcha-turnstile"
           data-captcha-turnstile-site-key-value="site-key-1">
        <div data-captcha-turnstile-target="mount"></div>
      </div>`
    await mountController("captcha-turnstile", Controller, htmlNoUrl)
    await flush()
    // window.turnstile is already present (set in beforeEach), so loadCaptchaSdk
    // resolves via the synchronous branch regardless of which URL was computed —
    // this exercises the `this.sdkUrlValue || <default>` false side without
    // ever touching the network / script tag.
    expect(render).toHaveBeenCalledOnce()
  })

  it("render() returns early when window.turnstile is unset", async () => {
    const { application, element } = await mountController("captcha-turnstile", Controller, html())
    await flush()
    const controller = controllerFor(application, element, "captcha-turnstile")
    delete window.turnstile
    expect(() => controller.render()).not.toThrow()
    expect(render).toHaveBeenCalledOnce() // no additional render call from the early-return render()
  })

  it("render() returns early when there is no mount target", async () => {
    const htmlNoMount = `
      <div data-controller="captcha-turnstile"
           data-captcha-turnstile-site-key-value="site-key-1">
      </div>`
    const { application, element } = await mountController("captcha-turnstile", Controller, htmlNoMount)
    await flush()
    const controller = controllerFor(application, element, "captcha-turnstile")
    expect(() => controller.render()).not.toThrow()
  })

  it("disconnect() removes the widget when it was rendered and turnstile.remove is available", async () => {
    const { application, element } = await mountController("captcha-turnstile", Controller, html())
    await flush()
    const controller = controllerFor(application, element, "captcha-turnstile")
    controller.disconnect()
    expect(remove).toHaveBeenCalledWith("widget-id-1")
  })

  it("disconnect() is a no-op when the widget was never rendered", async () => {
    const { application, element } = await mountController("captcha-turnstile", Controller, html())
    await flush()
    const controller = controllerFor(application, element, "captcha-turnstile")
    delete window.turnstile
    expect(() => controller.disconnect()).not.toThrow()
    expect(remove).not.toHaveBeenCalled()
  })

  it("disconnect() is a no-op when turnstile has no remove method", async () => {
    const { application, element } = await mountController("captcha-turnstile", Controller, html())
    await flush()
    const controller = controllerFor(application, element, "captcha-turnstile")
    window.turnstile = { render }
    expect(() => controller.disconnect()).not.toThrow()
  })

  // happy-dom actually attempts to fetch a <script src> as soon as it is
  // connected to the document, which races with (and clobbers) our manual
  // onload/onerror simulation below. Spy on document.head.appendChild and
  // capture the element WITHOUT actually attaching it to the live document,
  // so we can drive the script's onload/onerror callbacks ourselves.
  function interceptAppendedScripts() {
    const scripts = []
    vi.spyOn(document.head, "appendChild").mockImplementation((el) => {
      scripts.push(el)
      return el
    })
    return scripts
  }

  it("loads the SDK via a script tag when window.turnstile is absent, and resolves render() on load", async () => {
    vi.resetModules()
    const { default: FreshController } = await import("controllers/captcha_turnstile_controller")
    delete window.turnstile
    const scripts = interceptAppendedScripts()

    await mountController("captcha-turnstile", FreshController, html())
    expect(scripts.length).toBe(1)

    const freshRender = vi.fn().mockReturnValue("id")
    window.turnstile = { render: freshRender }
    scripts[0].onload()
    await flush()
    expect(freshRender).toHaveBeenCalledOnce()
  })

  it("caches the in-flight SDK promise so a second connect does not inject another script tag", async () => {
    vi.resetModules()
    const { default: FreshController } = await import("controllers/captcha_turnstile_controller")
    delete window.turnstile
    const scripts = interceptAppendedScripts()

    // First connect: no window.turnstile, no in-flight promise yet — creates one script.
    await mountController("captcha-turnstile", FreshController, html())
    // Second connect: window.turnstile still absent, but the in-flight promise
    // from the first connect is cached in the shared loader — must NOT create
    // a second script.
    await mountController("captcha-turnstile", FreshController, html())
    expect(scripts.length).toBe(1)
  })

  it("warns when the SDK script fails to load", async () => {
    vi.resetModules()
    const { default: FreshController } = await import("controllers/captcha_turnstile_controller")
    delete window.turnstile
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {})
    const scripts = interceptAppendedScripts()

    await mountController("captcha-turnstile", FreshController, html())
    scripts[0].onerror()
    await flush()
    expect(warn).toHaveBeenCalledWith("[captcha-turnstile]", expect.any(Error))
  })
})
