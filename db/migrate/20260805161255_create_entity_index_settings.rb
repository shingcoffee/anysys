# frozen_string_literal: true

class CreateEntityIndexSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :entity_index_settings do |t|
      t.references :customer, null: false, foreign_key: true, type: :bigint
      t.references :entity,   null: false, foreign_key: true, type: :bigint
      t.text :config, null: false, default: "{}"
      t.timestamps
    end

    add_index :entity_index_settings, %i[customer_id entity_id], unique: true,
              name: "idx_entity_index_settings_on_customer_and_entity"
  end
end
