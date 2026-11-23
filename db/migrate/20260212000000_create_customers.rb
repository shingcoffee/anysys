# frozen_string_literal: true

class CreateCustomers < ActiveRecord::Migration[8.1]
  def change
    create_table :customers, id: false do |t|
      t.integer :id, null: false, primary_key: true
      t.string :name, null: false
      t.string :alias
      t.text :address
      t.string :contact
      t.string :phone
      t.integer :tier, null: false, default: 0
      t.integer :status, null: false, default: 0

      t.timestamps
    end

    add_index :customers, :name
    add_index :customers, :tier
    add_index :customers, :status
    add_index :customers, :created_at
  end
end
