# frozen_string_literal: true

module Payments
  # Registry of payment gateway integrations. Each gateway subclass calls
  # `register!` when loaded; the registry then exposes them by key. Customers
  # may enable any subset of registered gateways for their tenant by activating
  # the matching Payments::MerchantAccount row.
  #
  # Unlike the Sms/Email/Captcha registries there is no "default" gateway —
  # customers pick per-tenant — so this registry is built with `defaults: false`.
  #
  # Usage:
  #   Payments::Gateways.for("alipay")    #=> Payments::Gateways::Alipay
  #   Payments::Gateways.keys             #=> [:wechat_pay, :alipay]
  #   Payments::Gateways.all              #=> [Payments::Gateways::WechatPay, ...]
  module Gateways
    extend PluginRegistry.build(label: "payment gateway", dir: "app/services/payments/gateways", defaults: false)
  end
end
