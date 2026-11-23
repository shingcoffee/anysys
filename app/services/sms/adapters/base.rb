# frozen_string_literal: true

require "json"

module Sms
  module Adapters
    # Abstract base for an SMS vendor adapter. Subclasses must declare:
    #   - `key` — stable string id (DB provider column, webhook URL segment)
    #   - `default_display_name` — English fallback shown when no i18n name exists
    #   - `config_fields` — vendor-specific non-secret config (rendered by the
    #     platform credential form; stored in Sms::Credential#config)
    #   - `configured?(credential)` — readiness check
    #   - instance `send_message(to:, template:, template_params:)` → { vendor_message_id:, raw: }
    #   - instance `query(message:)` → { status:, raw: } (for :poll vendors)
    #
    # Webhook (:webhook) vendors also implement `verify_webhook!`,
    # `parse_delivery_receipt`, and (for STOP) `parse_inbound`.
    #
    # See Sms::Adapters::Aliyun (:poll) and Sms::Adapters::Twilio (:webhook).
    class Base
      # SMS vendor calls are quick request/response APIs — fail fast.
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10

      # Default per-phone rate-limit windows: [name, span_seconds, limit].
      DEFAULT_RATE_LIMIT_WINDOWS = [
        [:minute, 60,    1],
        [:hour,   3600,  5],
        [:day,    86_400, 10]
      ].freeze

      # Identity/i18n class methods + initialize(credential:) come from the shared
      # mixin; only the SMS-specific class methods stay below.
      include VendorPlugin.mixin(
        i18n_prefix: "sms.adapters",
        registry:    Sms::Adapters,
        inject:      :credential,
        credential_fallback: ->(name) { I18n.t("sms.credentials.#{name}", default: name.to_s.humanize) }
      )

      class << self
        # :poll — reconciliation cron queries the vendor for status.
        # :webhook — the vendor pushes delivery receipts to our webhook.
        def delivery_mechanism = :poll

        # Webhook vendors may also support callback-loss reconciliation. Keep
        # fake/minimal adapters usable; concrete vendors opt in explicitly.
        def query_supported? = false

        def rate_limit_windows = DEFAULT_RATE_LIMIT_WINDOWS
      end

      # --- send / query interface ---

      # @return [Hash] { vendor_message_id:, raw: }
      def send_message(to:, template:, template_params:)
        raise NotImplementedError
      end

      # @return [Hash] { status:, raw:, phone:, provider_status:,
      #   failure_code:, failure_message:, occurred_at:, segments: } (optional details)
      def query(message:)
        raise NotImplementedError
      end

      # --- webhook interface (:webhook vendors) ---

      # Raise Sms::Errors::SignatureInvalid if the request is not trustworthy.
      def verify_webhook!(_request)
        raise NotImplementedError
      end

      # @return [Array<Hash>] [{ vendor_message_id:, status:, raw: }, ...]
      def parse_delivery_receipt(_request)
        raise NotImplementedError
      end

      # @return [Hash, nil] { phone:, keyword: } for inbound STOP, else nil
      def parse_inbound(_request)
        nil
      end

      protected

      # Transport goes through OutboundHttp (the app-level Faraday wrapper);
      # this layer only owns the SMS-specific error mapping.
      def http_post_form(url, params, headers: {})
        res = OutboundHttp.request(:post, url, form: params, headers: headers,
                                   open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
        [res, safe_json(res.body)]
      rescue OutboundHttp::TransportError => e
        raise Sms::Errors::TransportError, e.message
      end

      def safe_json(str)
        JSON.parse(str.to_s)
      rescue JSON::ParserError
        { "raw" => str.to_s }
      end

      # Retain only a syntactically safe ID, never treating it as proof of
      # acceptance. The worker quarantines the attempt as unknown and can bind
      # an early genuine receipt or query the retained sending account.
      def malformed_response!(vendor_message_id: nil, raw: nil)
        raise Sms::Errors::TransportError.new(
          I18n.t("sms_standards.errors.malformed_response"),
          vendor_message_id: validated_vendor_message_id(vendor_message_id),
          payload: raw.is_a?(Hash) ? raw : nil
        )
      end

      def validated_vendor_message_id(value, max_bytes: 256, format: /\A[A-Za-z0-9_\-^.]+\z/)
        value if value.is_a?(String) && value.valid_encoding? && value.ascii_only? &&
          value.bytesize.between?(1, max_bytes) && value.match?(format)
      end
    end
  end
end
