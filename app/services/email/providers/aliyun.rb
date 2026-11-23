# frozen_string_literal: true

require "json"
require "base64"
require_relative "../providers"

module Email
  module Providers
    # Aliyun DirectMail (邮件推送) SingleSendMail + HTTP delivery callbacks.
    # Distinct from Aliyun SMS. `:webhook` mechanism — DirectMail pushes
    # MNS query-string or EventBridge CloudEvents bodies to
    # `/email/webhooks/aliyun`. Invalid-address (status 2) and spam (status 3)
    # suppress; generic failure (status 4) does not.
    #
    # Credential mapping: encrypted `password` is AccessKeySecret; config holds
    # `access_key_id`, `region`, `from_email` (AccountName), optional
    # `from_alias`. webhook_secret is Basic-auth (`aliyun:<secret>`) or `?token=`.
    #
    # Signing goes through Vendor::AliyunRpc — the one shared Aliyun RPC signer.
    class Aliyun < Base
      DEFAULT_REGION = "cn-hangzhou"
      VERSION        = "2015-11-23"
      DEFAULT_HOST   = "https://dm.aliyuncs.com/"

      class << self
        def key                  = "aliyun"
        def default_display_name = "Aliyun DirectMail"
        def delivery_mechanism   = :webhook

        def config_fields
          [
            { name: :access_key_id, label: "Access Key ID", type: :string },
            { name: :region,        label: "Region",        type: :string, default: DEFAULT_REGION },
            { name: :from_email,    label: "From email",    type: :string },
            { name: :from_alias,    label: "From alias",    type: :string }
          ]
        end

        def configured?(credential)
          credential.password.present? &&
            credential.config_value(:access_key_id).present? &&
            credential.config_value(:from_email).present?
        end
      end

      register!

      def deliver(message:)
        validate_message!(message: message)
        params = common_params.merge(send_params(message))
        _res, json = http_post_form(endpoint, sign_params(params))
        code = json["Code"].to_s
        if code.present? && code != "OK"
          raise Email::Errors::ApiError.new(json["Message"].presence || "Aliyun DirectMail send failed",
                                            code: code, payload: json)
        end
        env_id = json["EnvId"].to_s
        if env_id.blank?
          raise Email::Errors::ApiError.new(json["Message"].presence || "Aliyun DirectMail send failed",
                                            code: code.presence, payload: json)
        end
        { provider_message_id: env_id, raw: json }
      end

      def verify_webhook!(request)
        secret = credential.webhook_secret.to_s
        raise Email::Errors::SignatureInvalid, "webhook secret not configured" if secret.empty?

        expected_basic = "Basic #{Base64.strict_encode64("aliyun:#{secret}")}"
        provided_basic = request.headers["Authorization"].to_s
        return if secure_match?(provided_basic, expected_basic)

        token = query_token(request)
        return if secure_match?(token, secret)

        raise Email::Errors::SignatureInvalid, "invalid Aliyun webhook auth"
      end

      def parse_events(request)
        data = notification_hash(request)
        return [] if data.empty?

        status = data["status"].to_s
        env_id = data["env_id"].to_s
        email  = data["rcpt"].to_s
        err    = data["err_msg"].presence || data["err_code"].presence
        case status
        when "0"
          [event(:delivered, env_id, email, raw: data)]
        when "2"
          [event(:bounced, env_id, email, code: data["err_code"], message: err, suppress: true, raw: data)]
        when "3"
          [event(:complained, env_id, email, code: data["err_code"].presence || "spam",
                 message: err, suppress: true, raw: data)]
        when "4"
          [event(:bounced, env_id, email, code: data["err_code"], message: err, suppress: false, raw: data)]
        else
          []
        end
      end

      private

      def endpoint
        region = credential.config_value(:region, DEFAULT_REGION).to_s
        region.blank? || region == DEFAULT_REGION ? DEFAULT_HOST : "https://dm.#{region}.aliyuncs.com/"
      end

      def common_params
        Vendor::AliyunRpc.common_params(
          access_key_id: credential.config_value(:access_key_id),
          region_id:     credential.config_value(:region, DEFAULT_REGION),
          version:       VERSION
        )
      end

      def sign_params(params)
        Vendor::AliyunRpc.sign(params, secret: credential.password)
      end

      def send_params(message)
        recipients = address_list(message.to).uniq
        params = {
          "Action"        => "SingleSendMail",
          "AccountName"   => message.from.to_s.presence || credential.config_value(:from_email).to_s,
          "AddressType"   => "1",
          "ReplyToAddress" => "false",
          "ToAddress"     => recipients.join(","),
          "Subject"       => message.subject.to_s,
          "HtmlBody"      => message.body_html.to_s,
          "ClickTrace"    => "0"
        }
        params["TextBody"]  = message.body_text.to_s if message.body_text.present?
        alias_name = credential.config_value(:from_alias).to_s
        params["FromAlias"] = alias_name if alias_name.present?
        params
      end

      # This implemented RPC transport sends To + HTML/text only. The current
      # SingleSendMail API documents Headers/BccAddress/ReplyAddress, but this
      # adapter does not implement those semantics or raw MIME. SDK attachments
      # are not supported by the RPC signing path. Reject before acceptance and
      # again before dispatch instead of flattening/dropping message features.
      # https://help.aliyun.com/zh/direct-mail/api-dm-2015-11-23-singlesendmail
      def unsupported_features(message:)
        features = %i[cc bcc reply_to].select { |field| message.public_send(field).present? }.map(&:to_s)
        features << "one_click_unsubscribe" if message.message_type.to_s == "campaign"
        if Array(message.metadata&.dig("attachment_blob_ids")).any? || message.body_html.to_s.match?(/\bcid:/i)
          features << "inline_attachments"
        end
        features
      end

      def address_list(value)
        value.to_s.split(/[,\s]+/).map(&:strip).reject(&:blank?)
      end

      def query_token(request)
        if request.respond_to?(:query_parameters)
          request.query_parameters["token"].to_s
        else
          request.params.to_h["token"].to_s
        end
      end

      def notification_hash(request)
        raw = request.respond_to?(:raw_post) ? request.raw_post.to_s : ""
        parsed = parse_json_notification(raw)
        return parsed if parsed.any?

        form = request.respond_to?(:request_parameters) ? request.request_parameters : {}
        return stringify(form) if form.is_a?(Hash) && form["status"].present?

        parse_query_notification(raw)
      end

      def parse_json_notification(raw)
        json = JSON.parse(raw)
        return {} unless json.is_a?(Hash)

        data = json["data"]
        if data.is_a?(Hash)
          stringify(data).merge("event" => (json["type"] || data["event"]).to_s)
        else
          stringify(json)
        end
      rescue JSON::ParserError
        {}
      end

      def parse_query_notification(raw)
        stripped = raw.to_s.sub(/\A-+\s*Message\s*-+\s*/i, "")
        stringify(Rack::Utils.parse_query(stripped))
      end

      def stringify(hash)
        hash.to_h.transform_keys(&:to_s).transform_values { |v| v.is_a?(Hash) ? stringify(v) : v }
      end

      def secure_match?(given, expected)
        return false if given.blank? || expected.blank? || given.bytesize != expected.bytesize

        ActiveSupport::SecurityUtils.secure_compare(given, expected)
      end

      def event(type, provider_message_id, email, code: nil, message: nil, suppress: false, raw: {})
        { type: type, provider_message_id: provider_message_id, email: email,
          code: code, message: message, suppress: suppress, raw: raw }
      end
    end
  end
end
