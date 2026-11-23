class AddRoleToCustomers < ActiveRecord::Migration[8.1]
  def change
    add_column :customers, :role, :integer, default: 0, null: false
  end
end
