class AddStatusToFlowcharts < ActiveRecord::Migration[8.1]
  def change
    add_column :flowcharts, :status, :integer, default: 0, null: false
    add_index :flowcharts, :status
  end
end
