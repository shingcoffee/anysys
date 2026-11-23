class CreatePaymentRefunds < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_refunds do |t|
      t.references :payment,  null: false, foreign_key: true
      t.references :customer, null: false, foreign_key: true
      t.string  :out_refund_no, null: false
      t.string  :psp_refund_id
      t.integer :amount_cents, null: false
      t.string  :reason
      t.string  :status, null: false, default: "requested"
      t.datetime :requested_at
      t.datetime :succeeded_at
      t.datetime :failed_at
      t.json :raw_notify, null: false, default: {}
      t.timestamps
    end
    add_index :payment_refunds, :out_refund_no, unique: true
  end
end
