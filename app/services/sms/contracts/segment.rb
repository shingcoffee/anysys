# frozen_string_literal: true

require "reform/form"

module Sms
  module Contracts
    class Segment < Reform::Form
      FIELDS = %i[name description segment_rules lock_version].freeze
      property :name
      property :description
      property :segment_rules
      property :lock_version
      attr_accessor :customer
      validate :segment_values

      private

      def segment_values
        errors.add(:name, I18n.t("sms_audience.errors.invalid_name")) unless Bounds.text?(name, bytes: 200, required: true)
        errors.add(:description, I18n.t("sms_audience.errors.invalid_description")) unless Bounds.text?(description, bytes: 2048)
        errors.add(:segment_rules, I18n.t("sms_audience.errors.invalid_rules")) unless Audience::SegmentQuery.valid?(customer: customer, rules: segment_rules)
      end
    end
  end
end
