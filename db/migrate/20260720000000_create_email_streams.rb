# frozen_string_literal: true

class CreateEmailStreams < ActiveRecord::Migration[8.1]
  def change
    create_table :email_streams do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :key, null: false
      t.string :name, null: false
      t.string :kind, null: false, default: "transactional"
      t.string :provider
      t.string :mode, null: false, default: "sandbox"
      t.string :status, null: false, default: "active"
      t.boolean :tracking_enabled, null: false, default: true
      t.integer :throttle_per_minute, null: false, default: 1000
      t.string :from_email
      t.string :reply_to
      t.boolean :default_for_kind, null: false, default: false
      t.timestamps
    end

    add_index :email_streams, %i[customer_id key], unique: true
    add_index :email_streams, %i[customer_id kind default_for_kind status], name: "idx_email_streams_default_lookup"
  end
end
