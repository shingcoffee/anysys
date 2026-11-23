# frozen_string_literal: true

# Per-module "handoff target" flag. When false (the fail-safe default), no
# resource may hand off control to the module and it is hidden from the
# page-builder handoff picker. Togglable only by the platform owner in
# Maintenance / Platform / Module Settings.
class AddHandoffEnabledToFeatureModules < ActiveRecord::Migration[8.1]
  def change
    add_column :feature_modules, :handoff_enabled, :boolean, default: false, null: false
  end
end
