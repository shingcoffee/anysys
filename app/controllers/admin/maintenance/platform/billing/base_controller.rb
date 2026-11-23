# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module Billing
        # Shared base for platform-owner billing controllers (Area d).
        #
        # Path-based platform-owner gating is applied automatically by
        # RouteAuthorization for any controller_path starting with
        # admin/maintenance/platform/ — no explicit before_action needed here.
        #
        # Plans, coupons, and settings are global records (no customer_id).
        # Subscriptions and invoices are tenant records accessed via
        # unscoped_by_tenant (cross-tenant oversight is owner-only).
        class BaseController < ApplicationController
          include ::Billing::Pagination
          include ::Billing::ControllerPresentation

          dashboard_menu_item :maintenance

          private

          def assign_billing_result(result)
            @result = result
            @form = result.form
            @contract = @form
            @errors = result.errors
          end

          def billing_failure_status(result)
            %i[conflict blocked exhausted skipped].include?(result.status) ? :conflict : :unprocessable_entity
          end

          def billing_failure_message(result)
            t(billing_reason_key(result.reason) || "admin_settings.flash.billing.command_invalid")
          end

          def render_billing_failure(result, template)
            assign_billing_result(result)
            flash.now[:alert] = billing_failure_message(result)
            render template, status: billing_failure_status(result)
          end

          def assign_subscription_detail
            relation = ::Billing::Invoice.unscoped_by_tenant.includes(:subscription)
                       .where(customer_id: @subscription.customer_id, billing_subscription_id: @subscription.id)
            @invoices = paginate_billing(recent_billing(filter_billing_invoices(relation)))
            assign_invoice_history_collections(platform: true)
            @pending_plan_change = ::Billing::PlanChange.unscoped_by_tenant
                                   .where(customer_id: @subscription.customer_id,
                                          billing_subscription_id: @subscription.id).outstanding.first
            @currency = @subscription.currency
            @entitlements = ::Billing::Entitlements.for(customer: @subscription.customer)
            @coupon_benefit = billing_coupon_benefit(@subscription, pending_change: @pending_plan_change)
            @can_cancel_immediately = ::Billing::PresentationFacts.can_cancel_immediately?(subscription: @subscription)
          end
        end
      end
    end
  end
end
