class CreatePaymentMerchantAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_merchant_accounts do |t|
      t.references :customer, null: false, foreign_key: true
      t.string  :provider,  null: false
      t.string  :mode,      null: false, default: "sandbox"
      t.string  :merchant_id, null: false
      t.text    :api_key_v3
      t.text    :private_key_pem
      t.text    :platform_public_key_pem
      t.string  :wechat_cert_serial
      t.string  :notify_url_override
      t.string  :status, null: false, default: "disabled"
      t.timestamps
    end
    add_index :payment_merchant_accounts, %i[customer_id provider mode], unique: true,
              name: "idx_payment_accounts_on_cust_prov_mode"
    add_index :payment_merchant_accounts, %i[provider merchant_id], unique: true,
              name: "idx_payment_accounts_on_prov_mch"
  end
end
