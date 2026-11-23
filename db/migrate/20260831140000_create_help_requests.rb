# frozen_string_literal: true

class CreateHelpRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :help_requests do |t|
      t.integer :customer_id, null: false
      t.bigint :user_id, null: false
      t.string :subject, null: false
      t.string :status, null: false, default: "open"
      t.datetime :last_message_at, null: false
      t.timestamps
    end

    add_index :help_requests, :customer_id
    add_index :help_requests, :user_id
    add_index :help_requests, [ :status, :last_message_at ]
    add_foreign_key :help_requests, :customers, on_delete: :cascade
    add_foreign_key :help_requests, :users, on_delete: :cascade

    create_table :help_request_messages do |t|
      t.integer :customer_id, null: false
      t.bigint :help_request_id, null: false
      t.bigint :user_id, null: false
      t.string :author_role, null: false
      t.text :body, null: false
      t.timestamps
    end

    add_index :help_request_messages, :customer_id
    add_index :help_request_messages, :help_request_id
    add_foreign_key :help_request_messages, :customers, on_delete: :cascade
    add_foreign_key :help_request_messages, :help_requests, on_delete: :cascade
    add_foreign_key :help_request_messages, :users, on_delete: :cascade

    create_table :help_request_reads do |t|
      t.integer :customer_id, null: false
      t.bigint :user_id, null: false
      t.bigint :help_request_id, null: false
      t.datetime :last_read_at, null: false
    end

    add_index :help_request_reads,
              [ :user_id, :help_request_id ],
              unique: true,
              name: "idx_help_request_reads_unique"
    add_index :help_request_reads, :customer_id
    add_foreign_key :help_request_reads, :customers, on_delete: :cascade
    add_foreign_key :help_request_reads, :users, on_delete: :cascade
    add_foreign_key :help_request_reads, :help_requests, on_delete: :cascade
  end
end
