# frozen_string_literal: true

module Payments
  module Cron
    # Scheduled job that iterates every active `Payments::MerchantAccount` across
    # tenants and triggers `Payments::Activities::Reconcile` for the previous
    # day's bills. Errors from a single account are logged and swallowed so the
    # rest of the batch continues processing.
    class DownloadBills
      def self.perform(bill_date: Date.yesterday)
        # Only providers that actually support downloadable settlement bills.
        # Iterating every active account (Stripe/PayPal included) would raise a
        # non-Payments RecordInvalid inside Reconcile (the ReconciliationBill
        # provider whitelist), which — being neither rescued here nor in Reconcile
        # — would abort the whole cross-tenant batch.
        Payments::MerchantAccount.unscoped_by_tenant.active
                                 .where(provider: Payments::ReconciliationBill::PROVIDERS,
                                        mode: Payments::CredentialResolver.default_mode)
                                 .find_each do |acc|
          next unless FeatureModules::Module.enabled?(key: "payment", customer_id: acc.customer_id)

          Current.customer = acc.customer
          Payments::Activities::Reconcile.call(customer: acc.customer, provider: acc.provider,
                                               bill_date: bill_date, merchant_account: acc)
        rescue Payments::Errors::Error => e
          Rails.logger.error("[payments.cron] #{e.class}: #{e.message}")
        end
      ensure
        Current.reset
      end
    end
  end
end
