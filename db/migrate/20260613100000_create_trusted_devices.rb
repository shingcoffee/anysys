class CreateTrustedDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :trusted_devices do |t|
      t.integer  :customer_id, null: false
      t.integer  :user_id,     null: false
      t.string   :token_digest, null: false
      t.datetime :expires_at,  null: false
      t.datetime :last_used_at
      t.string   :ip
      t.string   :user_agent
      t.timestamps
    end

    add_index :trusted_devices, :token_digest, unique: true
    add_index :trusted_devices, :customer_id
    add_index :trusted_devices, :user_id
    add_index :trusted_devices, :expires_at
  end
end
