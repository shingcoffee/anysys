# frozen_string_literal: true

class CreatePeoplePendingClaims < ActiveRecord::Migration[8.1]
  def change
    create_table :people_pending_claims do |t|
      t.references :customer, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: { to_table: :users, on_delete: :cascade },
                   index: { unique: true }
      t.references :entity_entry, foreign_key: { on_delete: :nullify }
      t.json :continuation
      t.boolean :created_user, null: false, default: false
      t.datetime :expires_at, null: false
      t.timestamps null: false
    end

    add_index :people_pending_claims, :expires_at
  end
end
