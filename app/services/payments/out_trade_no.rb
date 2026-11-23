# frozen_string_literal: true

require "securerandom"
module Payments
  module OutTradeNo
    module_function
    def generate(prefix:, customer_id:)
      ts  = Time.now.strftime("%y%m%d%H%M%S")
      rnd = SecureRandom.alphanumeric(6).downcase
      "#{prefix}-#{customer_id % 100_000_000}-#{ts}#{rnd}"[0, 32]
    end
  end
end
