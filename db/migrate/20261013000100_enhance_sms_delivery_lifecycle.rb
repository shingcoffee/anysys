# frozen_string_literal: true

class EnhanceSmsDeliveryLifecycle < ActiveRecord::Migration[8.1]
  def change
    change_table :sms_messages do |t|
      t.datetime :expires_at
      t.datetime :delivery_enqueued_at
      t.datetime :delivery_claimed_at
      t.string :delivery_claim_token
      t.datetime :dispatch_started_at
      t.integer :delivery_attempts, default: 0, null: false
    end
    add_index :sms_messages, %i[status dispatch_started_at delivery_enqueued_at], name: "idx_sms_delivery_outbox"
    change_column_default :sms_messages, :status, from: "pending", to: "queued"
  end
end
