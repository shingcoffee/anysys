# frozen_string_literal: true

class CreateJourneyRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :journey_runs do |t|
      t.references :customer, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: true, foreign_key: { to_table: :users, on_delete: :cascade }, index: false
      t.string :token_digest, null: false
      t.integer :status, null: false, default: 0
      t.text :state
      t.datetime :expires_at, null: false
      t.timestamps null: false
    end
    add_index :journey_runs, :token_digest, unique: true
    add_index :journey_runs, %i[customer_id user_id]
    add_index :journey_runs, :expires_at
  end
end
