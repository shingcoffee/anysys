# frozen_string_literal: true

module Billing
  module Activities
    class MakeDefaultPaymentMethod
      def self.call(customer:, payment_method:)
        Billing::Result.transaction(customer) do
          payment_method.reload
          return Billing::Result.new(status: :invalid, reason: :tenant_mismatch) unless payment_method.customer_id == customer.id
          reason = Providers.readiness_reason(payment_method: payment_method)
          return Billing::Result.new(status: :invalid, payment_method: payment_method, reason: reason) if reason
          PaymentMethod.unscoped_by_tenant.where(customer_id: customer.id).where.not(id: payment_method.id).update_all(is_default: false, requested_default: false)
          payment_method.update!(is_default: true, requested_default: true)
          Billing::Result.new(status: :active, payment_method: payment_method)
        end
      end
    end
  end
end
