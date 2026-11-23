import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/payments/jsapi_invoker_controller"
import { mountController } from "../../support/stimulus.js"

const ID = "payments--jsapi-invoker"
const html = ({ provider, params, resultUrl }) => `
  <div data-controller="${ID}"
       data-${ID}-provider-value="${provider}"
       data-${ID}-params-value='${params}'
       data-${ID}-result-url-value="${resultUrl}"></div>`

describe("payments--jsapi-invoker", () => {
  let originalLocation, setTimeoutSpy
  beforeEach(() => {
    originalLocation = window.location
    setTimeoutSpy = vi.spyOn(globalThis, "setTimeout")
  })
  afterEach(() => {
    window.location = originalLocation
    delete window.WeixinJSBridge
    delete window.ap
    vi.restoreAllMocks()
  })

  it("invokes the WeChat bridge and redirects from its callback", async () => {
    const invoke = vi.fn((name, params, cb) => cb())
    window.WeixinJSBridge = { invoke }
    await mountController(ID, Controller, html({
      provider: "wechat_pay",
      params: JSON.stringify({ appId: "wx", timeStamp: "1" }),
      resultUrl: "/result/wechat",
    }))

    expect(invoke).toHaveBeenCalledWith(
      "getBrandWCPayRequest",
      { appId: "wx", timeStamp: "1" },
      expect.any(Function),
    )
    expect(String(window.location)).toBe("/result/wechat")
  })

  it("invokes the Alipay bridge with the trade number and redirects", async () => {
    const tradePay = vi.fn((opts, cb) => cb())
    window.ap = { tradePay }
    await mountController(ID, Controller, html({
      provider: "alipay",
      params: JSON.stringify({ trade_no: "T-99" }),
      resultUrl: "/result/alipay",
    }))

    expect(tradePay).toHaveBeenCalledWith({ tradeNO: "T-99" }, expect.any(Function))
    expect(String(window.location)).toBe("/result/alipay")
  })

  it("falls back to a delayed plain redirect when no bridge is present", async () => {
    await mountController(ID, Controller, html({
      provider: "wechat_pay", // provider set but bridge absent
      params: "{}",
      resultUrl: "/result/fallback",
    }))

    const fallback = setTimeoutSpy.mock.calls.find(([, delay]) => delay === 1000)
    expect(fallback).toBeTruthy()
    // hasn't navigated yet
    expect(String(window.location)).not.toBe("/result/fallback")
    fallback[0]()
    expect(String(window.location)).toBe("/result/fallback")
  })

  it("defaults params to {} when the params value is empty", async () => {
    const invoke = vi.fn((name, params, cb) => cb())
    window.WeixinJSBridge = { invoke }
    await mountController(ID, Controller, html({
      provider: "wechat_pay",
      params: "",
      resultUrl: "/result/empty",
    }))
    expect(invoke).toHaveBeenCalledWith("getBrandWCPayRequest", {}, expect.any(Function))
  })

  it("falls back to a delayed plain redirect when params JSON is invalid", async () => {
    await mountController(ID, Controller, html({
      provider: "wechat_pay",
      params: "{not-json",
      resultUrl: "/result/bad-json",
    }))

    const fallback = setTimeoutSpy.mock.calls.find(([, delay]) => delay === 1000)
    expect(fallback).toBeTruthy()
    fallback[0]()
    expect(String(window.location)).toBe("/result/bad-json")
  })

  it("treats JSON null as empty params and still invokes WeChat", async () => {
    const invoke = vi.fn((name, params, cb) => cb())
    window.WeixinJSBridge = { invoke }
    await mountController(ID, Controller, html({
      provider: "wechat_pay",
      params: "null",
      resultUrl: "/result/null",
    }))
    expect(invoke).toHaveBeenCalledWith("getBrandWCPayRequest", {}, expect.any(Function))
    expect(String(window.location)).toBe("/result/null")
  })

  it("treats a JSON array as empty params and still invokes WeChat", async () => {
    const invoke = vi.fn((name, params, cb) => cb())
    window.WeixinJSBridge = { invoke }
    await mountController(ID, Controller, html({
      provider: "wechat_pay",
      params: "[]",
      resultUrl: "/result/array",
    }))
    expect(invoke).toHaveBeenCalledWith("getBrandWCPayRequest", {}, expect.any(Function))
    expect(String(window.location)).toBe("/result/array")
  })

  it("treats a JSON primitive as empty params and still invokes WeChat", async () => {
    const invoke = vi.fn((name, params, cb) => cb())
    window.WeixinJSBridge = { invoke }
    await mountController(ID, Controller, html({
      provider: "wechat_pay",
      params: "1",
      resultUrl: "/result/number",
    }))
    expect(invoke).toHaveBeenCalledWith("getBrandWCPayRequest", {}, expect.any(Function))
    expect(String(window.location)).toBe("/result/number")
  })
})
