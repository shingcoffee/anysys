# frozen_string_literal: true

class CreateCustomerHostnames < ActiveRecord::Migration[8.1]
  def change
    create_table :customer_hostnames do |t|
      t.references :customer, type: :bigint, null: false, foreign_key: { on_delete: :cascade }
      t.string :hostname, null: false, limit: 253
      t.timestamps
    end

    add_index :customer_hostnames, :hostname, unique: true
  end
end
