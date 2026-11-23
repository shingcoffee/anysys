# frozen_string_literal: true

module Admin
  module Settings
    class PageComponent < ApplicationComponent
      include Admin::Maintenance::Platform::ModuleSettingsHelper

      MODULE_PATHS = {
        "authentication" => %r{/modules/authentication},
        "email" => %r{/modules/emails},
        "sms" => %r{/modules/sms},
        "payment" => %r{/modules/payments},
        "captcha" => %r{/modules/captcha},
        "website" => %r{/modules/website},
        "ai_assistant" => %r{/modules/ai_assistant}
      }.freeze
      attr_reader :customer_id, :title, :description, :breadcrumbs, :actions, :badges, :width, :printable, :icon_path, :icon_class

      def initialize(customer_id:, title:, description: nil, breadcrumbs: [], actions: [], badges: [], width: :full, printable: false, icon_path: nil, icon_class: nil)
        @customer_id = customer_id
        @title = title
        @description = description
        @breadcrumbs = Array(breadcrumbs)
        @actions = Array(actions)
        @badges = Array(badges)
        @width = width
        @printable = printable
        @icon_path = icon_path
        @icon_class = icon_class
      end

      def before_render
        # Rails renders the page before its layout, including before the opening
        # html/body tags. The layout can therefore release every clipping ancestor.
        helpers.content_for(:settings_printable, "true", flush: true) if printable
      end

      def page_actions
        return actions unless printable

        actions.map { |action| action.merge(class: [action[:class], "print:hidden"].compact.join(" ")) }
      end

      def page_breadcrumbs
        crumbs = [{ label: I18n.t("chrome.menu_bar.items.settings"), path: "/#{customer_id}/admin/settings" }, *breadcrumbs]
        last = crumbs.last
        crumbs << { label: title } if title.present? && last[:label] != title
        crumbs
      end

      def header_icon_path
        icon_path.presence || inferred_header.first
      end

      def header_icon_class
        return icon_class if icon_path.present?

        icon_class.presence || inferred_header.last
      end

      private

      def inferred_header
        @inferred_header ||= begin
          path = helpers.request.path.to_s
          if (key = MODULE_PATHS.find { |_name, pattern| path.match?(pattern) }&.first)
            [module_header_icon_path(key), module_color_classes(key)]
          elsif path.include?("/settings/member")
            [SettingsContributor::ICONS[:member], "bg-info-subtle text-info"]
          elsif path.include?("/settings/billing")
            [SettingsContributor::GROUP_ICONS[:billing], "bg-accent-subtle text-accent-text"]
          else
            [SettingsContributor::ICONS[:overview], "bg-surface-active text-text-secondary"]
          end
        end
      end
    end
  end
end
