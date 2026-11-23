# frozen_string_literal: true

module Billing
  module Catalog
    class SaveCoupon
      def self.call(coupon:, params:)
        Result.transaction(coupon) do
          form = Contracts::Coupon.new(coupon)
          unless form.validate(params.to_h.except(:archived_at, "archived_at"))
            next Result.invalid(:validation_failed, record: coupon, form: form, errors: form.errors.messages)
          end
          form.sync
          coupon.save!
          Result.new(status: :saved, record: coupon, form: form)
        end
      end
    end
  end
end
