# frozen_string_literal: true

class RemoveExtendableFromBaseModelConfigurations < ActiveRecord::Migration[8.1]
  def change
    remove_column :base_model_configurations, :extendable, :boolean, default: false, null: false
  end
end
