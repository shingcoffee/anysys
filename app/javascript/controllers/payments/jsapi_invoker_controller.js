import { Controller } from "@hotwired/stimulus"

// Invokes the in-app JSAPI bridge provided by the payment provider
// (WeChat `WeixinJSBridge` / Alipay `ap.tradePay`) and redirects to
// the result page when the bridge callback fires. Falls back to a
// plain redirect when neither bridge is present (e.g. desktop testing).
// Registered as `payments--jsapi-invoker` via eager-loading.
export default class extends Controller {
  static values = { provider: String, params: String, resultUrl: String }

  connect() {
    let params = {}
    try {
      const parsed = JSON.parse(this.paramsValue || "{}")
      if (parsed !== null && typeof parsed === "object" && !Array.isArray(parsed)) {
        params = parsed
      }
    } catch {
      params = {}
    }
    if (this.providerValue === "wechat_pay" && window.WeixinJSBridge) {
      window.WeixinJSBridge.invoke("getBrandWCPayRequest", params, () => {
        window.location = this.resultUrlValue
      })
    } else if (this.providerValue === "alipay" && window.ap && window.ap.tradePay) {
      window.ap.tradePay({ tradeNO: params.trade_no }, () => { window.location = this.resultUrlValue })
    } else {
      setTimeout(() => { window.location = this.resultUrlValue }, 1000)
    }
  }
}
