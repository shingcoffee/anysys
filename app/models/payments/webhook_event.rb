# frozen_string_literal: true

module Payments
  # One row per inbound PSP webhook, keyed by the PSP's own stable event id —
  # the idempotency ledger for the async processing pipeline (verify+record
  # inline, then WebhookDispatcher hands off to ProcessWebhookEventJob).
  # Deliberately NOT TenantScoped: a webhook is recorded at dispatch time,
  # BEFORE the tenant is resolved from the (verified) body, so customer_id is
  # backfilled/optional rather than auto-set from Current.
  class WebhookEvent < ApplicationRecord
    include JsonSerializable

    self.table_name = "payment_webhook_events"

    STATUSES = %w[received processed failed].freeze
    VERIFICATION_KEY = "_anysys_verification"
    PROCESSING_KEY = "_anysys_processing"
    PROCESSING_LEASE = 10.minutes

    json_attribute :payload, default: {}

    validates :provider,     presence: true
    validates :psp_event_id, presence: true, uniqueness: { scope: :provider }
    validates :status,       inclusion: { in: STATUSES }

    # This envelope is written AFTER signature verification. Never accept the
    # similarly named field supplied by the PSP as our account identity.
    def self.payload_with_verification(payload, signing_account_id:)
      payload.deep_stringify_keys.except(PROCESSING_KEY)
             .merge(VERIFICATION_KEY => { "merchant_account_id" => signing_account_id })
    end

    def signing_account_id
      payload.dig(VERIFICATION_KEY, "merchant_account_id")
    end

    def verified_payload
      payload.except(VERIFICATION_KEY, PROCESSING_KEY)
    end

    # Only these short ledger mutations hold an event transaction. Provider HTTP
    # and projection run after claim commits; handlers retain domain idempotency.
    def claim_processing!(signing_merchant_id: nil, signing_account_id: nil)
      with_lock do
        next if status == "processed" || processing?

        if self.signing_account_id.blank? ||
           (signing_account_id.present? && signing_account_id != self.signing_account_id) ||
           (signing_merchant_id.present? && signing_merchant_id != self.signing_merchant_id)
          raise Payments::Errors::SignatureInvalid, "webhook verification identity is missing or changed"
        end
        token = SecureRandom.uuid
        update!(payload: payload.merge(PROCESSING_KEY => { "token" => token, "claimed_at" => Time.current.iso8601(6) }))
        token
      end
    end

    def processing?
      claim = payload[PROCESSING_KEY]
      claim.is_a?(Hash) && claim["token"].present? && Time.iso8601(claim["claimed_at"].to_s) > PROCESSING_LEASE.ago
    rescue ArgumentError
      false
    end

    def finish_processing!(token, customer_id: nil)
      with_lock do
        next false unless payload.dig(PROCESSING_KEY, "token") == token && status != "processed"

        update!(payload: payload.except(PROCESSING_KEY), status: "processed", processed_at: Time.current,
                customer_id: customer_id || self.customer_id)
        true
      end
    end

    def release_processing!(token)
      with_lock do
        next unless payload.dig(PROCESSING_KEY, "token") == token && status != "processed"

        update!(payload: payload.except(PROCESSING_KEY))
      end
    end

    def fail_processing!
      with_lock do
        next if status == "processed" || processing?

        update!(status: "failed")
      end
    end

    def mark_processed!(customer_id: nil)
      update!(status: "processed", processed_at: Time.current,
              customer_id: customer_id || self.customer_id)
    end
  end
end
