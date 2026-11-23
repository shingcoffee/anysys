# frozen_string_literal: true

class CreateBillingPaymentMethods < ActiveRecord::Migration[8.1]
  def change
    create_table :billing_payment_methods do |t|
      t.bigint   :customer_id, null: false
      t.string   :provider, null: false
      t.bigint   :payments_subscription_id
      t.string   :status, null: false, default: "pending"
      t.string   :display_label
      t.boolean  :is_default, null: false, default: false
      t.datetime :authorized_at

      t.timestamps
    end

    add_index :billing_payment_methods, :customer_id
    add_index :billing_payment_methods, :payments_subscription_id

    # Enforce at most one active default payment method per tenant at the DB level.
    add_index :billing_payment_methods,
              :customer_id,
              unique: true,
              where: "is_default = TRUE AND status = 'active'",
              name: "index_billing_payment_methods_on_customer_id_active_default"
  end
end
