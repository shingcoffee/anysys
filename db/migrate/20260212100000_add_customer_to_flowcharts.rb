# frozen_string_literal: true

class AddCustomerToFlowcharts < ActiveRecord::Migration[8.1]
  def change
    add_column :flowcharts, :customer_id, :integer

    add_index :flowcharts, :customer_id
    add_index :flowcharts, [:customer_id, :uuid], unique: true
  end
end
