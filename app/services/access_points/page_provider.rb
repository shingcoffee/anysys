# frozen_string_literal: true

module AccessPoints
  class PageProvider < Provider
    def group_key   = "pages.instances"
    def group_label = I18n.t("admin_settings.access_points.groups.pages_instances")

    def call(customer_id:)
      Page.where(customer_id: customer_id).map { |p| descriptor_for(p) }
    end

    def search(customer_id:, query:)
      relation = Page.where(customer_id: customer_id)
      relation = relation.where("LOWER(name) LIKE ?", "%#{query.downcase}%") if query.present?
      relation.limit(50).map { |p| descriptor_for(p) }
    end

    private

    def descriptor_for(page)
      Descriptor.new(
        subject_type: "Page",
        subject_key:  nil,
        subject_id:   page.id,
        actions:      [:read, :update, :destroy],
        group_key:    "pages.instances",
        label:        page.name.to_s,
        description:  nil
      )
    end
  end
end
