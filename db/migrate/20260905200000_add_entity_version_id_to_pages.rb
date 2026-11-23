# frozen_string_literal: true

class AddEntityVersionIdToPages < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :entity_version_id, :integer
    add_foreign_key :pages, :entity_versions, on_delete: :nullify

    add_index :pages, [:customer_id, :entity_version_id],
              unique: true,
              where: "entity_version_id IS NOT NULL AND customer_id IS NOT NULL AND status = 0",
              name: "index_pages_on_customer_entity_version"
    add_index :pages, :entity_version_id,
              unique: true,
              where: "entity_version_id IS NOT NULL AND customer_id IS NULL AND status = 0",
              name: "index_pages_on_shared_entity_version"
  end
end
