# frozen_string_literal: true

module Payments
  # Dispatches an inbound vendor webhook to the right tenant + activity. The
  # merchant_id parser is per-vendor and lives on the gateway class — adding
  # a new gateway requires no edits here.
  class WebhookDispatcher
    # ProcessWebhookEventJob retries with polynomially_longer over ATTEMPTS=5
    # attempts (~6 minutes end-to-end) before dead-lettering. A "received"
    # event redelivered inside that window is very likely still being retried
    # by its original job — re-driving it here would race a second job
    # against the first. Past this window, "received" can only mean the job
    # was never enqueued (crash) or never picked up (worker down), so
    # re-driving is safe and necessary.
    RECEIVED_REDRIVE_AFTER = 10.minutes

    def self.call(provider:, headers:, body:)
      normalized_headers = normalize_headers(headers)
      gateway_class      = Payments::Gateways.for(provider)
      merchant_id        = gateway_class.extract_merchant_id(normalized_headers, body)
      account            = Payments::CredentialResolver.by_merchant_id(provider: provider, merchant_id: merchant_id)
      gateway            = gateway_class.new(account: account)
      payload            = gateway.verify_notification(headers: normalized_headers, body: body)

      # No event ID means no ledger/queue handoff. Run outside our transaction:
      # the handler owns its own locks and may perform historical PSP lookups.
      if gateway_class.event_id(payload).blank?
        Payments::Activities::HandleWebhook.call(
          provider: provider, verified_payload: payload.except(Payments::WebhookEvent::VERIFICATION_KEY, Payments::WebhookEvent::PROCESSING_KEY),
          signing_merchant_id: account.merchant_id, signing_account_id: account.id
        )
        return :ok
      end

      # Roll back the ledger write when an immediate enqueue fails. Adapters
      # that defer enqueue until commit (or use another database) still need
      # RedriveWebhookEvents to recover a committed row after a queue outage.
      ActiveRecord::Base.transaction do
        event = record_event(provider, gateway_class, payload, account)
        next :duplicate if event == :duplicate

        Payments::ProcessWebhookEventJob.perform_later(event.id, event.signing_merchant_id, event.signing_account_id)
        :accepted
      end
    end

    # Returns the persisted WebhookEvent, :duplicate if the event id was already
    # recorded (and not eligible for re-drive), or nil when the gateway exposes
    # no event id (dedup skipped, processed inline).
    def self.record_event(provider, gateway_class, payload, account)
      event_id = gateway_class.event_id(payload)
      return nil if event_id.blank?

      event = Payments::WebhookEvent.new(
        provider: provider, psp_event_id: event_id, signing_merchant_id: account.merchant_id,
        event_type: gateway_class.event_type(payload), status: "received",
        payload: Payments::WebhookEvent.payload_with_verification(payload, signing_account_id: account.id)
      )
      return event if event.save

      # Only the uniqueness collision means "already delivered"; any other
      # validation failure is a real error and must surface.
      return redrive_or_duplicate(provider, event_id, account) if event.errors.of_kind?(:psp_event_id, :taken)

      raise ActiveRecord::RecordInvalid.new(event)
    rescue ActiveRecord::RecordNotUnique
      # DB unique index caught a race between two concurrent first-deliveries.
      redrive_or_duplicate(provider, event_id, account)
    end

    # Redelivery of a known event id: drop as :duplicate unless the prior
    # delivery is eligible for re-drive — either dead-lettered ("failed"), or
    # stuck "received" past RECEIVED_REDRIVE_AFTER — in which case the
    # redelivery (PSP retry or operator resend) re-drives it through the queue.
    def self.redrive_or_duplicate(provider, event_id, account)
      existing = Payments::WebhookEvent.find_by(provider: provider, psp_event_id: event_id)
      return :duplicate unless existing

      existing.with_lock do
        unless existing.signing_account_id == account.id
          raise Payments::Errors::SignatureInvalid, "webhook event belongs to a different signing account"
        end
        next :duplicate unless redrivable?(existing)

        # Replays retain the original verified body and account identity.
        existing.update!(status: "received")
        existing
      end
    end

    def self.redrivable?(existing)
      return false if existing.processing?

      return true if existing.status == "failed"
      existing.status == "received" && existing.updated_at <= RECEIVED_REDRIVE_AFTER.ago
    end

    # Accept both Rack env (`HTTP_WECHATPAY_SIGNATURE` style) and pre-normalized
    # (`Wechatpay-Signature`) hashes, and expose every header under the
    # canonical Hyphen-Case key the gateways read.
    def self.normalize_headers(headers)
      return {} if headers.nil?
      headers.each_with_object({}) do |(raw_key, value), h|
        key = raw_key.to_s
        key = key.sub(/\AHTTP_/, "").tr("_", "-") if key.match?(/\AHTTP_/)
        canonical = key.split("-").map(&:capitalize).join("-")
        h[canonical] = value
      end
    end
  end
end
