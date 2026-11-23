# frozen_string_literal: true

# Stamps each entry with the entity definition version_number in effect when it
# was authored (provenance only — see
# docs/superpowers/specs/2026-07-05-entity-entry-version-stamp-design.md).
#
# Stores the immutable per-entity version_number (not an FK): version rows are
# pruned to MAX_VERSIONS, so a foreign key would be nullified once its version is
# pruned, whereas the number stays meaningful forever. Existing rows stay NULL
# (their authoring version is genuinely unknown).
class AddEntityVersionNumberToEntityEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :entity_entries, :entity_version_number, :integer, null: true
  end
end
