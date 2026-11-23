# frozen_string_literal: true

module Billing
  # Owns the committed billing/payment attempt pair. No provider write runs in
  # the preparation or outcome transaction; an uncertain write remains live.
  module Collector
    PLATFORM_OWNER_CUSTOMER_ID = Authentication::User::PLATFORM_CUSTOMER_ID
    RECONCILE_DELAY = 15.minutes

    class << self
      def with_invoice(invoice)
        subscription = Billing::Subscription.unscoped_by_tenant.find(invoice.billing_subscription_id)
        Billing::Result.transaction(subscription) do
          subscription.lock!
          invoice.lock!
          raise Payments::Errors::TenantMismatch, "invoice subscription mismatch" unless invoice.customer_id == subscription.customer_id
          Current.set(customer: invoice.customer) { yield }
        end
      end

      def collect(invoice, trigger: :initial, at: Time.current)
        raise ArgumentError, "invalid collection trigger" unless %i[initial retry recovery reconcile].include?(trigger.to_sym)
        return reconcile(invoice, at: at) if trigger.to_sym == :reconcile
        # Local zero/manual transitions do not perform provider HTTP. A's
        # after-commit callback can also run under a nonjoinable fixture root;
        # the gateway branch alone must refuse a caller-owned transaction.
        provider_allowed = !Invoice.connection.transaction_open?
        prepared = prepare(invoice, trigger.to_sym, at, provider_allowed: provider_allowed)
        return prepared if prepared.is_a?(Billing::Result)
        submit(prepared, at: at)
      rescue ActiveRecord::RecordNotUnique
        invoice.reload
        result(invoice, :pending, :concurrent_collection)
      end

      def unresolved?(invoice)
        invoice.collection_attempts.inflight.exists? || platform_payments(invoice).where(status: %w[created pending succeeded]).where.not(id: invoice.payment_id).exists?
      end

      def platform_payments(invoice)
        orders = Payments::Order.unscoped_by_tenant.where(customer_id: PLATFORM_OWNER_CUSTOMER_ID, external_ref: "billing-inv-#{invoice.id}")
        Payments::Payment.unscoped_by_tenant.where(customer_id: PLATFORM_OWNER_CUSTOMER_ID, payment_order_id: orders.select(:id))
      end

      def result(invoice, status, reason = nil)
        Billing::Result.new(status: status, invoice: invoice, subscription: invoice.subscription.reload, reason: reason)
      end

      def restore_invoice_state_after_one_time_failure!(invoice)
        return if invoice.paid? || invoice.void?

        state = if invoice.effective_collection_mode == "manual"
          "manual"
        elsif invoice.uncollectible?
          "exhausted"
        elsif invoice.next_attempt_at.present?
          "retry_wait"
        elsif invoice.failure_code.present?
          "blocked"
        else
          "ready"
        end
        invoice.update!(collection_claimed_at: nil, collection_state: state)
      end

      def reconcile(invoice, at: Time.current)
        raise ArgumentError, "reconciliation must run after domain commit" if Invoice.connection.transaction_open?
        # A Payments webhook can commit success before the billing projection.
        succeeded = platform_payments(invoice).where(status: "succeeded").order(:id).to_a
        succeeded.each do |payment|
          settlement = Activities::MarkInvoicePaid.call(invoice: invoice, payment: payment, source: :gateway, paid_at: payment.paid_at || at)
          return result(invoice, :blocked, settlement.reason) if settlement.status == :invalid
        end
        attempt = invoice.collection_attempts.inflight.order(:ordinal).last
        return result(invoice.reload, invoice.paid? ? :succeeded : :skipped, :no_inflight_attempt) unless attempt
        if attempt.one_time? && attempt.state == "prepared"
          return result(invoice, :pending, :claimed) if attempt.created_at > at - RECONCILE_DELAY
          return with_invoice(invoice) do
            attempt.reload
            if attempt.state == "prepared"
              attempt.payment&.mark_closed!
              attempt.update!(state: "failed", failure_code: "abandoned", completed_at: at, claimed_at: nil, reconcile_at: nil)
              restore_invoice_state_after_one_time_failure!(invoice)
            end
            result(invoice.reload, :skipped, :abandoned)
          end
        end
        return submit(attempt, at: at) if attempt.state == "prepared"
        return result(invoice, :pending, :claimed) if attempt.claimed_at && attempt.claimed_at > at - RECONCILE_DELAY
        claimed = CollectionAttempt.where(id: attempt.id, state: CollectionAttempt::INFLIGHT_STATES)
          .where("claimed_at IS NULL OR claimed_at <= ?", at - RECONCILE_DELAY).update_all(claimed_at: at)
        return result(invoice, :pending, :claimed) unless claimed == 1

        payment = attempt.payment.reload
        outcome = if payment.status == "succeeded"
          { status: :succeeded, psp_transaction_id: payment.psp_transaction_id, settled_at: payment.paid_at }
        elsif %w[failed closed].include?(payment.status)
          { status: :failed, failure_code: payment.status }
        else
          Providers.query(attempt: attempt)
        end
        complete(attempt, outcome, at: at)
      rescue Payments::Errors::TransportError, Payments::Errors::CredentialsMissing => error
        unknown(attempt, error.class.name.demodulize.underscore, at)
      rescue Payments::Errors::ApiError => error
        if Providers.not_found?(error, attempt&.payment&.provider, attempt: attempt)
          complete(attempt, { status: :failed, failure_code: "provider_not_found" }, at: at)
        else
          unknown(attempt, "query_unavailable", at)
        end
      end

      def complete(attempt, outcome, at: Time.current)
        payment = attempt.payment.reload
        status = outcome.fetch(:status, :unknown).to_sym
        payload = outcome[:raw].is_a?(Hash) ? outcome[:raw] : {}
        # Persist provider identity for pending/SCA as well as final responses.
        if outcome[:psp_transaction_id].present?
          payment.update!(psp_transaction_id: outcome[:psp_transaction_id]) unless payment.status == "succeeded"
        end
        case status
        when :succeeded
          Providers.validate_capture!(payment: payment, outcome: outcome)
          payment.mark_succeeded!(psp_id: outcome[:psp_transaction_id] || payment.psp_transaction_id,
            at: outcome[:settled_at] || at, notify: payload)
          with_invoice(attempt.invoice) do
            attempt.reload.update!(state: "succeeded", completed_at: payment.paid_at, claimed_at: nil, reconcile_at: nil)
          end
          settled = Activities::MarkInvoicePaid.call(invoice: attempt.invoice, payment: payment, source: :gateway, paid_at: payment.paid_at)
          result(attempt.invoice, settled.status == :invalid ? :blocked : :succeeded, settled.reason)
        when :failed, :closed
          payment.mark_failed!(reason: outcome[:failure_code].presence || status.to_s, notify: payload)
          # A verified webhook outranks a simultaneous pessimistic response.
          return complete(attempt, { status: :succeeded, settled_at: payment.paid_at }, at: at) if payment.reload.status == "succeeded"
          definitive_failure(attempt, outcome[:failure_code].presence || status.to_s, at)
        else
          state = if status == :requires_action || (status == :unknown && attempt.state == "requires_action")
            "requires_action"
          else
            status == :pending ? "pending" : "unknown"
          end
          payment.with_lock do
            payment.update!(status: "pending", prepay_payload: payment.prepay_payload.merge(
              "requires_action" => state == "requires_action",
              "client_secret" => outcome[:client_secret] || payment.prepay_payload["client_secret"])) unless Payments::Payment::TERMINAL_STATUSES.include?(payment.status)
          end
          return complete(attempt, { status: :succeeded, settled_at: payment.paid_at }, at: at) if payment.reload.status == "succeeded"
          with_invoice(attempt.invoice) do
            attempt.reload
            unless %w[succeeded failed].include?(attempt.state)
              attempt.update!(state: state, claimed_at: nil, reconcile_at: at + RECONCILE_DELAY)
              attempt.invoice.update!(collection_state: state == "requires_action" ? state : "pending", collection_claimed_at: nil) unless attempt.invoice.paid? || attempt.invoice.void?
            end
          end
          result(attempt.invoice, state == "requires_action" ? :requires_action : :pending)
        end
      end

      private

      def prepare(invoice, trigger, at, provider_allowed:)
        with_invoice(invoice) do
          return result(invoice, :skipped, invoice.status.to_sym) if invoice.paid? || invoice.void? || invoice.draft?
          identity_reason = Providers.invoice_identity_reason(invoice)
          if identity_reason
            invoice.update!(collection_state: "blocked", failure_code: identity_reason, next_attempt_at: nil)
            return result(invoice, :blocked, identity_reason)
          end
          return result(invoice, :pending, :in_flight) if unresolved?(invoice)
          if at > invoice.collection_deadline || %w[cancelled expired].include?(invoice.subscription.status)
            invoice.update!(collection_state: "stopped", next_attempt_at: nil)
            return result(invoice, :blocked, :request_expired)
          end
          if invoice.total_cents.zero?
            Activities::MarkInvoicePaid.call(invoice: invoice, source: :zero)
            return result(invoice, :succeeded)
          end
          if invoice.effective_collection_mode == "manual"
            invoice.update!(collection_state: "manual", next_attempt_at: nil)
            return result(invoice, :pending_manual)
          end
          raise ArgumentError, "collection must run after domain commit" unless provider_allowed
          allowed = case trigger
          when :initial then invoice.open? && invoice.collection_state == "ready" && invoice.attempt_count.zero?
          when :retry then invoice.open? && invoice.collection_state == "retry_wait" && invoice.next_attempt_at && invoice.next_attempt_at <= at
          when :recovery then %w[open uncollectible].include?(invoice.status)
          end
          return result(invoice, :skipped, :not_due) unless allowed

          method = PaymentMethod.unscoped_by_tenant.where(customer_id: invoice.customer_id).default_method.first
          reason = Providers.readiness_reason(payment_method: method, invoice: invoice)
          if reason
            changed = invoice.collection_state != "blocked" || invoice.failure_code != reason.to_s
            invoice.update!(collection_state: "blocked", failure_code: reason, next_attempt_at: nil)
            Notifier.collection_blocked(invoice, reason) if changed
            return result(invoice, :blocked, reason)
          end
          # SQLite write boundary before inserting the unique live attempt.
          Invoice.where(id: invoice.id).update_all(collection_claimed_at: at)
          ordinal = invoice.collection_attempts.maximum(:ordinal).to_i + 1
          key = "billing-invoice-#{invoice.id}-#{ordinal}"
          amount = BigDecimal(invoice.total_cents.to_s) / 100
          order = Payments::Order.unscoped_by_tenant.find_or_create_by!(customer_id: PLATFORM_OWNER_CUSTOMER_ID, external_ref: "billing-inv-#{invoice.id}") do |row|
            row.amount = amount
            row.currency = invoice.currency
            row.subject = invoice.terms_snapshot.fetch("name")
          end
          raise Payments::Errors::OrderInFlight, "billing order financial identity mismatch" unless order.amount == amount && order.currency == invoice.currency
          payment = Payments::Payment.create!(customer_id: PLATFORM_OWNER_CUSTOMER_ID, payment_order: order,
            provider: method.provider, flow: method.provider == "stripe" ? "card" : "jsapi", out_trade_no: key, amount: amount)
          context = Payments::Activities::PrepareAttempt.call(customer: Customer.find(PLATFORM_OWNER_CUSTOMER_ID),
            order: order, payment: payment, operation: "billing_collection", attributes: { billing_invoice_id: invoice.id, billing_payment_method_id: method.id })
          raise Payments::Errors::CredentialsMissing, "pinned billing account differs from prepared payment" unless context["merchant_account_id"] == method.merchant_account_id
          attempt = invoice.collection_attempts.create!(customer_id: invoice.customer_id, ordinal: ordinal, request_key: key,
            payment: payment, payment_method: method, merchant_account_id: method.merchant_account_id, state: "prepared", reconcile_at: at)
          invoice.update!(collection_state: "pending", collection_claimed_at: at, next_attempt_at: nil, failure_code: nil)
          attempt
        end
      end

      def submit(attempt, at:)
        invoice = attempt.invoice
        allowed = with_invoice(invoice) do
          attempt.reload
          next false unless attempt.state == "prepared"
          reason = Providers.readiness_reason(payment_method: attempt.payment_method.reload, invoice: invoice)
          if reason || invoice.paid? || invoice.void? || at > invoice.collection_deadline || %w[cancelled expired].include?(invoice.subscription.status)
            attempt.update!(state: "failed", completed_at: at, failure_code: "not_submitted", reconcile_at: nil)
            attempt.payment.mark_closed!
            invoice.update!(collection_state: "blocked", failure_code: reason || "request_expired", collection_claimed_at: nil) unless invoice.paid? || invoice.void?
            next false
          end
          CollectionAttempt.where(id: attempt.id, state: "prepared").update_all(state: "submitting", submitted_at: at, claimed_at: at, reconcile_at: at + RECONCILE_DELAY) == 1
        end
        return result(invoice, :blocked, :not_submitted) unless allowed
        complete(attempt, Providers.charge(attempt: attempt), at: at)
      rescue Payments::Errors::TransportError => error
        unknown(attempt, "transport_unknown", at)
      rescue Payments::Errors::ApiError => error
        if Payments::Activities::AttemptSafety.definitive_rejection?(error)
          complete(attempt, { status: :failed, failure_code: Providers.failure_code(error) }, at: at)
        else
          unknown(attempt, "api_outcome_unknown", at)
        end
      rescue Payments::Errors::CredentialsMissing
        unknown(attempt, "credentials_unavailable", at)
      end

      def unknown(attempt, code, at)
        raise Payments::Errors::TransportError, code unless attempt
        complete(attempt, { status: :unknown }, at: at).tap do
          CollectionAttempt.where(id: attempt.id, state: "unknown").update_all(failure_code: code)
        end
      end

      def definitive_failure(attempt, code, at)
        if attempt.one_time?
          return with_invoice(attempt.invoice) do
            attempt.reload
            invoice = attempt.invoice
            return result(invoice, invoice.paid? ? :succeeded : :skipped) if %w[failed succeeded].include?(attempt.state)
            attempt.update!(state: "failed", failure_code: code, completed_at: at, claimed_at: nil, reconcile_at: nil)
            restore_invoice_state_after_one_time_failure!(attempt.invoice)
            result(attempt.invoice.reload, attempt.invoice.paid? ? :succeeded : :failed, code.to_sym)
          end
        end
        with_invoice(attempt.invoice) do
          attempt.reload
          invoice = attempt.invoice
          return result(invoice, invoice.paid? ? :succeeded : :skipped) if %w[failed succeeded].include?(attempt.state)
          attempt.update!(state: "failed", failure_code: code, completed_at: at, claimed_at: nil, reconcile_at: nil)
          count = invoice.attempt_count + 1
          first = invoice.first_failed_at || at
          if invoice.paid? || invoice.void?
            invoice.update!(attempt_count: count, first_failed_at: first)
            return result(invoice, invoice.paid? ? :succeeded : :skipped)
          end
          offsets = invoice.terms_snapshot.fetch("dunning_schedule").map { |day| Integer(day) }
          # One submission per pass: skipped past offsets are not catch-up charges.
          next_at = offsets.drop(count - 1).map { |day| first + day.days }.find { |date| date > at }
          exhausted = next_at.nil?
          invoice.update!(attempt_count: count, first_failed_at: first, failure_code: code, collection_claimed_at: nil,
            next_attempt_at: next_at, collection_state: exhausted ? "exhausted" : "retry_wait",
            status: invoice.paid? || invoice.void? ? invoice.status : (exhausted ? "uncollectible" : "open")) unless invoice.paid? || invoice.void?
          Notifier.payment_failed(invoice, attempt: attempt)
          Notifier.collection_exhausted(invoice) if exhausted
          result(invoice, invoice.paid? ? :succeeded : (exhausted ? :exhausted : :retry_scheduled), code.to_sym)
        end
      end
    end
  end
end
