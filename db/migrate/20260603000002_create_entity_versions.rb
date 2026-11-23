# frozen_string_literal: true

class CreateEntityVersions < ActiveRecord::Migration[8.1]
  def up
    create_table :entity_versions do |t|
      t.integer  :entity_id,            null: false
      t.integer  :customer_id,          null: false
      t.integer  :version_number,       null: false
      t.text     :snapshot,             null: false
      t.string   :description
      t.boolean  :is_default,           null: false, default: false
      t.integer  :based_on_version_id            # lineage: the version this one was derived from
      t.timestamps
    end

    add_index :entity_versions, %i[entity_id version_number], unique: true,
              name: "index_entity_versions_on_entity_id_and_version_number"
    add_index :entity_versions, :entity_id
    add_index :entity_versions, :customer_id
    add_index :entity_versions, %i[entity_id is_default]
    add_index :entity_versions, :based_on_version_id

    # Backfill an initial default version (v1) for existing non-bridge entities so
    # the Versions panel is populated for pre-existing data. Done in Ruby (not raw
    # SQL) so the snapshot is built exactly like Entity#definition_snapshot — JSON
    # columns stay parsed structures rather than being double-encoded as strings.
    say_with_time "Backfilling initial entity versions" do
      Entity.reset_column_information
      count = 0
      Entity.where(is_bridge_entity: false).find_each do |entity|
        next if EntityVersion.exists?(entity_id: entity.id)

        EntityVersion.create!(
          entity_id:           entity.id,
          customer_id:         entity.customer_id,
          version_number:      1,
          snapshot:            entity.definition_snapshot.to_json,
          description:         "Initial version",
          is_default:          true,
          based_on_version_id: nil
        )
        count += 1
      end
      count
    end
  end

  def down
    drop_table :entity_versions
  end
end
