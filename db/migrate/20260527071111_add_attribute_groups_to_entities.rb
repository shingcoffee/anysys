# frozen_string_literal: true

class AddAttributeGroupsToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :attribute_groups, :jsonb, default: [], null: false
  end
end
