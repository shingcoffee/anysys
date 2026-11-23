# frozen_string_literal: true

require "reform/form"

module Billing
  module Contracts
    class OneTimePayment < Reform::Form
      property :provider
      property :invoice_id
      property :openid

      validates :provider, presence: true
    end
  end
end
