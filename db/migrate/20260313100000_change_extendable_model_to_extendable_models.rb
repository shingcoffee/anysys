# frozen_string_literal: true

class ChangeExtendableModelToExtendableModels < ActiveRecord::Migration[8.0]
  def up
    add_column :entities, :extendable_models, :text

    # Migrate existing data: "User" → '["User"]', nil → '[]'
    Entity.unscoped.find_each do |entity|
      old_value = entity.read_attribute(:extendable_model)
      new_value = old_value.present? ? [old_value].to_json : "[]"
      entity.update_column(:extendable_models, new_value)
    end

    remove_index :entities, name: "index_entities_on_customer_id_and_extendable_model", if_exists: true
    remove_index :entities, name: "index_entities_on_extendable_model", if_exists: true
    remove_column :entities, :extendable_model
  end

  def down
    add_column :entities, :extendable_model, :string

    Entity.unscoped.find_each do |entity|
      raw = entity.read_attribute(:extendable_models)
      models = raw.present? ? JSON.parse(raw) : []
      entity.update_column(:extendable_model, models.first)
    end

    remove_column :entities, :extendable_models

    add_index :entities, :extendable_model, name: "index_entities_on_extendable_model"
    add_index :entities, [:customer_id, :extendable_model], name: "index_entities_on_customer_id_and_extendable_model"
  end
end
