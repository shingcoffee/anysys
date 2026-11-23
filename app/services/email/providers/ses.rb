# frozen_string_literal: true

require "json"
require "uri"
require "aws-sdk-sesv2"
require "aws-sdk-sns"
require_relative "../providers"

module Email
  module Providers
    # AWS SES v2 SendEmail + SNS bounce/complaint/delivery webhooks.
    # `:webhook` mechanism — SES publishes events to SNS, which POSTs the
    # existing `/email/webhooks/ses` URL. Hard bounces and complaints suppress.
    #
    # Credential mapping: encrypted `password` is the AWS secret access key;
    # config holds `access_key_id`, `region`, `from_email`, optional
    # `sns_topic_arn`. SNS signatures are verified with aws-sdk-sns
    # MessageVerifier (not webhook_secret).
    class Ses < Base
      DEFAULT_REGION = "us-east-1"
      SNS_HOST = /\Asns\.[a-zA-Z0-9\-]{3,}\.amazonaws\.com(\.cn)?\z/
      SNS_ENVELOPE_TYPES = %w[Notification SubscriptionConfirmation UnsubscribeConfirmation].freeze

      class << self
        def key                  = "ses"
        def default_display_name = "AWS SES"
        def delivery_mechanism   = :webhook
        def uses_webhook_secret? = false

        def config_fields
          [
            { name: :access_key_id,  label: "Access Key ID",  type: :string },
            { name: :region,         label: "Region",         type: :string, default: DEFAULT_REGION },
            { name: :from_email,     label: "From email",     type: :string },
            { name: :sns_topic_arn,  label: "SNS topic ARN",  type: :string }
          ]
        end

        def configured?(credential)
          credential.password.present? &&
            credential.config_value(:access_key_id).present? &&
            credential.config_value(:from_email).present? &&
            credential.config_value(:sns_topic_arn).present?
        end
      end

      register!

      def deliver(message:)
        response = ses_client.send_email(send_email_params(message))
        raw = response.to_h
        { provider_message_id: response.message_id, raw: raw.stringify_keys }
      rescue Aws::SESV2::Errors::ServiceError => e
        raise Email::Errors::ApiError.new(e.message, code: e.code, payload: { "error" => e.message })
      rescue Seahorse::Client::NetworkingError, Aws::Errors::NoSuchEndpointError => e
        raise Email::Errors::TransportError, e.message
      end

      def verify_webhook!(request)
        raw = sns_raw(request)
        payload = sns_json(raw)
        unless SNS_ENVELOPE_TYPES.include?(payload["Type"].to_s)
          raise Email::Errors::SignatureInvalid, "unrecognized SNS type"
        end
        validate_sns_envelope!(payload)
        unless sns_verifier.authentic?(raw)
          raise Email::Errors::SignatureInvalid, "invalid SES SNS signature"
        end

        expected_arn = credential.config_value(:sns_topic_arn).to_s
        if expected_arn.blank?
          raise Email::Errors::SignatureInvalid, "SNS topic ARN is not configured"
        end
        return if payload["TopicArn"].to_s == expected_arn

        raise Email::Errors::SignatureInvalid, "SNS topic mismatch"
      rescue Aws::SNS::MessageVerifier::VerificationError, URI::InvalidURIError,
             OpenSSL::X509::CertificateError, OpenSSL::PKey::PKeyError, ArgumentError, TypeError
        raise Email::Errors::SignatureInvalid, "invalid SES SNS signature"
      end

      def parse_events(request)
        payload = sns_json(sns_raw(request))
        case payload["Type"]
        when "SubscriptionConfirmation"
          confirm_subscription(payload["SubscribeURL"])
          []
        when "UnsubscribeConfirmation"
          []
        when "Notification"
          parse_ses_notification(payload)
        else
          []
        end
      end

      private

      def ses_client
        Aws::SESV2::Client.new(
          access_key_id:     credential.config_value(:access_key_id).to_s,
          secret_access_key: credential.password.to_s,
          region:            credential.config_value(:region, DEFAULT_REGION).presence || DEFAULT_REGION
        )
      end

      def sns_verifier
        Aws::SNS::MessageVerifier.new
      end

      def send_email_params(message)
        if Array(message.metadata&.dig("attachment_blob_ids")).any? || message.body_html.to_s.match?(/\bcid:/i)
          return {
            from_email_address: message.from,
            destination: destination_for(message),
            content: { raw: { data: Email::MimeMessage.call(message: message).encoded } }
          }
        end

        body = { html: charset_data(message.body_html) }
        body[:text] = charset_data(message.body_text) if message.body_text.present?

        params = {
          from_email_address: message.from,
          destination:        destination_for(message),
          content: {
            simple: {
              subject: charset_data(message.subject),
              body:    body
            }
          }
        }
        replies = address_list(message.reply_to)
        params[:reply_to_addresses] = replies if replies.any?
        headers = rfc8058_headers(message)
        params[:content][:simple][:headers] = headers if headers.any?
        params
      end

      # RFC 8058 one-click unsubscribe — same stamps SMTP's DeliveryMailer
      # already adds. SES v2 Simple content accepts a headers array; without
      # it Gmail/Yahoo mailbox unsubscribe never fires for campaign mail.
      def rfc8058_headers(message)
        Email::MimeMessage.unsubscribe_headers(message).map { |name, value| { name: name, value: value } }
      end

      def destination_for(message)
        destination = { to_addresses: address_list(message.to) }
        cc  = address_list(message.cc)
        bcc = address_list(message.bcc)
        destination[:cc_addresses]  = cc  if cc.any?
        destination[:bcc_addresses] = bcc if bcc.any?
        destination
      end

      def charset_data(value)
        { data: value.to_s, charset: "UTF-8" }
      end

      def address_list(value)
        value.to_s.split(/[,\s]+/).map(&:strip).reject(&:blank?)
      end

      def sns_raw(request)
        raw = request.respond_to?(:raw_post) ? request.raw_post.to_s : ""
        return raw if raw.present?

        params = request.respond_to?(:request_parameters) ? request.request_parameters : {}
        params.is_a?(Hash) ? params.to_json : params.to_s
      end

      def sns_json(raw)
        parsed = JSON.parse(raw.to_s)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end

      # The SDK assumes strings and can otherwise leak URI/TypeError exceptions
      # from its certificate and canonical-string paths. Validate before fetch.
      def validate_sns_envelope!(payload)
        required = %w[Message MessageId Timestamp TopicArn SignatureVersion Signature SigningCertURL]
        required += %w[Token SubscribeURL] unless payload["Type"] == "Notification"
        unless required.all? { |key| payload[key].is_a?(String) && payload[key].present? } &&
               %w[1 2].include?(payload["SignatureVersion"]) &&
               %w[Subject Token SubscribeURL].all? { |key| payload[key].nil? || payload[key].is_a?(String) } &&
               !payload.key?("SigningCertUrl")
          raise Email::Errors::SignatureInvalid, "invalid SNS envelope"
        end

        uri = URI.parse(payload["SigningCertURL"])
        unless sns_uri?(uri) && uri.path.end_with?(".pem") && uri.query.nil? && uri.fragment.nil?
          raise Email::Errors::SignatureInvalid, "invalid SNS SigningCertURL"
        end
      end

      def sns_uri?(uri)
        uri.is_a?(URI::HTTPS) && uri.host.to_s.match?(SNS_HOST) && uri.userinfo.nil? && uri.port == 443
      end

      def parse_ses_notification(payload)
        inner = payload["Message"]
        inner = JSON.parse(inner.to_s) if inner.is_a?(String)
        return [] unless inner.is_a?(Hash)

        kind = inner["notificationType"].presence || inner["eventType"].to_s
        mail_id = hash_section(inner, "mail")["messageId"]
        return [] unless mail_id.is_a?(String) && mail_id.present?

        case kind
        when "Delivery"
          recipients = hash_section(inner, "delivery")["recipients"] || hash_section(inner, "mail")["destination"]
          Array(recipients).filter_map do |email|
            event(:delivered, mail_id, email, raw: inner) if email.is_a?(String) && email.present?
          end
        when "Bounce"
          bounce = hash_section(inner, "bounce")
          recipients_for(bounce, "bouncedRecipients").map do |recipient|
            event(:bounced, mail_id, recipient["emailAddress"], code: bounce["bounceType"],
                  message: recipient["diagnosticCode"], suppress: bounce["bounceType"] == "Permanent", raw: inner)
          end
        when "Complaint"
          recipients_for(hash_section(inner, "complaint"), "complainedRecipients").map do |recipient|
            event(:complained, mail_id, recipient["emailAddress"], code: "Complaint", suppress: true, raw: inner)
          end
        else
          []
        end
      rescue JSON::ParserError
        []
      end

      def hash_section(inner, key)
        inner[key].is_a?(Hash) ? inner[key] : {}
      end

      def recipients_for(section, key)
        return [] unless section[key].is_a?(Array)

        section[key].select do |recipient|
          recipient.is_a?(Hash) && recipient["emailAddress"].is_a?(String) && recipient["emailAddress"].present?
        end
      end

      def confirm_subscription(url)
        uri = URI.parse(url.to_s)
        unless sns_uri?(uri)
          raise Email::Errors::SignatureInvalid, "invalid SNS SubscribeURL"
        end

        OutboundHttp.request(:get, uri.to_s, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
      rescue URI::InvalidURIError
        raise Email::Errors::SignatureInvalid, "invalid SNS SubscribeURL"
      rescue OutboundHttp::TransportError => e
        raise Email::Errors::TransportError, e.message
      end

      def event(type, provider_message_id, email, code: nil, message: nil, suppress: false, raw: {})
        { type: type, provider_message_id: provider_message_id, email: email,
          code: code, message: message, suppress: suppress,
          raw: raw.respond_to?(:stringify_keys) ? raw.stringify_keys : raw }
      end
    end
  end
end
