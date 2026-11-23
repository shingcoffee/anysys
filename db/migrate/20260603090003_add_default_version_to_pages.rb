# frozen_string_literal: true

class AddDefaultVersionToPages < ActiveRecord::Migration[8.1]
  def up
    add_reference :pages, :default_version, foreign_key: { to_table: :page_versions, on_delete: :nullify }
    execute <<~SQL
      UPDATE pages SET default_version_id = (
        SELECT pv.id FROM page_versions pv
        WHERE pv.page_id = pages.id
        ORDER BY pv.version_number DESC
        LIMIT 1
      )
    SQL
  end

  def down
    remove_reference :pages, :default_version
  end
end
