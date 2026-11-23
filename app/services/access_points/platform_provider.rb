# frozen_string_literal: true

module AccessPoints
  class PlatformProvider < Provider
    PLATFORM_FEATURES = [
      { key: "customers",          actions: [:read, :create, :update, :destroy] },
      { key: "module_settings",    actions: [:read, :update] },
      { key: "industry_templates", actions: [:read, :update] },
      { key: "code_generators",    actions: [:read, :create, :update, :destroy] }
    ].freeze

    def group_key   = "platform"
    def group_label = I18n.t("admin_settings.access_points.groups.platform")

    def applicable?(customer_id:)
      customer_id.to_i == Authentication::User::PLATFORM_CUSTOMER_ID
    end

    def call(customer_id:)
      PLATFORM_FEATURES.map do |f|
        Descriptor.new(
          subject_type: "Platform",
          subject_key:  f[:key],
          subject_id:   nil,
          actions:      f[:actions],
          group_key:    "platform",
          label:        I18n.t("admin_settings.access_points.platform.#{f[:key]}"),
          description:  nil
        )
      end
    end
  end
end
