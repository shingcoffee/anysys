class CreatePaymentSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_subscriptions do |t|
      t.references :customer, null: false, foreign_key: true
      t.string  :provider,     null: false
      t.string  :external_ref, null: false
      t.string  :plan_name,    null: false
      t.integer :amount_cents, null: false
      t.string  :cycle,        null: false
      t.string  :psp_agreement_id
      t.string  :status, null: false, default: "pending_sign"
      t.datetime :next_charge_at
      t.datetime :signed_at
      t.datetime :cancelled_at
      t.timestamps
    end
    add_index :payment_subscriptions, %i[customer_id external_ref], unique: true
    add_index :payment_subscriptions, %i[provider psp_agreement_id], unique: true,
              where: "psp_agreement_id IS NOT NULL"
  end
end
