# frozen_string_literal: true

require "twilio-ruby"

# Sms::Adapters (registry) is referenced by register! at load time.
require_relative "../adapters"

module Sms
  module Adapters
    # Twilio Programmable Messaging adapter (:webhook delivery mechanism — Twilio
    # pushes status callbacks and inbound messages to our webhook endpoints).
    #
    # Credential mapping onto the shared columns:
    #   access_key_id     -> Account SID
    #   access_key_secret -> Auth Token (encrypted; also the webhook-signing key)
    # config: `messaging_service_sid` (preferred) or `from` number.
    #
    # Templates map to an approved Content template SID
    # (template.provider_code("twilio")); vars ride as ContentVariables.
    #
    # Transport and webhook validation go through the official `twilio-ruby` gem
    # (per AGENTS.md: prefer a mature library over hand-rolled protocol/crypto
    # code). The gem is used per-call — a fresh Twilio::REST::Client is built from
    # this credential's SID/token so nothing leaks across tenants (no global
    # Twilio.configure). This adapter is the single app-level seam over the gem.
    class Twilio < Base
      STOP_WORDS = %w[STOP STOPALL UNSUBSCRIBE CANCEL END QUIT REVOKE OPTOUT].freeze
      # Twilio MessageStatus → our terminal/interim status.
      STATUS_MAP = {
        "delivered"   => :delivered,
        "undelivered" => :failed,
        "failed"      => :failed,
        "canceled"    => :failed,
        "sent"        => :unknown,
        "queued"      => :unknown,
        "sending"     => :unknown,
        "accepted"    => :unknown,
        "received"    => :unknown
      }.freeze
      DATE_FIELDS = %w[date_updated date_sent date_created].freeze
      RESPONSE_FIELDS = %i[sid status error_code error_message to from num_segments date_updated date_sent date_created account_sid messaging_service_sid].freeze
      AUDIT_FIELDS = (RESPONSE_FIELDS.map(&:to_s) + %w[code message]).freeze

      class << self
        def key                  = "twilio"
        def default_display_name = "Twilio"
        def delivery_mechanism   = :webhook
        def query_supported?     = true

        def config_fields
          [
            { name: :messaging_service_sid, label: "Messaging Service SID", type: :string },
            { name: :from,                  label: "From number",           type: :string }
          ]
        end

        def configured?(credential)
          credential.access_key_id.present? &&
            credential.access_key_secret.present? &&
            (credential.config_value(:messaging_service_sid).present? ||
             credential.config_value(:from).present?)
        end
      end

      register!

      def send_message(to:, template:, template_params:)
        params = message_params(to: to, template: template, template_params: template_params)
        client = rest_client
        raw = sdk_message_raw(client) { client.messages.create(**params) }
        # A 2xx create can still be a domain failure (Twilio echoes error_code on
        # the resource); treat it exactly like the non-2xx path.
        if raw["error_code"].present?
          raise Sms::Errors::ApiError.new(raw["error_message"].presence || I18n.t(Sms::Message::FAILURE_SEND),
                                         code: raw["error_code"], payload: raw)
        end
        { vendor_message_id: raw["sid"], raw: raw }
      rescue ::Twilio::REST::RestError => e
        # Twilio signals a send failure with a non-2xx status; the gem raises here
        # and still carries the machine-readable error_code/message in the body.
        body = rest_error_body(e)
        code = rest_error_code!(e, body)
        raise Sms::Errors::ApiError.new(body["message"].presence || body["error_message"].presence || I18n.t(Sms::Message::FAILURE_SEND),
                                       code: code, payload: body)
      rescue ::Twilio::REST::TwilioError => e
        # Network-level failure (DNS/connect/read timeout/refused) — the gem wraps
        # the Faraday error as a bare TwilioError (RestError is handled above).
        raise Sms::Errors::TransportError, e.message
      end

      # REST fallback for lost callbacks; use the retained sending account.
      def query(message:)
        client = rest_client
        raw = sdk_message_raw(client, expected_sid: message.vendor_message_id, require_status: true) do
          client.messages(message.vendor_message_id).fetch
        end

        delivery_event(raw, sid: raw["sid"], status: raw["status"], phone: raw["to"],
                       code: raw["error_code"], failure: raw["error_message"],
                       segments: raw["num_segments"], time: raw["date_updated"])
      rescue ::Twilio::REST::RestError => e
        body = rest_error_body(e, expected_sid: message.vendor_message_id)
        code = rest_error_code!(e, body, expected_sid: message.vendor_message_id)
        raise Sms::Errors::ApiError.new(body["message"].presence || body["error_message"].presence || I18n.t("sms_standards.errors.query_failed"),
                                       code: code, payload: body)
      rescue ::Twilio::REST::TwilioError => e
        raise Sms::Errors::TransportError, e.message
      end

      def verify_webhook!(request)
        provided = request.headers["X-Twilio-Signature"].to_s
        validator = ::Twilio::Security::RequestValidator.new(credential.access_key_secret.to_s)
        return if provided.present? &&
                  validator.validate(request.original_url, request.request_parameters, provided)

        raise Sms::Errors::SignatureInvalid, I18n.t("sms_standards.errors.invalid_signature")
      end

      def parse_delivery_receipt(request)
        p = request.request_parameters
        sid = p["MessageSid"] || p["SmsSid"]
        return [] if sid.blank?

        [delivery_event(p.to_h, sid: sid, status: p["MessageStatus"] || p["SmsStatus"], phone: p["To"],
                        code: p["ErrorCode"], failure: p["ErrorMessage"] || p["ChannelStatusMessage"],
                        segments: p["NumSegments"], time: p["DateUpdated"] || p["Timestamp"])]
      end

      def parse_inbound(request)
        p = request.request_parameters
        # Caller verifies the complete request with the official SDK first.
        # Signed Advanced Opt-Out classification is authoritative even for a
        # localized body. START/HELP are deliberately ignored: they must not
        # clear global or manual suppressions without a scoped consent model.
        opt_out_type = p["OptOutType"].to_s.upcase
        keyword = p["Body"].to_s.strip.upcase
        return nil if opt_out_type.present? && opt_out_type != "STOP"
        return nil unless opt_out_type == "STOP" || STOP_WORDS.include?(keyword)

        {
          phone: ReceiptDetails.phone(p["From"]), keyword: opt_out_type == "STOP" ? "STOP" : keyword,
          vendor_message_id: p["MessageSid"] || p["SmsSid"],
          account_sid: p["AccountSid"], messaging_service_sid: p["MessagingServiceSid"], raw: p.to_h
        }.compact
      end

      private

      # The official SDK stores parsed JSON on this call's HTTP client before
      # constructing MessageInstance. Construction can raise on date fields or
      # arrays, and error_code.to_i silently turns nonnumeric strings into 0.
      # Validate that original JSON, never a coerced resource, whenever available.
      # Only the SDK invocation is rescued; valid-response SDK bugs and errors in
      # application preparation/projection propagate rather than being relabeled.
      def sdk_message_raw(client, expected_sid: nil, require_status: false)
        begin
          resource = yield
        rescue JSON::ParserError
          response = sdk_response(client)
          if response
            validate_sdk_parse_failure!(response, expected_sid: expected_sid, require_status: require_status)
            raise
          end
          malformed_response!
        rescue TypeError, ArgumentError, NoMethodError
          response = sdk_response(client)
          validate_sdk_parse_failure!(response, expected_sid: expected_sid, require_status: require_status) if response
          raise
        end

        response = sdk_response(client)
        raw = response ? response_audit(response.body) : message_raw(resource)
        validate_resource!(raw, expected_sid: expected_sid, require_status: require_status)
        raw
      end

      def validate_sdk_parse_failure!(response, expected_sid:, require_status:)
        if (400..599).cover?(response.status_code)
          validate_error_envelope!(response.body, http_status: response.status_code, expected_sid: expected_sid)
        else
          validate_resource!(response_audit(response.body), expected_sid: expected_sid, require_status: require_status)
        end
      end

      def sdk_response(client)
        return unless client.respond_to?(:http_client)

        http = client.http_client
        http.last_response if http.respond_to?(:last_response)
      end

      def response_audit(body)
        body.is_a?(Hash) ? body.slice(*AUDIT_FIELDS) : {}
      end

      def validate_resource!(raw, expected_sid: nil, require_status: false)
        sid = resource_sid(raw["sid"])
        matching_sid = sid && (!expected_sid || sid == expected_sid)
        status = raw["status"]
        valid_status = status.nil? ? !require_status : status.is_a?(String) && status.present?
        unless matching_sid && valid_status && resource_fields_valid?(raw)
          malformed_response!(vendor_message_id: matching_sid ? sid : nil, raw: raw)
        end
      end

      def resource_fields_valid?(raw)
        valid_strings = %w[status error_message to from account_sid messaging_service_sid message].all? do |key|
          value = raw[key]
          value.nil? || value.is_a?(String)
        end
        valid_strings && (raw["error_code"].nil? || positive_integer?(raw["error_code"])) &&
          DATE_FIELDS.all? { |key| rfc2822_datetime?(raw[key]) } && segment_count_valid?(raw["num_segments"])
      end

      # A REST exception is an HTTP error envelope, not a Message resource.
      # Its optional status is the numeric HTTP status; Message status, dates
      # and segment fields must never be used to validate this different shape.
      def validate_error_envelope!(body, http_status:, expected_sid: nil)
        valid = body.is_a?(Hash) && http_status.is_a?(Integer) && http_status.between?(400, 599)
        if valid
          status = body["status"]
          valid = (status.nil? || (status.is_a?(Integer) && status == http_status)) &&
            %w[code error_code].all? { |key| body[key].nil? || positive_integer?(body[key]) } &&
            %w[message error_message more_info].all? { |key| body[key].nil? || body[key].is_a?(String) }
        end
        return if valid

        raw = response_audit(body)
        sid = resource_sid(raw["sid"])
        sid = nil if expected_sid && sid != expected_sid
        malformed_response!(vendor_message_id: sid, raw: raw)
      end

      def rest_error_code!(error, raw, expected_sid: nil)
        sid = resource_sid(raw["sid"])
        sid = nil if expected_sid && sid != expected_sid
        code = raw["error_code"] || raw["code"]
        if error.status_code >= 500
          # The worker treats HTTP 5xx as uncertain even if a body contains a
          # domain code; preserve a known ID as transport ambiguity when present.
          malformed_response!(vendor_message_id: sid, raw: raw) if sid
          return error.status_code
        end
        # Missing codes and the SDK's HTTP-status fallback (e.g. empty 400)
        # cannot establish a provider-level rejection. Never manufacture one.
        malformed_response!(vendor_message_id: sid, raw: raw) if code.nil? || code.to_i == error.status_code
        code
      end

      def positive_integer?(value)
        value.is_a?(Integer) ? value.positive? : value.is_a?(String) && value.match?(/\A[0-9]+\z/) && value.to_i.positive?
      end

      def segment_count_valid?(value)
        value.nil? || (value.is_a?(Integer) && value >= 0) || (value.is_a?(String) && value.match?(/\A[0-9]+\z/))
      end

      # REST resource dates are nullable RFC 2822 values per Twilio's contract;
      # no exact textual pattern, locale-dependent parser or invented timestamp.
      def rfc2822_datetime?(value)
        return true if value.nil?
        return false unless value.is_a?(String)

        Time.rfc2822(value)
        true
      rescue ArgumentError
        false
      end

      def resource_sid(value)
        validated_vendor_message_id(value, max_bytes: 128, format: /\A[A-Za-z0-9_]+\z/)
      end

      def delivery_event(raw, sid:, status:, phone:, code:, failure:, segments:, time:)
        {
          vendor_message_id: sid, status: STATUS_MAP.fetch(status.to_s, :unknown),
          provider_status: status.to_s, phone: ReceiptDetails.phone(phone),
          failure_code: code.presence&.to_s, failure_message: failure.presence,
          segments: ReceiptDetails.segments(segments), occurred_at: ReceiptDetails.time(time),
          account_sid: raw["AccountSid"] || raw["account_sid"],
          messaging_service_sid: raw["MessagingServiceSid"] || raw["messaging_service_sid"], raw: raw
        }.compact
      end

      # Per-call, per-tenant client — built from this credential's SID/token, with
      # the same open/read timeouts the shared HTTP transport uses (the gem's HTTP
      # client applies one timeout to both, so we set the finer open_timeout via a
      # connection block, which the gem runs after its own defaults).
      def rest_client
        http = ::Twilio::HTTP::Client.new(timeout: READ_TIMEOUT)
        http.configure_connection { |faraday| faraday.options.open_timeout = OPEN_TIMEOUT }
        ::Twilio::REST::Client.new(credential.access_key_id, credential.access_key_secret, nil, nil, http)
      end

      def message_params(to:, template:, template_params:)
        params = {
          to:                to,
          content_sid:       template.provider_code("twilio").to_s,
          content_variables: template_params.to_json
        }
        msid = credential.config_value(:messaging_service_sid)
        if msid.present?
          params[:messaging_service_sid] = msid.to_s
        else
          params[:from] = credential.config_value(:from).to_s
        end
        params[:status_callback] = Rails.application.routes.url_helpers.sms_webhook_url(
          provider: "twilio", kind: "delivery", host: ENV["APP_HOST"] || "localhost"
        )
        params
      end

      # Retain selected provider facts, never content/credential echoes or the
      # entire original body. The SDK replaces 5xx bodies before this boundary.
      def rest_error_body(error, expected_sid: nil)
        body = error.response&.body
        validate_error_envelope!(body, http_status: error.status_code, expected_sid: expected_sid)
        response_audit(body)
      end

      # The audit "raw" blob mirrors the fields the old JSON body carried.
      def message_raw(message)
        RESPONSE_FIELDS.to_h do |name|
          # SDK versions, partial create responses and test adapters may omit
          # optional attributes; do not assume every resource exposes them.
          value = message.public_send(name) if message.respond_to?(name)
          [name.to_s, value.is_a?(Time) ? value.rfc2822 : value]
        end
      end
    end
  end
end
