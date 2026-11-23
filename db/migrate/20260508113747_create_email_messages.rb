class CreateEmailMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :email_messages do |t|
      t.integer :customer_id, null: false
      t.integer :email_template_id
      t.string :to, null: false
      t.string :cc
      t.string :bcc
      t.string :from, null: false
      t.string :reply_to
      t.string :subject, null: false
      t.text :body_html, null: false
      t.text :body_text
      t.string :status, null: false, default: "pending"
      t.string :message_type, null: false, default: "transactional"
      t.datetime :scheduled_at
      t.datetime :sent_at
      t.datetime :delivered_at
      t.string :failure_code
      t.string :failure_message
      t.string :idempotency_key
      t.json :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :email_messages, [:customer_id, :created_at]
    add_index :email_messages, [:customer_id, :idempotency_key], unique: true, where: "idempotency_key IS NOT NULL", name: "idx_email_messages_customer_idem"
    add_index :email_messages, [:customer_id, :status]
    add_index :email_messages, :email_template_id
  end
end
