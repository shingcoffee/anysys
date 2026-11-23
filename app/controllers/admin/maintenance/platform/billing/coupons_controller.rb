# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module Billing
        class CouponsController < BaseController
          before_action :set_coupon, only: %i[show edit update destroy]

          def index
            @coupons = paginate_billing(::Billing::Coupon.order(:code, :id))
          end

          def show
          end

          def new
            @coupon = ::Billing::Coupon.new
            @form = @contract = ::Billing::Contracts::Coupon.new(@coupon)
          end

          def edit
            @form = @contract = ::Billing::Contracts::Coupon.new(@coupon)
          end

          def create
            @coupon = ::Billing::Coupon.new
            save_coupon(:new, "coupon_created")
          end

          def update
            save_coupon(:edit, "coupon_updated")
          end

          def destroy
            result = ::Billing::Catalog::ArchiveCoupon.call(coupon: @coupon)
            unless %i[archived unchanged].include?(result.status)
              @coupons = paginate_billing(::Billing::Coupon.order(:code, :id))
              return render_billing_failure(result, :index)
            end
            redirect_to admin_maintenance_platform_billing_coupons_path(current_customer_id), status: :see_other,
                        notice: t("maint_platform.flash.billing.coupon_archived")
          end

          private

          def save_coupon(template, notice_key)
            result = ::Billing::Catalog::SaveCoupon.call(coupon: @coupon, params: coupon_params.to_h)
            assign_billing_result(result)
            return render_billing_failure(result, template) unless result.status == :saved
            @coupon = result.record
            redirect_to admin_maintenance_platform_billing_coupons_path(current_customer_id), status: :see_other,
                        notice: t("maint_platform.flash.billing.#{notice_key}", code: @coupon.code)
          end

          def set_coupon
            @coupon = ::Billing::Coupon.find(params[:id])
          end

          def coupon_params
            params.require(:billing_coupon).permit(:code, :name, :discount_type, :percent_off, :amount_off_cents,
                                                   :currency, :duration, :duration_in_cycles, :max_redemptions,
                                                   :redeem_by, :active)
          end
        end
      end
    end
  end
end
