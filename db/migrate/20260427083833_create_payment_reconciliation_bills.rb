class CreatePaymentReconciliationBills < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_reconciliation_bills do |t|
      t.references :customer, null: false, foreign_key: true
      t.string  :provider,  null: false
      t.date    :bill_date, null: false
      t.string  :bill_type, null: false, default: "all"
      t.integer :total_count,      null: false, default: 0
      t.integer :total_amount_cents, null: false, default: 0
      t.integer :discrepancy_count,  null: false, default: 0
      t.string  :status, null: false, default: "downloading"
      t.json    :raw_summary, null: false, default: {}
      t.timestamps
    end
    add_index :payment_reconciliation_bills,
              %i[customer_id provider bill_date bill_type],
              unique: true,
              name: "idx_recon_bills_on_cust_prov_date_type"
  end
end
