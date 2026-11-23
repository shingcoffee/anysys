# frozen_string_literal: true

class AddBasedOnVersionToFlowchartVersions < ActiveRecord::Migration[8.1]
  # Use explicit up/down: auto-reversal of a self-referential `add_foreign_key`
  # can't disambiguate the FK by to_table alone on rollback, so remove it by
  # :column instead.
  def up
    add_column :flowchart_versions, :based_on_version_id, :bigint
    add_index  :flowchart_versions, :based_on_version_id
    add_foreign_key :flowchart_versions, :flowchart_versions, column: :based_on_version_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :flowchart_versions, column: :based_on_version_id
    remove_index :flowchart_versions, :based_on_version_id
    remove_column :flowchart_versions, :based_on_version_id
  end
end
