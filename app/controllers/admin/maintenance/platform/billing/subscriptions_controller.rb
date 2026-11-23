# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module Billing
        # Platform-owner cross-tenant subscription oversight (Area d).
        #
        # index — all subscriptions across all tenants (unscoped_by_tenant).
        # show  — single subscription with its invoices; re-applies
        #         unscoped_by_tenant so any tenant's subscription is reachable.
        #
        # Cancellation is a nested resource (POST .../subscriptions/:id/cancellation).
        # The immediate cancel is the only write here; plan changes / coupon apply
        # are done by the customer via Area b settings.
        class SubscriptionsController < BaseController
          before_action :set_subscription, only: :show

          def index
            billing_filters(statuses: ::Billing::Subscription::STATUSES, platform: true)
            relation = ::Billing::Subscription.unscoped_by_tenant.includes(:plan, :customer)
            relation = relation.where(status: @filters[:status]) if @filters[:status]
            relation = relation.where(customer_id: @filters[:tenant_id]) if @filters[:tenant_id]
            if @filters[:q]
              pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@filters[:q].downcase)}%"
              relation = relation.joins(:plan).where(
                "LOWER(billing_plans.name) LIKE ? ESCAPE '\\' OR LOWER(billing_plans.code) LIKE ? ESCAPE '\\'",
                pattern, pattern
              )
            end
            @subscriptions = paginate_billing(recent_billing(relation))
            ids = @subscriptions.map(&:id)
            @pending_changes = ::Billing::PlanChange.unscoped_by_tenant.outstanding
                               .where(billing_subscription_id: ids).to_a.to_h do |change|
              subscription = @subscriptions.find { |row| row.id == change.billing_subscription_id }
              raise ::Payments::Errors::TenantMismatch, "billing plan change tenant mismatch" unless change.customer_id == subscription.customer_id
              [subscription.id, change]
            end
          end

          def show
            assign_subscription_detail
          end

          private

          def set_subscription
            @subscription = ::Billing::Subscription.unscoped_by_tenant.find(params[:id])
          end
        end
      end
    end
  end
end
