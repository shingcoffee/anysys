# frozen_string_literal: true

class CreateEntityEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :entity_entries do |t|
      t.references :entity, null: false, foreign_key: true
      t.text :data

      t.timestamps
    end

    add_index :entity_entries, :created_at
  end
end
