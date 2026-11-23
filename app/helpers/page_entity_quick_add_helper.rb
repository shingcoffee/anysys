# frozen_string_literal: true

# Generated page ERB calls this for dropdowns whose options are entries of
# another entity. On admin render surfaces (PageRendering quick_add_depth) it
# returns the "+ Add New" option config, opening that dialog level, consumed by
# FormFields::SelectFieldComponent; everywhere else (public/member pages,
# previews) it returns nil.
module PageEntityQuickAddHelper
  def page_entity_quick_add(entity_id, label_field)
    depth = page_quick_add_depth if respond_to?(:page_quick_add_depth)
    return unless depth
    return unless current_user&.admin_or_owner?

    entity = quick_add_entity(entity_id)
    return unless entity

    Admin::Entities::QuickAddDialogComponent.opener(entity: entity, customer_id: current_customer_id,
                                                    label_field: label_field, depth: depth)
  end

  private

  def quick_add_entity(entity_id)
    @quick_add_entities ||= {}
    return @quick_add_entities[entity_id] if @quick_add_entities.key?(entity_id)

    @quick_add_entities[entity_id] =
      Entity.where(customer_id: current_customer_id).or(Entity.shared).active.non_bridge.find_by(id: entity_id)
  end
end
