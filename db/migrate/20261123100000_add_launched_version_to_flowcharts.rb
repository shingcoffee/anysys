# frozen_string_literal: true

class AddLaunchedVersionToFlowcharts < ActiveRecord::Migration[8.1]
  def up
    add_reference :flowcharts, :launched_version, foreign_key: { to_table: :flowchart_versions }
    execute <<~SQL.squish
      UPDATE flowcharts SET launched_version_id = current_version_id WHERE status = 0
    SQL
  end

  def down
    remove_reference :flowcharts, :launched_version, foreign_key: { to_table: :flowchart_versions }
  end
end
