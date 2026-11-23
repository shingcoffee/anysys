# frozen_string_literal: true

require "ostruct"

module Billing
  module Activities
    class StartOneTimePayment
      def self.call(invoice:, provider:, request: nil, openid: nil, at: Time.current)
        raise ArgumentError, "one-time payment must run after domain commit" if Invoice.connection.transaction_open?

        form = Contracts::OneTimePayment.new(OpenStruct.new)
        unless form.validate(provider: provider.to_s.strip, invoice_id: invoice&.id, openid: openid)
          return Billing::Result.invalid(:validation_failed, form: form, errors: form.errors.messages, invoice: invoice)
        end

        return Billing::Result.new(status: :succeeded, invoice: invoice, subscription: invoice.subscription) if invoice.paid?
        if invoice.void? || invoice.draft? || !invoice.total_cents.positive?
          return Billing::Result.new(status: :blocked, invoice: invoice, reason: :invoice_not_payable)
        end
        identity_reason = Providers.invoice_identity_reason(invoice)
        return Billing::Result.new(status: :blocked, invoice: invoice, reason: identity_reason) if identity_reason
        if at > invoice.collection_deadline || %w[cancelled expired].include?(invoice.subscription.status)
          return Billing::Result.new(status: :blocked, invoice: invoice, reason: :request_expired)
        end

        available = OneTimeProviders.call(currency: invoice.currency).map { |entry| entry[:key] }
        unless available.include?(provider.to_s)
          form.errors.add(:provider, I18n.t("admin_settings.flash.billing.reasons.provider_unavailable"))
          return Billing::Result.invalid(:provider_unavailable, form: form, errors: form.errors.messages, invoice: invoice)
        end

        captured = resume_or_close_existing(invoice: invoice, provider: provider, at: at)
        return captured if captured.is_a?(Billing::Result)

        attempt = nil
        payment = nil
        prepared = prepare_attempt(invoice: invoice, provider: provider, request: request, openid: openid, at: at)
        return prepared if prepared.is_a?(Billing::Result)
        attempt, order, payment, flow, req = prepared

        CollectionAttempt.where(id: attempt.id, state: "prepared").update_all(
          state: "submitting", submitted_at: at, claimed_at: at, reconcile_at: at + Collector::RECONCILE_DELAY)
        charge_res = Payments::Gateway.charge(customer: Providers.platform, order: order, payment: payment,
          flow: flow, openid: openid, save_card: false, request: req, user: nil)
        payment.with_lock do
          if charge_res[:psp_transaction_id].present? && payment.psp_transaction_id.blank?
            payment.update!(psp_transaction_id: charge_res[:psp_transaction_id])
          end
        end
        payment.mark_pending!(charge_res[:prepay_payload])
        Collector.with_invoice(invoice) do
          attempt.reload
          attempt.update!(state: "pending", claimed_at: nil, reconcile_at: at + Collector::RECONCILE_DELAY) unless %w[succeeded failed].include?(attempt.state)
        end
        if payment.reload.status == "succeeded"
          MarkInvoicePaid.call(invoice: invoice, payment: payment, source: :gateway)
          return Billing::Result.new(status: :succeeded, invoice: invoice.reload, subscription: invoice.subscription.reload)
        end
        action = OneTimePaymentAction.for(invoice: invoice.reload)
        Billing::Result.new(status: :action_required, invoice: invoice, record: attempt.reload, action: action)
      rescue ActiveRecord::RecordNotUnique
        Billing::Result.new(status: :conflict, invoice: invoice.reload, reason: :concurrent_collection)
      rescue Payments::Errors::ApiError => error
        if Payments::Activities::AttemptSafety.definitive_rejection?(error)
          payment.mark_failed!(reason: Providers.failure_code(error)) if payment
          Collector.complete(attempt, { status: :failed, failure_code: Providers.failure_code(error) }, at: at) if attempt
          Billing::Result.new(status: :invalid, invoice: invoice.reload, reason: :one_time_charge_failed)
        elsif attempt
          Collector.complete(attempt, { status: :unknown }, at: at)
          Billing::Result.new(status: :pending, invoice: invoice.reload, reason: :in_flight)
        else
          Billing::Result.new(status: :invalid, invoice: invoice, reason: :provider_unavailable)
        end
      rescue Payments::Errors::TransportError, Payments::Errors::CredentialsMissing
        if attempt
          Collector.complete(attempt, { status: :unknown }, at: at)
          Billing::Result.new(status: :pending, invoice: invoice.reload, reason: :in_flight)
        else
          Billing::Result.new(status: :invalid, invoice: invoice, reason: :provider_unavailable)
        end
      end

      def self.resume_or_close_existing(invoice:, provider:, at:)
        if Collector.platform_payments(invoice).where(status: "succeeded").where.not(id: invoice.payment_id).exists?
          reconciled = Collector.reconcile(invoice, at: at)
          return reconciled if invoice.reload.paid? || reconciled.status == :blocked
        end
        if invoice.collection_attempts.inflight.where.not(billing_payment_method_id: nil).exists?
          return Billing::Result.new(status: :conflict, invoice: invoice, reason: :collection_in_flight)
        end

        existing = invoice.collection_attempts.inflight.where(billing_payment_method_id: nil).order(:ordinal).last
        return unless existing

        existing_payment = existing.payment
        if existing.state == "pending" && existing_payment&.provider == provider.to_s &&
            existing_payment.status == "pending" &&
            !Payments::Activities::AttemptSafety.expired?(existing_payment, provider: provider.to_s)
          action = OneTimePaymentAction.for(invoice: invoice.reload)
          return Billing::Result.new(status: :action_required, invoice: invoice, record: existing, action: action) if action
        end

        unless existing.state == "pending"
          return Billing::Result.new(status: :conflict, invoice: invoice, reason: :collection_in_flight)
        end

        if existing_payment&.status == "pending"
          queried = query_existing(invoice: invoice, payment: existing_payment)
          return queried if queried.is_a?(Billing::Result)
          closed = close_existing(invoice: invoice, payment: existing_payment)
          return closed if closed.is_a?(Billing::Result)
          existing_payment.mark_closed!
        end

        Collector.with_invoice(invoice) do
          existing.reload
          if existing.state == "pending"
            existing.update!(state: "failed", failure_code: "provider_switched", completed_at: at,
              claimed_at: nil, reconcile_at: nil)
            Collector.restore_invoice_state_after_one_time_failure!(invoice)
          end
        end
        nil
      end
      private_class_method :resume_or_close_existing

      def self.query_existing(invoice:, payment:)
        begin
          Payments::Activities::Query.call(customer: Providers.platform, payment: payment)
        rescue Payments::Errors::ApiError
          nil
        rescue Payments::Errors::TransportError
          return Billing::Result.new(status: :conflict, invoice: invoice, reason: :collection_in_flight)
        end
        settle_if_captured(invoice: invoice, payment: payment)
      end
      private_class_method :query_existing

      def self.close_existing(invoice:, payment:)
        skip_close = payment.provider == "stripe" && payment.psp_transaction_id.blank?
        unless skip_close
          begin
            Payments::Gateway.close(customer: Providers.platform, payment: payment)
          rescue Payments::Errors::Error => error
            unless missing_remote_trade?(error)
              begin
                Payments::Activities::Query.call(customer: Providers.platform, payment: payment)
              rescue Payments::Errors::Error
                nil
              end
              captured = settle_if_captured(invoice: invoice, payment: payment)
              return captured if captured.is_a?(Billing::Result)
              return Billing::Result.new(status: :conflict, invoice: invoice, reason: :collection_in_flight)
            end
          end
        end
        nil
      end
      private_class_method :close_existing

      def self.settle_if_captured(invoice:, payment:)
        if payment.reload.status == "succeeded" || invoice.reload.paid?
          MarkInvoicePaid.call(invoice: invoice, payment: payment, source: :gateway) unless invoice.paid?
          Billing::Result.new(status: :succeeded, invoice: invoice.reload, subscription: invoice.subscription.reload)
        end
      end
      private_class_method :settle_if_captured

      def self.missing_remote_trade?(error)
        return false unless error.is_a?(Payments::Errors::ApiError)
        return false unless Payments::Activities::AttemptSafety.definitive_rejection?(error)
        payload = error.payload.is_a?(Hash) ? error.payload : {}
        token = [payload["sub_code"], payload["code"], error.code, error.message].compact.map(&:to_s).join(" ")
        token.match?(/TRADE_NOT_EXIST|ORDER_NOT_EXIST|RESOURCE_NOT_EXISTS/)
      end
      private_class_method :missing_remote_trade?

      def self.prepare_attempt(invoice:, provider:, request:, openid:, at:)
        Collector.with_invoice(invoice) do
          if invoice.paid?
            next Billing::Result.new(status: :succeeded, invoice: invoice, subscription: invoice.subscription)
          end
          if invoice.void? || invoice.draft? || !invoice.total_cents.positive?
            next Billing::Result.new(status: :blocked, invoice: invoice, reason: :invoice_not_payable)
          end
          identity_reason = Providers.invoice_identity_reason(invoice)
          next Billing::Result.new(status: :blocked, invoice: invoice, reason: identity_reason) if identity_reason
          if at > invoice.collection_deadline || %w[cancelled expired].include?(invoice.subscription.status)
            next Billing::Result.new(status: :blocked, invoice: invoice, reason: :request_expired)
          end
          if Collector.unresolved?(invoice)
            next Billing::Result.new(status: :conflict, invoice: invoice, reason: :collection_in_flight)
          end

          account = Payments::CredentialResolver.call(customer: Providers.platform, provider: provider.to_s)
          amount = BigDecimal(invoice.total_cents.to_s) / 100
          order = Payments::Order.unscoped_by_tenant.find_or_create_by!(
            customer_id: Collector::PLATFORM_OWNER_CUSTOMER_ID, external_ref: "billing-inv-#{invoice.id}") do |row|
            row.amount = amount
            row.currency = invoice.currency
            row.subject = invoice.terms_snapshot.fetch("name")
          end
          raise Payments::Errors::OrderInFlight, "billing order financial identity mismatch" unless order.amount == amount && order.currency == invoice.currency
          order.update!(status: "pending") if %w[failed closed].include?(order.status)
          req = request || OpenStruct.new(user_agent: "", remote_ip: nil)
          flow = Payments::FlowSelector.call(request: req, provider: provider.to_s)
          ordinal = invoice.collection_attempts.maximum(:ordinal).to_i + 1
          key = Payments::OutTradeNo.generate(prefix: "bi", customer_id: invoice.customer_id)
          payment = Payments::Payment.create!(customer_id: Collector::PLATFORM_OWNER_CUSTOMER_ID, payment_order: order,
            provider: provider.to_s, flow: flow.to_s, out_trade_no: key, amount: amount)
          context = Payments::Activities::PrepareAttempt.call(customer: Providers.platform, order: order, payment: payment,
            operation: "charge", attributes: { billing_invoice_id: invoice.id, billing_one_time: true, openid: openid,
              save_card: false, client_ip: (req.remote_ip if req.respond_to?(:remote_ip)) })
          raise Payments::Errors::CredentialsMissing, "pinned billing account differs from prepared payment" unless context["merchant_account_id"] == account.id
          attempt = invoice.collection_attempts.create!(customer_id: invoice.customer_id, ordinal: ordinal, request_key: key,
            payment: payment, billing_payment_method_id: nil, merchant_account_id: account.id, state: "prepared",
            reconcile_at: at + Collector::RECONCILE_DELAY)
          invoice.update!(collection_state: "pending", collection_claimed_at: at)
          [attempt, order, payment, flow, req]
        end
      end
      private_class_method :prepare_attempt
    end
  end
end
