# frozen_string_literal: true

module Billing
  module Admin
    class CouponBenefitComponent < ApplicationComponent
      def initialize(benefit:, currency:)
        @benefit, @currency = benefit.to_h.symbolize_keys, currency
      end

      attr_reader :benefit, :currency

      def repeating_progress?
        benefit[:duration].to_s == "repeating" && benefit[:duration_in_cycles].to_i.positive? && !benefit[:remaining_cycles].nil?
      end

      def remaining_percent
        total = benefit[:duration_in_cycles].to_i
        return 0 if total <= 0

        [(benefit[:remaining_cycles].to_i * 100.0 / total).round, 100].min
      end
    end
  end
end
