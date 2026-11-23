# frozen_string_literal: true

require "benchmark"

module Sms
  # SMS deliberately has no send retry: after dispatch starts, ambiguity is an
  # outcome to reconcile, not permission to send the same payload again.
  class DeliverMessageJob < ApplicationJob
    queue_as :default
    LEDGER_COMPLETION_ATTEMPTS = 3

    def perform(message_id)
      claim = DeliveryDispatch.claim(message_id)
      return unless claim

      message, token = claim
      return if DeliveryDispatch.apply_block(message, token)

      credential = DeliveryCredential.for_message(message)
      adapter = credential.adapter_class.new(credential: credential)
      template = DeliveryDispatch.template_for(message)
      params = message.metadata.fetch("template_snapshot").fetch("vars")

      # Final ordered policy/account-clock transaction commits the sole attempt
      # before any network call. A defer releases preparation without an attempt.
      authorization = DispatchLimiter.acquire(credential: credential, message: message, claim_token: token, at: Time.current)
      return unless authorization[:action] == :started
      attempt_started_at = authorization.fetch(:attempt_started_at)

      started = true
      result = nil
      duration = Benchmark.realtime { result = adapter.send_message(to: message.to, template: template, template_params: params) }
      unless accepted_result?(result)
        complete_unknown(message, token, attempt_started_at, result: result)
        reconcile_recorded(message)
        log_outcome("unknown", message, duration)
        return
      end

      ledger_write do
        message.mark_sent!(vendor_message_id: result[:vendor_message_id], raw: result[:raw], claim_token: token,
                           attempt_started_at: attempt_started_at)
      end
      reconcile_recorded(message)
      log_outcome("sent", message, duration)
    rescue Errors::ApiError => error
      if started && result.nil? && definitive_rejection?(error)
        ledger_write do
          message.mark_failed!(code: error.code.to_s, message: error.message, raw: error.payload || {}, claim_token: token,
                               attempt_started_at: attempt_started_at)
        end
        if message.provider == "twilio" && error.code.to_s == "21610"
          OptOut.record_global!(phone_e164: message.to, provider: message.provider, reason: "vendor:21610")
        end
        log_outcome("failed", message)
      else
        record_error(message, token, started, error, result: result, attempt_started_at: attempt_started_at)
      end
    rescue StandardError => error
      record_error(message, token, started, error, result: result, attempt_started_at: attempt_started_at)
    ensure
      DeliveryDispatch.release(message, token) if message && token
    end

    private

    def definitive_rejection?(error)
      code = error.code.to_s
      code.present? && code != "OK" && !code.match?(/\A5\d\d\z/)
    end

    def accepted_result?(result)
      result.is_a?(Hash) && usable_id?(result[:vendor_message_id]) && result[:raw].is_a?(Hash)
    end

    def usable_id?(id)
      id.is_a?(String) && id.valid_encoding? && (id.encoding == Encoding::UTF_8 || id.ascii_only?) && id.present?
    end

    # Retry only the fenced ledger transition, never adapter.send_message or
    # receipt projection. A reload failure may follow a successful DB update.
    def ledger_write
      attempts = 0
      begin
        attempts += 1
        yield
      rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished
        retry if attempts < LEDGER_COMPLETION_ATTEMPTS
        raise
      end
    end

    def complete_unknown(message, token, attempt_started_at, result: nil, error: nil)
      result = {} unless result.is_a?(Hash)
      vendor_id = result[:vendor_message_id]
      vendor_id = error.vendor_message_id if !usable_id?(vendor_id) && error.respond_to?(:vendor_message_id)
      vendor_id = nil unless usable_id?(vendor_id)
      raw = result[:raw]
      raw = error.payload if !raw.is_a?(Hash) && error.respond_to?(:payload)
      raw = {} unless raw.is_a?(Hash)
      ledger_write do
        message.mark_unknown!(raw: raw, claim_token: token, vendor_message_id: vendor_id,
                              attempt_started_at: attempt_started_at)
      end
    end

    def reconcile_recorded(message)
      # Use a fresh persisted identity even if the completion update succeeded
      # but its instance reload failed. Never correlate using an unsaved ID.
      recorded = Message.uncached do
        Message.find_by(id: message.id, customer_id: message.customer_id, provider: message.provider)
      end
      return unless recorded && usable_id?(recorded.vendor_message_id)

      ReceiptInbox.reconcile(provider: recorded.provider, vendor_message_id: recorded.vendor_message_id)
    end

    def record_error(message, token, started, error, result:, attempt_started_at:)
      raise error unless message && token

      if started
        complete_unknown(message, token, attempt_started_at, result: result, error: error)
        reconcile_recorded(message)
        log_outcome(message.sent_at ? "sent" : "unknown", message)
      end
      # Provider payloads and exception messages can contain raw SDK responses;
      # retain facts in the ledger, never dump them (or secrets) into logs.
      Rails.logger.warn("[sms.deliver] message=#{message.id} #{error.class}")
    end

    # Do not shadow ActiveJob::Instrumentation#instrument.
    def log_outcome(outcome, message, duration = nil)
      ActiveSupport::Notifications.instrument("sms.send", outcome: outcome, provider: message.provider, duration: duration)
    end
  end
end
