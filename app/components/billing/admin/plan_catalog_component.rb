# frozen_string_literal: true

module Billing
  module Admin
    # Renders the platform billing plan catalog as a responsive grid of plan
    # cards (Area d). Replaces the older wide-table layout, which sprawled a
    # column per countable item; cards keep each plan's pricing, status and
    # per-item limits legible no matter how many countable items exist.
    #
    # Constructor:
    #   plans:       Array/relation of Billing::Plan records
    #   customer_id: current customer_id for building route helpers
    #   items:       enabled Billing::CountableItem records (limit rows per card)
    class PlanCatalogComponent < ApplicationComponent
      def initialize(plans:, customer_id:, items: [], pagination: nil, page_path: nil)
        @plans       = plans
        @customer_id = customer_id.to_s
        @items       = items
        @pagination, @page_path = pagination, page_path
      end

      attr_reader :plans, :customer_id, :items
      attr_reader :pagination, :page_path

      def any_plans? = plans.any?

      # Display string for a plan/item limit: the integer, or "Unlimited" when
      # the limit is not set (matches Billing::Admin::PlanComparisonComponent).
      def limit_display(plan, item)
        unlimited?(plan, item) ? I18n.t("comp_billing.plan_catalog.unlimited") : plan.limit_for(item.key).to_s
      end

      def unlimited?(plan, item)
        plan.limit_for(item.key) == Billing::PlanLimit::UNLIMITED
      end

      def format_amount(amount, currency = "CNY")
        ::Billing::CurrencyResolver.format_amount(amount, currency)
      end

      # A plan is free when both currency amounts are zero.
      def free?(plan)
        plan.free?
      end

      # Short per-interval price suffix, e.g. "/mo" or "/yr".
      def interval_suffix(plan)
        plan.interval.to_s == "yearly" ? I18n.t("comp_billing.plan_catalog.interval_year") : I18n.t("comp_billing.plan_catalog.interval_month")
      end

      # Full interval label, e.g. "Monthly" / "Yearly".
      def interval_label(plan)
        I18n.t("comp_billing.plan_form.intervals.#{plan.interval}")
      end

      def plan_path(plan)
        helpers.admin_maintenance_platform_billing_plan_path(customer_id, plan)
      end

      def edit_plan_path(plan)
        helpers.edit_admin_maintenance_platform_billing_plan_path(customer_id, plan)
      end

      def new_plan_path
        helpers.new_admin_maintenance_platform_billing_plan_path(customer_id)
      end
    end
  end
end
