class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments do |t|
      t.references :payment_order, null: false, foreign_key: true
      t.references :customer,      null: false, foreign_key: true
      t.string  :provider, null: false
      t.string  :flow,     null: false
      t.string  :out_trade_no,       null: false
      t.string  :psp_transaction_id
      t.string  :status,   null: false, default: "created"
      t.integer :amount_cents, null: false
      t.json    :prepay_payload, null: false, default: {}
      t.json    :raw_notify,     null: false, default: {}
      t.text    :failure_reason
      t.datetime :paid_at
      t.datetime :closed_at
      t.timestamps
    end
    add_index :payments, :out_trade_no, unique: true
    add_index :payments, %i[provider psp_transaction_id]
  end
end
