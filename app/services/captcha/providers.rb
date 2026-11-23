# frozen_string_literal: true

module Captcha
  # Registry of captcha providers. Each provider subclass calls `register!`
  # when loaded; the registry then exposes them by key. The default provider
  # (the one auto-created on first access of ProviderSettings.active) is
  # whichever provider declares `default!`.
  #
  # Usage:
  #   Captcha::Providers.for("aliyun")  #=> Captcha::Providers::Aliyun
  #   Captcha::Providers.keys           #=> [:aliyun]
  #   Captcha::Providers.default_key    #=> :aliyun
  module Providers
    extend PluginRegistry.build(label: "captcha provider", dir: "app/services/captcha/providers")
  end
end
