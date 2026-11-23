# frozen_string_literal: true

class AddCustomerToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :customer_id, :integer

    add_index :entities, :customer_id
    add_index :entities, [:customer_id, :name], unique: true
  end
end
