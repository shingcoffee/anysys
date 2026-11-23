# frozen_string_literal: true

module Payments
  module Activities
    class HandleWebhook
      # A validly-signed success notification whose reported amount does not match
      # the amount we recorded for the payment MUST NOT mark the order paid — that
      # is how underpayment (a smaller capture) slips through. We refuse and log,
      # rather than raise, so the PSP is not driven into a retry storm over a
      # persistent discrepancy; the payment simply stays non-terminal for review.
      # When the payload carries no amount we proceed (nil == "not asserted").
      def self.amount_matches?(payment, notified_amount)
        return true if notified_amount.nil?
        notified_amount.to_d == payment.amount
      end

      def self.reject_amount_mismatch(payment, notified_amount)
        Rails.logger.error(
          "[payments.webhook] amount mismatch out_trade_no=#{payment.out_trade_no} " \
          "expected=#{payment.amount} notified=#{notified_amount}; not marking paid"
        )
      end

      # Per-PSP amount extractors → major-unit decimal amount (or nil when absent).
      def self.wechat_amount(payload)
        total = payload.dig("resource", "amount", "total") || payload.dig("amount", "total")
        return nil if total.nil?

        Payments::Money.from_smallest_unit(total, "CNY")&.amount
      end

      def self.alipay_amount(payload)
        Payments::Money.from_major(payload["total_amount"], "CNY")&.amount
      end

      def self.stripe_amount(object, currency)
        amt = object["amount_received"] || object["amount"]
        Payments::Money.from_smallest_unit(amt, currency)&.amount
      end

      def self.paypal_amount(resource)
        fields = paypal_amount_fields(resource)
        return nil unless fields

        value = fields["value"]
        return nil unless value.is_a?(String) || value.is_a?(Numeric)

        Payments::Money.from_major(value, paypal_currency_code(fields))&.amount
      end

      def self.paypal_currency(resource)
        fields = paypal_amount_fields(resource)
        return nil unless fields

        paypal_currency_code(fields)
      end

      def self.paypal_amount_fields(resource)
        return nil unless resource.is_a?(Hash)

        # Capture webhooks nest amount at the resource root. Order GET/capture
        # responses (Query) nest it under purchase_units[0] on the capture.
        fields = resource.dig("purchase_units", 0, "payments", "captures", 0, "amount")
        fields = resource["amount"] unless fields.is_a?(Hash)
        fields.is_a?(Hash) ? fields : nil
      end
      private_class_method :paypal_amount_fields

      def self.paypal_currency_code(fields)
        fields["currency_code"].presence || "USD"
      end
      private_class_method :paypal_currency_code

      def self.currency_mismatch?(payment, notified_currency)
        return false if notified_currency.blank?

        notified_currency.to_s.upcase != payment.payment_order.currency.to_s.upcase
      end
      private_class_method :currency_mismatch?

      # Amount-mismatch guard shared by every provider's success handler: compute
      # the notified cents once, and log + signal "drop" when it disagrees with
      # what we recorded. Returns true when the caller should stop processing.
      def self.reject_if_amount_mismatch?(payment, notified_amount)
        return false if amount_matches?(payment, notified_amount)

        reject_amount_mismatch(payment, notified_amount)
        true
      end

      # The success ritual shared by every provider's payment handler: run the
      # amount-mismatch guard, then mark the payment succeeded. Kept as one method
      # so the guard and the mark_succeeded! call cannot drift apart across the
      # four providers. Returns true when the payment was marked succeeded, false
      # when the guard rejected it — so a caller with post-success work (Stripe's
      # subscription reactivation) can skip it on rejection.
      def self.finalize_success!(payment, notified_amount:, psp_id:, at:, notify:, notified_currency: nil)
        if currency_mismatch?(payment, notified_currency)
          reject_amount_mismatch(payment, notified_amount)
          return false
        end
        return false if reject_if_amount_mismatch?(payment, notified_amount)

        payment.mark_succeeded!(psp_id: psp_id, at: at, notify: notify)
        settle_billing_invoice!(payment)
        true
      end

      # Billing collection charges live on platform-owned orders keyed
      # `billing-inv-<invoice id>`. A PSP success for that order must close the
      # invoice immediately — waiting for the next CollectInvoice tick left
      # captured invoices `open` (and collectible) until cron or a manual retry.
      def self.settle_billing_invoice!(payment)
        return unless payment.customer_id == Billing::Collector::PLATFORM_OWNER_CUSTOMER_ID

        ref = payment.payment_order&.external_ref.to_s
        return unless ref.start_with?("billing-inv-")

        invoice = Billing::Invoice.unscoped_by_tenant.find_by!(id: ref.delete_prefix("billing-inv-"))
        result = Billing::Activities::MarkInvoicePaid.call(invoice: invoice, payment: payment, source: :gateway)
        unless result.status.in?(%i[paid unchanged review_required])
          raise Payments::Errors::TransportError, "billing settlement projection incomplete: #{result.reason}"
        end
        result
      end

      # Alipay sends Beijing-local wall-clock strings with no UTC offset — parsing
      # them against the app's Time.zone (UTC) would silently shift paid_at by 8
      # hours. The Alipay gateway's own notify-time validation already parses
      # against this same zone (see Gateways::Alipay#reject_stale_notification!).
      ALIPAY_TIMEZONE = "Asia/Shanghai"

      # PSP-reported completion time (fallback: now). paid_at drives the
      # reconciliation reverse leg, so it must reflect PSP settlement time, not
      # local webhook-processing time. `zone:` lets a provider whose timestamps
      # carry no UTC offset (Alipay) be parsed against its own local zone instead
      # of the app's Time.zone.
      def self.psp_time(value, zone: Time.zone)
        return Time.zone.now if value.blank?

        zone.parse(value.to_s) || Time.zone.now
      rescue ArgumentError
        Time.zone.now
      end

      # Stripe timestamps embedded in objects (Refund#created, etc.) are Unix
      # seconds rather than ISO strings — a separate helper from psp_time, which
      # parses PSP wall-clock strings.
      def self.unix_time(value)
        value.present? ? Time.zone.at(value.to_i) : Time.zone.now
      end

      def self.call(provider:, verified_payload:, signing_merchant_id: nil, signing_account_id: nil)
        # Fail loudly for a registered gateway with no matching handler rather
        # than acknowledging a verified event that we never acted on.
        unless %w[wechat_pay alipay stripe paypal].include?(provider)
          raise ArgumentError, "no webhook handler for provider #{provider.inspect}"
        end
        signing_account = verified_account(provider: provider, signing_merchant_id: signing_merchant_id,
                                           signing_account_id: signing_account_id)
        return unless signing_account

        # Authorization events belong to Billing even when there is no trade
        # reference, or an agreement callback also carries trade-shaped fields.
        authorization = Billing::PaymentAuthorization.handle_verified_event!(account: signing_account, payload: verified_payload)
        return project_authorization!(authorization) if authorization

        case provider
        when "wechat_pay" then handle_wechat(verified_payload, signing_account)
        when "alipay"     then handle_alipay(verified_payload, signing_account)
        when "stripe"     then handle_stripe(verified_payload, signing_account)
        when "paypal"     then handle_paypal(verified_payload, signing_account)
        end
      end

      def self.project_authorization!(result)
        Current.customer = result.payment_method.customer if result.payment_method
        if result.status == :pending && result.reason.in?(%i[authorization_unknown authorization_unavailable])
          raise Payments::Errors::TransportError, "billing authorization projection unavailable: #{result.reason}"
        end
        result
      end
      private_class_method :project_authorization!

      # Identity comes from signature verification, never from the record named
      # by the payload. Disabled accounts still own their historical operations.
      def self.verified_account(provider:, signing_merchant_id:, signing_account_id:)
        scope = Payments::MerchantAccount.unscoped_by_tenant.where(provider: provider)
        if signing_account_id.present?
          account = scope.find_by(id: signing_account_id)
          unless account
            raise Payments::Errors::CredentialsMissing, "verified webhook account identity is unavailable"
          end
          # The dispatcher already verified this exact row. Merchant routing
          # labels can change after receipt; rechecking today's label consumes
          # a genuine historical settlement without ever projecting it.
          account
        elsif signing_merchant_id.present?
          scope.find_by(merchant_id: signing_merchant_id)
        end
      end
      private_class_method :verified_account

      # Verify that the merchant whose key signed the notification is the
      # SAME merchant that owns the payment referenced by `out_trade_no`.
      # If they differ, an attacker holding credentials for merchant A
      # could sign a body naming merchant B's trade_no and flip B's
      # payment status — the signature alone proves "some known merchant
      # signed", not "the merchant for this trade signed".
      def self.signing_matches_payment?(payment, signing_account, provider:)
        return false unless signing_account
        return false unless payment.provider == provider && signing_account.provider == provider
        return false unless signing_account.customer_id == payment.customer_id
        if payment.merchant_account_id.present?
          payment.merchant_account_id == signing_account.id
        else
          # Pre-snapshot operations used the environment's single account row.
          signing_account.mode == CredentialResolver.default_mode
        end
      end

      def self.find_verified_payment(provider:, signing_account:, **identifiers)
        Payments::Payment.unscoped_by_tenant
          .where(provider: provider, customer_id: signing_account.customer_id, **identifiers)
          .detect { |payment| signing_matches_payment?(payment, signing_account, provider: provider) }
      end
      private_class_method :find_verified_payment

      # Shared async-refund settlement. Looks the refund up by whichever id the
      # PSP echoes (out_refund_no for WeChat, psp_refund_id for Stripe/PayPal),
      # applies the same merchant-binding guard as payment notifications, and
      # transitions the refund. mark_succeeded!/mark_failed! are terminal-idempotent
      # and mark_succeeded! recalculates the order to partial_refund/refunded.
      def self.settle_refund(success:, provider:, signing_account:, notify:,
                             out_refund_no: nil, psp_refund_id: nil, psp_id: nil, at: Time.zone.now)
        scope = Payments::Refund.unscoped_by_tenant.joins(:payment)
                  .where(payments: { provider: provider, customer_id: signing_account.customer_id })
        bound = ->(refund) { signing_matches_payment?(refund.payment, signing_account, provider: provider) }
        refund = scope.where(out_refund_no: out_refund_no).detect(&bound) if out_refund_no.present?
        refund ||= scope.where(psp_refund_id: psp_refund_id).detect(&bound) if psp_refund_id.present?
        return unless refund
        return if psp_refund_id.present? && refund.psp_refund_id.present? && refund.psp_refund_id != psp_refund_id

        Current.customer = refund.payment.payment_order.customer
        if success
          refund.mark_succeeded!(at: at,
                                 psp_refund_id: psp_id || refund.psp_refund_id, notify: notify)
        else
          refund.mark_failed!(notify: notify)
        end
      end

      # WeChat refund callbacks arrive as their own event_type (REFUND.SUCCESS /
      # REFUND.ABNORMAL / REFUND.CLOSED) carrying resource.out_refund_no — NOT as a
      # payment trade_state of "REFUND" (which is why the old trade_state=="REFUND"
      # mapping never fired on a real refund notification).
      WECHAT_REFUND_EVENTS = %w[REFUND.SUCCESS REFUND.ABNORMAL REFUND.CLOSED].freeze

      def self.handle_wechat_refund(payload, signing_account)
        res = payload["resource"] || {}
        return unless res["out_refund_no"].present?

        status  = res["refund_status"]
        success = status == "SUCCESS"
        failed  = %w[ABNORMAL CLOSED].include?(status)
        return unless success || failed

        # REFUND.SUCCESS carries resource.success_time (RFC3339, WeChat's server
        # time zone/offset) — the PSP-reported settlement instant, not our
        # webhook-processing time.
        settle_refund(success: success, provider: "wechat_pay", signing_account: signing_account,
                      out_refund_no: res["out_refund_no"], psp_id: res["refund_id"], notify: payload,
                      at: psp_time(res["success_time"]))
      end

      def self.handle_wechat(payload, signing_account)
        return handle_wechat_refund(payload, signing_account) if
          WECHAT_REFUND_EVENTS.include?(payload["event_type"])

        out_trade_no = payload["out_trade_no"] || payload.dig("resource", "out_trade_no")
        return unless out_trade_no

        payment = find_verified_payment(provider: "wechat_pay", signing_account: signing_account, out_trade_no: out_trade_no)
        return unless payment

        Current.customer = payment.payment_order.customer

        psp_id = payload["transaction_id"] || payload.dig("resource", "transaction_id")
        trade_state = payload["trade_state"] || payload.dig("resource", "trade_state")

        # Idempotency: a replay of SUCCESS on an already-succeeded payment is
        # dropped. failed/closed MAY still transition to succeeded — the model
        # documents that a verified PSP capture outranks a locally pessimistic
        # terminal state (late SUCCESS after a premature Query close/fail).
        return settle_billing_invoice!(payment) if payment.status == "succeeded"

        case trade_state
        when "SUCCESS"
          success_time = payload.dig("resource", "success_time") || payload["success_time"]
          finalize_success!(payment, notified_amount: wechat_amount(payload),
                            psp_id: psp_id, at: psp_time(success_time), notify: payload)
        when "CLOSED", "REVOKED"
          # NOTE: "REFUND" is intentionally NOT here — refunds arrive as their own
          # event_type (handled above), not as a payment trade_state.
          payment.mark_closed!
        when "PAYERROR", "USERPAYING", "NOTPAY"
          # Non-terminal — leave as-is.
        end
      end

      def self.handle_alipay(payload, signing_account)
        return unless payload["out_trade_no"]

        payment = find_verified_payment(provider: "alipay", signing_account: signing_account,
                                        out_trade_no: payload["out_trade_no"])
        return unless payment

        Current.customer = payment.payment_order.customer

        # Idempotency: skip SUCCESS replays once captured. failed/closed still
        # recover when Alipay later confirms TRADE_SUCCESS / TRADE_FINISHED.
        # TRADE_CLOSED after a capture (post-refund) must not regress it — the
        # succeeded guard runs first, matching WeChat CLOSED/REVOKED.
        return settle_billing_invoice!(payment) if payment.status == "succeeded"

        case payload["trade_status"]
        when "TRADE_SUCCESS", "TRADE_FINISHED"
          finalize_success!(payment, notified_amount: alipay_amount(payload),
                            psp_id: payload["trade_no"],
                            at: psp_time(payload["gmt_payment"] || payload["notify_time"],
                                         zone: Time.find_zone(ALIPAY_TIMEZONE)),
                            notify: payload)
        when "TRADE_CLOSED"
          payment.mark_closed!
        end
      end

      # The verified account identity accompanies every dispatched event.
      def self.handle_stripe(payload, signing_account)
        event_type = payload["type"]
        object     = payload.dig("data", "object") || {}

        case event_type
        when "setup_intent.succeeded"
          backfill_payment_method_from_setup_intent(object, signing_account)
        when "payment_intent.succeeded"
          handle_stripe_payment_intent_succeeded(object, signing_account, event_time: payload["created"])
        when "refund.updated", "charge.refund.updated"
          handle_stripe_refund(object, signing_account)
        when "charge.dispute.created", "charge.dispute.updated", "charge.dispute.closed"
          record_stripe_dispute(object, signing_account)
        end
      end

      # Record/advance a Stripe dispute (chargeback). data.object is a Dispute
      # (dp_…) carrying the disputed payment_intent (pi_…), which our payment
      # stored as psp_transaction_id. The dispute row is upserted by dispute id,
      # so created → updated → closed events converge on one record.
      def self.record_stripe_dispute(object, signing_account)
        record_dispute(
          provider:            "stripe",
          psp_dispute_id:      object["id"],
          psp_transaction_id:  object["payment_intent"],
          signing_account:     signing_account,
          reason:              object["reason"],
          status:              map_stripe_dispute_status(object["status"]),
          raw:                 object,
          amount: ->(payment) {
            Payments::Money.from_smallest_unit(object["amount"], payment.payment_order.currency)&.amount
          }
        )
      end

      def self.map_stripe_dispute_status(status)
        case status
        when "won"                                  then "won"
        when "lost"                                 then "lost"
        when "warning_closed", "charge_refunded"    then "closed"
        when "under_review", "warning_under_review" then "under_review"
        else                                             "open"
        end
      end

      # Idempotent upsert keyed on (provider, psp_dispute_id). Terminal statuses
      # stamp resolved_at once; open_at is stamped on first sight.
      def self.upsert_dispute(provider:, psp_dispute_id:, payment:, reason:, status:, amount:, raw:)
        dispute = Payments::Dispute.unscoped_by_tenant
                    .find_or_initialize_by(provider: provider, psp_dispute_id: psp_dispute_id)
        dispute.payment       = payment
        dispute.customer_id ||= payment.customer_id
        dispute.reason        = reason if reason.present?
        if amount.to_d.positive?
          dispute.amount = amount
        elsif dispute.new_record?
          dispute.amount = 0
        end
        dispute.raw           = raw
        dispute.opened_at   ||= Time.zone.now

        # Out-of-order guard: PSP events are deduped per event id but NOT ordered —
        # a delayed non-terminal event must not reopen a resolved dispute.
        resolved_already  = dispute.persisted? && Payments::Dispute::RESOLVED_STATUSES.include?(dispute.status)
        incoming_resolved = Payments::Dispute::RESOLVED_STATUSES.include?(status)
        dispute.status = status unless resolved_already && !incoming_resolved
        if Payments::Dispute::RESOLVED_STATUSES.include?(dispute.status) && dispute.resolved_at.nil?
          dispute.resolved_at = Time.zone.now
        end
        dispute.save!
      end

      # Shared skeleton for the two provider dispute recorders: resolve the local
      # payment by its PSP transaction id, apply the same merchant-binding guard as
      # payment notifications, bind Current.customer, and upsert the dispute row.
      # `amount` is a callable because Stripe needs the resolved payment's
      # currency to convert its smallest-unit amount, while PayPal already carries
      # major units. Early-returns on missing ids / no payment / failed guard,
      # preserving each recorder's original short-circuits.
      def self.record_dispute(provider:, psp_dispute_id:, psp_transaction_id:, signing_account:,
                              reason:, status:, raw:, amount:)
        return unless psp_dispute_id.present? && psp_transaction_id.present?

        payment = find_verified_payment(provider: provider, signing_account: signing_account,
                                        psp_transaction_id: psp_transaction_id)
        return unless payment

        Current.customer = payment.payment_order.customer
        upsert_dispute(provider: provider, psp_dispute_id: psp_dispute_id, payment: payment,
                       reason: reason, status: status, amount: amount.call(payment), raw: raw)
      end

      # Stripe async refund result. data.object is a Refund (re_…); we bound the
      # local row to it via psp_refund_id at synchronous refund time.
      def self.handle_stripe_refund(object, signing_account)
        psp_refund_id = object["id"]
        return unless psp_refund_id.present?

        success = object["status"] == "succeeded"
        failed  = %w[failed canceled].include?(object["status"])
        return unless success || failed

        # Stripe Refund objects carry `created` (Unix seconds) — the PSP-reported
        # settlement instant, not our webhook-processing time. metadata.out_refund_no
        # is sent on refunds.create so we can match before psp_refund_id is persisted.
        settle_refund(success: success, provider: "stripe", signing_account: signing_account,
                      out_refund_no: object.dig("metadata", "out_refund_no"),
                      psp_refund_id: psp_refund_id, psp_id: psp_refund_id, notify: object,
                      at: unix_time(object["created"]))
      end

      # Backfill brand/last4/exp_month/exp_year/psp_payment_method_id on the
      # pending Payments::PaymentMethod row created by VaultCard or checkout
      # save-card (Charge inserts pending:<setup_intent_id|payment_intent_id>).
      #
      # setup_intent.succeeded does NOT carry payment_method_details.card — that
      # field appears on Charge objects. We fetch the real PaymentMethod object from
      # Stripe via Gateway#fetch_payment_method to get the card details.
      #
      # Tenant-binding guard: the MerchantAccount that signed the webhook must
      # belong to the SAME customer as the pending PaymentMethod. Without this,
      # any registered Stripe merchant could overwrite another tenant's pending
      # PaymentMethod row by crafting a setup_intent webhook.
      def self.backfill_payment_method_from_setup_intent(object, signing_account)
        psp_customer_id = object["customer"]
        psp_pm_id       = object["payment_method"]
        return unless psp_customer_id.present? && psp_pm_id.present?

        pm = locate_pending_payment_method(
          psp_customer_id: psp_customer_id,
          setup_intent_id: object["id"], customer_id: signing_account.customer_id
        )
        return unless pm

        return unless signing_account.provider == "stripe" && signing_account.customer_id == pm.customer_id

        Current.customer = pm.customer

        # Fetch card details from the PSP — the SetupIntent object does not
        # embed them; they live on the PaymentMethod resource itself.
        card = Payments::Gateway.fetch_payment_method(
          customer:  pm.customer,
          provider:  "stripe",
          psp_pm_id: psp_pm_id,
          merchant_account: signing_account, historical: true
        )

        original_placeholder = pm.psp_payment_method_id
        pm.with_lock do
          return unless pm.psp_payment_method_id == original_placeholder && pm.psp_customer_id == psp_customer_id
          pm.update!(
            psp_payment_method_id: psp_pm_id,
            brand: card[:brand], last4: card[:last4],
            exp_month: card[:exp_month], exp_year: card[:exp_year]
          )
        end
        authorization = Billing::PaymentAuthorization.sync_payment_method!(
          payment_method: pm,
          verified_event: Billing::PaymentAuthorization.verified_event(account: signing_account, payload: object)
        )
        project_authorization!(authorization) if authorization
      end

      def self.locate_pending_payment_method(psp_customer_id:, setup_intent_id:, customer_id:)
        return if setup_intent_id.blank?
        pending = Payments::PaymentMethod
                    .unscoped_by_tenant
                    .where(provider: "stripe", customer_id: customer_id, psp_customer_id: psp_customer_id)
                    .where("psp_payment_method_id LIKE ?", "#{Payments::PaymentMethod::PENDING_TOKEN_PREFIX}%")

        pending.find_by(psp_payment_method_id: "#{Payments::PaymentMethod::PENDING_TOKEN_PREFIX}#{setup_intent_id}")
      end

      # PayPal PAYMENT.CAPTURE.COMPLETED — final state for a captured Order.
      #
      # `resource["invoice_id"]` is present on capture resources because we set
      # `purchase_units[].invoice_id = out_trade_no` at order creation and PayPal
      # propagates invoice_id from the order's purchase unit down to each capture.
      #
      # The query()/status-poll path is the primary capture mechanism (it issues a
      # server-side capture on APPROVED orders); this webhook handler is the async
      # safety net for captures completed before the cron fires.
      #
      # Applies the same merchant-binding + idempotency guards as other handlers:
      # the merchant that signed the webhook must own the payment's customer, and
      # terminal payments are not re-processed by replayed notifications.
      PAYPAL_DISPUTE_EVENTS = %w[
        CUSTOMER.DISPUTE.CREATED CUSTOMER.DISPUTE.UPDATED CUSTOMER.DISPUTE.RESOLVED
      ].freeze

      def self.handle_paypal(payload, signing_account)
        return record_paypal_dispute(payload, signing_account) if
          PAYPAL_DISPUTE_EVENTS.include?(payload["event_type"])

        if payload["event_type"] == "PAYMENT.CAPTURE.REFUNDED"
          resource = payload["resource"] || {}
          return settle_refund(success: true, provider: "paypal", signing_account: signing_account,
                               out_refund_no: resource["invoice_id"],
                               psp_refund_id: resource["id"], psp_id: resource["id"], notify: payload,
                               at: psp_time(resource["update_time"] || resource["create_time"]))
        end

        return unless payload["event_type"] == "PAYMENT.CAPTURE.COMPLETED"

        resource     = payload["resource"] || {}
        out_trade_no = resource["invoice_id"]
        return unless out_trade_no.present?

        payment = find_verified_payment(provider: "paypal", signing_account: signing_account, out_trade_no: out_trade_no)
        return unless payment

        Current.customer = payment.payment_order.customer

        # Idempotency: drop succeeded replays. A verified capture still
        # recovers a locally failed/closed payment.
        return settle_billing_invoice!(payment) if payment.status == "succeeded"

        finalize_success!(payment, notified_amount: paypal_amount(resource),
                          notified_currency: paypal_currency(resource),
                          psp_id: resource["id"], at: psp_time(resource["create_time"]), notify: payload)
      end

      # Record/advance a PayPal dispute. resource.disputed_transactions[].
      # seller_transaction_id is the capture id our payment stored as
      # psp_transaction_id, so it links the dispute to the local payment.
      def self.record_paypal_dispute(payload, signing_account)
        res = payload["resource"] || {}
        record_dispute(
          provider:            "paypal",
          psp_dispute_id:      res["dispute_id"],
          psp_transaction_id:  res.dig("disputed_transactions", 0, "seller_transaction_id"),
          signing_account:     signing_account,
          reason:              res["reason"],
          status:              map_paypal_dispute_status(res),
          raw:                 payload,
          amount: ->(_payment) {
            Payments::Money.from_major(res.dig("dispute_amount", "value"), "USD")&.amount || 0
          }
        )
      end

      def self.map_paypal_dispute_status(resource)
        case resource["status"]
        when "UNDER_REVIEW"
          "under_review"
        when "RESOLVED"
          case resource.dig("dispute_outcome", "outcome_code")
          when "RESOLVED_SELLER_FAVOUR", "RESOLVED_SELLER_FAVOR" then "won"
          when "RESOLVED_BUYER_FAVOUR", "RESOLVED_BUYER_FAVOR"   then "lost"
          else                                                        "closed"
          end
        else
          "open"
        end
      end

      # Handle payment_intent.succeeded for Stripe (analogous to WeChat/Alipay
      # out_trade_no lookup but keyed on metadata[out_trade_no]).
      # Applies the same merchant-binding guard as handle_wechat/handle_alipay.
      def self.handle_stripe_payment_intent_succeeded(object, signing_account, event_time: nil)
        out_trade_no = object.dig("metadata", "out_trade_no")
        return unless out_trade_no.present?

        payment = find_verified_payment(provider: "stripe", signing_account: signing_account, out_trade_no: out_trade_no)
        return unless payment

        Current.customer = payment.payment_order.customer

        unless payment.status == "succeeded"
          notified = stripe_amount(object, object["currency"].presence || payment.payment_order.currency)
          return unless finalize_success!(payment, notified_amount: notified,
                                          psp_id: object["id"], at: stripe_capture_time(object, fallback: event_time),
                                          notify: object, notified_currency: object["currency"])

          reactivate_paused_subscription(payment)
        else
          # Payment success and invoice projection commit independently. Retry
          # the projection even if a previous delivery already recorded capture.
          settle_billing_invoice!(payment)
        end

        # Checkout save-card placeholders are keyed pending:<pi_id>. Query may
        # mark the payment succeeded before this webhook arrives — still backfill.
        backfill_payment_method_from_setup_intent(object, signing_account)
      end

      # A PaymentIntent's own `created` is when the intent was FIRST created —
      # for an SCA-recovered off-session charge that can be days before the
      # member actually authenticates and the charge captures. Capture time
      # lives on the settled Charge, reachable either as an expanded
      # `latest_charge` object or (the legacy/list shape) the first entry of
      # `charges.data`. The signed success event's timestamp is the fallback for
      # an unexpanded charge; arrival time is used only when neither is present.
      # The intent's own `created` is never a settlement timestamp.
      def self.stripe_capture_time(object, fallback: nil)
        latest_charge   = object["latest_charge"]
        charge_created  = latest_charge.is_a?(Hash) ? latest_charge["created"] : nil
        charge_created ||= object.dig("charges", "data", 0, "created")
        unix_time(charge_created || fallback)
      end

      # SCA-recovery: when the member completes on-session authentication for a
      # subscription charge that had stalled, its PaymentIntent succeeds and lands
      # here. The payment's order ref encodes the subscription; if that sub was
      # paused for this reason, reactivate it and re-anchor to the next period.
      # No-op for one-off payments or non-paused subs.
      def self.reactivate_paused_subscription(payment)
        ref = payment.payment_order.external_ref.to_s
        match = ref.match(/\Asub-(\d+)-/)
        return unless match

        sub = Payments::Subscription.unscoped_by_tenant.payments_managed.find_by(id: match[1])
        return unless sub && sub.customer_id == payment.customer_id
        return unless sub.provider == payment.provider && !sub.billing_owned?

        # Re-anchor from NOW (the moment of reactivation), not the stale
        # pre-pause anchor: advance_next_charge! advances from the EXISTING
        # next_charge_at, so calling it on the untouched anchor after a
        # multi-period pause would land next_charge_at in the past and the
        # cron would immediately re-fire an off-session charge for every
        # period missed during the pause. The paused gap itself is not
        # retroactively billed — this very payment already covers the period
        # whose stalled charge triggered the pause.
        #
        # status and next_charge_at are written in a SINGLE update! (reusing
        # the model's own period arithmetic — next_charge_time_from — rather
        # than duplicating it) so no intermediate "active + already due" row
        # is ever committed. Two separate writes would open a race window
        # where ChargeDueSubscriptions' hourly batch could observe the sub as
        # active-with-a-past-due next_charge_at and fire a duplicate charge.
        sub.reactivate_paused!
      end
    end
  end
end
