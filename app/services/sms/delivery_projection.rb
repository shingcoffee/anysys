# frozen_string_literal: true

module Sms
  # The same normalized event projection for webhook and REST reconciliation.
  # Model transitions retain the delivered floor. Provider facts live in the
  # existing metadata/raw blobs; no per-vendor columns or text estimates.
  class DeliveryProjection
    def self.recipient_matches?(message, event)
      return true unless event.key?("phone") && !event["phone"].nil?

      phone = PhoneNumber.normalize(event["phone"])
      phone.present? && phone == message.to
    end

    def self.apply!(message:, event:)
      event = event.deep_stringify_keys
      return false unless recipient_matches?(message, event)
      return false unless %w[delivered failed unknown].include?(event["status"].to_s)

      message.with_lock do
        # Twilio 21610 is a confirmed provider opt-out. The matched recorded
        # recipient, never an unchecked callback address, is the suppression key.
        if message.provider == "twilio" && event["failure_code"].to_s == "21610"
          OptOut.record_global!(phone_e164: message.to, provider: "twilio", reason: "provider:21610")
        end
        next if message.status == "delivered" && event["status"].to_s != "delivered"

        raw = event["raw"].is_a?(Hash) ? event["raw"] : {}
        case event["status"].to_s
        when "delivered"
          message.mark_delivered!(at: ReceiptDetails.time(event["occurred_at"]) || Time.current, raw: raw)
        when "failed"
          message.mark_failed!(code: event["failure_code"].presence&.to_s || "VENDOR_DLR",
                               message: event["failure_message"].presence || Message::FAILURE_DELIVERY, raw: raw)
        when "unknown"
          message.mark_unknown!(raw: raw)
        end
        metadata = (message.metadata || {}).dup
        metadata["provider_status"] = event["provider_status"] if event["provider_status"].present?
        segments = ReceiptDetails.segments(event["segments"])
        metadata["provider_segments"] = segments if segments
        occurred_at = ReceiptDetails.time(event["occurred_at"])
        metadata["provider_occurred_at"] = occurred_at.iso8601 if occurred_at
        message.update!(metadata: metadata) if metadata != message.metadata
      end
      true
    end
  end
end
