class CreateEmailCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :email_credentials do |t|
      t.string :host, null: false
      t.integer :port, null: false, default: 587
      t.string :username, null: false
      t.text :password, null: false
      t.string :domain
      t.string :authentication, null: false, default: "plain"
      t.boolean :enable_starttls, null: false, default: true
      t.boolean :ssl, null: false, default: false
      t.string :mode, null: false
      t.string :status, null: false, default: "active"
      t.integer :daily_limit
      t.timestamps
    end

    add_index :email_credentials, :mode, unique: true
  end
end
