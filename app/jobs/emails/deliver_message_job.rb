# frozen_string_literal: true

module Emails
  # Owns delivery + status for a queued Emails::Message, provider-agnostically.
  # Resolves the provider from the message and calls provider.deliver; SMTP
  # delegates to the mailer (deliver_now), API vendors POST their API. Definitive
  # vendor rejections (ApiError) mark the row failed immediately; transient/
  # transport errors retry with backoff and, once exhausted, mark failed.
  # NOTE: delivery is at-least-once. Neither SMTP nor the API send endpoints
  # exposes a client idempotency key, so a transient failure that occurs AFTER
  # the vendor accepted the message (e.g. a client-side timeout on the response)
  # can re-send on retry. This is the accepted trade-off for transient-error
  # recovery; the window is small and duplicates are far rarer than lost mail.
  class DeliverMessageJob < ApplicationJob
    queue_as :default
    ATTEMPTS = 3

    retry_on StandardError, wait: :polynomially_longer, attempts: ATTEMPTS do |job, error|
      message = Emails::Message.find_by(id: job.arguments.first)
      if message && message.delivery_claim_token.nil?
        message.mark_failed!(code: error.class.name, message: error.message, claim_token: :unclaimed)
      end
      Rails.logger.error("[emails.deliver] permanent failure message=#{job.arguments.first}: #{error.class}: #{error.message}")
    end

    def perform(message_id, mode = nil)
      message = Emails::Message.find_by(id: message_id)
      return if message.nil? || message.status != "queued"
      return unless FeatureModules::Module.enabled?(key: "email", customer_id: message.customer_id)

      claim = DeliveryDispatch.claim(message_id)
      return unless claim

      message, token = claim
      if DeliveryDispatch.blocked?(message)
        message.mark_suppressed!(claim_token: token)
        return
      end

      inject_tracking_if_enabled!(message)

      credential = DeliveryCredential.for_message(message, mode: mode)
      provider = Email::Providers.for(message.provider).new(credential: credential)

      # Recheck after preparation, immediately before the external side effect.
      if DeliveryDispatch.blocked?(message)
        message.mark_suppressed!(claim_token: token)
        return
      end
      return unless Emails::Message.exists?(id: message.id, status: "queued", delivery_claim_token: token)
      return unless FeatureModules::Module.enabled?(key: "email", customer_id: message.customer_id)

      result = provider.deliver(message: message)
      message.mark_sent!(provider_message_id: result[:provider_message_id], claim_token: token)
      if result[:provider_message_id].present?
        ReceiptInbox.reconcile(provider: message.provider, vendor_message_id: result[:provider_message_id])
      end
      log_send_outcome("sent", message.provider)
    rescue Email::Errors::ApiError => e
      # Definitive vendor rejection (bad address, rejected content) — don't retry.
      message.mark_failed!(code: e.code.to_s, message: e.message, claim_token: token)
      log_send_outcome("failed", message.provider)
    rescue StandardError => error
      if token && message.delivery_attempts >= DeliveryDispatch::MAX_ATTEMPTS
        message.mark_failed!(code: error.class.name, message: error.message, claim_token: token)
      end
      raise
    ensure
      DeliveryDispatch.release(message, token) if token && message
      refresh_campaign_stats(message) if token && message
    end

    private

    def refresh_campaign_stats(message)
      return unless message.email_send_activity_id

      campaign = SendActivities::SendActivity.find_by(id: message.email_send_activity_id, customer_id: message.customer_id)
      SendActivities::RefreshStats.call(campaign) if campaign
    rescue StandardError => error
      Rails.logger.warn("[emails.stats] message=#{message.id} #{error.class}: #{error.message}")
    end

    def inject_tracking_if_enabled!(message)
      return unless message.metadata.try(:[], "tracking_enabled") || message.metadata.try(:[], :tracking_enabled)

      body_html = Emails::TemplateRenderer.inject_tracking(message.body_html, message.id)
      message.update!(body_html: body_html)
    end

    # NB: must NOT be named `instrument` — that shadows
    # ActiveJob::Instrumentation#instrument and breaks enqueue/perform.
    def log_send_outcome(outcome, provider)
      ActiveSupport::Notifications.instrument("email.send", outcome: outcome, provider: provider, duration: nil)
    end
  end
end
