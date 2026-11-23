# frozen_string_literal: true

require "digest"
require "json"

module Emails
  # Call only AFTER provider authentication, passing the credential that
  # verified the callback. Unknown vendor IDs stay pending and are redriven
  # both after mark_sent! and by the recovery job.
  class ReceiptInbox
    TYPES = %w[delivered bounced complained].freeze

    def self.record!(credential:, event:, event_key: nil)
      payload = event.deep_stringify_keys
      payload["type"] = payload["type"].to_s
      raise ArgumentError, "invalid normalized email receipt" unless TYPES.include?(payload["type"].to_s)

      identity = payload.except("raw")
      # One vendor notification can contain several recipient/type events.
      # Include normalized identity even when the caller supplies an envelope ID.
      key = Digest::SHA256.hexdigest(JSON.generate([event_key.presence, identity.sort.to_h]))
      receipt = BackendReceipt.create_or_find_by!(credential_id: credential.id, event_key: key) do |row|
        row.provider = credential.provider
        row.vendor_message_id = payload["provider_message_id"].presence
        row.payload = payload
      end
      process(receipt)
      receipt
    end

    def self.reconcile(provider: nil, vendor_message_id: nil)
      scope = BackendReceipt.pending
      scope = scope.where(provider: provider) if provider
      scope = scope.where(vendor_message_id: vendor_message_id) if vendor_message_id.present?
      scope.find_each do |receipt|
        process(receipt)
      rescue StandardError => error
        Rails.logger.warn("[emails.receipts] receipt=#{receipt.id} #{error.class}: #{error.message}")
      end
    end

    def self.process(receipt)
      receipt.with_lock do
        next if receipt.processed_at

        event = receipt.payload
        if event["suppress"] == true && event["email"].present?
          Suppression.record_global!(email: event["email"], provider: receipt.provider,
                                     reason: event["type"] == "complained" ? "complaint" : "hard_bounce")
        end
        message = correlated_message(receipt)
        # An address-only suppression needs no message correlation.
        next if message.nil? && receipt.vendor_message_id.present?

        if message
          case event["type"]
          when "delivered" then message.mark_delivered!
          when "bounced" then message.mark_bounced!(code: event["code"], message: event["message"])
          when "complained" then message.mark_complained!(code: event["code"], message: event["message"])
          end
          campaign = SendActivities::SendActivity.find_by(id: message.email_send_activity_id, customer_id: message.customer_id)
          SendActivities::RefreshStats.call(campaign) if campaign
        end
        receipt.update!(customer_id: message&.customer_id, processed_at: Time.current)
      end
    end

    def self.correlated_message(receipt)
      return if receipt.vendor_message_id.blank?

      credential = Credential.find_by(id: receipt.credential_id, provider: receipt.provider)
      return unless credential

      Message.where(provider: receipt.provider, provider_message_id: receipt.vendor_message_id)
             .where("json_extract(metadata, '$.credential_id') = ?", receipt.credential_id).detect do |message|
        WebhookCredentialBinding.recorded_match?(message, credential) &&
          WebhookCredentialBinding.email_recipient?(message, receipt.payload["email"])
      end
    end
    private_class_method :correlated_message
  end
end
