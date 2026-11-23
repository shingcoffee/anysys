# frozen_string_literal: true

module Sms
  # Registry of SMS vendor adapters. Each adapter subclass calls `register!`
  # when loaded; the registry then exposes them by key. The default adapter
  # (used when a caller doesn't name a provider) is whichever declares `default!`.
  #
  # Mirrors Captcha::Providers / Payments::Gateways so adding a vendor is a
  # single new file under app/services/sms/adapters/<vendor>.rb.
  #
  #   Sms::Adapters.for("aliyun")  #=> Sms::Adapters::Aliyun
  #   Sms::Adapters.keys           #=> [:aliyun, :twilio]
  #   Sms::Adapters.default_key    #=> :aliyun
  module Adapters
    extend PluginRegistry.build(label: "sms adapter", dir: "app/services/sms/adapters")
  end
end
