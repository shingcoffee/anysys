# frozen_string_literal: true

module Payments
  module Cron
    # Scheduled job that iterates every active+due `Payments::Subscription` across
    # tenants, creates a fresh `Payment`, charges it via the provider's
    # subscription API (or via off-session card token for card-recurring plans),
    # then advances the next charge timestamp. Errors from a single subscription
    # are logged and swallowed so the rest of the batch continues processing.
    class ChargeDueSubscriptions
      # Re-claim window: a claim older than this is assumed to belong to a dead
      # worker (crashed mid-charge) and is eligible for re-processing.
      CLAIM_TTL = 15.minutes

      def self.perform
        Payments::Subscription.unscoped_by_tenant.due_now.find_each do |sub|
          next if sub.billing_owned?
          next unless FeatureModules::Module.enabled?(key: "payment", customer_id: sub.customer_id)
          next unless claim!(sub)
          claimed_at = sub.charge_claimed_at

          begin
            Current.customer = sub.customer
            charge_one(sub)
          rescue Payments::Errors::PaymentRequiresAction, Payments::Errors::CardDeclined => e
            # Recurring charge could not complete (issuer auth / dead card). Move
            # the subscription to dunning so it stops being re-selected every tick
            # and next_charge_at is NOT advanced (no free period granted).
            sub.mark_paused!
            Rails.logger.warn("[payments.cron] dunning sub=#{sub.id}: #{e.class}: #{e.message}")
          rescue Payments::Errors::Error => e
            Rails.logger.error("[payments.cron] #{e.class}: #{e.message}")
          ensure
            Payments::Subscription.unscoped_by_tenant.where(id: sub.id, charge_claimed_at: claimed_at)
              .update_all(charge_claimed_at: nil)
          end
        end
      ensure
        Current.reset
      end

      # Atomic re-entrancy claim for overlapping cron workers (DB-agnostic; SQLite
      # has no SELECT … FOR UPDATE SKIP LOCKED). The UPDATE's WHERE re-checks
      # status + next_charge_at, so of two overlapping workers exactly one
      # matches (the other sees 0 rows and skips). Stale claims (dead worker)
      # expire after CLAIM_TTL.
      def self.claim!(sub)
        claimed_at = Time.zone.now
        claimed = Payments::Subscription.unscoped_by_tenant.payments_managed
          .where(id: sub.id, status: "active", next_charge_at: sub.next_charge_at)
          .where("charge_claimed_at IS NULL OR charge_claimed_at < ?", CLAIM_TTL.ago)
          .update_all(charge_claimed_at: claimed_at) == 1
        sub.charge_claimed_at = claimed_at if claimed
        claimed
      end

      # One subscription's due charge. next_charge_at is advanced ONLY after the
      # period is genuinely resolved (a recorded success, or an already-succeeded
      # prior attempt); every non-success path raises (so the rescues above skip
      # the advance). The recorded Payment/Order reflect the real outcome.
      #
      # Period idempotency (DB-agnostic; SQLite has no SELECT … FOR UPDATE SKIP
      # LOCKED): the per-period order (external_ref "sub-<id>-<date>") is the
      # anchor.
      #   - a `pending` payment (awaiting SCA / webhook resolution) means the
      #     period is still in flight: neither re-charge (double-charge risk)
      #     nor advance (free-period risk) — skip this tick entirely.
      #   - a `succeeded` payment means a prior run already collected this
      #     period — likely crashing before it could advance — so we advance
      #     WITHOUT charging again.
      #   - otherwise (no payment yet, or a stalled/failed prior attempt) we
      #     (re)charge; see charge_card_subscription / charge_agreement_subscription
      #     for how a stalled attempt is safely retried.
      def self.charge_one(sub)
        sub.reload
        return unless sub.managed_by == "payments" && sub.status == "active"
        anchor = sub.next_charge_at
        order = ensure_order_for(sub)

        return if order.payments.where(status: "pending").exists?

        unless order.payments.where(status: "succeeded").exists?
          if sub.card_recurring?
            charge_card_subscription(sub, order)
          else
            charge_agreement_subscription(sub, order)
          end
        end

        sub.advance_next_charge!(expected_anchor: anchor)
      end

      # Card-recurring: delegate to ChargeToken which uses the vaulted token.
      # Guards against a structurally unchargeable card (removed by the member, or
      # a still-pending vault placeholder) BEFORE hitting the PSP.
      def self.charge_card_subscription(sub, order)
        pm = sub.payment_method
        unless pm&.chargeable?
          raise Payments::Errors::CardDeclined,
                "subscription #{sub.id} payment method is not chargeable"
        end

        # Reuse a stalled prior attempt (ambiguous transport failure / crash) so
        # the PSP-side idempotency key stays stable across the retry.
        stalled = order.payments.where(status: "created").order(:created_at).last
        Payments::Activities::ChargeToken.call(
          customer:       sub.customer,
          order:          order,
          payment_method: pm,
          payment:        stalled
        )
      end

      # Agreement-based recurring (Alipay / WeChat contract pay): use the
      # provider's charge_subscription API, then RECORD the outcome on the
      # payment/order. The gateway raises ApiError on a hard failure (caught
      # upstream), so reaching mark_succeeded! means the PSP accepted the charge.
      def self.charge_agreement_subscription(sub, order)
        if (stalled = order.payments.where(status: "created").order(:created_at).last)
          return if resolve_stalled_agreement_payment(sub, stalled) # succeeded at PSP
        end

        payment = order.with_lock do
          attempt = Payments::Payment.create!(
            payment_order: order, provider: sub.provider, flow: "jsapi",
            out_trade_no: Payments::OutTradeNo.generate(prefix: "sb", customer_id: sub.customer_id),
            amount: sub.amount, user_id: sub.payment_method&.user_id
          )
          Payments::Activities::PrepareAttempt.call(customer: sub.customer, order: order, payment: attempt,
                                                    operation: "charge_subscription",
                                                    attributes: { subscription_id: sub.id,
                                                                  psp_agreement_id: sub.psp_agreement_id })
          attempt
        end
        begin
          result = Payments::Gateway.charge_subscription(
            customer: sub.customer, subscription: sub, payment: payment
          )
        rescue Payments::Errors::ApiError => e
          payment.mark_failed!(reason: "#{e.class}: #{e.message}") if Payments::Activities::AttemptSafety.definitive_rejection?(e)
          raise
        end
        if result[:status].in?([:pending, :processing, :requires_action])
          payment.mark_pending!(result[:raw] || {})
          raise Payments::Errors::PaymentRequiresAction, "subscription charge is unresolved"
        elsif result[:status].in?([:failed, :closed])
          payment.mark_failed!(reason: result[:raw].to_s)
          raise Payments::Errors::CardDeclined, "subscription charge was rejected"
        end
        payment.mark_succeeded!(
          psp_id: result[:psp_transaction_id], at: result[:settled_at] || result[:paid_at] || Time.zone.now, notify: result[:raw] || {}
        )
      end

      # A prior agreement attempt died mid-flight. Agreement APIs are NOT
      # idempotent on re-submission the way card Idempotency-Keys are, so ask the
      # PSP what actually happened first. Returns true when the stalled attempt
      # turned out to have succeeded (Query already recorded it).
      def self.resolve_stalled_agreement_payment(sub, payment)
        Payments::Activities::Query.call(customer: sub.customer, payment: payment)
        case payment.reload.status
        when "succeeded" then true
        when "failed", "closed" then false
        else
          raise Payments::Errors::OrderInFlight, "subscription charge is still unresolved at the PSP"
        end
      end

      def self.ensure_order_for(sub)
        # Current.customer is set by the caller loop above; the explicit scope
        # prevents a cross-tenant collision on the unique external_ref key.
        # Orders store currency UPPERCASE; subscriptions store it lowercase — copy
        # it so an off-session charge is never silently made in the wrong currency.
        # Anchor the ref on the billing period being collected (next_charge_at),
        # NOT wall-clock "today": next_charge_at is only advanced after the period
        # is genuinely resolved (see charge_one), so it stays stable across retries
        # of the SAME unpaid period even when a retry crosses midnight. Keying on
        # Time.zone.today would mint a brand-new order ref after midnight, hiding
        # the stalled 'created' payment from the recovery lookup below and causing
        # a duplicate charge for one period (H-critical double-charge bug).
        ref = "sub-#{sub.id}-#{sub.next_charge_at.to_date}"
        Payments::Order.for_current_customer.find_or_create_by!(external_ref: ref) do |o|
          o.amount = sub.amount
          o.currency     = sub.currency.to_s.upcase
          o.subject      = sub.plan_name
        end
      rescue ActiveRecord::RecordNotUnique
        # Concurrent run created the period order first — reuse it.
        Payments::Order.for_current_customer.find_by!(external_ref: ref)
      end
    end
  end
end
