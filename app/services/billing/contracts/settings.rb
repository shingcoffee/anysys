# frozen_string_literal: true

require "reform/form"

module Billing
  module Contracts
    # Validates platform billing settings inputs.
    class Settings < Reform::Form
      property :tax_rate_bps
      property :collection_mode
      property :dunning_schedule
      property :grace_period_days
      property :trial_ending_notice_days

      validates :collection_mode, inclusion: { in: Billing::Settings::COLLECTION_MODES }
      validates :tax_rate_bps, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10_000, only_integer: true }
      validates :grace_period_days,
                numericality: { greater_than_or_equal_to: 0, only_integer: true }
      validates :trial_ending_notice_days,
                numericality: { greater_than_or_equal_to: 0, only_integer: true }

      validate :dunning_schedule_order

      def parsed_dunning_schedule
        return dunning_schedule if dunning_schedule.is_a?(Array)
        return [] if dunning_schedule.is_a?(String) && dunning_schedule.strip.empty?
        return unless dunning_schedule.is_a?(String)
        tokens = dunning_schedule.split(",", -1).map(&:strip)
        return unless tokens.all? { |token| token.match?(/\A[1-9]\d*\z/) }
        tokens.map { |token| Integer(token, 10) }
      end

      private

      def dunning_schedule_order
        schedule = parsed_dunning_schedule
        return if schedule && schedule.all? { |n| n.is_a?(Integer) && n.positive? } && schedule.each_cons(2).all? { |a, b| a < b }
        errors.add(:dunning_schedule, I18n.t("admin_settings.errors.validations.dunning_schedule_order"))
      end
    end
  end
end
