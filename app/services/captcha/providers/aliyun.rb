# frozen_string_literal: true

# Captcha::Providers (registry) is referenced by `register!` / `default!` calls
# at class-body load time. Force-load it so this file is safe to require in
# isolation (e.g. the eager loader that walks app/services in alphabetical
# order may hit aliyun.rb before providers.rb).
require_relative "../providers"

module Captcha
  module Providers
    # Aliyun Captcha 2.0 (RPC-style, HMAC-SHA1, v1.0 signing).
    #
    # The RPC v1.0 signature lives in Vendor::AliyunRpc — the one shared signer
    # for every Aliyun RPC adapter in the app (captcha, SMS, speech-to-text). It
    # is hand-rolled there because no maintained Ruby SDK covers Aliyun RPC APIs
    # (the official `aliyun-sdk` gem is OSS only), and it is golden-tested.
    #
    # Outcomes:
    #   :success              -> HTTP 200 + Result.VerifyResult == true
    #   :invalid              -> HTTP 200 + Result.VerifyResult == false
    #   :configuration_error  -> HTTP 4xx
    #   :unreachable          -> HTTP 5xx, timeout, network error
    class Aliyun < Base
      VERSION         = "2023-03-05"
      DEFAULT_ENDPOINT = "captcha.cn-shanghai.aliyuncs.com"
      DEFAULT_REGION   = "cn-shanghai"
      SDK_URL          = "https://o.alicdn.com/captcha-frontend/aliyunCaptcha/AliyunCaptcha.js"
      # https://www.alibabacloud.com/help/en/captcha/captcha2-0/user-guide/server-access
      ENDPOINTS = {
        "cn-shanghai" => %w[captcha.cn-shanghai.aliyuncs.com captcha-dualstack.cn-shanghai.aliyuncs.com captcha-vpc.cn-shanghai.aliyuncs.com],
        "ap-southeast-1" => %w[captcha.ap-southeast-1.aliyuncs.com captcha-dualstack.ap-southeast-1.aliyuncs.com captcha-vpc.ap-southeast-1.aliyuncs.com]
      }.freeze

      class << self
        def key                  = "aliyun"
        def default_display_name = "Aliyun Captcha"

        def config_fields
          [
            { name: :scene_id, label: "Scene ID", type: :string },
            { name: :prefix, label: "Identity credential", type: :string },
            { name: :endpoint, label: "Endpoint", type: :string, default: DEFAULT_ENDPOINT },
            { name: :region,   label: "Region",   type: :string, default: DEFAULT_REGION }
          ]
        end

        def configured?(settings)
          settings.access_key_id.present? &&
            settings.access_key_secret.present? &&
            settings.config_json.is_a?(Hash) &&
            settings.config_value(:scene_id).present? && settings.config_value(:prefix).present?
        end

        def valid_configuration?(config)
          return false unless config.is_a?(Hash)

          region = config.fetch("region", DEFAULT_REGION)
          ENDPOINTS.fetch(region, []).include?(config.fetch("endpoint", DEFAULT_ENDPOINT))
        end

        def widget(settings)
          {
            stimulus_controller: "captcha-aliyun",
            sdk_url:             SDK_URL,
            data: {
              "captcha-aliyun-scene-id-value" => settings.config_value(:scene_id).to_s,
              "captcha-aliyun-prefix-value"   => settings.config_value(:prefix).to_s,
              "captcha-aliyun-region-value"   => settings.config_value(:region, DEFAULT_REGION).to_s == "ap-southeast-1" ? "sgp" : "cn",
              "captcha-aliyun-locale-value"   => I18n.locale.to_s,
              "captcha-aliyun-sdk-url-value"  => SDK_URL
            }
          }
        end
      end

      register!
      default!

      def verify(context:)
        with_transport_rescue do
          url = host_url
          params = common_params.merge(
            "Action"             => "VerifyIntelligentCaptcha",
            "SceneId"            => settings.config_value(:scene_id).to_s,
            "CaptchaVerifyParam" => context.verify_param
          )
          res, json = http_post_form(url, sign_params(params))
          { outcome: map_outcome(res, json), http_status: res.code.to_i, raw: json, score: nil }
        end
      end

      # Binds this adapter's credential to the shared signer. The algorithm and
      # the "Signature" merge both live in Vendor::AliyunRpc; only the secret's
      # location is per-adapter.
      def sign_params(params)
        Vendor::AliyunRpc.sign(params, secret: settings.access_key_secret.to_s)
      end

      private

      def host_url
        raise Captcha::Errors::ConfigurationError unless self.class.valid_configuration?(settings.config_json)

        "https://#{settings.config_value(:endpoint, DEFAULT_ENDPOINT)}/"
      end

      def common_params
        Vendor::AliyunRpc.common_params(
          access_key_id: settings.access_key_id,
          region_id:     settings.config_value(:region, DEFAULT_REGION),
          version:       VERSION
        )
      end

      def map_outcome(res, json)
        code = res.code.to_i
        return :unreachable          if code >= 500
        return :configuration_error  if code >= 400
        result = json["Result"]
        return :unreachable unless result.is_a?(Hash) && [true, false].include?(result["VerifyResult"])
        return :success if result["VerifyResult"] == true
        :invalid
      end
    end
  end
end
