# frozen_string_literal: true

class AddExtendableModelsToFeatureModules < ActiveRecord::Migration[8.1]
  def change
    add_column :feature_modules, :extendable_models, :text
  end
end
