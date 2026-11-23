# frozen_string_literal: true

class CreateFlowchartRuntimeTables < ActiveRecord::Migration[8.1]
  def change
    create_table :flowchart_sequences do |t|
      t.integer :customer_id, null: false
      t.string :name, null: false
      t.string :period, null: false
      t.integer :last_value, null: false, default: 0
    end
    add_index :flowchart_sequences, :customer_id
    add_index :flowchart_sequences, %i[customer_id name period],
              unique: true,
              name: "index_flowchart_sequences_on_customer_name_period"

    create_table :flowchart_audit_events do |t|
      t.integer :customer_id, null: false
      t.integer :flowchart_id
      t.string :event_type, null: false
      t.string :resource_type
      t.string :resource_id
      t.integer :actor_user_id
      t.string :ip
      t.text :user_agent
      t.string :severity, null: false, default: "info"
      t.json :metadata, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :flowchart_audit_events, :customer_id

    create_table :flowchart_notifications do |t|
      t.integer :customer_id, null: false
      t.integer :user_id, null: false
      t.json :title, null: false, default: {}
      t.json :body, null: false, default: {}
      t.integer :page_id
      t.datetime :read_at
      t.timestamps
    end
    add_index :flowchart_notifications, :customer_id
  end
end
