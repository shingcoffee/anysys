# frozen_string_literal: true

class CreateOperationInvocations < ActiveRecord::Migration[8.1]
  def change
    create_table :operation_invocations do |t|
      t.references :customer, null: false, foreign_key: true
      t.references :user, foreign_key: { to_table: :users }
      t.string :operation, null: false
      t.integer :operation_version, null: false
      t.string :channel, null: false
      t.string :status, null: false
      t.string :idempotency_key
      t.string :input_digest
      t.json :input, null: false, default: {}
      t.json :plan, null: false, default: []
      t.json :snapshot, null: false, default: {}
      t.json :result, null: false, default: {}
      t.json :violations, null: false, default: []
      t.bigint :conversation_id
      t.bigint :generation_id
      t.references :confirmed_by, foreign_key: { to_table: :users }
      t.datetime :confirmed_at
      t.integer :duration_ms
      t.timestamps null: false
    end

    add_index :operation_invocations, %i[customer_id idempotency_key],
              unique: true,
              where: "idempotency_key IS NOT NULL",
              name: "idx_operation_invocations_idempotency"
    add_index :operation_invocations, %i[customer_id operation created_at],
              name: "idx_operation_invocations_directory"
    add_index :operation_invocations, :conversation_id
    add_index :operation_invocations, :generation_id
  end
end
