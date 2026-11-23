class CreatePaymentDefaultGateways < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_default_gateways do |t|
      t.bigint :customer_id, null: false
      t.string :provider,    null: false
      t.timestamps
    end
    add_index :payment_default_gateways, :customer_id, unique: true
  end
end
