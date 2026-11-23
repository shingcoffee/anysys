# frozen_string_literal: true

class AddTriggerLabelToFlowcharts < ActiveRecord::Migration[8.1]
  def change
    add_column :flowcharts, :trigger_label, :text
  end
end
