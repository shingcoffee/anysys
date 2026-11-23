# frozen_string_literal: true

class AddBaseModelSettingsToFeatureModules < ActiveRecord::Migration[8.1]
  def change
    add_column :feature_modules, :base_model_settings, :text
  end
end
