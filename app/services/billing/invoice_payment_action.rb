# frozen_string_literal: true

module Billing
  module InvoicePaymentAction
    def self.for(invoice:)
      attempt = invoice.collection_attempts.where(state: "requires_action").order(:ordinal).last
      return unless attempt && !invoice.paid? && !invoice.void?
      payment = attempt.payment
      return unless payment.provider == "stripe" && payment.requires_action? && payment.recovery_client_secret.present?
      return unless attempt.customer_id == invoice.customer_id && payment.merchant_account_id == attempt.merchant_account_id

      { kind: :stripe_sca, publishable_key: attempt.merchant_account.credential(:publishable_key), client_secret: payment.recovery_client_secret }
    end
  end
end
