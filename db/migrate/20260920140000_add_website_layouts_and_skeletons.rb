# frozen_string_literal: true

class AddWebsiteLayoutsAndSkeletons < ActiveRecord::Migration[8.1]
  def change
    create_table :website_layouts do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.string :description
      t.integer :position, null: false, default: 0
      t.boolean :archived, null: false, default: false
      t.json :sections, null: false, default: []
      t.timestamps
    end
    add_index :website_layouts, :key, unique: true

    create_table :website_skeletons do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.string :description
      t.integer :position, null: false, default: 0
      t.boolean :archived, null: false, default: false
      t.json :pages, null: false, default: []
      t.timestamps
    end
    add_index :website_skeletons, :key, unique: true

    add_column :website_pages, :layout_key, :string
    add_index :website_pages, :layout_key

    add_column :websites, :default_layout_key, :string
  end
end
