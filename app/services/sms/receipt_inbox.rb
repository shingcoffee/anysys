# frozen_string_literal: true

require "digest"
require "json"

module Sms
  # Authenticated controller handoff: event is either
  # { type: :delivery, vendor_message_id:, status:, raw: } or
  # { type: :inbound, phone:, keyword:, raw: } (adapter-classified opt-out).
  class ReceiptInbox
    def self.record!(credential:, event:, event_key: nil)
      payload = event.deep_stringify_keys
      payload["type"] = payload["type"].to_s
      payload["status"] = payload["status"].to_s if payload.key?("status")
      raise ArgumentError, I18n.t("sms_standards.errors.invalid_receipt") unless %w[delivery inbound].include?(payload["type"].to_s)
      payload["phone"] = ReceiptDetails.phone(payload["phone"]) if payload.key?("phone")
      payload["occurred_at"] = ReceiptDetails.time(payload["occurred_at"])&.iso8601 if payload.key?("occurred_at")

      key = Digest::SHA256.hexdigest(JSON.generate([event_key.presence, payload.except("raw").sort.to_h]))
      receipt = BackendReceipt.create_or_find_by!(credential_id: credential.id, event_key: key) do |row|
        row.provider = credential.provider
        row.vendor_message_id = payload["vendor_message_id"].presence
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
        Rails.logger.warn("[sms.receipts] receipt=#{receipt.id} #{error.class}: #{error.message}")
      end
    end

    def self.process(receipt)
      receipt.with_lock do
        next if receipt.processed_at

        event = receipt.payload
        credential = Credential.find_by(id: receipt.credential_id, provider: receipt.provider)
        next unless credential
        next if event["account_sid"].present? && event["account_sid"] != credential.access_key_id

        if event["type"] == "inbound"
          phone = PhoneNumber.new(event["phone"])
          OptOut.record_global!(phone_e164: phone.e164, provider: receipt.provider,
                                reason: "inbound:#{event['keyword']}") if phone.valid?
          receipt.update!(processed_at: Time.current)
          next
        end

        next if receipt.vendor_message_id.blank?

        message = Message.where(provider: receipt.provider, vendor_message_id: receipt.vendor_message_id)
                         .where("json_extract(metadata, '$.credential_id') = ?", receipt.credential_id).detect do |candidate|
          WebhookCredentialBinding.recorded_match?(candidate, credential) &&
            DeliveryProjection.recipient_matches?(candidate, event)
        end
        next unless message

        DeliveryProjection.apply!(message: message, event: event)
        receipt.update!(customer_id: message.customer_id, processed_at: Time.current)
      end
    end
  end
end
