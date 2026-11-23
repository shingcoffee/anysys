class CreatePaymentOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_orders do |t|
      t.references :customer, null: false, foreign_key: true
      t.string  :external_ref, null: false
      t.integer :amount_cents, null: false
      t.string  :currency,     null: false, default: "CNY"
      t.string  :subject,      null: false
      t.text    :body
      t.string  :status,       null: false, default: "pending"
      t.json    :metadata,     null: false, default: {}
      t.datetime :expires_at
      t.datetime :paid_at
      t.timestamps
    end
    add_index :payment_orders, %i[customer_id external_ref], unique: true
    add_index :payment_orders, :status
  end
end
