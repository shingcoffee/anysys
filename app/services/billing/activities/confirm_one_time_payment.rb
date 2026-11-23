# frozen_string_literal: true

module Billing
  module Activities
    class ConfirmOneTimePayment
      def self.call(invoice:, out_trade_no: nil, at: Time.current)
        raise ArgumentError, "confirmation must run after domain commit" if Invoice.connection.transaction_open?

        attempts = invoice.collection_attempts.where(billing_payment_method_id: nil)
        attempt = out_trade_no.present? ? attempts.find_by(request_key: out_trade_no.to_s) : attempts.order(:ordinal).last
        return Billing::Result.invalid(:payment_not_found, invoice: invoice) unless attempt && attempt.payment
        return Billing::Result.new(status: :succeeded, invoice: invoice, subscription: invoice.subscription,
          record: attempt) if invoice.paid? && attempt.payment.status == "succeeded"

        payment = attempt.payment
        if payment.status == "pending"
          begin
            Payments::Activities::Query.call(customer: Providers.platform, payment: payment)
          rescue Payments::Errors::Error
            nil
          end
        end

        payment.reload
        invoice.reload
        if payment.status == "succeeded"
          MarkInvoicePaid.call(invoice: invoice, payment: payment, source: :gateway) unless invoice.paid?
          Billing::Result.new(status: :succeeded, invoice: invoice.reload, subscription: invoice.subscription.reload,
            record: attempt.reload)
        elsif payment.status.in?(%w[failed closed])
          Collector.complete(attempt, { status: :failed, failure_code: payment.status }, at: at) unless attempt.reload.state == "failed"
          Billing::Result.new(status: :failed, invoice: invoice.reload, record: attempt.reload, reason: :one_time_charge_failed)
        else
          Billing::Result.new(status: :pending, invoice: invoice.reload, record: attempt.reload)
        end
      end
    end
  end
end
