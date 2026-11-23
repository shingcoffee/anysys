# frozen_string_literal: true

module Captcha
  module Errors
    class Error          < StandardError; end
    class TransportError < Error; end   # 5xx, timeouts, network
    class ConfigurationError < Error; end
  end
end
