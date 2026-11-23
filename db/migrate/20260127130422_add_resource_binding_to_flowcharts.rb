class AddResourceBindingToFlowcharts < ActiveRecord::Migration[8.1]
  def change
    add_column :flowcharts, :resource_id, :integer
    add_index :flowcharts, :resource_id
  end
end
