# frozen_string_literal: true

class CreateRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :roles do |t|
      t.references :customer, null: false, foreign_key: true, type: :bigint
      t.string  :key,          null: false
      t.string  :name,         null: false
      t.text    :description
      t.boolean :system,         null: false, default: false
      t.boolean :locked_grants,  null: false, default: false
      t.timestamps
    end

    add_index :roles, %i[customer_id key], unique: true
  end
end
