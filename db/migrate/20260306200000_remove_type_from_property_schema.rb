# frozen_string_literal: true

class RemoveTypeFromPropertySchema < ActiveRecord::Migration[8.1]
  def up
    Entity.find_each do |entity|
      schema = entity.property_schema_json
      next if schema.blank?

      updated = schema.map do |attr|
        attr.except('type', 'entity_id')
      end

      entity.update_column(:property_schema, updated.to_json)
    end
  end

  def down
    # Cannot restore removed type data
  end
end
