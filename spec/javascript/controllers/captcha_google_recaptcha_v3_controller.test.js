import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/captcha_google_recaptcha_v3_controller"
import { _resetForTests } from "lib/captcha_sdk_loader"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = (overrides = "") => `
  <form>
    <div data-controller="captcha-google-recaptcha-v3"
         data-captcha-google-recaptcha-v3-site-key-value="site-key-1"
         ${overrides}>
      <div data-captcha-google-recaptcha-v3-target="mount">
        <p>Loading...</p>
      </div>
      <input type="hidden" data-captcha-google-recaptcha-v3-target="input">
    </div>
    <button type="submit">Go</button>
  </form>`

const flush = () => new Promise((r) => setTimeout(r, 0))

// happy-dom attempts to fetch a newly appended <script> immediately. Capture the
// element without attaching it so we can drive onload/onerror manually.
function interceptAppendedScripts() {
  const scripts = []
  vi.spyOn(document.head, "appendChild").mockImplementation((el) => {
    scripts.push(el)
    return el
  })
  return scripts
}

describe("captcha-google-recaptcha-v3 controller", () => {
  let executeMock
  let readyMock

  beforeEach(() => {
    executeMock = vi.fn().mockResolvedValue("TOKEN-XYZ")
    readyMock = vi.fn((cb) => cb())
    window.grecaptcha = { execute: executeMock, ready: readyMock }
  })

  afterEach(() => {
    delete window.grecaptcha
    _resetForTests()
    vi.restoreAllMocks()
  })

  it("loads the SDK on connect and clears the mount target, but does not fetch a token", async () => {
    delete window.grecaptcha
    const scripts = interceptAppendedScripts()

    const { element } = await mountController("captcha-google-recaptcha-v3", Controller, html())

    expect(element.querySelector("[data-captcha-google-recaptcha-v3-target='mount']").textContent).toBe("")

    expect(scripts).toHaveLength(1)
    expect(scripts[0].src).toBe("https://www.google.com/recaptcha/api.js")

    window.grecaptcha = { execute: executeMock, ready: readyMock }
    scripts[0].onload()
    await flush()

    expect(executeMock).not.toHaveBeenCalled()
    expect(element.querySelector("[data-captcha-google-recaptcha-v3-target='mount']").textContent).toBe("")
  })

  it("fetches a token on form submit, writes it to the input, and dispatches a real submit event", async () => {
    const { element } = await mountController("captcha-google-recaptcha-v3", Controller, html())
    await flush()

    const form = document.querySelector("form")
    const submit = document.querySelector("button[type='submit']")
    const submitSpy = vi.spyOn(form, "requestSubmit").mockImplementation(() => {})

    form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
    expect(submit.disabled).toBe(true)

    await flush()

    expect(readyMock).toHaveBeenCalledOnce()
    expect(executeMock).toHaveBeenCalledWith("site-key-1", { action: "submit" })
    expect(element.querySelector("[data-captcha-google-recaptcha-v3-target='input']").value).toBe("TOKEN-XYZ")
    expect(submitSpy).toHaveBeenCalledOnce()
  })

  it("does not recurse when requestSubmit dispatches a submit event", async () => {
    const { element } = await mountController("captcha-google-recaptcha-v3", Controller, html())
    await flush()

    const form = document.querySelector("form")
    let requestSubmitCallCount = 0
    vi.spyOn(form, "requestSubmit").mockImplementation(() => {
      requestSubmitCallCount++
      // requestSubmit dispatches a real submit event in the browser. Simulate
      // that so we can prove the controller unbinds itself before re-dispatching.
      form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
    })

    form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
    await flush()

    expect(requestSubmitCallCount).toBe(1)
    expect(executeMock).toHaveBeenCalledOnce()
    expect(element.querySelector("[data-captcha-google-recaptcha-v3-target='input']").value).toBe("TOKEN-XYZ")
  })

  it("defaults a falsy token to an empty string", async () => {
    executeMock.mockResolvedValue("")
    const { element } = await mountController("captcha-google-recaptcha-v3", Controller, html())
    await flush()

    const form = document.querySelector("form")
    vi.spyOn(form, "requestSubmit").mockImplementation(() => {})
    form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
    await flush()

    expect(element.querySelector("[data-captcha-google-recaptcha-v3-target='input']").value).toBe("")
  })

  it("re-enables submit and logs a warning when token fetching fails", async () => {
    executeMock.mockRejectedValue(new Error("API Error"))
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {})

    const { element } = await mountController("captcha-google-recaptcha-v3", Controller, html())
    await flush()

    const form = document.querySelector("form")
    const submit = document.querySelector("button[type='submit']")
    const submitSpy = vi.spyOn(form, "requestSubmit").mockImplementation(() => {})

    form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
    await flush()

    expect(warn).toHaveBeenCalledWith("[captcha-google-recaptcha-v3]", expect.any(Error))
    expect(submitSpy).not.toHaveBeenCalled()
    expect(submit.disabled).toBe(false)
  })

  it("warns and does not lock the form when the SDK fails to load", async () => {
    delete window.grecaptcha
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {})
    const scripts = interceptAppendedScripts()

    await mountController("captcha-google-recaptcha-v3", Controller, html())
    scripts[0].onerror()
    await flush()

    expect(warn).toHaveBeenCalledWith("[captcha-google-recaptcha-v3]", expect.any(Error))
    expect(document.querySelector("button[type='submit']").disabled).toBe(false)
  })

  it("uses the provider-supplied sdk-url value when present", async () => {
    delete window.grecaptcha
    const scripts = interceptAppendedScripts()
    const customUrl = "about:blank"

    await mountController(
      "captcha-google-recaptcha-v3",
      Controller,
      html(`data-captcha-google-recaptcha-v3-sdk-url-value="${customUrl}"`)
    )

    expect(scripts).toHaveLength(1)
    expect(scripts[0].src).toBe(customUrl)
  })

  it("tolerates a missing mount target", async () => {
    const htmlNoMount = `
      <form>
        <div data-controller="captcha-google-recaptcha-v3"
             data-captcha-google-recaptcha-v3-site-key-value="site-key-1">
          <input type="hidden" data-captcha-google-recaptcha-v3-target="input">
        </div>
        <button type="submit">Go</button>
      </form>`

    const { element } = await mountController("captcha-google-recaptcha-v3", Controller, htmlNoMount)
    await flush()

    const form = document.querySelector("form")
    const submitSpy = vi.spyOn(form, "requestSubmit").mockImplementation(() => {})
    form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
    await flush()

    expect(executeMock).toHaveBeenCalledOnce()
    expect(submitSpy).toHaveBeenCalledOnce()
    expect(element.querySelector("[data-captcha-google-recaptcha-v3-target='input']").value).toBe("TOKEN-XYZ")
  })

  it("tolerates a missing input target", async () => {
    const htmlNoInput = `
      <form>
        <div data-controller="captcha-google-recaptcha-v3"
             data-captcha-google-recaptcha-v3-site-key-value="site-key-1">
          <div data-captcha-google-recaptcha-v3-target="mount"></div>
        </div>
        <button type="submit">Go</button>
      </form>`

    await mountController("captcha-google-recaptcha-v3", Controller, htmlNoInput)
    await flush()

    const form = document.querySelector("form")
    const submitSpy = vi.spyOn(form, "requestSubmit").mockImplementation(() => {})
    expect(() => {
      form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
    }).not.toThrow()
    await flush()

    expect(executeMock).toHaveBeenCalledOnce()
    expect(submitSpy).toHaveBeenCalledOnce()
  })

  it("tolerates a missing form", async () => {
    delete window.grecaptcha
    const scripts = interceptAppendedScripts()

    const htmlNoForm = `
      <div data-controller="captcha-google-recaptcha-v3"
           data-captcha-google-recaptcha-v3-site-key-value="site-key-1">
        <div data-captcha-google-recaptcha-v3-target="mount"></div>
        <input type="hidden" data-captcha-google-recaptcha-v3-target="input">
      </div>`

    const { application, element } = await mountController("captcha-google-recaptcha-v3", Controller, htmlNoForm)

    window.grecaptcha = { execute: executeMock, ready: readyMock }
    scripts[0].onload()
    await flush()

    expect(executeMock).not.toHaveBeenCalled()
    expect(element.querySelector("[data-captcha-google-recaptcha-v3-target='mount']").textContent).toBe("")

    const controller = controllerFor(application, element, "captcha-google-recaptcha-v3")
    expect(() => controller.disconnect()).not.toThrow()
  })

  it("tolerates a missing submit button", async () => {
    const htmlNoButton = `
      <form>
        <div data-controller="captcha-google-recaptcha-v3"
             data-captcha-google-recaptcha-v3-site-key-value="site-key-1">
          <div data-captcha-google-recaptcha-v3-target="mount"></div>
          <input type="hidden" data-captcha-google-recaptcha-v3-target="input">
        </div>
      </form>`

    const { element } = await mountController("captcha-google-recaptcha-v3", Controller, htmlNoButton)
    await flush()

    const form = document.querySelector("form")
    const submitSpy = vi.spyOn(form, "requestSubmit").mockImplementation(() => {})
    form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
    await flush()

    expect(executeMock).toHaveBeenCalledOnce()
    expect(submitSpy).toHaveBeenCalledOnce()
    expect(element.querySelector("[data-captcha-google-recaptcha-v3-target='input']").value).toBe("TOKEN-XYZ")
  })

  it("removes the submit listener on disconnect", async () => {
    const { application, element } = await mountController("captcha-google-recaptcha-v3", Controller, html())
    await flush()

    const controller = controllerFor(application, element, "captcha-google-recaptcha-v3")
    controller.disconnect()

    const form = document.querySelector("form")
    form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
    await flush()

    expect(executeMock).not.toHaveBeenCalled()
  })

  it("rejects fetchToken when the SDK is not ready", async () => {
    const { application, element } = await mountController("captcha-google-recaptcha-v3", Controller, html())
    await flush()

    const controller = controllerFor(application, element, "captcha-google-recaptcha-v3")
    delete window.grecaptcha

    await expect(controller.fetchToken()).rejects.toThrow("reCAPTCHA SDK is not ready")
  })

  it("returns null from submitButton when there is no form", async () => {
    const htmlNoForm = `
      <div data-controller="captcha-google-recaptcha-v3"
           data-captcha-google-recaptcha-v3-site-key-value="site-key-1">
        <div data-captcha-google-recaptcha-v3-target="mount"></div>
        <input type="hidden" data-captcha-google-recaptcha-v3-target="input">
      </div>`

    const { application, element } = await mountController("captcha-google-recaptcha-v3", Controller, htmlNoForm)
    await flush()

    const controller = controllerFor(application, element, "captcha-google-recaptcha-v3")
    expect(controller.submitButton).toBeNull()
  })
})
