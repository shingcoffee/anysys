# frozen_string_literal: true

class AddTriggerToFlowcharts < ActiveRecord::Migration[8.1]
  def change
    add_column :flowcharts, :trigger_timing, :string
    add_column :flowcharts, :trigger_condition, :text
    add_column :flowcharts, :trigger_position, :integer, null: false, default: 0
    add_index :flowcharts, %i[customer_id entity_id trigger_timing],
              where: "trigger_timing IS NOT NULL", name: "idx_flowcharts_automations"
  end
end
