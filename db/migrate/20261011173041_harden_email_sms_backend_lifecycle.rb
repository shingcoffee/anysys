# frozen_string_literal: true

class HardenEmailSmsBackendLifecycle < ActiveRecord::Migration[8.1]
  def change
    reversible do |direction|
      direction.up { reject_unresolved_email_outbox! }
    end

    change_table :email_messages do |t|
      t.datetime :delivery_due_at
      t.datetime :delivery_enqueued_at
      t.datetime :delivery_claimed_at
      t.string :delivery_claim_token
      t.integer :delivery_attempts, default: 0, null: false
    end
    add_index :email_messages, %i[status delivery_due_at delivery_enqueued_at], name: "idx_email_backend_dispatch_due"

    change_table :email_send_activities do |t|
      t.datetime :deferred_until
      t.string :deferred_reason
      t.datetime :progressed_at
      t.datetime :fanout_claimed_at
      t.string :fanout_claim_token
    end
    add_index :email_send_activities, %i[status deferred_until], name: "idx_email_backend_campaign_deferral"

    add_column :sms_messages, :metadata, :json, default: {}, null: false
    add_index :sms_messages, %i[customer_id to created_at], name: "idx_sms_backend_phone_window"

    # Authenticated receipts may arrive before a send's vendor ID is persisted.
    # customer_id is intentionally nullable until correlation identifies the
    # tenant; these are platform ingress ledgers, not customer-authored rows.
    %i[email_backend_receipts sms_backend_receipts].each do |table|
      create_table table do |t|
        t.bigint :customer_id
        t.bigint :credential_id, null: false
        t.string :provider, null: false
        t.string :event_key, null: false
        t.string :vendor_message_id
        t.json :payload, default: {}, null: false
        t.datetime :processed_at
        t.timestamps
      end
      add_index table, %i[credential_id event_key], unique: true, name: "idx_#{table}_identity"
      add_index table, %i[provider vendor_message_id], name: "idx_#{table}_correlation"
      add_index table, %i[processed_at created_at], name: "idx_#{table}_pending"
      add_index table, :customer_id
    end
    add_foreign_key :email_backend_receipts, :email_credentials, column: :credential_id
    add_foreign_key :sms_backend_receipts, :sms_credentials, column: :credential_id
  end

  private

  # Before these columns exist, queued rows do not record whether delivery is
  # immediate or deferred. Production Solid Queue lives in another database;
  # absence of a scheduled execution in the primary DB proves nothing. This
  # brand-new application's migration refuses that unresolved input rather than
  # guessing due times or adding an old-envelope runtime compatibility path.
  def reject_unresolved_email_outbox!
    return if select_value("SELECT COUNT(*) FROM email_messages WHERE status = 'queued'").to_i.zero?

    raise ActiveRecord::MigrationError,
          "Resolve or quarantine queued email messages before this migration: their delivery schedules are not recorded in the primary database."
  end
end
