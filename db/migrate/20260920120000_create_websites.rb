# frozen_string_literal: true

class CreateWebsites < ActiveRecord::Migration[8.1]
  def change
    create_table :websites do |t|
      t.integer :customer_id, null: false
      t.string :name, null: false
      t.string :tagline
      t.boolean :published, null: false, default: false
      t.string :skeleton_key, null: false, default: "presence"
      t.json :theme, null: false, default: {}
      t.json :seo, null: false, default: {}
      t.json :footer, null: false, default: {}
      t.timestamps
    end
    add_index :websites, :customer_id, unique: true

    create_table :website_pages do |t|
      t.integer :customer_id, null: false
      t.integer :website_id, null: false
      t.string :title, null: false
      t.string :slug, null: false, default: ""
      t.integer :position, null: false, default: 0
      t.boolean :published, null: false, default: false
      t.boolean :home, null: false, default: false
      t.boolean :nav_visible, null: false, default: true
      t.json :sections, null: false, default: []
      t.timestamps
    end
    add_index :website_pages, :customer_id
    add_index :website_pages, :website_id
    add_index :website_pages, [ :website_id, :slug ], unique: true
    add_index :website_pages, :website_id, unique: true, where: "home = 1", name: "index_website_pages_one_home"
  end
end
