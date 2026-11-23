# frozen_string_literal: true

class AddUuidToFlowcharts < ActiveRecord::Migration[8.1]
  def change
    add_column :flowcharts, :uuid, :string

    reversible do |dir|
      dir.up do
        # Generate UUIDs for existing records
        execute <<-SQL.squish
          UPDATE flowcharts SET uuid = lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab', abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))
          WHERE uuid IS NULL
        SQL
      end
    end

    change_column_null :flowcharts, :uuid, false
    add_index :flowcharts, :uuid, unique: true
  end
end
