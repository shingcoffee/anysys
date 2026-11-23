# frozen_string_literal: true

module Sms
  # Public vendor callback endpoint for :webhook adapters (e.g. Twilio). No
  # session/auth — trust is established by per-adapter signature verification.
  # ActionController::API skips CSRF/session middleware.
  #
  #   POST /sms/webhooks/:provider/delivery  — delivery-status callbacks (DLR)
  #   POST /sms/webhooks/:provider/inbound   — inbound messages (STOP → opt-out)
  class WebhooksController < ActionController::API
    MAX_ENVELOPE_BYTES = 64 * 1024

    before_action :limit_known_envelope_size

    def create
      candidates = verified_adapters
      adapter = candidates.first.first

      events = case params[:kind]
      when "delivery" then adapter.parse_delivery_receipt(request).map { |event| event.merge(type: :delivery) }
      when "inbound" then Array.wrap(adapter.parse_inbound(request)).map { |event| event.merge(type: :inbound) }
      else return head(:not_found)
      end
      bound_events = events.map { |event| [event, credential_for_event(candidates.map(&:last), event)] }
      bound_events.each { |event, credential| Sms::ReceiptInbox.record!(credential: credential, event: event) }
      if provider == "twilio" && params[:kind] == "inbound"
        render body: "<Response/>", content_type: "application/xml", status: :ok
      else
        head :ok
      end
    rescue WebhookCredentialBinding::Ambiguous
      head :conflict
    rescue ArgumentError
      head :not_found
    rescue Sms::Errors::SignatureInvalid
      head :forbidden
    rescue Sms::Errors::CredentialsMissing
      head :service_unavailable
    rescue Sms::Errors::TemplateVarsInvalid
      render json: { error: "invalid_request", message: I18n.t("sms_integration.errors.webhook_recipient_invalid") },
             status: :bad_request
    end

    private

    # Do not read an unbounded stream merely to measure it. Reject a known
    # oversized envelope before adapter verification/event parsing; the edge
    # server remains responsible for streaming/chunked request limits.
    def limit_known_envelope_size
      length = request.get_header("CONTENT_LENGTH").to_s
      head :content_too_large if length.match?(/\A\d+\z/) && length.to_i > MAX_ENVELOPE_BYTES
    end

    def provider = params[:provider].to_s

    # Resolve the adapter AND verify the request signature. Two guards beyond
    # the happy path:
    #   * Poll-only adapters (e.g. Aliyun) have no webhook — reject as 404
    #     rather than letting Base#verify_webhook! raise NotImplementedError
    #     (an unauthenticated 500 with a logged backtrace).
    #   * Disabled credentials retain ownership of their accepted sends. Verify
    #     retained keys across modes, then pass the verified ID to ReceiptInbox.
    def verified_adapters
      provider_class = Sms::Adapters.for(provider)
      unless provider_class.delivery_mechanism == :webhook
        raise ArgumentError, "provider #{provider} has no webhook endpoint"
      end

      credentials = Sms::Credential.where(provider: provider).order(:id)
      if credentials.empty?
        raise Sms::Errors::CredentialsMissing, "no retained sms credential for provider=#{provider}"
      end

      candidates = credentials.filter_map do |credential|
        adapter = provider_class.new(credential: credential)
        adapter.verify_webhook!(request)
        # AccountSid is covered by Twilio's signature, unlike a query-mode hint.
        sender = request.request_parameters["AccountSid"] if provider == "twilio"
        next if sender.present? && sender != credential.access_key_id

        [adapter, credential]
      rescue Sms::Errors::SignatureInvalid
        nil
      end
      return candidates if candidates.any?

      raise Sms::Errors::SignatureInvalid, "no retained #{provider} credential verified the webhook signature"
    end

    def credential_for_event(credentials, event)
      recipient = event_recipient(event)
      # Legacy delivery parsers supplied only raw["To"]. Carry that checked
      # recipient into the normalized envelope so inbox projection also guards
      # a mismatch when only one credential verified the signature.
      event[:phone] = recipient if recipient
      messages = if event[:type] == :delivery && event[:vendor_message_id].present?
        Sms::Message.where(provider: provider, vendor_message_id: event[:vendor_message_id])
      elsif event[:type] == :inbound
        recipient ? Sms::Message.where(provider: provider, to: recipient).where.not(sent_at: nil).where.not(status: "suppressed") : Sms::Message.none
      else
        Sms::Message.none
      end
      WebhookCredentialBinding.call(credentials: credentials, messages: messages) do |message|
        recipient.nil? || message.to == recipient
      end
    end

    def event_recipient(event)
      raw = event[:raw].is_a?(Hash) ? event[:raw] : {}
      # Inbound To is OUR sender number. The actual contact is the adapter's
      # normalized From; delivery To is the contact, with raw fallback only for
      # a legacy envelope lacking the normalized phone key.
      source = event[:type] == :inbound ? raw["From"] : raw["To"]
      value = event.key?(:phone) ? event[:phone] : (source if event[:type] == :delivery)
      return if value.nil? && (source.nil? || source == "")

      phone = Sms::PhoneNumber.new(value)
      unless phone.valid?
        raise Sms::Errors::TemplateVarsInvalid, I18n.t("sms_integration.errors.webhook_recipient_invalid")
      end

      phone.e164
    end
  end
end
