# frozen_string_literal: true

# AiAssistant::Providers (registry) is referenced by `register!` at
# class-body load time. Force-load it so this file is safe to require in
# isolation (eager load may hit this file before providers.rb).
require_relative "../providers"

module AiAssistant
  module Providers
    # Aliyun Intelligent Speech Interaction Flash Recognizer. Short clips
    # (5–120s) are POSTed as raw bytes — no OSS object. Token is minted through
    # Vendor::AliyunRpc, the one shared RPC v1.0 HMAC-SHA1 signer also used by
    # the Captcha and SMS Aliyun adapters (no maintained Ruby NLS SDK).
    #
    # Transcription only — #chat stays on Base (fail closed).
    class Aliyun < Base
      TOKEN_HOST     = "https://nls-meta.cn-shanghai.aliyuncs.com/"
      TOKEN_VERSION  = "2019-02-28"
      TOKEN_REGION   = "cn-shanghai"
      DEFAULT_REGION = "cn-shanghai"
      SUCCESS_STATUS = 20_000_000
      OPEN_TIMEOUT   = 5
      READ_TIMEOUT   = 30
      DEFAULT_FORMAT = "wav"

      class << self
        def key                  = "aliyun"
        def default_display_name = "Aliyun"

        def config_fields
          [
            { name: :access_key_id, label: "Access Key ID", type: :string, required: true },
            { name: :app_key,       label: "App Key",       type: :string, required: true },
            { name: :region,        label: "Region",        type: :string, default: DEFAULT_REGION }
          ]
        end

        def configured?(settings)
          settings.api_key.present? &&
            settings.config_value(:access_key_id).present? &&
            settings.config_value(:app_key).present?
        end
      end

      register!

      def transcribe(io:, filename:, content_type:, language: nil) # rubocop:disable Lint/UnusedMethodArgument
        # Flash language is owned by the Aliyun project / appkey.
        return { outcome: :configuration_error, text: nil, raw: nil } unless self.class.configured?(settings)

        token_result = create_token
        return token_result unless token_result[:outcome] == :success

        bytes = io.respond_to?(:read) ? io.read : io.to_s
        recognize(bytes, filename, content_type, token_result[:text])
      rescue OutboundHttp::TransportError => e
        { outcome: :unreachable, text: nil, raw: { "error" => e.message } }
      end

      # Binds this adapter's credential to the shared signer. The algorithm and
      # the "Signature" merge both live in Vendor::AliyunRpc; only the secret's
      # location is per-adapter.
      def sign_params(params)
        Vendor::AliyunRpc.sign(params, secret: settings.api_key.to_s)
      end

      def common_params
        Vendor::AliyunRpc.common_params(
          access_key_id: settings.config_value(:access_key_id),
          region_id:     TOKEN_REGION,
          version:       TOKEN_VERSION
        )
      end

      private

      def create_token
        res, json = http_post_form(TOKEN_HOST, sign_params(common_params.merge("Action" => "CreateToken")))
        status = res.status
        return { outcome: :unreachable, text: nil, raw: json } if status >= 500
        return { outcome: :configuration_error, text: nil, raw: json } if status >= 400

        token = json.dig("Token", "Id").to_s
        if token.blank?
          { outcome: :configuration_error, text: nil, raw: json }
        else
          { outcome: :success, text: token, raw: json }
        end
      end

      def recognize(bytes, filename, content_type, token)
        res = OutboundHttp.request(
          :post,
          flash_url(token, filename, content_type),
          headers: { "Content-Type" => "application/octet-stream" },
          body: bytes,
          open_timeout: OPEN_TIMEOUT,
          read_timeout: READ_TIMEOUT
        )
        json = safe_json(res.body)
        map_flash(res, json)
      end

      def flash_url(token, filename, content_type)
        query = {
          "appkey"      => settings.config_value(:app_key).to_s,
          "token"       => token,
          "format"      => audio_format(filename, content_type),
          "sample_rate" => "16000"
        }
        "#{gateway_host}/stream/v1/FlashRecognizer?#{URI.encode_www_form(query)}"
      end

      def gateway_host
        region = settings.config_value(:region, DEFAULT_REGION).presence || DEFAULT_REGION
        "https://nls-gateway-#{region}.aliyuncs.com"
      end

      def map_flash(res, json)
        status = res.status
        return { outcome: :unreachable, text: nil, raw: json } if status >= 500
        return { outcome: :configuration_error, text: nil, raw: json } if status >= 400

        vendor_status = json["status"].to_i
        return { outcome: :unreachable, text: nil, raw: json } if vendor_status.zero? || vendor_status >= 50_000_000
        return { outcome: :configuration_error, text: nil, raw: json } unless vendor_status == SUCCESS_STATUS

        text = Array(json.dig("flash_result", "sentences")).filter_map { |row| row["text"].to_s.strip }.join
        if text.blank?
          { outcome: :empty, text: nil, raw: json }
        else
          { outcome: :success, text: text, raw: json }
        end
      end

      # Flash's `format=` token, resolved from the one canonical audio table the
      # upload contract validates against. Unrecognised input cannot normally
      # reach here (the contract rejects it); DEFAULT_FORMAT keeps the request
      # well-formed if it ever does.
      def audio_format(filename, content_type)
        SpeechToText::AudioFormats.vendor_format(
          :aliyun, filename: filename, content_type: content_type, default: DEFAULT_FORMAT
        )
      end

      def http_post_form(url, params)
        res = OutboundHttp.request(:post, url, form: params, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
        [res, safe_json(res.body)]
      end

      def safe_json(str)
        JSON.parse(str.to_s)
      rescue JSON::ParserError
        { "raw" => str.to_s }
      end

    end
  end
end
