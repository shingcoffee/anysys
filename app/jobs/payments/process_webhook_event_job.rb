# frozen_string_literal: true

module Payments
  # Asynchronous webhook processing (the dispatcher verifies + records inline,
  # then hands off here). The queue owns retries; after ATTEMPTS failures the
  # event dead-letters as status "failed" — visible for operator re-drive via
  # PSP redelivery (the dispatcher re-accepts failed event ids).
  class ProcessWebhookEventJob < ApplicationJob
    queue_as :default

    ATTEMPTS = 5

    retry_on StandardError, wait: :polynomially_longer, attempts: ATTEMPTS do |job, error|
      event = Payments::WebhookEvent.find_by(id: job.arguments.first)
      event&.fail_processing!
      Rails.logger.error(
        "[payments.webhook_job] event=#{job.arguments.first} dead-lettered: #{error.class}: #{error.message}"
      )
    end

    def perform(event_id, signing_merchant_id = nil, signing_account_id = nil)
      Current.reset
      event = Payments::WebhookEvent.find_by(id: event_id)
      return if event.nil?

      token = event.claim_processing!(signing_merchant_id: signing_merchant_id, signing_account_id: signing_account_id)
      return unless token

      Payments::Activities::HandleWebhook.call(
        provider:           event.provider,
        verified_payload:   event.verified_payload,
        signing_merchant_id: event.signing_merchant_id,
        signing_account_id:  event.signing_account_id
      )
      unless event.finish_processing!(token, customer_id: Current.customer&.id)
        raise Payments::Errors::TransportError, "webhook processing lease was replaced before completion"
      end
    ensure
      begin
        event&.release_processing!(token) if token
      ensure
        Current.reset
      end
    end
  end
end
