# frozen_string_literal: true

module Billing
  module Catalog
    class ArchiveCoupon
      def self.call(coupon:)
        Result.transaction(coupon) do
          next Result.new(status: :unchanged, record: coupon) if coupon.archived_at
          coupon.update!(archived_at: Time.current, active: false)
          Result.new(status: :archived, record: coupon)
        end
      end
    end
  end
end
