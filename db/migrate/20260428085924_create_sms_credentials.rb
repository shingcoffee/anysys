class CreateSmsCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :sms_credentials do |t|
      t.string  :mode,              null: false
      t.string  :access_key_id,     null: false
      t.text    :access_key_secret, null: false
      t.string  :sign_name,         null: false
      t.string  :region,            null: false, default: "cn-hangzhou"
      t.string  :status,            null: false, default: "active"
      t.timestamps
    end
    add_index :sms_credentials, :mode, unique: true
  end
end
