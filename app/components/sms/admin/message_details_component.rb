# frozen_string_literal: true

module Sms
  module Admin
    class MessageDetailsComponent < ApplicationComponent
      FIELDS = [
        [:to, "admin_modules.sms.messages.show.to", :text],
        [:template_key, "admin_modules.sms.messages.show.template", :text],
        [:provider, "admin_modules.emails.suppressions.provider", :text],
        [:vendor_message_id, "admin_modules.sms.messages.show.vendor_message_id", :text],
        [:dispatch_started_at, "sms_presentation.fields.dispatch_started_at", :time],
        [:delivery_attempts, "sms_presentation.fields.delivery_attempts", :text],
        [:sent_at, "admin_modules.sms.messages.show.sent_at", :time],
        [:delivered_at, "admin_modules.sms.messages.show.delivered_at", :time],
        [:expires_at, "comp_billing.coupon_form.expires_at_label", :time],
        [:provider_occurred_at, "sms_presentation.fields.provider_occurred_at", :time],
        [:provider_status, "sms_presentation.fields.provider_status", :text],
        [:provider_segments, "sms_presentation.fields.provider_segments", :text]
      ].map(&:freeze).freeze

      STATUS_VARIANTS = {
        "queued" => :default, "pending" => :info, "sent" => :info,
        "delivered" => :success, "failed" => :danger, "unknown" => :default,
        "suppressed" => :default, "expired" => :warning
      }.freeze

      attr_reader :message

      def initialize(message:)
        @message = message
      end

      def status_variant
        STATUS_VARIANTS.fetch(message.status, :default)
      end

      def status_label
        t(message.status == "expired" ? "sms.statuses.expired" : "common.status.#{message.status}")
      end

      def field_value(field)
        case field
        when :provider
          return if message.provider.blank?

          t("sms.adapters.#{message.provider}.name", default: message.provider)
        when :provider_status
          message.metadata&.fetch("provider_status", nil)
        when :provider_segments
          # Only an actual positive provider count is a segment fact. Remote
          # template text and variable values must never be used for estimates.
          value = message.metadata&.fetch("provider_segments", nil)
          value.to_i if value.to_s.match?(/\A[1-9][0-9]*\z/)
        when :provider_occurred_at
          parse_timestamp(message.metadata&.fetch("provider_occurred_at", nil))
        else
          message.public_send(field)
        end
      end

      def missing_value(field)
        t(%i[expires_at provider_segments].include?(field) ? "common.status.unknown" : "sms_presentation.not_recorded")
      end

      def field_help_key(field)
        "sms_presentation.help.#{field}" if %i[sent_at provider_segments].include?(field)
      end

      def help_id(field)
        "sms-message-#{message.id}-#{field}-help"
      end

      def variable_names
        (message.vars || {}).keys.map(&:to_s)
      end

      private

      def parse_timestamp(value)
        return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
        return if value.blank?

        Time.iso8601(value)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
