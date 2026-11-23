# frozen_string_literal: true

class CreateBaseModelConfigurations < ActiveRecord::Migration[8.0]
  def change
    create_table :base_model_configurations do |t|
      t.string :base_class_name, null: false
      t.boolean :extendable, default: false, null: false
      t.text :field_configurations

      t.timestamps
    end

    add_index :base_model_configurations, :base_class_name, unique: true
  end
end
