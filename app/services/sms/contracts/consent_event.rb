# frozen_string_literal: true

require "reform/form"

module Sms
  module Contracts
    class ConsentEvent < Reform::Form
      FIELDS = %i[action occurred_at reference statement notes event_key].freeze
      Input = Struct.new(*FIELDS, keyword_init: true)
      FIELDS.each { |field| property field }
      validate :evidence_values

      def parsed_occurred_at = Bounds.time(occurred_at)
      def evidence = { "reference" => reference, "statement" => statement, "notes" => notes }.compact

      private

      def evidence_values
        errors.add(:action, I18n.t("sms_audience.errors.invalid_action")) unless Sms::ConsentEvent::ACTIONS.include?(action)
        errors.add(:occurred_at, I18n.t("sms_audience.errors.invalid_occurred_at")) unless parsed_occurred_at && parsed_occurred_at <= Time.current
        errors.add(:event_key, I18n.t("sms_audience.errors.invalid_event_key")) unless Bounds.text?(event_key, bytes: 128, required: true)
        { reference: true, statement: action == "granted", notes: false }.each do |field, required|
          errors.add(field, I18n.t("sms_audience.errors.invalid_evidence")) unless Bounds.text?(public_send(field), bytes: 1024, required: required)
        end
        errors.add(:base, I18n.t("sms_audience.errors.invalid_evidence")) unless Bounds.object?(evidence, bytes: 4096)
      end
    end
  end
end
