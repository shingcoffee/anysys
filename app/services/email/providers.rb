# frozen_string_literal: true

module Email
  # Registry of email delivery providers. Each provider subclass calls
  # `register!` on load; the default (used when a caller doesn't name one) calls
  # `default!`. Mirrors Sms::Adapters / Payments::Gateways so adding a provider
  # is a single new file under app/services/email/providers/<name>.rb.
  #
  #   Email::Providers.for("smtp")   #=> Email::Providers::Smtp
  #   Email::Providers.keys          #=> [:smtp, :ses, :aliyun]
  #   Email::Providers.default_key   #=> :smtp
  module Providers
    extend PluginRegistry.build(label: "email provider", dir: "app/services/email/providers")
  end
end
