# frozen_string_literal: true

module Billing
  module Admin
    # Settings page frame shared by the tenant billing surfaces (Area b —
    # /:cid/admin/settings/billing/*): the page header plus Plan / Payment
    # methods / Invoices section tabs, so customers can move between billing
    # tasks without opening the settings sidebar (hidden on small screens).
    class CustomerBillingPageComponent < ApplicationComponent
      TABS = {
        plan:            { label_key: "settings_navigation.items.plan_subscription",
                           route: :admin_settings_billing_subscription_path },
        payment_methods: { label_key: "settings_navigation.items.billing_payment_methods",
                           route: :admin_settings_billing_payment_methods_path },
        invoices:        { label_key: "settings_navigation.items.invoices",
                           route: :admin_settings_billing_invoices_path }
      }.freeze

      attr_reader :customer_id, :active, :description, :actions

      def initialize(customer_id:, active:, title: nil, description: nil, breadcrumbs: nil, actions: [], tab_counts: {})
        @customer_id = customer_id
        @active = TABS.key?(active.to_sym) ? active.to_sym : raise(ArgumentError, "unknown billing tab: #{active}")
        @title = title
        @description = description
        @breadcrumbs = breadcrumbs
        @actions = Array(actions)
        @tab_counts = tab_counts || {}
      end

      def title = @title.presence || t(TABS.fetch(active).fetch(:label_key))

      def page_breadcrumbs = @breadcrumbs.presence || [{ label: title }]

      def tab_count(key)
        value = @tab_counts[key] || @tab_counts[key.to_s]
        count = value.to_i
        count.positive? ? count : nil
      end

      def tabs
        TABS.map do |key, tab|
          { key: key, label: t(tab.fetch(:label_key)), current: key == active,
            href: helpers.public_send(tab.fetch(:route), customer_id), count: tab_count(key) }
        end
      end

      def tab_class(current)
        base = "relative inline-flex h-11 items-center gap-2 whitespace-nowrap text-body-sm font-medium transition-colors " \
               "focus-visible:outline-accent after:absolute after:inset-x-0 after:-bottom-px after:h-0.5 after:rounded-full"
        state = current ? "text-text-primary after:bg-accent" : "text-text-secondary hover:text-text-primary hover:after:bg-border-strong"
        "#{base} #{state}"
      end
    end
  end
end
