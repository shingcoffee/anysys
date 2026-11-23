# frozen_string_literal: true

class AddCustomerToEntityEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :entity_entries, :customer_id, :integer

    add_index :entity_entries, :customer_id
    add_index :entity_entries, [:customer_id, :entity_id]
  end
end
