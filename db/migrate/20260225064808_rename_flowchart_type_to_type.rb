# frozen_string_literal: true

# Migration to rename flowchart_type to type
#
# Changes:
#   1. Renames column flowchart_type to type
#   2. Updates enum mapping (in model):
#      - 0: custom → customer_specific
#      - 1: blueprint → shared
#   3. Index is automatically renamed by SQLite during column rename
#
class RenameFlowchartTypeToType < ActiveRecord::Migration[8.1]
  def change
    # Rename column (index will be automatically renamed in SQLite)
    rename_column :flowcharts, :flowchart_type, :type
  end
end
