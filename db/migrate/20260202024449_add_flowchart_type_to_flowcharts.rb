class AddFlowchartTypeToFlowcharts < ActiveRecord::Migration[8.1]
  def change
    add_column :flowcharts, :flowchart_type, :integer, default: 0, null: false
    add_index :flowcharts, :flowchart_type
  end
end
