# frozen_string_literal: true

class CreateSmsAudiencesAndCampaigns < ActiveRecord::Migration[8.1]
  def change
    create_table :sms_contacts do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :phone_e164, null: false
      t.string :name
      t.string :country_code, null: false, default: "CN"
      t.string :timezone
      t.string :status, null: false, default: "active"
      t.string :consent_status, null: false, default: "unknown"
      t.datetime :consent_changed_at
      t.json :custom_attributes, null: false, default: {}
      t.string :source_kind, null: false, default: "manual"
      t.references :source_entity, foreign_key: { to_table: :entities, on_delete: :nullify }
      t.references :source_entry, foreign_key: { to_table: :entity_entries, on_delete: :nullify }
      t.json :source_mapping, null: false, default: {}
      t.datetime :synced_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps null: false
    end
    add_index :sms_contacts, %i[customer_id phone_e164], unique: true
    add_index :sms_contacts, %i[customer_id status consent_status], name: "idx_sms_contacts_permission"
    add_index :sms_contacts, %i[customer_id source_entity_id source_entry_id], unique: true,
      where: "source_entity_id IS NOT NULL AND source_entry_id IS NOT NULL", name: "idx_sms_contacts_source"

    create_table :sms_consent_events do |t|
      t.references :customer, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: { to_table: :sms_contacts }
      t.string :phone_e164, null: false
      t.string :action, null: false
      t.string :source, null: false
      t.datetime :occurred_at, null: false
      t.references :actor_user, foreign_key: { to_table: :users }
      t.json :evidence, null: false, default: {}
      t.string :event_key, null: false
      t.timestamps null: false
    end
    add_index :sms_consent_events, %i[customer_id event_key], unique: true
    add_index :sms_consent_events, %i[customer_id contact_id id], name: "idx_sms_consent_contact"
    add_index :sms_consent_events, %i[customer_id phone_e164 id], name: "idx_sms_consent_phone"

    create_table :sms_segments do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.json :segment_rules, null: false, default: {}
      t.integer :lock_version, null: false, default: 0
      t.timestamps null: false
    end
    add_index :sms_segments, %i[customer_id name]

    create_table :sms_campaigns do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :name, null: false
      t.references :template, foreign_key: { to_table: :sms_templates }
      t.references :segment, foreign_key: { to_table: :sms_segments, on_delete: :nullify }
      t.json :variable_map, null: false, default: {}
      t.string :send_timing, null: false, default: "immediate"
      t.datetime :scheduled_at
      t.string :timezone, null: false, default: "Asia/Shanghai"
      t.integer :quiet_hours_start, null: false, default: 21
      t.integer :quiet_hours_end, null: false, default: 9
      t.integer :frequency_window_hours, null: false, default: 24
      t.integer :send_rate_per_minute, null: false, default: 60
      t.integer :deadline_hours, null: false, default: 24
      t.string :status, null: false, default: "draft"
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :launched_by, foreign_key: { to_table: :users }
      t.datetime :launched_at
      t.datetime :started_at
      t.datetime :expires_at
      t.datetime :finished_at
      t.datetime :cancelled_at
      t.json :settings_snapshot, null: false, default: {}
      t.json :audience_snapshot, null: false, default: {}
      t.json :stats, null: false, default: {}
      t.datetime :stats_refreshed_at
      t.string :run_token
      t.datetime :run_lease_expires_at
      t.datetime :heartbeat_at
      t.string :failure_code
      t.integer :lock_version, null: false, default: 0
      t.timestamps null: false
    end
    add_index :sms_campaigns, %i[customer_id status created_at], name: "idx_sms_campaigns_directory"
    add_index :sms_campaigns, %i[status scheduled_at]
    add_index :sms_campaigns, %i[status run_lease_expires_at]

    create_table :sms_campaign_recipients do |t|
      t.references :customer, null: false, foreign_key: true
      t.references :campaign, null: false, foreign_key: { to_table: :sms_campaigns }
      t.references :contact, null: false, foreign_key: { to_table: :sms_contacts }
      t.string :phone_e164, null: false
      t.json :contact_snapshot, null: false, default: {}
      t.json :vars, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.string :skip_reason
      t.string :deferral_reason
      t.references :message, index: false, foreign_key: { to_table: :sms_messages }
      t.datetime :delivery_due_at
      t.datetime :admitted_at
      t.datetime :processed_at
      t.timestamps null: false
    end
    add_index :sms_campaign_recipients, %i[campaign_id contact_id], unique: true
    add_index :sms_campaign_recipients, %i[campaign_id phone_e164], unique: true
    add_index :sms_campaign_recipients, :message_id, unique: true, where: "message_id IS NOT NULL"
    add_index :sms_campaign_recipients, %i[campaign_id status delivery_due_at id], name: "idx_sms_recipients_due"
    add_index :sms_campaign_recipients, %i[customer_id phone_e164 admitted_at], name: "idx_sms_recipients_admissions"

    add_column :sms_templates, :purpose, :string, null: false, default: "transactional"
    add_column :sms_templates, :body_template, :text
    add_reference :sms_messages, :campaign, foreign_key: { to_table: :sms_campaigns }
    add_reference :sms_messages, :contact, foreign_key: { to_table: :sms_contacts }
    add_column :sms_messages, :delivery_due_at, :datetime
    add_index :sms_messages, %i[status dispatch_started_at delivery_due_at], name: "idx_sms_messages_due"
    add_column :sms_credentials, :dispatch_next_at, :datetime
  end
end
