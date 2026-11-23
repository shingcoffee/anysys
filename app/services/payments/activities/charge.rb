# frozen_string_literal: true

module Payments
  module Activities
    class Charge
      # save_card: when true AND the gateway has :tokenized_cards capability AND a
      # user is present, passes setup_future_usage: "off_session" into the gateway
      # charge call so the PSP vaults the card alongside the one-time payment.
      # Mechanism: the flag is forwarded to Gateway#charge, which forwards it to the
      # concrete gateway's `charge` method as an optional keyword — zero changes needed
      # in non-card gateways because Ruby keyword args with defaults are ignored when
      # the receiver does not declare them (callers use **kwargs passthrough pattern
      # inside the gateway if desired). Stripe's charge implementation reads the flag
      # and appends setup_future_usage when true.
      def self.call(customer:, order:, provider:, request:, openid: nil, save_card: false, user: nil, handoff_token: nil)
        # Close siblings before the order lock so a Query that records a
        # capture is committed — raising OrderSettled inside with_lock would
        # otherwise roll that capture back and look like the order is still open.
        close_other_provider_attempts!(customer: customer, order: order, provider: provider)
        # Serialize find-or-create on the order so two overlapping POSTs cannot
        # each insert a Payment and call the PSP with two out_trade_nos.
        payment = order.with_lock do
          order.reload
          # close_other_provider_attempts! runs before the lock so a Query
          # capture can commit. Overlapping POSTs for two providers can both
          # see "no siblings" out here; refuse if another attempt appeared
          # before we insert.
          refuse_if_other_provider_inflight!(order: order, provider: provider)
          prepare_locked!(
            customer: customer, order: order, provider: provider, request: request,
            openid: openid, save_card: save_card, user: user, handoff_token: handoff_token
          )
        end

        # The attempt and idempotency key have committed before any remote write.
        # Pending retries return the original payload/flow without changing PSP
        # parameters to match a later request's browser or save-card preference.
        return response(payment) if AttemptSafety.reconcile_expired!(customer: customer, payment: payment)
        return response(payment) if payment.status == "pending"

        context = payment.attempt_context
        AttemptSafety.assert_write_binding!(customer: customer, payment: payment)
        begin
          result = Payments::Gateway.charge(
            customer: customer, order: order, payment: payment, flow: payment.flow.to_sym,
            openid: context["openid"], save_card: context["save_card"], request: request,
            user: payment.user
          )
        rescue Payments::Errors::ApiError => e
          payment.mark_failed!(reason: "#{e.class}: #{e.message}") if AttemptSafety.definitive_rejection?(e)
          raise
        end
        payment.with_lock do
          if result[:psp_transaction_id].present? && payment.psp_transaction_id.blank?
            payment.update!(psp_transaction_id: result[:psp_transaction_id])
          end
        end
        record_save_card_placeholder!(customer: customer, user: payment.user, provider: provider,
                                      result: result) if context["save_card"]
        payment.mark_pending!(result[:prepay_payload])
        response(payment)
      end

      def self.prepare_locked!(customer:, order:, provider:, request:, openid:, save_card:, user:, handoff_token:)
        if order.status.in?(Payments::Order::SETTLED_STATUSES)
          raise Payments::Errors::OrderSettled,
                "order #{order.external_ref} is already #{order.status}"
        end
        if order.expires_at.present? && order.expires_at <= Time.current
          raise Payments::Errors::OrderExpired,
                "order #{order.external_ref} expired at #{order.expires_at}"
        end

        flow    = Payments::FlowSelector.call(request: request, provider: provider)
        payment = Payments::Payment.where(payment_order_id: order.id, provider: provider,
                                status: %w[created pending]).first
        # handoff_token is set ONLY on first creation. A reused created/pending
        # payment keeps the token of the invocation that first charged it, so a
        # later shopper sharing the order cannot re-stamp it to their own session.
        payment ||= Payments::Payment.create!(
          payment_order: order,
          provider: provider, flow: flow.to_s,
          out_trade_no: Payments::OutTradeNo.generate(prefix: "ch",
                                                     customer_id: customer.id),
          amount: order.amount,
          user_id: user&.id,
          handoff_token: handoff_token
        )

        # Only forward save_card when the gateway supports tokenized cards and a
        # user context is available. This prevents accidental opt-in for QR/H5 flows
        # where card vaulting is meaningless.
        gateway_klass = Payments::Gateways.for(provider)
        effective_save_card = save_card &&
                              user.present? &&
                              gateway_klass.capabilities.include?(:tokenized_cards)

        PrepareAttempt.call(customer: customer, order: order, payment: payment, operation: "charge",
                            attributes: { openid: openid, save_card: effective_save_card,
                                          client_ip: (request.remote_ip if request.respond_to?(:remote_ip)) })
        payment
      end
      private_class_method :prepare_locked!

      def self.response(payment)
        payload = payment.prepay_payload.except(Payments::Payment::ATTEMPT_CONTEXT_KEY).with_indifferent_access
        { payment: payment, flow: payment.flow.to_sym, prepay_payload: payload }
      end
      private_class_method :response

      def self.record_save_card_placeholder!(customer:, user:, provider:, result:)
        return unless user
        pi_id = result[:psp_transaction_id].to_s.presence
        cus_id = result[:psp_customer_id].to_s.presence
        return if pi_id.blank? || cus_id.blank?

        token = "#{Payments::PaymentMethod::PENDING_TOKEN_PREFIX}#{pi_id}"
        Payments::PaymentMethod.find_or_create_by!(
          customer_id: customer.id,
          provider: provider,
          psp_payment_method_id: token
        ) do |pm|
          pm.user_id = user.id
          pm.provider = provider
          pm.psp_customer_id = cus_id
          pm.status = "active"
        end
      end
      private_class_method :record_save_card_placeholder!

      def self.refuse_if_other_provider_inflight!(order:, provider:)
        return unless Payments::Payment.where(payment_order_id: order.id, status: %w[created pending])
                                       .where.not(provider: provider)
                                       .exists?

        raise Payments::Errors::OrderInFlight,
              "order #{order.external_ref} still has an open attempt with another provider"
      end
      private_class_method :refuse_if_other_provider_inflight!

      def self.close_other_provider_attempts!(customer:, order:, provider:)
        Payments::Payment.where(payment_order_id: order.id, status: %w[created pending])
                         .where.not(provider: provider)
                         .find_each do |sibling|
          refuse_if_sibling_captured!(customer: customer, order: order, payment: sibling)

          begin
            Payments::Gateway.close(customer: customer, payment: sibling)
          rescue Payments::Errors::Error => e
            Rails.logger.warn("[payments.charge] close sibling #{sibling.id}: #{e.class}: #{e.message}")
            refuse_if_sibling_captured!(customer: customer, order: order, payment: sibling)
            raise Payments::Errors::OrderInFlight,
                  "order #{order.external_ref} still has an open #{sibling.provider} attempt"
          end
          sibling.mark_closed!
        end
      end
      private_class_method :close_other_provider_attempts!

      # A delayed webhook can leave a sibling "pending" after the PSP has
      # already captured. Closing then charging another provider would collect
      # twice; Query first and abort if the order is already paid.
      def self.refuse_if_sibling_captured!(customer:, order:, payment:)
        if payment.status == "pending"
          Payments::Activities::Query.call(customer: customer, payment: payment)
          payment.reload
        end
        order.reload
        return unless payment.status == "succeeded" || order.status.in?(Payments::Order::SETTLED_STATUSES)

        raise Payments::Errors::OrderSettled,
              "order #{order.external_ref} is already #{order.status.presence || payment.status}"
      rescue Payments::Errors::ApiError
        nil
      end
      private_class_method :refuse_if_sibling_captured!
    end
  end
end
