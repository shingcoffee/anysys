# frozen_string_literal: true

module Billing
  module Admin
    # Shared sub-navigation tab strip for the platform billing config screens.
    #
    # Renders a horizontal tab bar (with overflow-x scroll on mobile) linking to
    # all platform billing areas: Plans, Countable Items, Coupons,
    # Subscriptions, Invoices, and Settings. The active tab is derived
    # by matching the supplied `current_path` against each tab's path prefix.
    #
    # Usage:
    #   render Billing::Admin::PlatformBillingNavComponent.new(
    #     customer_id:  current_customer_id,
    #     current_path: request.path
    #   )
    class PlatformBillingNavComponent < ApplicationComponent
      # Labels are resolved at render time via I18n (see #tabs) — "comp_billing.nav.<key>".
      TABS = [
        { key: :plans,           path_helper: :admin_maintenance_platform_billing_plans_path,           segment: "plans" },
        { key: :countable_items, path_helper: :admin_maintenance_platform_billing_countable_items_path, segment: "countable_items" },
        { key: :coupons,         path_helper: :admin_maintenance_platform_billing_coupons_path,         segment: "coupons" },
        { key: :subscriptions,   path_helper: :admin_maintenance_platform_billing_subscriptions_path,   segment: "subscriptions" },
        { key: :invoices,        path_helper: :admin_maintenance_platform_billing_invoices_path,        segment: "invoices" },
        { key: :settings,        path_helper: :admin_maintenance_platform_billing_settings_path,        segment: "settings" }
      ].freeze

      def initialize(customer_id:, current_path:)
        @customer_id  = customer_id.to_s
        @current_path = current_path.to_s
      end

      attr_reader :customer_id, :current_path

      def tabs
        TABS.map do |tab|
          path = helpers.public_send(tab[:path_helper], customer_id)
          {
            id:     tab[:key],
            label:  I18n.t("comp_billing.nav.#{tab[:key]}"),
            path:   path,
            active: active_tab?(tab[:segment])
          }
        end
      end

      private

      # A tab is active when its segment appears as a path component immediately
      # after "/billing/" in the current URL.
      def active_tab?(segment)
        current_path.include?("/billing/#{segment}")
      end
    end
  end
end
