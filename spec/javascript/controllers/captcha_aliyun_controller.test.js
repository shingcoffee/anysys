import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/captcha_aliyun_controller"
import { loadCaptchaSdk } from "lib/captcha_sdk_loader"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

vi.mock("lib/captcha_sdk_loader", () => ({ loadCaptchaSdk: vi.fn() }))

// SDK contract from the official V2 example (not the nonexistent AliyunCaptcha.init):
// https://www.alibabacloud.com/help/en/captcha/captcha2-0/user-guide/client-access
const html = (locale = "en") => `
  <form>
    <div data-controller="captcha-aliyun"
         data-captcha-aliyun-scene-id-value="scene-1"
         data-captcha-aliyun-prefix-value="identity-1"
         data-captcha-aliyun-region-value="sgp"
         data-captcha-aliyun-locale-value="${locale}"
         data-captcha-aliyun-sdk-url-value="about:blank">
      <div data-captcha-aliyun-target="mount"></div>
      <input type="hidden" data-captcha-aliyun-target="input">
    </div>
    <button type="submit">Go</button>
  </form>`

describe("captcha-aliyun V2 controller", () => {
  let init
  beforeEach(() => {
    init = vi.fn()
    window.initAliyunCaptcha = init
    loadCaptchaSdk.mockReset()
    loadCaptchaSdk.mockImplementation((_url, ready) => {
      expect(window.AliyunCaptchaConfig).toEqual(expect.objectContaining({ region: expect.any(String), prefix: expect.any(String) }))
      expect(ready()).toBe(window.initAliyunCaptcha)
      return Promise.resolve()
    })
  })
  afterEach(() => {
    delete window.initAliyunCaptcha
    delete window.AliyunCaptchaConfig
    vi.restoreAllMocks()
  })

  async function mount(markup = html()) {
    const mounted = await mountController("captcha-aliyun", Controller, markup)
    await tick()
    return { ...mounted, controller: controllerFor(mounted.application, mounted.element, "captcha-aliyun") }
  }

  function serverEvent(form, { result = "true", success = true } = {}) {
    const headers = new Headers()
    if (result !== null) headers.set("X-Captcha-Result", result)
    form.dispatchEvent(new CustomEvent("turbo:submit-end", {
      detail: { success, fetchResponse: { response: { headers } } }
    }))
  }

  function interceptSubmit(form) {
    return vi.spyOn(form, "requestSubmit").mockImplementation(() => {
      const event = new Event("submit", { cancelable: true })
      form.dispatchEvent(event)
      expect(event.defaultPrevented).toBe(false)
    })
  }

  it("sets the pre-load region/prefix and initializes documented selector, button and instance callbacks", async () => {
    const { element, controller } = await mount()
    const options = init.mock.calls[0][0]
    expect(window.AliyunCaptchaConfig).toEqual({ region: "sgp", prefix: "identity-1" })
    expect(loadCaptchaSdk).toHaveBeenCalledWith("about:blank", expect.any(Function))
    expect(options).toMatchObject({ SceneId: "scene-1", mode: "embed", language: "en" })
    expect(document.querySelector(options.element)).toBe(element.querySelector("[data-captcha-aliyun-target='mount']"))
    expect(document.querySelector(options.button)).toBe(document.querySelector("button"))
    const instance = {}
    options.getInstance(instance)
    expect(controller.captcha).toBe(instance)
    expect(() => options.onBizResultCallback(true)).not.toThrow()
  })

  it.each([["zh-CN", "cn"], ["en", "en"], ["", "en"]])("maps %s to the vendor locale %s", async (locale, language) => {
    await mount(html(locale))
    expect(init.mock.calls[0][0].language).toBe(language)
  })

  it("defaults the region and SDK URL when values are absent", async () => {
    await mount(html().replace('data-captcha-aliyun-region-value="sgp"', "").replace('data-captcha-aliyun-sdk-url-value="about:blank"', ""))
    expect(window.AliyunCaptchaConfig.region).toBe("cn")
    expect(loadCaptchaSdk).toHaveBeenCalledWith("https://o.alicdn.com/captcha-frontend/aliyunCaptcha/AliyunCaptcha.js", expect.any(Function))
  })

  it("blocks native submit before a vendor token is available", async () => {
    await mount()
    const event = new Event("submit", { cancelable: true })
    document.querySelector("form").dispatchEvent(event)
    expect(event.defaultPrevented).toBe(true)
  })

  it("waits for server verification instead of manufacturing a successful callback result", async () => {
    const { element } = await mount()
    const form = element.closest("form")
    const submit = interceptSubmit(form)
    const settled = vi.fn()
    const result = init.mock.calls[0][0].captchaVerifyCallback("VERIFY-XYZ")
    result.then(settled)
    await tick()
    expect(settled).not.toHaveBeenCalled()
    expect(element.querySelector("input").value).toBe("VERIFY-XYZ")
    expect(submit).toHaveBeenCalledOnce()
    const duplicate = init.mock.calls[0][0].captchaVerifyCallback("OTHER-TOKEN")
    expect(duplicate).toBe(result)
    expect(submit).toHaveBeenCalledOnce()
    const nativeRetry = new Event("submit", { cancelable: true })
    form.dispatchEvent(nativeRetry)
    expect(nativeRetry.defaultPrevented).toBe(true)
    serverEvent(form)
    await expect(result).resolves.toEqual({ captchaResult: true, bizResult: true })
  })

  it.each([
    ["false", true, false, true], [null, true, false, true],
    ["true", false, true, false], ["true", "true", true, false]
  ])("separates server captcha result %s from business success %s", async (result, success, captchaResult, bizResult) => {
    const { element } = await mount()
    const form = element.closest("form")
    interceptSubmit(form)
    const promise = init.mock.calls[0][0].captchaVerifyCallback("VERIFY")
    serverEvent(form, { result, success })
    await expect(promise).resolves.toEqual({ captchaResult, bizResult })
    expect(element.querySelector("input").value).toBe(captchaResult ? "VERIFY" : "")
  })

  it.each([undefined, null, {}, { success: true }, { fetchResponse: {} }])("fails the captcha closed on incomplete server event detail %j", async detail => {
    const { element, controller } = await mount()
    interceptSubmit(element.closest("form"))
    const promise = controller.onVerify("VERIFY")
    controller.onServerResult({ detail })
    await expect(promise).resolves.toMatchObject({ captchaResult: false })
  })

  it("supports the documented ES5 result callback", async () => {
    const { element } = await mount()
    const form = element.closest("form")
    interceptSubmit(form)
    const callback = vi.fn()
    const promise = init.mock.calls[0][0].captchaVerifyCallback("VERIFY", callback)
    serverEvent(form)
    await promise
    expect(callback).toHaveBeenCalledWith({ captchaResult: true, bizResult: true })
  })

  it("returns a negative result for a missing token", async () => {
    const { controller } = await mount()
    await expect(controller.onVerify(undefined)).resolves.toEqual({ captchaResult: false, bizResult: false })
  })

  it.each(["mount", "input", "form", "button"])("does not initialize an incomplete %s mount", async missing => {
    let markup = html()
    if (missing === "form") markup = markup.replace("<form>", "").replace("</form>", "")
    else if (missing === "button") markup = markup.replace('<button type="submit">Go</button>', "")
    else markup = markup.replace(`data-captcha-aliyun-target="${missing}"`, "")
    const { controller } = await mount(markup)
    expect(init).not.toHaveBeenCalled()
    if (missing === "input" || missing === "form") {
      await expect(controller.onVerify("VERIFY")).resolves.toEqual({ captchaResult: false, bizResult: false })
    }
    controller.disconnect()
  })

  it("does not re-render when the official SDK global is unavailable", async () => {
    const { controller } = await mount()
    delete window.initAliyunCaptcha
    controller.render()
    expect(init).toHaveBeenCalledOnce()
  })

  it("settles pending verification negatively on SDK error and removes stale input", async () => {
    const { element } = await mount()
    interceptSubmit(element.closest("form"))
    const options = init.mock.calls[0][0]
    const promise = options.captchaVerifyCallback("VERIFY")
    options.onError()
    await expect(promise).resolves.toEqual({ captchaResult: false, bizResult: false })
    expect(element.querySelector("input").value).toBe("")
    expect(() => options.onError()).not.toThrow()
  })

  it("settles pending verification on disconnect and unbinds form listeners", async () => {
    const { element, controller } = await mount()
    const form = element.closest("form")
    interceptSubmit(form)
    const promise = controller.onVerify("VERIFY")
    controller.disconnect()
    await expect(promise).resolves.toEqual({ captchaResult: false, bizResult: false })
    expect(controller.captcha).toBeNull()
    const event = new Event("submit", { cancelable: true })
    form.dispatchEvent(event)
    expect(event.defaultPrevented).toBe(false)
    serverEvent(form)
  })

  it("tolerates an input removed while verification is pending", async () => {
    const { element, controller } = await mount()
    interceptSubmit(element.closest("form"))
    const promise = controller.onVerify("VERIFY")
    element.querySelector("input").remove()
    controller.finish({ captchaResult: false, bizResult: false })
    await expect(promise).resolves.toEqual({ captchaResult: false, bizResult: false })
  })

  it("returns a controlled failure if the form cannot submit", async () => {
    const { element, controller } = await mount()
    vi.spyOn(console, "warn").mockImplementation(() => {})
    vi.spyOn(element.closest("form"), "requestSubmit").mockImplementation(() => { throw new Error("unavailable") })
    await expect(controller.onVerify("VERIFY")).resolves.toEqual({ captchaResult: false, bizResult: false })
    expect(console.warn).toHaveBeenCalledWith("[captcha-aliyun]", expect.any(Error))
  })

  it("does not render after disconnect during an in-flight SDK load", async () => {
    let loaded
    loadCaptchaSdk.mockReturnValue(new Promise(resolve => { loaded = resolve }))
    const { controller } = await mount()
    controller.disconnect()
    loaded()
    await tick()
    expect(init).not.toHaveBeenCalled()
  })

  it("reports an SDK load failure", async () => {
    const error = new Error("SDK failed")
    vi.spyOn(console, "warn").mockImplementation(() => {})
    loadCaptchaSdk.mockRejectedValue(error)
    await mount()
    expect(console.warn).toHaveBeenCalledWith("[captcha-aliyun]", error)
  })
})
