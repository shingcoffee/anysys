# frozen_string_literal: true

class CreatePages < ActiveRecord::Migration[8.1]
  def change
    create_table :pages do |t|
      t.string :name, null: false
      t.string :name_slug
      t.text :description
      t.text :content
      t.text :configuration
      t.integer :status, null: false, default: 0
      t.integer :customer_id, null: false

      t.timestamps
    end

    add_index :pages, :customer_id
    add_index :pages, [:customer_id, :name], unique: true
    add_index :pages, :status
    add_index :pages, :created_at

    add_foreign_key :pages, :customers
  end
end
