# frozen_string_literal: true

require "json"

module Captcha
  module Providers
    # Abstract base class for a captcha vendor integration. Subclasses must:
    #
    #   - declare a stable `key` (e.g. "aliyun") used as the DB row identifier
    #   - declare `default_display_name` — the English fallback shown when no
    #     `captcha.providers.<key>.name` translation exists
    #   - declare `config_fields` — vendor-specific fields the platform-owner UI
    #     should render. These are stored in ProviderSettings#config_json. Each
    #     `label` is the English fallback; the UI shows `field_label(field)`
    #     which translates `captcha.providers.<key>.fields.<name>` at call time.
    #   - implement `verify(settings:, context:)` returning a hash with
    #       :outcome  — one of :success, :invalid, :configuration_error, :unreachable
    #       :http_status
    #       :raw
    #       :score    — optional Float for score-based vendors (nil otherwise)
    #       :hostname — optional hostname the vendor echoed back
    #   - implement `configured?(settings)` — when may the verify activity skip
    #     the call and treat the request as :disabled instead?
    #   - declare `widget` — Stimulus controller name, SDK url, etc., consumed
    #     by Captcha::WidgetComponent. Returning nil disables in-page rendering.
    #
    # See Captcha::Providers::Aliyun for a complete reference implementation.
    class Base
      OPEN_TIMEOUT = 2
      READ_TIMEOUT = 3

      # Identity/i18n class methods + initialize(settings:) come from the shared
      # mixin. `credential_label` falls back to the generic platform-settings
      # label; providers may override per-vendor wording (e.g. Turnstile's
      # "Site Key" / "Secret Key") via a captcha.providers.<key>.credentials.<name>
      # translation.
      include VendorPlugin.mixin(
        i18n_prefix: "captcha.providers",
        registry:    Captcha::Providers,
        inject:      :settings,
        credential_fallback: ->(name) { I18n.t("captcha.platform_settings.#{name}") }
      )

      class << self
        # Whether this vendor returns a risk score (score-based) vs a binary
        # pass/fail token. Score-based vendors honour ProviderSettings#score_threshold.
        def score_based?
          false
        end

        def verify(settings:, context:)
          new(settings: settings).verify(context: context)
        end

        # Optional widget metadata. Override in subclasses to enable in-page
        # rendering. Return shape:
        #   { stimulus_controller: "captcha-aliyun", sdk_url: "https://...", ... }
        def widget(_settings)
          nil
        end

        def valid_configuration?(config)
          config.is_a?(Hash)
        end

        # Whether the provider renders an invisible widget (no user-visible
        # challenge). Used by Captcha::WidgetComponent to suppress the generic
        # "complete verification to enable submit" hint for invisible vendors.
        def invisible?
          false
        end
      end

      def verify(context:)
        raise NotImplementedError
      end

      protected

      # Transport goes through OutboundHttp (the app-level Faraday wrapper);
      # this layer only owns the captcha-specific error mapping. Captcha
      # verification sits on the request path, so the timeouts stay tight.
      def http_post_form(url, params)
        res = OutboundHttp.request(:post, url, form: params,
                                   open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
        [res, safe_json(res.body)]
      rescue OutboundHttp::TransportError => e
        raise Captcha::Errors::TransportError, e.message
      end

      # Every vendor's #verify ends in the same unreachable-on-transport-error
      # shape; wrap the vendor-specific request/mapping block in it rather than
      # repeating the rescue clause in each provider.
      def with_transport_rescue
        yield
      rescue Captcha::Errors::TransportError
        { outcome: :unreachable, http_status: nil, raw: nil, score: nil }
      rescue OutboundHttp::InvalidRequestError, URI::InvalidURIError, Captcha::Errors::ConfigurationError
        { outcome: :configuration_error, http_status: nil, raw: nil, score: nil }
      end

      def safe_json(str)
        parsed = JSON.parse(str.to_s)
        parsed.is_a?(Hash) ? parsed : { "raw" => str.to_s }
      rescue JSON::ParserError
        { "raw" => str.to_s }
      end
    end
  end
end
