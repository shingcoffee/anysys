# frozen_string_literal: true

require "base64"

module Payments
  module Gateways
    # PayPal Standard Checkout — Orders v2 API + Smart Payment Buttons.
    # Flow: server creates an Order (CAPTURE intent), browser approves via
    # Smart Buttons, server captures once the button callback fires (or the
    # status-poll/reconcile cron picks up APPROVED orders).
    #
    # Implements the Payments::Gateways::Base API surface via REST calls through
    # OutboundHttp (the app's Faraday wrapper) — Basic-auth OAuth2 token + Bearer
    # JSON. Deliberately NOT on a PayPal SDK (evaluated 2026-07-15): the legacy
    # Ruby SDKs are deprecated, and the official paypal-server-sdk 2.3.0 covers
    # orders/payments/vault/transaction_search/subscriptions/oauth but NOT
    # notifications/verify-webhook-signature — the one security-sensitive call —
    # so adopting it would split this gateway across two HTTP transports for
    # byte-identical behavior. Revisit when the SDK gains a notifications API.
    #
    # Credential fields (stored in encrypted credentials blob on MerchantAccount):
    #   - client_id      (string, not encrypted — sent to the browser for Smart Buttons)
    #   - client_secret  (password, encrypted)
    #   - webhook_id     (string, not encrypted — referenced during signature verification)
    #
    # Flow: :card only (Smart Payment Buttons handle card + PayPal wallet in one widget).
    #
    # Named `Paypal` (not `PayPal`) to satisfy Zeitwerk's file-to-constant mapping
    # (`paypal.rb` → `Paypal`). The canonical alias `PayPal` is defined below.
    class Paypal < Base
      NONEXECUTION_ISSUES = %w[INSTRUMENT_DECLINED INVALID_PARAMETER_VALUE MISSING_REQUIRED_PARAMETER CURRENCY_NOT_SUPPORTED].freeze

      class << self
        # NOTE: the OAuth2 client-credentials flow and Orders v2 calls are
        # intentionally hand-rolled: PayPal has deprecated all of its Ruby
        # SDKs (paypal-checkout-sdk et al). Webhook verification delegates to
        # PayPal's verify-webhook-signature endpoint rather than local crypto.
        def key          = "paypal"
        def display_name = "PayPal"

        def supported_flows = %i[card]

        def capabilities
          %i[one_time refunds webhooks]
        end

        def supported_currencies
          %w[usd eur gbp cad aud jpy chf hkd sgd nzd sek dkk nok pln]
        end

        def credential_fields
          [
            { name: :client_id,     label: "Client ID",     type: :string,   encrypted: false },
            { name: :client_secret, label: "Client secret", type: :password, encrypted: true },
            { name: :webhook_id,    label: "Webhook ID",    type: :string,   encrypted: false }
          ]
        end

        # In-page checkout widget descriptor consumed by Payments::WidgetCheckoutComponent.
        # The :card flow mounts PayPal Smart Buttons, which handle both PayPal wallet
        # and card payments — no separate pay button needed from our side.
        def checkout_widget
          {
            controller:         "payments--paypal-buttons",
            value_keys:         %i[client_id paypal_order_id currency],
            renders_pay_button: false,
            supports_save_card: false,
            secured_by:         "PayPal"
          }
        end

        # Pull the tenant's merchant_id from the webhook body. PayPal stamps
        # custom_id on the resource (or inside purchase_units[0]).
        # Runs BEFORE signature verification — routing only, never trusted cryptographically.
        def extract_merchant_id(_headers, body)
          json = notification_payload(body)
          resource = notification_hash(json["resource"])
          unit = notification_hash(notification_array(resource["purchase_units"]).first)
          mid = notification_id(resource["custom_id"]) || notification_id(unit["custom_id"])
          return mid if mid.present?

          if json["event_type"] == "PAYMENT.CAPTURE.REFUNDED"
            mid = merchant_id_for_refund(invoice_id: notification_id(resource["invoice_id"]),
                                         refund_id: notification_id(resource["id"]))
            return mid if mid

            related = notification_hash(notification_hash(resource["supplementary_data"])["related_ids"])
            return merchant_id_for_capture(notification_id(related["capture_id"]) || capture_link_id(resource))
          end

          # Dispute webhooks (CUSTOMER.DISPUTE.*) carry no custom_id; resolve the
          # tenant from the disputed capture id (= our payment.psp_transaction_id).
          disputed = notification_hash(notification_array(resource["disputed_transactions"]).first)
          merchant_id_for_capture(notification_id(disputed["seller_transaction_id"]))
        end

        def notification_payload(body)
          payload = parse_notification(body)
          resource = notification_hash(payload["resource"])
          notification_array(resource["purchase_units"]).each { |unit| notification_hash(unit) }
          notification_array(resource["disputed_transactions"]).each { |transaction| notification_hash(transaction) }
          notification_array(resource["links"]).each { |link| notification_hash(link) }
          notification_hash(notification_hash(resource["supplementary_data"])["related_ids"])
          payload
        end

        def merchant_id_for_refund(invoice_id:, refund_id:)
          refunds = Payments::Refund.unscoped_by_tenant.joins(:payment).where(payments: { provider: key })
          refund = refunds.find_by(out_refund_no: invoice_id) if invoice_id.present?
          if refund.nil? && refund_id.present?
            matches = refunds.where(psp_refund_id: refund_id).limit(2).to_a
            refund = matches.first if matches.one?
          end
          merchant_id_for_payment(refund.payment) if refund
        end

        # Routing only: no HTTP request to an unverified notification's link.
        # The Refund representation uses rel=up to link its parent Capture.
        # https://developer.paypal.com/api/payments/v2/captures-refund/
        def capture_link_id(resource)
          link = notification_array(resource["links"]).find { |entry| entry["rel"] == "up" }
          return nil unless link

          uri = URI.parse(notification_id(link["href"]).to_s)
          uri.path.match(%r{\A/v2/payments/captures/([A-Za-z0-9_-]+)\z})&.captures&.first
        rescue URI::InvalidURIError
          nil
        end

        # Look up the tenant's PayPal merchant id from a capture id we previously
        # stored as a payment's psp_transaction_id. Lets dispute webhooks — which
        # don't echo our custom_id — still route to the right tenant + credentials.
        def merchant_id_for_capture(capture_id)
          return nil if capture_id.blank?

          Payments::CredentialResolver.for_psp_operation(
            provider: key, psp_transaction_id: capture_id
          )&.merchant_id
        end

        def merchant_id_for_payment(payment)
          return nil unless payment.provider == key && payment.merchant_account_id.present?

          Payments::CredentialResolver.for_payment(customer: payment.customer, payment: payment).merchant_id
        end

        def event_id(payload)   = payload["id"].presence
        def event_type(payload) = payload["event_type"].presence
      end

      # Create a PayPal Order (CAPTURE intent).
      # Returns { prepay_payload: { paypal_order_id:, client_id:, currency:, intent: } }
      # The browser completes approval via Smart Buttons; capture is triggered by
      # the public status/result query after approval.
      #
      # **_ absorbs save_card: and other card-flow kwargs we do not support —
      # no vaulting in scope for this integration.
      def charge(order:, payment:, flow:, openid: nil, **_)
        res = api_post("/v2/checkout/orders", {
          intent: "CAPTURE",
          purchase_units: [
            {
              invoice_id: payment.out_trade_no,
              custom_id:  account.merchant_id,
              amount: {
                currency_code: order.currency.to_s.upcase,
                value:         amount_value(order)
              },
              description: order.subject
            }
          ]
        }, request_id: payment.out_trade_no)
        {
          prepay_payload: {
            paypal_order_id: res["id"],
            client_id:       account.credential(:client_id),
            currency:        order.currency.to_s.upcase,
            intent:          "capture"
          }
        }
      end

      # Poll an Order or capture an APPROVED one server-side.
      #
      # PayPal's recommended server-side capture: when the buyer has approved the
      # order (status APPROVED) but the browser-side onApprove callback did not
      # complete capture, a later status/result query captures server-side.
      def query(payment:)
        # Always use the Order id — psp_transaction_id holds the CAPTURE id after a
        # successful capture, and GET /v2/checkout/orders/<capture_id> would 404.
        id  = payment.prepay_payload["paypal_order_id"].presence || payment.psp_transaction_id
        order = api_get("/v2/checkout/orders/#{id}")

        case order["status"]
        when "COMPLETED"
          query_result(order, status: :succeeded)
        when "APPROVED"
          # Server-side capture: APPROVED means the buyer authorised but capture
          # was not yet issued. We capture now so the cron loop can close the gap.
          cap = api_post("/v2/checkout/orders/#{id}/capture", {}, request_id: "#{payment.out_trade_no}-capture")
          query_result(cap, status: cap["status"] == "COMPLETED" ? :succeeded : :pending)
        when "VOIDED"
          { status: :closed, psp_transaction_id: id, raw: order }
        else
          { status: :pending, psp_transaction_id: id, raw: order }
        end
      end

      # Issue a partial or full refund against a captured PayPal payment.
      def refund(payment:, refund:)
        currency = payment.payment_order.currency
        res = api_post("/v2/payments/captures/#{payment.psp_transaction_id}/refund", {
          amount: {
            value:         format_amount_value(refund.amount, currency),
            currency_code: currency.to_s.upcase
          },
          # Echoed on PAYMENT.CAPTURE.REFUNDED so we can settle before
          # psp_refund_id is written locally (the webhook can race the create response).
          invoice_id: refund.out_refund_no,
          custom_id: account.merchant_id
        }, request_id: refund.out_refund_no)
        {
          psp_refund_id: res["id"],
          status:        res["status"] == "COMPLETED" ? :succeeded : :processing,
          raw:           res
        }
      end

      # CAPTURE-intent orders have no pre-capture void in this integration.
      # Returning a local :closed would let Charge mark the sibling dead and
      # start another PSP while the PayPal order stays capturable.
      def close(payment:)
        raise Payments::Errors::ApiError.new(
          "PayPal CAPTURE-intent orders cannot be voided before capture",
          code: "cannot_close",
          payload: {}
        )
      end

      # PayPal reconciliation uses the Transaction Search API, which is not
      # implemented in this integration. Use the PayPal dashboard or API directly.
      def download_bill(bill_date:, bill_type:)
        raise Payments::Errors::ApiError.new(
          "PayPal reconciliation uses the Transaction Search API (unsupported in this integration)",
          code: "unsupported", payload: {}
        )
      end

      # Verify a PayPal webhook notification via their server-side signature check.
      # Headers arrive canonicalized as "Paypal-Transmission-Id" etc. by WebhookDispatcher.normalize_headers.
      # Raises Payments::Errors::SignatureInvalid when the PSP reports a bad signature.
      #
      # Defence-in-depth: we validate the cert URL origin before forwarding it to
      # PayPal's verify endpoint so an attacker cannot supply an arbitrary cert URL.
      # PayPal also validates server-side, but this is cheap and avoids the round-trip.
      def verify_notification(headers:, body:)
        payload = self.class.notification_payload(body)
        cert_url = headers["Paypal-Cert-Url"].to_s
        begin
          uri = URI.parse(cert_url)
          host = uri.scheme == "https" && uri.userinfo.nil? ? uri.host.to_s : ""
        rescue URI::InvalidURIError
          host = ""
        end
        raise Payments::Errors::SignatureInvalid, "bad cert url" unless host.end_with?(".paypal.com")

        res = api_post("/v1/notifications/verify-webhook-signature", {
          transmission_id:   headers["Paypal-Transmission-Id"],
          transmission_time: headers["Paypal-Transmission-Time"],
          cert_url:          headers["Paypal-Cert-Url"],
          auth_algo:         headers["Paypal-Auth-Algo"],
          transmission_sig:  headers["Paypal-Transmission-Sig"],
          webhook_id:        account.credential(:webhook_id),
          webhook_event:     payload
        })
        raise Payments::Errors::SignatureInvalid, "bad signature" unless res["verification_status"] == "SUCCESS"
        payload
      end

      # Lightweight connectivity check via an OAuth token fetch.
      # Returns { ok: Boolean, message: String, verified_at: Time }.
      def ping
        ping_via("PayPal") { access_token } # access_token raises on bad credentials
      end

      register!

      private

      def definitive_api_rejection?(status:, payload:)
        return false unless payload.is_a?(Hash)
        return true if [401, 403].include?(status) && %w[AUTHENTICATION_FAILURE NOT_AUTHORIZED].include?(payload["name"])
        return false unless [400, 422].include?(status)

        details = payload["details"]
        details.is_a?(Array) && details.any? && details.all? do |detail|
          detail.is_a?(Hash) && NONEXECUTION_ISSUES.include?(detail["issue"])
        end
      end

      # OAuth2 client-credentials token. Memoized per instance — valid for ~9 h;
      # a new gateway instance is constructed per request so no stale-token risk.
      def access_token
        @access_token ||= begin
          client_id     = account.credential(:client_id)
          client_secret = account.credential(:client_secret)
          res = http_post(
            "#{base_url}/v1/oauth2/token",
            body:    URI.encode_www_form("grant_type" => "client_credentials"),
            headers: {
              "Authorization" => "Basic #{Base64.strict_encode64("#{client_id}:#{client_secret}")}",
              "Content-Type"  => "application/x-www-form-urlencoded"
            }
          )
          token = response_json(res.body)["access_token"]
          raise Payments::Errors::CredentialsMissing, "PayPal access token is missing" unless token.is_a?(String) && token.present?

          token
        end
      end

      def base_url
        account.mode == "production" ? "https://api-m.paypal.com" : "https://api-m.sandbox.paypal.com"
      end

      def bearer_headers
        { "Authorization" => "Bearer #{access_token}", "Content-Type" => "application/json" }
      end

      # request_id: PayPal-Request-Id makes create-order / refund idempotent — a
      # retry with the same id returns the original result instead of a duplicate
      # capture/refund. Keyed on our own out_trade_no / out_refund_no by callers.
      def api_post(path, json_hash, request_id: nil)
        headers = bearer_headers
        headers["PayPal-Request-Id"] = request_id if request_id.present?
        post_json("#{base_url}#{path}", body: json_hash.to_json, headers: headers)
      end

      def api_get(path)
        get_json("#{base_url}#{path}", headers: bearer_headers)
      end

      def query_result(order, status:)
        capture = order.dig("purchase_units", 0, "payments", "captures", 0) || {}
        amount = capture["amount"] || {}
        currency = reported_currency(amount["currency_code"])
        { status: status, psp_transaction_id: capture["id"], raw: order,
          amount: reported_amount(amount["value"], currency: currency), currency: currency,
          settled_at: (reported_time(capture["create_time"]) if status == :succeeded) }
      rescue TypeError, NoMethodError
        raise Payments::Errors::TransportError, "malformed PayPal capture response"
      end

      # Format an order's amount for the PayPal API.
      # Zero-decimal currencies (JPY etc.) skip the .00 suffix.
      def amount_value(order)
        format_amount_value(order.amount, order.currency)
      end

      def format_amount_value(amount, currency)
        Payments::Money.new(amount, currency).decimal_string
      end
    end

    # Canonical alias so callers may use Payments::Gateways::PayPal or ::Paypal.
    PayPal = Paypal
  end
end
