# frozen_string_literal: true

module Billing
  module Cron
    class RevokePaymentMethods
      def self.perform(at: Time.current)
        PaymentMethod.unscoped_by_tenant.where(status: "removed", revocation_state: %w[pending failed])
          .where("revocation_next_attempt_at <= ?", at).find_each do |method|
          claimed = PaymentMethod.where(id: method.id, revocation_state: %w[pending failed])
            .where("revocation_next_attempt_at <= ?", at).update_all(revocation_next_attempt_at: at + 15.minutes)
          next unless claimed == 1
          Current.set(customer: method.customer) do
            if method.merchant_account.nil? || method.failure_code == "historical_authorization_review"
              method.update!(revocation_state: "failed", failure_code: "historical_authorization_review", revocation_next_attempt_at: at + 1.day)
              next
            end
            unless method.payments_subscription
              method.update!(revocation_state: "complete", revocation_next_attempt_at: nil)
              next
            end
            # Pending setup must be queried: a late successful authorization
            # needs a real token/agreement id before remote cleanup can finish.
            if method.provider == "stripe" ? !method.payments_subscription.payment_method&.confirmed? : method.payments_subscription.psp_agreement_id.blank?
              confirmation = PaymentAuthorization.confirm!(payment_method: method)
              next if confirmation.status == :pending && method.provider == "alipay"
              method.reload
            end
            next if Providers.for(method).revoke == :pending
            method.update!(revocation_state: "complete", revocation_next_attempt_at: nil, failure_code: nil)
          end
        rescue Payments::Errors::Error => error
          count = method.revocation_attempt_count + 1
          method.update!(revocation_state: "failed", revocation_attempt_count: count,
            revocation_next_attempt_at: at + [2**[count, 10].min, 1440].min.minutes, failure_code: "revocation_failed")
          Rails.logger.error("[billing.revoke] method=#{method.id} #{error.class}")
        end
      end
    end
  end
end
