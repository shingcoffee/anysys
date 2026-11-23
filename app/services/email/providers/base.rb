# frozen_string_literal: true

require "json"

module Email
  module Providers
    # Abstract base for an email delivery provider. Subclasses declare:
    #   - `key` / `default_display_name`
    #   - `config_fields` — vendor config rendered by the credential form (SMTP
    #     keeps its typed columns; API vendors use the JSON config blob)
    #   - `configured?(credential)`
    #   - `delivery_mechanism` — :none (SMTP: status stops at `sent`) or :webhook
    #     (API vendors push delivery/bounce/complaint events)
    #   - instance `deliver(message:)` → { provider_message_id:, raw: }; raises
    #     Email::Errors::ApiError / TransportError on failure
    #   - instance `supports_message?` / `validate_message!` inspect capabilities
    #     before reservation; override protected `unsupported_features` as needed
    #
    # Webhook (:webhook) providers also implement `verify_webhook!(request)` and
    # `parse_events(request)` → [{ type: :delivered|:bounced|:complained,
    # provider_message_id:, email:, code:, message:, raw: }].
    #
    # See Email::Providers::Smtp (:none), Ses / Aliyun (:webhook).
    class Base
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 15

      # Identity/i18n class methods + initialize(credential:) come from the shared
      # mixin. `credential_label` falls back to the generic email credential label
      # so SMTP shows "Password" while API vendors show e.g. "Secret Access Key".
      include VendorPlugin.mixin(
        i18n_prefix: "email.providers",
        registry:    Email::Providers,
        inject:      :credential,
        credential_fallback: ->(name) { I18n.t("email.credentials.#{name}", default: name.to_s.humanize) }
      )

      class << self
        def delivery_mechanism = :none

        # Aliyun stores a shared secret in the encrypted webhook_secret
        # column. SES verifies the SNS signing cert instead, so the form hides
        # that field when this returns false.
        def uses_webhook_secret? = delivery_mechanism == :webhook
      end

      # @return [Hash] { provider_message_id:, raw: }
      def deliver(message:)
        raise NotImplementedError
      end

      # Inspect the unsaved ledger envelope before quota reservation/enqueue.
      # Providers override unsupported_features, keeping admission and dispatch
      # on one capability contract rather than duplicating vendor checks.
      def supports_message?(message:)
        unsupported_features(message: message).empty?
      end

      def validate_message!(message:)
        features = unsupported_features(message: message)
        return message if features.empty?

        reason = features.include?("one_click_unsubscribe") ? "unsupported_campaign" : "unsupported_message"
        raise Email::Errors::UnsupportedMessage.new(
          I18n.t("email.providers.errors.#{reason}", provider: self.class.display_name),
          code: "UNSUPPORTED_FEATURE", payload: { "features" => features }
        )
      end

      # --- webhook interface (:webhook providers) ---
      def verify_webhook!(_request)
        raise NotImplementedError
      end

      # @return [Array<Hash>] normalized delivery/bounce/complaint events
      def parse_events(_request)
        raise NotImplementedError
      end

      protected

      def unsupported_features(message:)
        []
      end

      def http_post_json(url, body, headers: {})
        res = OutboundHttp.request(:post, url, body: body,
                                   headers: headers.merge("Content-Type" => "application/json", "Accept" => "application/json"),
                                   open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
        [res, safe_json(res.body)]
      rescue OutboundHttp::TransportError => e
        raise Email::Errors::TransportError, e.message
      end

      def http_post_form(url, params, headers: {})
        res = OutboundHttp.request(:post, url, form: params, headers: headers,
                                   open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
        [res, safe_json(res.body)]
      rescue OutboundHttp::TransportError => e
        raise Email::Errors::TransportError, e.message
      end

      def safe_json(str)
        JSON.parse(str.to_s)
      rescue JSON::ParserError
        { "raw" => str.to_s }
      end
    end
  end
end
