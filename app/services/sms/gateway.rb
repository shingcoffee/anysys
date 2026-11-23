# frozen_string_literal: true

module Sms
  # Single public entry point for the SMS module. Host code and the
  # FeatureModules::Module handoff controller call .send / .query; all
  # vendor/credential/rate-limit/idempotency logic lives one layer down. The
  # adapter is resolved from the message's provider so send and query always use
  # the same vendor.
  class Gateway
    class << self
      def send(customer:, to:, template_key:, vars:, idempotency_key: nil, mode: nil, provider: nil, expires_at: nil)
        Sms::Activities::Send.call(
          customer: customer, to: to, template_key: template_key, vars: vars,
          idempotency_key: idempotency_key, mode: mode, provider: provider, expires_at: expires_at
        )
      end

      def send_campaign(customer:, recipient:, at: nil)
        Sms::Activities::Send.call_campaign(customer: customer, recipient: recipient, at: at)
      end

      def query(message:, mode: nil)
        return message if message.vendor_message_id.blank?

        identity = message.metadata || {}
        cred    = Sms::CredentialResolver.call(mode: identity["credential_mode"] || mode || Sms::CredentialResolver.default_mode,
                                               provider: message.provider, credential_id: identity["credential_id"])
        adapter = cred.adapter_class.new(credential: cred)
        result = adapter.query(message: message)
        # REST queries run against the recorded account; do not project a
        # response that unexpectedly identifies a different provider account.
        return message if result[:account_sid].present? && result[:account_sid] != cred.access_key_id

        apply_query_result(message, result)
      end

      def apply_query_result(message, result)
        DeliveryProjection.apply!(message: message, event: result)
        message
      end
    end
  end
end
