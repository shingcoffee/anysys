class ChangeFlowchartStatusDefaultToDraft < ActiveRecord::Migration[8.1]
  def change
    change_column_default :flowcharts, :status, from: 0, to: 2
  end
end
