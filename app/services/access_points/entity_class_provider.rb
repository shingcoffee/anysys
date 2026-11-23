# frozen_string_literal: true

module AccessPoints
  class EntityClassProvider < Provider
    def group_key   = "entities"
    def group_label = I18n.t("admin_settings.access_points.groups.entities")

    def call(customer_id:)
      [
        Descriptor.new(
          subject_type: "EntityClass",
          subject_key:  "Entity",
          subject_id:   nil,
          actions:      [:read, :create, :update, :destroy],
          group_key:    "entities",
          label:        I18n.t("admin_settings.access_points.entities_all"),
          description:  I18n.t("admin_settings.access_points.entities_all_description")
        )
      ]
    end
  end
end
