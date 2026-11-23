class AddCurrencyAndPaymentMethodToPaymentSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :payment_subscriptions, :currency, :string, null: false, default: "cny"
    add_reference :payment_subscriptions, :payment_method, null: true, foreign_key: { to_table: :payment_methods }
  end
end
