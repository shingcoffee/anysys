# frozen_string_literal: true

class AddUserIdToEntityEntries < ActiveRecord::Migration[8.1]
  def change
    add_reference :entity_entries, :user, null: true, index: false,
                  foreign_key: { to_table: :users, on_delete: :nullify }
    add_index :entity_entries, %i[entity_id user_id], unique: true,
              where: "user_id IS NOT NULL", name: "idx_entity_entries_person_link"
    add_index :entity_entries, %i[customer_id user_id]
  end
end
