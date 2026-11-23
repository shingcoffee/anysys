# frozen_string_literal: true

# A page names the flowchart that processes its submissions; flowcharts no
# longer bind an entity or carry triggers.
class BindPagesToFlowcharts < ActiveRecord::Migration[8.1]
  def up
    add_reference :pages, :flowchart, type: :integer, index: true, foreign_key: { on_delete: :nullify }

    remove_index :flowcharts, name: "idx_flowcharts_automations"
    remove_index :flowcharts, name: "index_flowcharts_on_entity_id"
    remove_column :flowcharts, :entity_id, :integer
    remove_column :flowcharts, :crud_type, :string
    remove_column :flowcharts, :trigger_timing, :string
    remove_column :flowcharts, :trigger_condition, :text
    remove_column :flowcharts, :trigger_position, :integer, default: 0, null: false
    remove_column :flowcharts, :trigger_label, :text
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
