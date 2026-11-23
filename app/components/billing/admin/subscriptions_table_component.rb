# frozen_string_literal: true

module Billing
  module Admin
    # Renders a table of billing subscriptions. Used by:
    #   - Platform cross-tenant oversight (Area d, platform: true)
    #
    # Constructor:
    #   subscriptions: Array/relation of Billing::Subscription (with :plan, :customer eager-loaded)
    #   customer_id:   current customer_id (owner's) for route helpers
    #   platform:      bool — true renders platform paths and includes Customer column
    class SubscriptionsTableComponent < ApplicationComponent
      include Presentation
      STATUS_BADGE_MAP = {
        "pending"   => :warning,
        "trialing"  => :info,
        "active"    => :success,
        "past_due"  => :danger,
        "paused"    => :warning,
        "cancelled" => :default,
        "expired"   => :default
      }.freeze

      def initialize(subscriptions:, customer_id:, platform: false, filters: {}, pagination: nil, page_path: nil, pending_changes: {})
        @subscriptions = subscriptions
        @customer_id   = customer_id.to_s
        @platform      = platform
        @filters, @pagination, @page_path, @pending_changes = filters, pagination, page_path, pending_changes || {}
      end

      attr_reader :subscriptions, :customer_id, :platform
      attr_reader :filters, :pagination, :page_path, :pending_changes

      def platform? = platform

      # Column set varies with platform? (cross-tenant view adds Customer).
      # Plan and interval share one cell; interval is secondary text.
      def headers
        base = [
          { label: t("comp_billing.subscriptions_table.plan"),       align: :left },
          { label: t("comp_billing.subscriptions_table.amount"),     align: :right },
          { label: t("comp_billing.subscriptions_table.period_end"), align: :left },
          { label: t("common.labels.status"),                        align: :left },
          { label: t("common.labels.actions") }
        ]
        return base unless platform?

        [{ label: t("comp_billing.subscriptions_table.customer"), align: :left }, *base]
      end

      def empty_key = filtered? ? "comp_billing.history.no_matches" : "comp_billing.subscriptions_table.empty"

      def date_label(value)
        value.present? ? I18n.l(value.to_date, format: :long) : I18n.t("common.labels.em_dash")
      end

      def customer_name(sub)
        sub.customer.name if sub.respond_to?(:customer) && sub.customer.respond_to?(:name)
      end

      def pending_change?(sub)
        pending_changes[sub.id] || pending_changes[sub.id.to_s]
      end

      def cancelling?(sub)
        !sub.status.in?(%w[cancelled expired]) && sub.cancel_at_period_end?
      end

      def status_variant(status)
        STATUS_BADGE_MAP.fetch(status.to_s, :default)
      end

      def status_label(status)
        I18n.t("comp_billing.subscription_summary.statuses.#{status}")
      end

      def interval_label(interval)
        I18n.t("comp_billing.plan_form.intervals.#{interval}")
      end

      def format_amount(amount_cents, currency = "CNY")
        billing_amount(amount_cents, currency)
      end

      def subscription_path(sub)
        helpers.admin_maintenance_platform_billing_subscription_path(customer_id, sub)
      end

      def cancel_path(sub)
        helpers.admin_maintenance_platform_billing_subscription_cancellation_path(customer_id, sub)
      end

      def filter_keys = %i[q status tenant_id]

      def history_path(**query)
        helpers.admin_maintenance_platform_billing_subscriptions_path(customer_id, **query)
      end
    end
  end
end
