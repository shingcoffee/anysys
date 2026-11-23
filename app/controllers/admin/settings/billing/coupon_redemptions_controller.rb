# frozen_string_literal: true

module Admin
  module Settings
    module Billing
      class CouponRedemptionsController < BaseController
        def create
          @coupon_code = coupon_params[:coupon_code]
          unless live_subscription
            return render_subscription_failure(::Billing::Result.new(status: :invalid, reason: :no_active_subscription))
          end
          coupon = ::Billing::Coupon.find_by(code: @coupon_code)
          unless coupon
            return render_subscription_failure(::Billing::Result.new(status: :invalid, reason: :coupon_not_found,
                                                                      errors: { coupon_code: [t("admin_settings.flash.coupon_redemptions.not_found")] }))
          end

          result = ::Billing::Activities::ApplyCoupon.call(subscription: live_subscription, coupon: coupon)
          return render_subscription_failure(result) unless %i[applied unchanged].include?(result.status)

          redirect_to admin_settings_billing_subscription_path(current_customer_id), status: :see_other,
                      notice: t("admin_settings.flash.coupon_redemptions.applied", code: coupon.code)
        end

        private

        def coupon_params
          params.require(:coupon_redemption).permit(:coupon_code)
        end
      end
    end
  end
end
