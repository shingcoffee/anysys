# frozen_string_literal: true

module Billing
  module Providers
    class << self
      def supported?(provider) = %w[stripe alipay].include?(provider.to_s)

      def for(payment_method)
        case payment_method.provider
        when "stripe" then Stripe.new(payment_method)
        when "alipay" then Alipay.new(payment_method)
        else raise ArgumentError, "unsupported billing provider"
        end
      end

      def platform = Customer.find(Collector::PLATFORM_OWNER_CUSTOMER_ID)

      def readiness_reason(payment_method:, invoice: nil)
        identity_reason = invoice_identity_reason(invoice) if invoice
        return identity_reason if identity_reason
        return :no_payment_method unless payment_method
        return :method_inactive unless payment_method.active? && payment_method.removed_at.nil?
        account = payment_method.merchant_account
        mandate = payment_method.payments_subscription
        return :account_mismatch unless account && account.customer_id == Collector::PLATFORM_OWNER_CUSTOMER_ID && account.provider == payment_method.provider
        return :account_mismatch if payment_method.failure_code == "historical_authorization_review"
        context = mandate&.metadata&.fetch("billing_authorization_context", {}) || {}
        if context.present? && (context["merchant_account_id"] != account.id || context["provider"] != account.provider ||
            context["merchant_id"] != account.merchant_id || context["mode"] != account.mode)
          return :account_mismatch
        end
        return :mandate_inactive unless mandate && mandate.status == "active" && mandate.billing_owned? && mandate.customer_id == account.customer_id && mandate.provider == account.provider && mandate.next_charge_at.nil?
        subscription = invoice&.subscription || Entitlements.current_subscription(customer: payment_method.customer)
        currency = invoice&.currency || subscription&.currency || CurrencyResolver.for_customer(payment_method.customer)
        interval = invoice&.terms_snapshot&.fetch("interval") || subscription&.interval || "monthly"
        return :currency_mismatch unless mandate.currency.upcase == currency && (payment_method.provider != "alipay" || currency == "CNY")
        return :reauthorization_required if payment_method.provider == "alipay" && (interval != "monthly" || mandate.cycle != "monthly")
        options = { customer: payment_method.customer, currency: currency }
        options[:interval] = interval if invoice
        available = AvailableProviders.call(**options).any? { |entry| entry[:key] == payment_method.provider }
        return :provider_unavailable unless available && account.mode == Payments::CredentialResolver.default_mode && account.configured?
        if payment_method.provider == "stripe"
          token = mandate.payment_method
          return :mandate_incomplete unless token&.chargeable? && token.customer_id == account.customer_id && token.user_id.nil? &&
            token.billing_customer_id == payment_method.customer_id && token.billing_authorized_by_id == payment_method.authorized_by_id && token.provider == "stripe"
        elsif payment_method.provider == "alipay"
          return :mandate_incomplete if mandate.psp_agreement_id.blank?
          return :reauthorization_required if invoice && (interval != mandate.cycle ||
            Payments::Money.new(mandate.amount, "CNY").smallest_unit < invoice.total_cents)
          if invoice
            # CYCLE_PAY_AUTH authorizes a monthly frequency as well as a ceiling.
            # A proration/recovery must not silently collect twice in that cycle.
            billing_timezone = Payments::Gateways::Alipay::TIMEZONE
            now = Time.current.in_time_zone(billing_timezone)
            day = mandate.created_at.in_time_zone(billing_timezone).day
            calendar_start = now.beginning_of_month.change(day: [day, now.end_of_month.day].min)
            if calendar_start > now
              previous = now.beginning_of_month - 1.month
              calendar_start = previous.change(day: [day, previous.end_of_month.day].min)
            end
            recently_collected = CollectionAttempt.unscoped_by_tenant.where(billing_payment_method_id: payment_method.id)
              .joins(:payment).where(payments: { status: "succeeded" }).where("payments.paid_at >= ?", calendar_start).exists?
            return :reauthorization_required if recently_collected
          end
        end
        nil
      end

      def invoice_identity_reason(invoice)
        subscription = invoice.subscription
        return :tenant_mismatch unless subscription.customer_id == invoice.customer_id
        return :currency_mismatch unless invoice.currency == subscription.currency && invoice.terms_snapshot["currency"] == invoice.currency
        nil
      end

      def charge(attempt:)
        if invoice_identity_reason(attempt.invoice.reload)
          raise Payments::Errors::TenantMismatch, "billing invoice identity mismatch before capture"
        end
        payment = attempt.payment
        outcome = Payments::Gateway.charge_subscription(customer: platform, subscription: attempt.payment_method.payments_subscription,
          payment: payment, merchant_account: attempt.merchant_account)
        outcome = outcome.symbolize_keys
        # Alipay trade.pay code=10000 establishes success; unknown statuses from
        # other adapters never silently become a successful capture.
        outcome[:status] ||= payment.provider == "alipay" ? :succeeded : :unknown
        if outcome[:status] == :succeeded
          payment.update!(psp_transaction_id: outcome[:psp_transaction_id]) if outcome[:psp_transaction_id]
          begin
            outcome = query(attempt: attempt)
          rescue Payments::Errors::ApiError
            # A query failure AFTER capture acceptance is not a decline.
            raise Payments::Errors::TransportError, "capture accepted; query evidence unavailable"
          end
        end
        outcome
      end

      def query(attempt:)
        payment = attempt.payment
        account = attempt.merchant_account
        unless payment.customer_id == account.customer_id && payment.provider == account.provider &&
            payment.attempt_context["merchant_account_id"] == account.id && payment.attempt_context["provider"] == account.provider
          raise Payments::Errors::TenantMismatch, "billing attempt merchant account binding changed"
        end
        outcome = Payments::Gateway.billing_query(customer: platform, payment: payment, merchant_account: account)
        if outcome[:status] == :unknown && payment.provider == "stripe" && payment.psp_transaction_id.blank? &&
            attempt.submitted_at && attempt.submitted_at > 23.hours.ago && Time.current < attempt.invoice.collection_deadline &&
            !attempt.invoice.paid? && !attempt.invoice.void? &&
            payment.attempt_context["merchant_id"] == account.merchant_id && payment.attempt_context["mode"] == account.mode &&
            attempt.payment_method.present? &&
            readiness_reason(payment_method: attempt.payment_method.reload, invoice: attempt.invoice).nil?
          # Replay within Stripe's documented 24h idempotency retention only.
          # The same committed payment/key/amount is reused, never a new attempt.
          charge(attempt: attempt)
        else
          outcome
        end
      end

      def validate_capture!(payment:, outcome:)
        return if payment.status == "succeeded" # Already verified by Payments.
        unless outcome[:amount].present? && outcome[:currency].to_s.upcase == payment.payment_order.currency &&
          Payments::Money.new(outcome[:amount], outcome[:currency]).smallest_unit == Payments::Money.new(payment.amount, payment.payment_order.currency).smallest_unit && outcome[:settled_at].present?
          raise Payments::Errors::TransportError, "billing capture evidence is incomplete or mismatched"
        end
      end

      def not_found?(error, provider, attempt: nil)
        return false unless Payments::Activities::AttemptSafety.definitive_rejection?(error)
        if attempt
          context = attempt.payment.attempt_context
          account = attempt.merchant_account
          return false unless context["merchant_id"] == account.merchant_id && context["mode"] == account.mode
        end
        payload = error.payload.is_a?(Hash) ? error.payload : {}
        provider == "alipay" && payload["sub_code"] == "ACQ.TRADE_NOT_EXIST"
      end

      def failure_code(error)
        payload = error.payload.is_a?(Hash) ? error.payload : {}
        code = payload.dig("error", "decline_code") || payload.dig("error", "code") || payload["sub_code"] || error.code
        code.to_s.presence || "provider_rejected"
      end
    end
  end
end
