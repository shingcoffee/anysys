# frozen_string_literal: true

require "stripe"

module Payments
  module Gateways
    # Stripe card gateway — Visa / Mastercard / Amex / etc.
    # Implements the full Payments::Gateways::Base API surface via the official
    # `stripe` gem. All API traffic goes through a per-tenant Stripe::StripeClient
    # (built from this account's secret_key) so no credential is ever set globally —
    # a hard multi-tenant requirement. Webhook signatures are verified by
    # Stripe::Webhook::Signature rather than a hand-rolled HMAC.
    #
    # Credential fields (stored in encrypted credentials blob on MerchantAccount):
    #   - secret_key             (password, encrypted)
    #   - publishable_key        (string, not encrypted — sent to the browser)
    #   - webhook_signing_secret (password, encrypted)
    #
    # Flow: :card only (no QR/H5/JSAPI). The browser confirms via Stripe Payment Element
    # or SetupIntent — the PAN never reaches our servers (PCI SAQ-A).
    class Stripe < Base
      REPLAY_WINDOW = 300 # seconds — Stripe webhook signature tolerance

      class << self
        def key          = "stripe"
        def display_name = "Credit / Debit Card (Stripe)"

        def supported_flows = %i[card]

        def capabilities
          # No :reconciliation — Stripe has no downloadable settlement-bill flow
          # here (download_bill raises); reconciliation is Alipay/WeChat only.
          %i[one_time recurring tokenized_cards refunds webhooks]
        end

        def supported_currencies
          %w[usd eur gbp cad aud sgd hkd jpy cny]
        end

        def credential_fields
          [
            { name: :secret_key,             label: "Secret key",             type: :password, encrypted: true },
            { name: :publishable_key,        label: "Publishable key",        type: :string,   encrypted: false },
            { name: :webhook_signing_secret, label: "Webhook signing secret", type: :password, encrypted: true }
          ]
        end

        # In-page checkout widget descriptor consumed by Payments::WidgetCheckoutComponent.
        # The Stripe Payment Element renders card + wallets; our side supplies the submit button.
        def checkout_widget
          {
            controller:         "payments--stripe-card",
            value_keys:         %i[publishable_key client_secret],
            renders_pay_button: true,
            supports_save_card: true,
            secured_by:         "Stripe"
          }
        end

        # Stripe stamps our merchant_id in PaymentIntent/SetupIntent metadata.
        # Connect events also carry `account`. Either routes us to the right tenant.
        #
        # Dispute (dp_…) and Refund (re_…) objects carry their OWN metadata
        # (never stamped by us — empty) and direct (non-Connect) webhooks have
        # no top-level `account` field, so neither primary path resolves for
        # them. Fall back to the payment_intent id they reference, looked up
        # against the payment record we stored it on at charge time.
        #
        # Runs BEFORE signature verification — routing only, never trusted cryptographically.
        def extract_merchant_id(headers, body)
          json = notification_payload(body)
          object = notification_hash(notification_hash(json["data"])["object"])
          metadata = notification_hash(object["metadata"])
          operation_id = notification_id(object["payment_intent"])
          operation_id ||= notification_id(object["id"]) if json["type"].to_s.start_with?("payment_intent.")
          bound = merchant_id_for_payment_intent(operation_id)
          return bound if bound

          routed = notification_id(metadata["merchant_id"]) ||
            notification_id(json["account"]) ||
            notification_id(metadata["merchant_account_id"])
          return routed if routed
          return nil if headers.to_h.empty?

          authenticated_notification_account(headers: headers, body: body).merchant_id
        end

        # No routing hint is authenticated by its PSP ID alone. For a genuinely
        # uncorrelated signed event the official verifier can identify a unique
        # configured account; known local operations always take precedence.
        def authenticated_notification_account(headers:, body:)
          signature = headers["Stripe-Signature"] || headers["HTTP_STRIPE_SIGNATURE"]
          matches = Payments::MerchantAccount.unscoped_by_tenant.where(provider: key).select do |account|
            secret = account.credential(:webhook_signing_secret).to_s
            next false if secret.blank?

            ::Stripe::Webhook::Signature.verify_header(body.to_s, signature.to_s, secret, tolerance: REPLAY_WINDOW)
          rescue ::Stripe::SignatureVerificationError
            false
          end
          unless matches.one?
            raise Payments::Errors::SignatureInvalid, "notification signing account is invalid or ambiguous"
          end
          matches.first
        end

        def notification_payload(body)
          payload = parse_notification(body)
          object = notification_hash(notification_hash(payload["data"])["object"])
          notification_hash(object["metadata"])
          payload
        end

        # Look up the tenant's Stripe merchant id from a PaymentIntent id we
        # previously stored as a payment's psp_transaction_id. Lets dispute and
        # async-refund webhooks — which carry no metadata of their own — still
        # route to the right tenant + credentials.
        def merchant_id_for_payment_intent(payment_intent_id)
          return nil if payment_intent_id.blank?

          Payments::CredentialResolver.for_psp_operation(
            provider: key, psp_transaction_id: payment_intent_id
          )&.merchant_id
        end

        def event_id(payload)   = payload["id"].presence
        def event_type(payload) = payload["type"].presence
      end

      # Create a PaymentIntent for the card flow.
      # Returns { prepay_payload: { client_secret:, publishable_key: } }
      # The browser confirms via Stripe Payment Element — card never touches our server.
      #
      # When save_card: true the PaymentIntent is created with
      # setup_future_usage: "off_session" so Stripe vaults the payment method
      # alongside the one-time charge. The resulting PaymentMethod id is returned
      # via the payment_intent.payment_method field and backfilled to
      # Payments::PaymentMethod by the payment_intent.succeeded webhook handler.
      def charge(order:, payment:, flow:, openid: nil, save_card: false, user: nil)
        # Reopening an existing intent must not create another Customer or change
        # the original opt-in/parameters under its idempotency key.
        if payment.psp_transaction_id.present?
          res = stripe_call { as_hash(client.v1.payment_intents.retrieve(payment.psp_transaction_id)) }
          return charge_result(res, customer_id: payment.prepay_payload["psp_customer_id"],
                               save_card: payment.prepay_payload["save_card"] == true)
        end

        context = payment.prepay_payload
        save_card = context.fetch("save_card", save_card)
        params = {
          amount:                    amount_for(order),
          currency:                  order.currency.to_s.downcase,
          automatic_payment_methods: { enabled: true },
          description:               order.subject,
          metadata:                  { merchant_id: account.merchant_id, out_trade_no: payment.out_trade_no }
        }
        stripe_customer_id = nil
        if save_card
          params[:setup_future_usage] = "off_session"
          stripe_customer_id = context["psp_customer_id"].presence
          if stripe_customer_id.nil? && user
            stripe_customer_id = create_stripe_customer(user, idempotency_key: "#{payment.out_trade_no}-customer")
          end
          if stripe_customer_id
            params[:customer] = stripe_customer_id
          end
        end
        res = create_payment_intent(params, idempotency_key: payment.out_trade_no)
        charge_result(res, customer_id: stripe_customer_id, save_card: save_card)
      end

      # Query a PaymentIntent by psp_transaction_id (falling back to out_trade_no).
      def query(payment:)
        id = payment.psp_transaction_id.presence ||
             payment.prepay_payload["psp_payment_intent_id"].presence || payment.out_trade_no
        res = stripe_call { as_hash(client.v1.payment_intents.retrieve(id)) }
        currency = reported_currency(res["currency"])
        { status: map_status(res["status"]), psp_transaction_id: res["id"], raw: res,
          currency: currency,
          amount: reported_amount(res["amount_received"] || res["amount"], currency: currency, minor_units: true),
          settled_at: settlement_time(res) }
      end

      # Issue a refund against a captured PaymentIntent.
      def refund(payment:, refund:)
        res = stripe_call(financial_write: true) do
          as_hash(client.v1.refunds.create(
            {
              payment_intent: payment.psp_transaction_id,
              amount: Payments::Money.new(
                refund.amount,
                payment.payment_order.currency
              ).smallest_unit,
              # Echoed on refund.updated so we can settle before psp_refund_id
              # is written locally (the webhook can race the create response).
              metadata: { out_refund_no: refund.out_refund_no }
            },
            { idempotency_key: refund.out_refund_no }
          ))
        end
        { psp_refund_id: res["id"], status: (res["status"] == "succeeded" ? :succeeded : :processing), raw: res }
      end

      # Cancel a PaymentIntent.
      def close(payment:)
        stripe_call(financial_write: true) { client.v1.payment_intents.cancel(payment.psp_transaction_id) }
        { status: :closed }
      end

      # Create a Stripe Customer + SetupIntent so the browser can vault a card off-session.
      # Returns { client_secret:, psp_customer_id: }.
      def vault_card(user:, return_url:)
        customer_id = create_stripe_customer(user)
        seti = stripe_call do
          as_hash(client.v1.setup_intents.create(
            customer: customer_id,
            usage:    "off_session",
            metadata: { merchant_id: account.merchant_id }
          ))
        end
        { client_secret: seti["client_secret"], psp_customer_id: customer_id,
          setup_intent_id: seti["id"] }
      end

      # Billing is the platform's vault, not the authorizing admin's member
      # vault. All replay parameters come from the persisted billing identity.
      def billing_vault_card(payment_method:, return_url:)
        context = payment_method.payments_subscription.metadata.fetch("billing_authorization_context", {})
        metadata = { merchant_id: context.fetch("merchant_id", account.merchant_id), merchant_account_id: account.id,
          billing_payment_method_id: payment_method.id, billing_customer_id: payment_method.customer_id }
        prefix = "billing-method-#{payment_method.id}"
        customer = stripe_call(financial_write: true) do
          as_hash(client.v1.customers.create({ metadata: metadata }, { idempotency_key: "#{prefix}-customer" }))
        end
        intent = stripe_call(financial_write: true) do
          as_hash(client.v1.setup_intents.create({ customer: customer.fetch("id"), usage: "off_session",
            payment_method_types: ["card"], metadata: metadata }, { idempotency_key: "#{prefix}-setup" }))
        end
        { setup_intent_id: intent.fetch("id"), psp_customer_id: customer.fetch("id"),
          action: { kind: :stripe_setup, publishable_key: account.credential(:publishable_key), client_secret: intent.fetch("client_secret") } }
      end

      def billing_setup_intent(authorization_reference:)
        stripe_call { as_hash(client.v1.setup_intents.retrieve(authorization_reference, { expand: ["payment_method"] })) }
      end

      def billing_cancel_setup_intent(authorization_reference:)
        stripe_call(financial_write: true) { client.v1.setup_intents.cancel(authorization_reference) }
      end

      def billing_find_setup_intent(billing_payment_method_id:)
        customers = stripe_call do
          as_hash(client.v1.customers.search({ query: "metadata['billing_payment_method_id']:'#{Integer(billing_payment_method_id)}'", limit: 2 }))
        end.fetch("data")
        return nil unless customers.length == 1
        intents = stripe_call do
          as_hash(client.v1.setup_intents.list({ customer: customers.first.fetch("id"), limit: 100, expand: ["data.payment_method"] }))
        end.fetch("data")
        matches = intents.select { |intent| intent.dig("metadata", "billing_payment_method_id").to_s == billing_payment_method_id.to_s }
        matches.one? ? matches.first : nil
      end

      # A lost create response cannot be queried by our merchant trade number.
      # Search retrieves the exact metadata correlation without creating a new
      # charge; an empty eventually-consistent search is NOT proof of absence.
      def billing_query(payment:)
        if payment.psp_transaction_id.blank?
          response = stripe_call { as_hash(client.v1.payment_intents.search({ query: "metadata['out_trade_no']:'#{payment.out_trade_no}'", limit: 2 })) }
          matches = response.fetch("data")
          return { status: :unknown } unless matches.length == 1
          payment.update!(psp_transaction_id: matches.first.fetch("id"))
        end
        query(payment: payment)
      end

      # Off-session charge against a vaulted PaymentMethod token.
      # Returns { psp_transaction_id:, status:, raw: }
      def charge_token(order:, payment:, payment_method:)
        description = order.respond_to?(:subject) ? order.subject : order.plan_name
        res = create_payment_intent({
          amount:         amount_for(order),
          currency:       order.currency.to_s.downcase,
          customer:       payment_method.psp_customer_id,
          payment_method: payment_method.psp_payment_method_id,
          off_session:    true,
          confirm:        true,
          description:    description,
          metadata:       { merchant_id: account.merchant_id, out_trade_no: payment.out_trade_no }
        }, idempotency_key: payment.out_trade_no)
        charge_token_result(res)
      rescue Payments::Errors::ApiError => e
        # Off-session confirmation that needs SCA comes back HTTP 402 with the
        # PaymentIntent embedded in the error body. Surface it as recoverable
        # (with the client_secret) instead of a hard decline, so the member can
        # authenticate on-session.
        pi = e.payload.is_a?(Hash) ? e.payload.dig("error", "payment_intent") : nil
        raise unless pi && e.payload.dig("error", "code") == "authentication_required"

        requires_action_result(pi)
      end

      # Card-recurring: delegate to charge_token via subscription.payment_method.
      # The subscription duck-types as an order (amount, currency) plus plan_name.
      def charge_subscription(subscription:, payment:)
        order = ChargeAmount.new(
          amount:   payment.amount,
          currency: payment_currency(payment, subscription),
          subject:  subscription.plan_name,
          plan_name: subscription.plan_name
        )
        charge_token(order: order, payment: payment, payment_method: subscription.payment_method)
      end

      ChargeAmount = Struct.new(:amount, :currency, :subject, :plan_name, keyword_init: true)

      def payment_currency(payment, subscription)
        order = payment.respond_to?(:payment_order) ? payment.payment_order : nil
        order&.currency.presence || subscription.currency
      end
      private :payment_currency

      # Revoke a vaulted token at the PSP.
      def detach_token(payment_method:)
        stripe_call { client.v1.payment_methods.detach(payment_method.psp_payment_method_id) }
        { status: :removed }
      end

      # Fetch a PaymentMethod object from Stripe and return card details.
      # Returns { brand:, last4:, exp_month:, exp_year: } (string/integer values as
      # returned by Stripe). Used to backfill vault rows after setup_intent.succeeded.
      def fetch_payment_method(psp_pm_id)
        res = stripe_call { as_hash(client.v1.payment_methods.retrieve(psp_pm_id)) }
        card = res.dig("card") || {}
        {
          brand:     card["brand"],
          last4:     card["last4"],
          exp_month: card["exp_month"],
          exp_year:  card["exp_year"]
        }
      end

      def create_stripe_customer(user, idempotency_key: nil)
        params = { metadata: { user_id: user.id, merchant_id: account.merchant_id } }
        # Email is mutable and optional at Stripe. A checkout's keyed Customer
        # creation uses immutable identity only, so even a profile edit between
        # ambiguous retries cannot change the request behind that key.
        # https://docs.stripe.com/api/customers/create
        params[:email] = user.email unless idempotency_key
        stripe_call(financial_write: true) do
          as_hash(client.v1.customers.create(params, { idempotency_key: idempotency_key }.compact))
        end["id"]
      end
      private :create_stripe_customer

      # Card-recurring lifecycle is managed by our engine (Subscription + cron).
      # subscribe ensures a vaulted token exists; local-state stub only.
      def subscribe(subscription:)
        { status: :pending_sign }
      end

      # Local-state flip; actual token detach handled separately when last use.
      def cancel_subscription(subscription:)
        { status: :cancelled }
      end

      # Stripe reconciliation uses Sigma/Report Runs — not the bill-download model.
      def download_bill(bill_date:, bill_type:)
        raise Payments::Errors::ApiError.new(
          "Stripe reconciliation uses report runs (unsupported in this integration)",
          code: "unsupported", payload: {}
        )
      end

      # Lightweight connectivity check via GET /v1/account.
      # Returns { ok: Boolean, message: String, verified_at: Time }.
      # A valid secret key grants access to the account object; a 401 means the key is wrong.
      def ping
        # GET /v1/account is not surfaced as a v19 service method; raw_request
        # keeps the exact endpoint while still going through the gem's transport.
        ping_via("Stripe") { stripe_call { client.raw_request(:get, "/v1/account") } }
      end

      # Verify the Stripe-Signature header (HMAC-SHA256, 5-minute replay window)
      # via the gem's timing-safe verifier.
      # Raises Payments::Errors::SignatureInvalid on bad or stale signatures.
      def verify_notification(headers:, body:)
        secret = account.credential(:webhook_signing_secret).to_s
        raise Payments::Errors::CredentialsMissing, "Stripe webhook signing secret is not configured" if secret.blank?

        sig = headers["Stripe-Signature"] || headers["HTTP_STRIPE_SIGNATURE"]
        ::Stripe::Webhook::Signature.verify_header(
          body.to_s, sig.to_s, secret, tolerance: REPLAY_WINDOW
        )
        self.class.notification_payload(body)
      rescue ::Stripe::SignatureVerificationError => e
        # Preserve the pre-gem failure taxonomy the dispatcher/specs rely on:
        # timestamp problems (stale or unparsable header) => "stale", else "bad signature".
        reason = e.message.match?(/timestamp/i) ? "stale" : "bad signature"
        raise Payments::Errors::SignatureInvalid, reason
      end

      register!

      private

      def charge_result(res, customer_id:, save_card:)
        customer_id = res["customer"].is_a?(Hash) ? res["customer"]["id"] : res["customer"].presence || customer_id
        payload = { client_secret: res["client_secret"], publishable_key: account.credential(:publishable_key),
                    save_card: save_card || res["setup_future_usage"] == "off_session" }
        payload[:psp_customer_id] = customer_id if customer_id.present?
        { prepay_payload: payload, psp_transaction_id: res["id"], psp_customer_id: customer_id }
      end

      def settlement_time(res)
        return nil unless res["status"] == "succeeded"

        charge = res["latest_charge"]
        if charge.is_a?(String) && charge.present?
          charge = stripe_call { as_hash(client.v1.charges.retrieve(charge)) }
        end
        return nil unless charge.is_a?(Hash) && charge["created"].present?

        Time.zone.at(Integer(charge["created"]))
      rescue ArgumentError, TypeError
        raise Payments::Errors::TransportError, "invalid Stripe capture timestamp"
      end

      # Convert major-unit decimal amount to the smallest Stripe unit.
      def amount_for(order)
        Payments::Money.new(order.amount, order.currency).smallest_unit
      end

      # A 200 charge response that itself asks for authentication is treated the
      # same as the 402 path: recoverable, carrying the client_secret.
      def charge_token_result(res)
        return requires_action_result(res) if res["status"] == "requires_action"

        { psp_transaction_id: res["id"], status: map_status(res["status"]), raw: res }
      end

      def requires_action_result(payment_intent)
        { psp_transaction_id: payment_intent["id"], status: :requires_action,
          client_secret: payment_intent["client_secret"], raw: payment_intent }
      end

      def map_status(s)
        case s
        when "succeeded"                                                 then :succeeded
        when "requires_action"                                           then :requires_action
        when "processing", "requires_confirmation",
             "requires_payment_method", "requires_capture"               then :pending
        when "canceled"                                                  then :closed
        else :failed
        end
      end

      # Per-tenant API client built from this account's secret key — credentials
      # are never set on the global ::Stripe module (hard multi-tenant requirement).
      def client
        @client ||= begin
          secret = account.credential(:secret_key).to_s
          raise Payments::Errors::CredentialsMissing, "Stripe secret key is not configured" if secret.blank?

          ::Stripe::StripeClient.new(secret)
        end
      rescue ArgumentError
        raise Payments::Errors::CredentialsMissing, "invalid Stripe client configuration"
      end

      # idempotency_key: Stripe replays the original response for a repeated key
      # instead of creating a second charge/refund — so a transport retry after a
      # committed PSP write cannot double-charge. Keyed on our own out_trade_no /
      # out_refund_no (globally unique) by the callers.
      def create_payment_intent(params, idempotency_key:)
        stripe_call(financial_write: true) do
          as_hash(client.v1.payment_intents.create(params, { idempotency_key: idempotency_key }))
        end
      end

      # Run a stripe-gem call, mapping its exceptions onto the payments error
      # contract shared by every gateway (ApiError for HTTP-level rejections,
      # TransportError for network failures) so the Activities layer sees the
      # same classes regardless of transport.
      def stripe_call(financial_write: false)
        yield
      rescue ::Stripe::APIConnectionError => e
        raise Payments::Errors::TransportError, e.message
      rescue ::Stripe::StripeError => e
        # API v1 caches 500s and may reconcile them into real charges/refunds.
        # Transient 429/409 writes must likewise retain the original operation.
        # https://docs.stripe.com/error-low-level#server-errors
        should_retry = e.http_headers["stripe-should-retry"].to_s == "true"
        malformed_success = e.is_a?(::Stripe::APIError) && e.http_status.to_i.between?(200, 299)
        if financial_write && (e.http_status.to_i >= 500 || [409, 429].include?(e.http_status.to_i) || should_retry || malformed_success)
          raise Payments::Errors::TransportError, "uncertain Stripe write (HTTP #{e.http_status})"
        end
        raise Payments::Errors::ApiError.new("HTTP #{e.http_status} from api.stripe.com",
                                             code: e.http_status, payload: error_payload(e),
                                             definitive: definitive_stripe_rejection?(e))
      end

      def definitive_stripe_rejection?(error)
        return false unless [400, 401, 402, 403, 404].include?(error.http_status.to_i)
        return false if error.code == "authentication_required"

        # IdempotencyError is deliberately excluded: the earlier operation may
        # have succeeded even though this changed-parameter request was refused.
        [::Stripe::InvalidRequestError, ::Stripe::AuthenticationError,
         ::Stripe::PermissionError, ::Stripe::CardError].any? { |type| error.is_a?(type) }
      end

      def error_payload(error)
        JSON.parse(error.http_body.to_s)
      rescue JSON::ParserError
        { "raw" => error.http_body.to_s }
      end

      # `raw:` results are persisted and read back downstream — keep them plain
      # string-keyed hashes, never Stripe::StripeObject instances.
      def as_hash(obj)
        response_json(obj.to_json)
      end
    end
  end
end
