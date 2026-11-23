# frozen_string_literal: true

class AddExtendableModelsToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :extendable_models, :text
  end
end
