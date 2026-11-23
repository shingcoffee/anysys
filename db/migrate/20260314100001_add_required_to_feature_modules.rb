# frozen_string_literal: true

class AddRequiredToFeatureModules < ActiveRecord::Migration[8.1]
  def change
    add_column :feature_modules, :required, :boolean, default: false, null: false
  end
end
