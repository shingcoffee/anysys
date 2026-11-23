# frozen_string_literal: true

require "reform/form"
module Payments
  module Contracts
    class Refund < Reform::Form
      include Payments::Contracts::NormalizesAmount

      property :amount
      property :reason
      validates :amount, presence: true, numericality: { greater_than: 0 }
    end
  end
end
