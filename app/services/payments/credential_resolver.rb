# frozen_string_literal: true

module Payments
  class CredentialResolver
    def self.default_mode
      Rails.env.production? ? "production" : "sandbox"
    end

    def self.call(customer:, provider:, mode: default_mode)
      acc = Payments::MerchantAccount.unscoped_by_tenant
                                  .where(customer_id: customer.id,
                                         provider: provider, mode: mode,
                                         status: "active")
                                  .first
      unless acc
        raise Payments::Errors::CredentialsMissing,
              "No active #{provider} account for customer #{customer.id} in #{mode}"
      end
      acc
    end

    def self.by_merchant_id(provider:, merchant_id:)
      # Verification/settlement of an existing operation must survive disabling
      # NEW charges. Call still requires active credentials; this lookup does not.
      acc = Payments::MerchantAccount.unscoped_by_tenant
                                  .where(provider: provider, merchant_id: merchant_id)
                                  .first
      unless acc
        raise Payments::Errors::TenantNotFound,
              "No #{provider} account for merchant_id #{merchant_id}"
      end
      acc
    end

    # For query/refund/close of a committed attempt. The facade/activity caller
    # must opt into this lookup; it must never silently use today's replacement
    # merchant for an existing payment. Account disablement only gates new writes.
    def self.for_payment(customer:, payment:, historical: true)
      unless payment.customer_id == customer.id
        raise Payments::Errors::TenantMismatch, "payment does not belong to the supplied customer"
      end

      pinned_payment_account(payment, historical: historical)
    end

    # Pre-verification routing only: an exact locally recorded PSP operation
    # resolves its historical account, independent of today's environment mode.
    # Missing/ambiguous correlation must not guess a tenant or replacement row.
    def self.for_psp_operation(provider:, psp_transaction_id:)
      return nil unless psp_transaction_id.is_a?(String) && psp_transaction_id.present?

      matches = Payments::Payment.unscoped_by_tenant
                                 .where(provider: provider, psp_transaction_id: psp_transaction_id)
                                 .limit(2).to_a
      return nil if matches.empty?
      unless matches.one?
        raise Payments::Errors::CredentialsMissing, "PSP operation has ambiguous local merchant evidence"
      end

      payment = matches.first
      unless payment.merchant_account_id.present?
        raise Payments::Errors::CredentialsMissing, "PSP operation requires an offline historical merchant binding"
      end

      pinned_payment_account(payment, historical: true)
    end

    def self.pinned_payment_account(payment, historical:)
      context = payment.attempt_context
      account = Payments::MerchantAccount.unscoped_by_tenant.find_by(
        id: payment.merchant_account_id, customer_id: payment.customer_id, provider: payment.provider
      )
      identity_matches = account && context["provider"] == payment.provider
      write_matches = identity_matches && account.merchant_id == context["merchant_id"] && account.mode == context["mode"]
      unless identity_matches && (historical || write_matches)
        raise Payments::Errors::CredentialsMissing, "historical payment merchant identity is unavailable or changed"
      end
      account
    end
    private_class_method :pinned_payment_account
  end
end
