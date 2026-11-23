# frozen_string_literal: true

require "json"
require "openssl"

# Force-load the registry so Base subclasses' `register!` calls work even when
# autoloaded out of order.
require_relative "../gateways"

module Payments
  module Gateways
    # Abstract base class for a payment gateway integration. Subclasses must:
    #
    #   - declare a stable `key` (e.g. "alipay") used as Payments::MerchantAccount#provider
    #   - declare a human-readable `display_name`
    #   - declare `credential_fields` — vendor-specific credential fields the
    #     Settings UI should render. Stored encrypted inside MerchantAccount#credentials.
    #     Each is `{ name:, label:, type: (:string|:password|:text), encrypted: bool }`.
    #   - declare `supported_flows` — subset of [:qr, :h5, :jsapi]
    #   - implement the API surface used by Payments::Activities::*:
    #       charge / query / refund / close / subscribe /
    #       cancel_subscription / charge_subscription /
    #       download_bill / verify_notification
    #   - implement `extract_merchant_id(headers, body)` — used by the
    #     webhook dispatcher to route a vendor callback to the right tenant
    #     before signature verification runs.
    #   - call `register!` at the end of the class body.
    #
    # See Payments::Gateways::Alipay / WechatPay for reference implementations.
    class Base
      class << self
        def key
          raise NotImplementedError, "#{name} must declare .key"
        end

        def display_name
          raise NotImplementedError, "#{name} must declare .display_name"
        end

        # Array of `{ name:, label:, type:, encrypted: }`. Encrypted values are
        # stored inside the JSON credentials blob and never round-trip back to
        # the form (placeholder shown instead).
        def credential_fields
          []
        end

        # Subset of [:qr, :h5, :jsapi, :card]. Used by FlowSelector to decide which
        # paths are even valid for this gateway. Card processors declare only
        # [:card]; China gateways declare [:qr, :h5, :jsapi].
        def supported_flows
          %i[qr h5 jsapi]
        end

        # Subset of [:one_time, :recurring, :tokenized_cards, :refunds,
        # :reconciliation, :webhooks]. Drives Settings UI badges and feature
        # guards (e.g. only show "save card for later" when :tokenized_cards).
        def capabilities
          %i[one_time refunds webhooks]
        end

        # ISO 4217 lowercase codes this gateway can transact in.
        def supported_currencies
          %w[cny]
        end

        # Zero-decimal (no minor unit) currencies per ISO 4217, sourced from
        # RubyMoney via Billing::CurrencyResolver rather than a hand-maintained list.
        def zero_decimal_currency?(code)
          Billing::CurrencyResolver.zero_decimal?(code)
        end

        # Per-gateway parser of incoming webhook bodies. Must return the
        # tenant-scoped merchant_id used to look up the right MerchantAccount,
        # without trusting the body cryptographically (verify_notification is
        # what does that, *after* the credential row is loaded).
        def extract_merchant_id(_headers, _body)
          raise NotImplementedError, "#{name} must implement .extract_merchant_id"
        end

        # Stable, PSP-assigned unique id for a verified notification, used by the
        # WebhookDispatcher as the event-level dedup key. Return nil when the
        # gateway's payload has no such id (dedup is then skipped; the per-payment
        # terminal-state check still guards replays).
        def event_id(_verified_payload) = nil

        # Human/audit label for the event (Stripe type, PayPal/WeChat event_type,
        # Alipay trade_status). Best-effort; nil is acceptable.
        def event_type(_verified_payload) = nil

        # In-page checkout widget descriptor for gateways whose :card-style flow mounts
        # a hosted JS widget (Stripe Payment Element, PayPal Smart Buttons). Returns nil
        # for redirect/QR gateways. Consumed by Payments::WidgetCheckoutComponent.
        def checkout_widget = nil

        # Parsing is only a routing/shape boundary, never signature verification.
        # JSON null/arrays and malformed nested containers must become a 400 at
        # WebhooksController, not a raw Ruby exception before verification.
        def parse_notification(body)
          payload = JSON.parse(body.to_s)
          raise Payments::Errors::SignatureInvalid, "notification must be a JSON object" unless payload.is_a?(Hash)

          payload
        rescue JSON::ParserError
          raise Payments::Errors::SignatureInvalid, "malformed notification JSON"
        end

        def notification_hash(value)
          return {} if value.nil?
          return value if value.is_a?(Hash)

          raise Payments::Errors::SignatureInvalid, "notification field must be an object"
        end

        def notification_array(value)
          return [] if value.nil?
          return value if value.is_a?(Array)

          raise Payments::Errors::SignatureInvalid, "notification field must be an array"
        end

        def notification_id(value)
          return nil if value.nil?
          return value.presence if value.is_a?(String)

          raise Payments::Errors::SignatureInvalid, "notification identifier must be a string"
        end

        def register!
          Payments::Gateways.register(self)
        end
      end

      def initialize(account:)
        @account = account
      end

      # Subclasses that support card-vaulting (e.g. Stripe) may declare
      # `save_card:` in their own override. The Base implementation absorbs
      # any extra keyword arguments via **kwargs so non-card gateways do not
      # need to declare parameters they will never use.
      def charge(order:, payment:, flow:, openid: nil, **kwargs); raise NotImplementedError; end
      def query(payment:);                              raise NotImplementedError; end
      def refund(payment:, refund:);                    raise NotImplementedError; end
      def close(payment:);                              raise NotImplementedError; end
      def subscribe(subscription:);                     raise NotImplementedError; end
      def cancel_subscription(subscription:);           raise NotImplementedError; end
      def charge_subscription(subscription:, payment:); raise NotImplementedError; end
      def download_bill(bill_date:, bill_type:);        raise NotImplementedError; end
      def verify_notification(headers:, body:);         raise NotImplementedError; end

      # Tokenization API — default raises NotImplementedError; overridden by
      # card-capable gateways (e.g. Stripe).
      def vault_card(user:, return_url:);                    raise NotImplementedError; end
      def detach_token(payment_method:);                     raise NotImplementedError; end
      def charge_token(order:, payment:, payment_method:);   raise NotImplementedError; end
      def fetch_payment_method(psp_pm_id);                   raise NotImplementedError; end

      # Lightweight connectivity check for the admin "Test connection" button.
      # Returns { ok: Boolean, message: String, verified_at: Time }.
      # Default: no-op success (for gateways that lack a cheap ping endpoint).
      # Card gateways (e.g. Stripe) override this to call a real API endpoint.
      def ping
        { ok: true, message: I18n.t("comp_payments.test_connection.ping_assumed_ok"), verified_at: Time.current }
      end

      protected

      # Shared connectivity-probe wrapper for card gateways whose ping is "call a
      # cheap endpoint; ApiError/TransportError means not-ok". Maps the outcome to
      # the standard { ok:, message:, verified_at: } hash so Stripe/PayPal (and any
      # future card PSP) don't each re-implement the same three-branch rescue.
      def ping_via(label)
        yield
        { ok: true, message: I18n.t("comp_payments.test_connection.ping_success", label: label),
          verified_at: Time.current }
      rescue Payments::Errors::ApiError, Payments::Errors::CredentialsMissing
        { ok: false, message: I18n.t("comp_payments.test_connection.ping_api_error", label: label),
          verified_at: Time.current }
      rescue Payments::Errors::TransportError
        { ok: false, message: I18n.t("comp_payments.test_connection.ping_network_error"),
          verified_at: Time.current }
      end

      attr_reader :account

      # Canonical PSP notification (webhook) URL for this gateway. Tenants may
      # override it per-account via notify_url_override; otherwise we build the
      # standard route from the gateway key. Shared by every gateway whose PSP
      # pushes asynchronous callbacks (Alipay, WeChat Pay, ...).
      def notify_url
        account.notify_url_override.presence ||
          Rails.application.routes.url_helpers.payments_webhook_url(
            **canonical_url_options, provider: self.class.key
          )
      end

      # Shopper-facing result URL the PSP should return to after an H5/WAP cashier.
      def result_url(payment)
        Rails.application.routes.url_helpers.payment_result_url(
          **canonical_url_options,
          customer_id: payment.customer_id,
          payment_id: payment.out_trade_no
        )
      end

      def canonical_url_options
        CanonicalUrlOptions.validate(Rails.application.default_url_options, production: Rails.env.production?)
      rescue ArgumentError
        raise Payments::Errors::CredentialsMissing, "invalid canonical application URL configuration"
      end

      # PSP calls must never hang a request thread: connect fast, allow slower
      # reads for bill downloads and slow acquirer responses.
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 30

      # Transport goes through OutboundHttp (the app-level Faraday wrapper);
      # this layer only owns the payments-specific error mapping.
      def http_post(url, body:, headers: {})
        do_request(:post, url, body: body, headers: headers)
      end

      def http_get(url, headers: {})
        do_request(:get, url, headers: headers)
      end

      # JSON convenience over the transport layer: issue the request and parse the
      # response body as JSON. Body encoding (form vs JSON) and auth/signature
      # headers stay the caller's concern — this only removes the repeated
      # JSON response parsing duplicated across every gateway.
      def post_json(url, body:, headers: {})
        response_json(http_post(url, body: body, headers: headers).body)
      end

      def get_json(url, headers: {})
        response_json(http_get(url, headers: headers).body)
      end

      def do_request(method, url, body: nil, headers: {})
        res = OutboundHttp.request(method, url, headers: headers, body: body,
                                   open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
        return res if res.success? || res.redirect?

        # A server error or throttled/conflicting write does not prove the PSP
        # did not execute it. Keep the caller's financial idempotency key alive.
        if method == :post && (res.code.to_i >= 500 || [409, 429].include?(res.code.to_i))
          raise Payments::Errors::TransportError, "uncertain PSP write (HTTP #{res.code})"
        end

        payload = safe_json(res.body)
        raise Payments::Errors::ApiError.new("HTTP #{res.code} from #{URI(url).host}",
                                             code: res.code, payload: payload,
                                             definitive: definitive_api_rejection?(status: res.code.to_i, payload: payload))
      rescue OutboundHttp::TransportError => e
        raise Payments::Errors::TransportError, e.message
      rescue OutboundHttp::InvalidRequestError
        raise Payments::Errors::CredentialsMissing, "invalid gateway URL or request configuration"
      end

      # A provider may positively identify non-execution. The shared HTTP layer
      # cannot infer it from an arbitrary client-error status/body.
      def definitive_api_rejection?(status:, payload:)
        false
      end

      def response_json(body)
        payload = JSON.parse(body.to_s)
        raise Payments::Errors::TransportError, "PSP response must be a JSON object" unless payload.is_a?(Hash)

        payload
      rescue JSON::ParserError
        raise Payments::Errors::TransportError, "malformed PSP response JSON"
      end

      def rsa_key(pem, private_key: false)
        key = OpenSSL::PKey::RSA.new(pem.to_s)
        if private_key && !key.private?
          raise Payments::Errors::CredentialsMissing, "gateway signing key must be a private RSA key"
        end
        key
      rescue OpenSSL::OpenSSLError, ArgumentError, TypeError
        raise Payments::Errors::CredentialsMissing, "invalid gateway RSA key configuration"
      end

      def rsa_sign(message)
        rsa_key(account.credential(:private_key_pem), private_key: true)
          .sign(OpenSSL::Digest::SHA256.new, message)
      rescue OpenSSL::OpenSSLError
        raise Payments::Errors::CredentialsMissing, "invalid gateway RSA signing configuration"
      end

      def verify_rsa_signature!(key:, signature:, message:)
        return if key.verify(OpenSSL::Digest::SHA256.new, signature, message)

        raise Payments::Errors::SignatureInvalid, "invalid notification signature"
      rescue OpenSSL::OpenSSLError
        raise Payments::Errors::SignatureInvalid, "invalid notification signature"
      end

      # Optional normalized Query fields: major-unit BigDecimal, upper-case
      # currency and PSP settlement Time. Missing assertions stay nil; never
      # substitute wall-clock now or a locally expected currency here.
      def reported_amount(value, currency:, minor_units: false)
        return nil if value.nil? || currency.blank?

        if minor_units
          unless value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A\d+\z/))
            raise ArgumentError
          end
          money = Payments::Money.from_smallest_unit(value, currency)
        else
          money = Payments::Money.from_major(value, currency)
        end
        raise ArgumentError unless money&.amount&.finite?

        money.amount
      rescue ArgumentError, TypeError
        raise Payments::Errors::TransportError, "invalid PSP amount assertion"
      end

      def reported_currency(value)
        return nil if value.nil?
        return value.upcase if value.is_a?(String) && value.match?(/\A[A-Za-z]{3}\z/)

        raise Payments::Errors::TransportError, "invalid PSP currency assertion"
      end

      def reported_time(value, zone: Time.zone)
        return nil if value.blank?

        zone.parse(value.to_s) || raise(ArgumentError)
      rescue ArgumentError, TypeError
        raise Payments::Errors::TransportError, "invalid PSP settlement timestamp"
      end

      def safe_json(str)
        JSON.parse(str.to_s)
      rescue JSON::ParserError
        { "raw" => str.to_s }
      end
    end
  end
end
