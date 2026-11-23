# frozen_string_literal: true

class AddDefaultVersionToFlowcharts < ActiveRecord::Migration[8.1]
  def change
    add_column :flowcharts, :default_version_id, :bigint
    add_index  :flowcharts, :default_version_id
    add_foreign_key :flowcharts, :flowchart_versions, column: :default_version_id, on_delete: :nullify
  end
end
