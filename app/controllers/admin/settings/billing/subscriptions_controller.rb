# frozen_string_literal: true

module Admin
  module Settings
    module Billing
      class SubscriptionsController < BaseController
        def show
          assign_subscription_overview
        end

        def plan_change_preview
          @subscription = live_subscription
          unless @subscription
            result = ::Billing::Result.new(status: :invalid, reason: :no_active_subscription)
            return respond_to do |format|
              format.json { render json: { allowed: false, reason: "no_active_subscription" }, status: :unprocessable_entity }
              format.html { render_subscription_failure(result) }
            end
          end
          @review_plan = ::Billing::Plan.active.find_by(code: params.permit(:plan_code)[:plan_code])
          unless @review_plan
            result = ::Billing::Result.new(status: :invalid, reason: :plan_not_active)
            return respond_to do |format|
              format.json { render json: { allowed: false, reason: "plan_not_active" }, status: :unprocessable_entity }
              format.html { render_subscription_failure(result) }
            end
          end

          @review_preview = ::Billing::PlanChangePolicy.preview(subscription: @subscription, new_plan: @review_plan)
          respond_to do |format|
            format.json do
              payload = @review_preview.slice(:kind, :effective_at, :currency, :subtotal_cents, :tax_cents,
                                              :total_cents, :allowed, :reason)
              payload[:effective_at] = payload[:effective_at]&.iso8601
              render json: payload
            end
            format.html do
              assign_subscription_overview
              render :show
            end
          end
        end

        def update
          attributes = subscription_params.to_h.symbolize_keys
          @request_key = attributes[:request_key]
          @form = subscription_form(attributes)
          plan = ::Billing::Plan.find_by(code: attributes[:plan_code])
          @review_plan = plan
          coupon = ::Billing::Coupon.find_by(code: attributes[:coupon_code]) if attributes[:coupon_code].present?

          @form.errors.add(:plan_code, t("admin_settings.errors.validations.plan_not_active")) unless plan
          unless valid_billing_request_key?(@request_key)
            @form.errors.add(:request_key, t("admin_settings.errors.validations.billing_request_key"))
          end
          if !live_subscription && attributes[:coupon_code].present? && !coupon
            @form.errors.add(:coupon_code, t("admin_settings.errors.validations.coupon_not_found"))
          end
          if @form.errors.any?
            return render_subscription_failure(::Billing::Result.new(status: :invalid, form: @form,
                                                                      errors: @form.errors.messages))
          end

          result = if live_subscription
                     ::Billing::Activities::ChangePlan.call(subscription: live_subscription, new_plan: plan,
                                                           request_key: @request_key)
                   else
                     ::Billing::Activities::Subscribe.call(customer: current_customer, plan: plan, coupon: coupon,
                                                          request_key: @request_key)
                   end
          assign_billing_result(result)
          case result.status
          when :active, :trialing
            redirect_subscription("subscribed", name: plan.name)
          when :applied
            redirect_subscription("plan_changed", name: plan.name)
          when :scheduled
            redirect_subscription("plan_change_scheduled", date: l(result.plan_change.effective_at, format: :long))
          when :awaiting_payment
            key = result.plan_change ? "plan_change_pending" : "subscription_pending"
            redirect_subscription(key)
          when :unchanged
            redirect_subscription("unchanged")
          else
            render_subscription_failure(result)
          end
        end

        private

        def redirect_subscription(key, **values)
          redirect_to admin_settings_billing_subscription_path(current_customer_id), status: :see_other,
                      notice: t("admin_settings.flash.subscriptions.#{key}", **values)
        end

        def subscription_params
          params.require(:billing_subscription).permit(:plan_code, :coupon_code, :request_key)
        end
      end
    end
  end
end
