# frozen_string_literal: true

module Payments
  module Activities
    # Stands up a card-recurring subscription against a member's already-vaulted
    # card, initiated by a customer admin. Card-recurring is the only flow an
    # operator can complete headlessly: agreement-based tenders (Alipay/WeChat)
    # require the member to interactively sign a withholding agreement at the PSP,
    # whereas a card subscription is billed off-session by ChargeDueSubscriptions
    # against the vaulted token — so once a card exists, the admin can create the
    # whole subscription end-to-end.
    class CreateSubscription
      # Already billing. A second POST must not insert another row or call the
      # gateway again. pending_sign is not in this list: a failed activation
      # leaves that status, and returning it made the admin UI flash success
      # without ever billing.
      SETTLED_STATUSES = %w[active paused].freeze
      RESUMABLE_STATUSES = %w[pending_sign active paused].freeze

      def self.call(customer:, payment_method:, plan_name:, amount:, cycle:, currency:)
        currency = currency.to_s.downcase
        amount   = Payments::Money.normalize(amount, currency)

        # Serialize on the vaulted card so two overlapping admin POSTs cannot
        # each insert an active subscription and let ChargeDueSubscriptions
        # collect twice for the same plan on the same token.
        subscription = payment_method.with_lock do
          unless payment_method.customer_id == customer.id && !payment_method.billing_token?
            raise Payments::Errors::TenantMismatch, "payment method does not belong to the supplied customer"
          end
          existing = matching_live_subscription(
            customer: customer, payment_method: payment_method,
            plan_name: plan_name, amount: amount, cycle: cycle, currency: currency
          )
          if existing && SETTLED_STATUSES.include?(existing.status)
            existing
          else
            existing || Payments::Subscription.create!(
              customer_id: customer.id, provider: payment_method.provider,
              payment_method_id: payment_method.id, plan_name: plan_name,
              amount: amount, cycle: cycle, currency: currency,
              status: "pending_sign", external_ref: generate_external_ref(customer)
            )
          end
        end

        return subscription if SETTLED_STATUSES.include?(subscription.status)

        activate_subscription!(
          customer: customer, subscription: subscription
        )
      end

      def self.matching_live_subscription(customer:, payment_method:, plan_name:, amount:, cycle:, currency:)
        Payments::Subscription.where(
          customer_id:       customer.id,
          payment_method_id: payment_method.id,
          plan_name:         plan_name,
          amount:            amount,
          cycle:             cycle,
          currency:          currency,
          status:            RESUMABLE_STATUSES
        ).order(:id).first
      end
      private_class_method :matching_live_subscription

      def self.activate_subscription!(customer:, subscription:)
        # Provider hook. For card-recurring gateways (Stripe) this is a local-state
        # stub that just ensures a vaulted token exists; there is no PSP-managed
        # agreement to sign, so no psp_agreement_id comes back.
        begin
          Payments::Gateway.subscribe(customer: customer, subscription: subscription)
        rescue Payments::Errors::CredentialsMissing
          subscription.with_lock { subscription.destroy! if subscription.status == "pending_sign" }
          raise
        end

        # Activate immediately and anchor the first charge so ChargeDueSubscriptions
        # #due_now selects it. The locked transition also preserves a concurrent
        # cancellation while the gateway hook was in flight.
        subscription.mark_active!(psp_agreement_id: nil, at: Time.current)
        subscription
      end
      private_class_method :activate_subscription!

      def self.generate_external_ref(customer)
        Payments::OutTradeNo.generate(prefix: "ms", customer_id: customer.id)
      end
    end
  end
end
