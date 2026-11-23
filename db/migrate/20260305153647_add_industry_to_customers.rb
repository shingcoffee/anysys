class AddIndustryToCustomers < ActiveRecord::Migration[8.1]
  def change
    add_column :customers, :industry, :integer
    add_index :customers, :industry
  end
end
