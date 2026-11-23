# frozen_string_literal: true

class AddExtendableAttributesToFeatureModules < ActiveRecord::Migration[8.1]
  def change
    add_column :feature_modules, :extendable_attributes, :text
  end
end
