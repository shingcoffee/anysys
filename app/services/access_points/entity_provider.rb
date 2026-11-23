# frozen_string_literal: true

module AccessPoints
  class EntityProvider < Provider
    def group_key   = "entities.instances"
    def group_label = I18n.t("admin_settings.access_points.groups.entities_instances")

    def call(customer_id:)
      Entity.where(customer_id: customer_id).map { |e| descriptor_for(e) }
    end

    def search(customer_id:, query:)
      relation = Entity.where(customer_id: customer_id)
      relation = relation.where("LOWER(name) LIKE ?", "%#{query.downcase}%") if query.present?
      relation.limit(50).map { |e| descriptor_for(e) }
    end

    private

    def descriptor_for(entity)
      Descriptor.new(
        subject_type: "Entity",
        subject_key:  nil,
        subject_id:   entity.id,
        actions:      [:read, :update, :destroy],
        group_key:    "entities.instances",
        label:        entity.display_label.to_s,
        description:  nil
      )
    end
  end
end
