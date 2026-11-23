# frozen_string_literal: true

module ActivitySteps
  # Trailblazer step that persists the primary model and all bridge entries
  # within a single database transaction.
  #
  # After the primary model is saved, each bridge entry's EntityReference to the
  # primary entity is auto-populated with the primary model's ID. The bridge's
  # EntityReference to the associated entity is already set from the form
  # submission params.
  #
  # Requires ctx[:contract] (for primary) and ctx[:associated_entries] to be set.
  # Falls back to ctx[:model].save! if no contract is present.
  #
  # @example Usage in a Trailblazer Activity
  #   step ActivitySteps::SaveAll
  #
  module SaveAll
    module_function

    def call(ctx, **)
      return false if BaseModelInput.rejected?(ctx)
      ActiveRecord::Base.transaction(requires_new: true) do
        save_primary(ctx)
        save_bridge_entries(ctx)
      end

      true
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
      ctx[:error] = e.message
      false
    end

    def save_primary(ctx)
      if ctx[:contract]
        unless ctx[:contract].save
          raise ActiveRecord::RecordNotSaved, I18n.t("common.errors.dynamic.activity_execution_failed")
        end
      elsif ctx[:model]
        ctx[:model].save!
      end
    end

    def save_bridge_entries(ctx)
      (ctx[:associated_entries] || []).each do |assoc|
        bridge_entry = assoc[:bridge_entry]
        next unless bridge_entry

        link_source_entity(ctx, bridge_entry)
        bridge_entry.save!
      end
    end

    # Sets the EntityReference field on the bridge entry that points to the
    # primary entity. The associated-entity reference is already set from the
    # form params (the user selected it via a dropdown).
    def link_source_entity(ctx, bridge_entry)
      return unless ctx[:model]&.id

      bridge_entity = bridge_entry.entity
      primary_entity = ctx[:bound_entity] || ctx[:entity]
      return unless primary_entity

      refs = (bridge_entity.property_schema_json || []).select { |f| f["type"] == Entity::ENTITY_REFERENCE_TYPE }

      refs.each do |ref|
        if ref["entity_id"].to_s == primary_entity.id.to_s
          bridge_entry[ref["name_slug"]] = ctx[:model].id
        end
      end
    end
  end
end
