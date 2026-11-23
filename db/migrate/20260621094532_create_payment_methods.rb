class CreatePaymentMethods < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_methods do |t|
      t.integer :customer_id,            null: false
      t.integer :user_id,                null: false
      t.string  :provider,               null: false
      t.string  :psp_customer_id
      t.string  :psp_payment_method_id,  null: false
      t.string  :brand
      t.string  :last4
      t.integer :exp_month
      t.integer :exp_year
      t.boolean :is_default,             null: false, default: false
      t.string  :status,                 null: false, default: "active"
      t.timestamps
    end

    add_index :payment_methods, %i[customer_id user_id]
    add_index :payment_methods, %i[provider psp_payment_method_id], unique: true
  end
end
