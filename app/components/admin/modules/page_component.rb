# frozen_string_literal: true

module Admin
  module Modules
    # Shared header chrome for the Modules hub and nested entry pages.
    # Fills AdminPageComponent's identity tile from the feature-module key
    # unless the page passes its own `icon_path` / `icon_class` (a record page).
    class PageComponent < ApplicationComponent
      include Admin::Maintenance::Platform::ModuleSettingsHelper

      def initialize(module_key: nil, breadcrumbs:, title: nil, description: nil,
                     actions: [], width: nil, badges: [], wrap_title: false, wrap_actions: false,
                     icon_path: nil, icon_class: nil)
        @module_key = module_key.to_s.presence
        @icon_path = icon_path
        @icon_class = icon_class
        @breadcrumbs = breadcrumbs
        @title = title
        @description = description
        @actions = Array(actions)
        @width = width
        @badges = Array(badges)
        @wrap_title = wrap_title
        @wrap_actions = wrap_actions
      end

      def page_kwargs
        {
          breadcrumbs: hub_linked_breadcrumbs,
          title: @title,
          description: @description,
          actions: @actions,
          width: @width,
          badges: @badges,
          wrap_title: @wrap_title,
          wrap_actions: @wrap_actions,
          icon_path: icon_path,
          icon_class: icon_class
        }
      end

      private

      # Nested module pages list "Modules" as the first crumb with no path.
      # Point that crumb at the hub so customers can walk back without the sidebar.
      def hub_linked_breadcrumbs
        crumbs = Array(@breadcrumbs).map { |crumb| crumb.respond_to?(:dup) ? crumb.dup : crumb }
        return crumbs if crumbs.empty?

        hub_label = t("admin_modules.nav.modules")
        first = crumbs.first
        first_label = first[:label] || first["label"]

        if first_label == hub_label
          first[:path] ||= hub_path if crumbs.size > 1
          return crumbs
        end

        [{ label: hub_label, path: hub_path }, *crumbs]
      end

      def hub_path
        helpers.admin_modules_path(hub_customer_id)
      end

      def hub_customer_id
        if helpers.respond_to?(:current_customer_id) && helpers.current_customer_id.present?
          helpers.current_customer_id
        else
          helpers.params[:customer_id]
        end
      end

      def icon_path
        return @icon_path if @icon_path.present?
        return Admin::Maintenance::Platform::ModuleSettingsHelper::DEFAULT_MODULE_ICON_PATH if @module_key.blank?

        module_header_icon_path(@module_key)
      end

      def icon_class
        return @icon_class if @icon_path.present? && @icon_class.present?
        return "bg-surface-active text-text-secondary" if @module_key.blank?

        module_color_classes(@module_key)
      end
    end
  end
end
