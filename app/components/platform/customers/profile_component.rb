# frozen_string_literal: true

module Platform
  module Customers
    # Read-only organization profile for a platform customer record.
    class ProfileComponent < ApplicationComponent
      HEADER_ICON = "M3.75 21h16.5M4.5 3h15M5.25 3v18m13.5-18v18M9 6.75h1.5m-1.5 3h1.5m-1.5 3h1.5m3-6H15m-1.5 3H15m-1.5 3H15M9 21v-3.375c0-.621.504-1.125 1.125-1.125h3.75c.621 0 1.125.504 1.125 1.125V21"

      PLAN_BADGE_VARIANTS = {
        "basic" => :default,
        "standard" => :info,
        "premium" => :purple,
        "enterprise" => :warning
      }.freeze

      def initialize(customer:)
        @customer = customer
      end

      attr_reader :customer

      def active?
        customer.respond_to?(:active?) && customer.active?
      end

      def in_trash?
        customer.respond_to?(:deleted?) && customer.deleted?
      end

      def header_badges
        [
          { label: status_label, variant: active? ? :success : :default },
          { label: plan_label, variant: plan_badge_variant }
        ]
      end

      def status_label
        return I18n.t("maint_platform.customers.show.unknown") if customer.status.blank?

        I18n.t("common.status.#{customer.status}")
      end

      def plan_label
        I18n.t("chrome.customer_form.tiers.#{customer.tier}")
      end

      def plan_badge_variant
        PLAN_BADGE_VARIANTS.fetch(customer.tier.to_s, :default)
      end

      def locale_label
        code = customer.locale.presence
        return I18n.t("maint_platform.customers.show.language_browser") if code.blank?

        LocaleSwitcherComponent::DISPLAY_NAMES[code.to_sym] ||
          LocaleSwitcherComponent::DISPLAY_NAMES[code] ||
          code
      end

      def phone_href
        number = customer.phone.to_s.gsub(/[^\d+]/, "")
        return if number.gsub(/\D/, "").length < 3

        "tel:#{number}"
      end

      def blank_value
        tag.span(t("maint_platform.customers.show.not_set"), class: "text-text-muted")
      end

      def formatted_time(value)
        return blank_value if value.blank?

        tag.time(helpers.format_datetime(value), datetime: value.iso8601)
      end
    end
  end
end
