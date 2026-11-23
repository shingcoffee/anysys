# frozen_string_literal: true

class AddSourceKeyToMemberSurfaceSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :member_surface_settings, :source_key, :string
    add_index  :member_surface_settings, %i[customer_id source_key],
               name: "idx_member_surface_settings_on_customer_and_source"

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE member_surface_settings
             SET source_key = 'modules'
           WHERE source_key IS NULL
        SQL
      end
    end
  end
end
