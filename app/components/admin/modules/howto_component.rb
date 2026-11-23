# frozen_string_literal: true

module Admin
  module Modules
    class HowtoComponent < ApplicationComponent
      # Select links already contributed by each module, so guide actions follow
      # the same tenant-scoped destinations as the navigation and settings menu.
      STEP_DESTINATIONS = {
        "authentication" => [
          [:settings, "sign_up"],
          [:settings, "forget_password"],
          [:features, "users"],
          [:features, "events"]
        ],
        "email" => [
          [:settings, "daily_cap"],
          [:features, "templates"],
          [:features, "lists"],
          [:features, "send_activities"]
        ],
        "payment" => [
          [:settings, "merchant_accounts"],
          [:features, "transactions"],
          [:features, "reconciliations"]
        ],
        "sms" => [
          [:settings, "daily_cap"],
          [:features, "campaigns"],
          [:features, "contacts"],
          [:features, "messages"]
        ],
        "captcha" => [
          [:settings, "captcha"],
          [:settings, "captcha"],
          [:pages, nil],
          [:pages, nil]
        ],
        "ai_assistant" => [
          [:settings, "ai_assistant"],
          [:features, "assistant"],
          [:features, "assistant"]
        ],
        "website" => [
          [:settings, "website"],
          [:features, "modules/website"],
          [:settings, "website"],
          [:features, "modules/website"]
        ]
      }.freeze

      attr_reader :module_card, :settings_links, :customer_id

      def initialize(module_card:, customer_id:, settings_links: [])
        @module_card = module_card
        @customer_id = customer_id
        @settings_links = settings_links
      end

      def steps
        guide_key = "admin_modules.index.howto.steps.#{module_card.key}"
        fallback = links.any? ? "with_links" : "without_links"
        t(I18n.exists?(guide_key) ? guide_key : "admin_modules.index.howto.steps.#{fallback}")
      end

      def links
        Array(module_card.links).uniq(&:href)
      end

      def step_link(index)
        destinations = STEP_DESTINATIONS[module_card.key]
        return fallback_link(index) unless destinations

        source, suffix = destinations.fetch(index)
        return ::Dashboard::Link.new(label: t("chrome.menu_bar.items.pages"), href: helpers.admin_domains_path(customer_id)) if source == :pages

        collection = source == :settings ? settings_links : links
        collection.find { |link| link.href.to_s.end_with?("/#{suffix}") }
      end

      private

      def fallback_link(index)
        return links.first if links.any?
        return settings_links.first if index.zero? && settings_links.any?

        if index.zero?
          ::Dashboard::Link.new(label: t("chrome.menu_bar.items.settings"), href: helpers.admin_setting_path(customer_id))
        else
          ::Dashboard::Link.new(label: t("admin_modules.nav.modules"), href: helpers.admin_modules_path(customer_id))
        end
      end
    end
  end
end
