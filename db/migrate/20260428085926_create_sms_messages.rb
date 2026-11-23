class CreateSmsMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :sms_messages do |t|
      t.references :customer,     null: false, foreign_key: true
      t.references :sms_template, null: true,  foreign_key: true
      t.string     :to,                 null: false
      t.string     :template_key,       null: false
      t.json       :vars,               null: false, default: {}
      t.string     :idempotency_key
      t.string     :status,             null: false, default: "pending"
      t.string     :vendor_message_id
      t.string     :failure_code
      t.string     :failure_message
      t.json       :raw_response,       null: false, default: {}
      t.datetime   :sent_at
      t.datetime   :delivered_at
      t.timestamps
    end
    add_index :sms_messages, [:customer_id, :idempotency_key],
              unique: true, name: "idx_sms_messages_customer_idem",
              where: "idempotency_key IS NOT NULL"
    add_index :sms_messages, [:to, :template_key, :created_at], name: "idx_sms_messages_rate_limit"
    add_index :sms_messages, [:customer_id, :created_at],       name: "idx_sms_messages_daily_cap"
  end
end
