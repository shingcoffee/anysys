# frozen_string_literal: true

module Admin
  module Maintenance
    # One module on the Maintenance / Modules catalog: identity, status, the
    # enable/disable switch, a shortcut into the module and — for the platform
    # owner — the owner-managed limits form.
    class ModuleCatalogCardComponent < ApplicationComponent
      include Admin::Maintenance::Platform::ModuleSettingsHelper

      LOCK_ICON_PATH = "M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"

      attr_reader :customer_id, :feature_module, :open_link, :owner_assignment

      def initialize(customer_id:, feature_module:, enabled:, open_link: nil, owner_assignment: nil)
        @customer_id = customer_id
        @feature_module = feature_module
        @enabled = enabled
        @open_link = open_link
        @owner_assignment = owner_assignment
      end

      def enabled? = @enabled

      def required? = feature_module.required?

      def locked? = required? && enabled?

      def name = feature_module.display_name

      def description = ::Dashboard::ModuleCards.blurb_for(feature_module)

      def icon_path = module_header_icon_path(feature_module.key)

      def icon_classes = module_color_classes(feature_module.key)

      def search_text = [name, feature_module.key.humanize, description].join(" ")

      def status_badge
        if required?
          { variant: :warning, label: t("common.labels.required") }
        elsif enabled?
          { variant: :success, label: t("common.status.enabled") }
        else
          { variant: :default, label: t("common.status.disabled") }
        end
      end

      def show_open_link? = enabled? && open_link.present?

      def show_footer? = locked? || show_open_link?

      def card_classes
        state = enabled? ? "" : " bg-canvas"
        "card flex h-full flex-col gap-4 p-5 transition-shadow hover:shadow-md#{state}"
      end

      def toggle
        Admin::Maintenance::Platform::ModuleToggleComponent.new(
          url: helpers.admin_maintenance_module_enablement_path(customer_id, feature_module),
          field: nil,
          on: enabled?,
          http_method: enabled? ? :delete : :post,
          disabled: locked?,
          confirm: (t("maint_core.modules.index.disable_confirm", name: name) if enabled?),
          show_label: false,
          aria_label: t("maint_core.modules.index.toggle_aria", name: name)
        )
      end
    end
  end
end
