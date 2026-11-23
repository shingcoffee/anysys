import { Controller } from "@hotwired/stimulus"
import { loadCaptchaSdk } from "lib/captcha_sdk_loader"

let sequence = 0

function mapLocale(rails) {
  return rails && rails.toLowerCase().startsWith("zh") ? "cn" : "en"
}

// Aliyun V2: https://www.alibabacloud.com/help/en/captcha/captcha2-0/user-guide/client-access
// The callback result comes from the server's Turbo response, never from merely
// receiving a client token. Keep the SDK's documented getInstance contract.
export default class extends Controller {
  static targets = ["mount", "input"]
  static values = { sceneId: String, prefix: String, region: { type: String, default: "cn" }, locale: String, sdkUrl: String }

  connect() {
    this.connected = true
    this.form = this.element.closest("form")
    this.guardSubmit = event => {
      if (!this.allowSubmit) event.preventDefault()
      this.allowSubmit = false
    }
    this.serverResult = event => this.onServerResult(event)
    if (this.form) {
      this.form.addEventListener("submit", this.guardSubmit)
      this.form.addEventListener("turbo:submit-end", this.serverResult)
    }
    window.AliyunCaptchaConfig = { region: this.regionValue, prefix: this.prefixValue }
    const url = this.sdkUrlValue || "https://o.alicdn.com/captcha-frontend/aliyunCaptcha/AliyunCaptcha.js"
    loadCaptchaSdk(url, () => window.initAliyunCaptcha)
      .then(() => { if (this.connected) this.render() })
      .catch(err => console.warn("[captcha-aliyun]", err))
  }

  render() {
    if (!window.initAliyunCaptcha || !this.hasMountTarget || !this.form || !this.hasInputTarget) return
    const submit = this.form.querySelector("button[type='submit'], input[type='submit']")
    if (!submit) return

    const id = ++sequence
    this.mountTarget.id = `captcha-aliyun-mount-${id}`
    submit.id = `captcha-aliyun-submit-${id}`
    window.initAliyunCaptcha({
      SceneId: this.sceneIdValue,
      mode: "embed",
      element: `#${this.mountTarget.id}`,
      button: `#${submit.id}`,
      language: mapLocale(this.localeValue),
      captchaVerifyCallback: (param, callback) => this.onVerify(param, callback),
      onBizResultCallback: () => {},
      getInstance: instance => { this.captcha = instance },
      onError: () => this.finish({ captchaResult: false, bizResult: false })
    })
  }

  onVerify(verifyParam, callback) {
    if (!verifyParam || !this.form || !this.hasInputTarget) {
      return Promise.resolve({ captchaResult: false, bizResult: false })
    }
    if (this.pending) return this.pending.promise

    this.inputTarget.value = verifyParam
    const promise = new Promise(resolve => { this.resolveResult = resolve })
    this.pending = { promise }
    if (callback) promise.then(callback)
    try {
      this.allowSubmit = true
      this.form.requestSubmit()
    } catch (err) {
      console.warn("[captcha-aliyun]", err)
      this.finish({ captchaResult: false, bizResult: false })
    }
    return promise
  }

  onServerResult(event) {
    const detail = event.detail
    const response = detail && detail.fetchResponse && detail.fetchResponse.response
    this.finish({
      captchaResult: !!response && response.headers.get("X-Captcha-Result") === "true",
      bizResult: !!detail && detail.success === true
    })
  }

  finish(result) {
    if (!this.pending) return
    this.resolveResult(result)
    this.pending = null
    this.allowSubmit = false
    this.resolveResult = null
    if (!result.captchaResult && this.hasInputTarget) this.inputTarget.value = ""
  }

  disconnect() {
    this.connected = false
    if (this.form) {
      this.form.removeEventListener("submit", this.guardSubmit)
      this.form.removeEventListener("turbo:submit-end", this.serverResult)
    }
    this.finish({ captchaResult: false, bizResult: false })
    this.captcha = null
  }
}
