# frozen_string_literal: true

module Emails
  # Public provider callback endpoint for :webhook providers (e.g. SES, Aliyun). No
  # session/auth — trust is established by per-provider signature/basic-auth
  # verification. ActionController::API skips CSRF/session middleware.
  #
  #   POST /email/webhooks/:provider  — delivery / bounce / complaint events
  #
  # Providers post all event types to one URL; the provider's parse_events reads
  # the event type from the body.
  class WebhooksController < ActionController::API
    def create
      candidates = verified_providers
      events = candidates.first.first.parse_events(request)
      # Resolve the whole envelope before any receipt/suppression mutation.
      bound_events = events.map { |event| [event, credential_for_event(candidates.map(&:last), event)] }
      bound_events.each do |event, credential|
        Emails::ReceiptInbox.record!(credential: credential, event: event)
      end
      head :ok
    rescue WebhookCredentialBinding::Ambiguous
      head :conflict
    rescue ArgumentError
      head :not_found
    rescue Email::Errors::SignatureInvalid
      head :forbidden
    rescue Email::Errors::CredentialsMissing
      head :service_unavailable
    rescue Email::Errors::TransportError
      head :service_unavailable
    end

    private

    def provider = params[:provider].to_s

    # Retained credentials still verify receipts for sends accepted before they
    # were disabled. ReceiptInbox binds correlation to this exact credential ID.
    def verified_providers
      provider_class = Email::Providers.for(provider)
      unless provider_class.delivery_mechanism == :webhook
        raise ArgumentError, "provider #{provider} has no webhook endpoint"
      end

      credentials = Emails::Credential.where(provider: provider).order(:id)
      if credentials.empty?
        raise Email::Errors::CredentialsMissing, "no retained email credential for provider=#{provider}"
      end

      candidates = credentials.filter_map do |credential|
        adapter = provider_class.new(credential: credential)
        adapter.verify_webhook!(request)
        [adapter, credential]
      rescue Email::Errors::SignatureInvalid
        nil
      end
      return candidates if candidates.any?

      raise Email::Errors::SignatureInvalid, "no retained #{provider} credential verified the webhook signature"
    end

    def credential_for_event(credentials, event)
      # SES's authenticated sender account must agree with its configured SNS
      # account. Shared topic/key verification alone does not choose a mode.
      if provider == "ses"
        mail = event.dig(:raw, "mail")
        sender = mail["sendingAccountId"] if mail.is_a?(Hash)
        credentials = credentials.select { |credential| credential.config_value(:sns_topic_arn).to_s.split(":")[4] == sender } if sender.present?
        raise Email::Errors::SignatureInvalid, "SES sender account does not match verified credentials" if credentials.empty?
      end
      messages = if event[:provider_message_id].present?
        Emails::Message.where(provider: provider, provider_message_id: event[:provider_message_id])
      else
        Emails::Message.none
      end
      WebhookCredentialBinding.call(credentials: credentials, messages: messages) do |message|
        WebhookCredentialBinding.email_recipient?(message, event[:email])
      end
    end
  end
end
