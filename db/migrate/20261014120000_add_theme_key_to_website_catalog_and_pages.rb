# frozen_string_literal: true

class AddThemeKeyToWebsiteCatalogAndPages < ActiveRecord::Migration[8.1]
  def change
    add_column :website_skeletons, :theme_key, :string
    add_column :website_layouts, :theme_key, :string
    add_column :website_pages, :theme_key, :string
  end
end
