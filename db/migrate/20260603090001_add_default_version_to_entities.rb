# frozen_string_literal: true

class AddDefaultVersionToEntities < ActiveRecord::Migration[8.1]
  def up
    add_reference :entities, :default_version, foreign_key: { to_table: :entity_versions, on_delete: :nullify }
    # Backfill: the version currently flagged is_default (or the latest) becomes the FK default.
    execute <<~SQL
      UPDATE entities SET default_version_id = (
        SELECT ev.id FROM entity_versions ev
        WHERE ev.entity_id = entities.id
        ORDER BY ev.is_default DESC, ev.version_number DESC
        LIMIT 1
      )
    SQL
  end

  def down
    remove_reference :entities, :default_version
  end
end
