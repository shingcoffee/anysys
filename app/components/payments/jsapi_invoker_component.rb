# frozen_string_literal: true

module Payments
  # Renders the thin bridge view that invokes the in-app JSAPI payment
  # flow (WeChat `WeixinJSBridge`, Alipay `ap.tradePay`). Paired with
  # the `payments--jsapi-invoker` Stimulus controller.
  class JsapiInvokerComponent < ApplicationComponent
    def initialize(payment:)
      @payment = payment
    end

    attr_reader :payment

    def params_json
      payment.prepay_payload.to_json
    end
  end
end
