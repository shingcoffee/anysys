# frozen_string_literal: true

module AccessPoints
  class PageClassProvider < Provider
    def group_key   = "pages"
    def group_label = I18n.t("admin_settings.access_points.groups.pages")

    def call(customer_id:)
      [
        Descriptor.new(
          subject_type: "PageClass",
          subject_key:  "Page",
          subject_id:   nil,
          actions:      [:read, :create, :update, :destroy],
          group_key:    "pages",
          label:        I18n.t("admin_settings.access_points.pages_all"),
          description:  I18n.t("admin_settings.access_points.pages_all_description")
        )
      ]
    end
  end
end
