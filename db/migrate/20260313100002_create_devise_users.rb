# frozen_string_literal: true

class CreateDeviseUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      # Devise: database_authenticatable
      t.string :email, null: false
      t.string :encrypted_password, null: false, default: ""

      # Devise: recoverable
      t.string :reset_password_token
      t.datetime :reset_password_sent_at

      # Devise: rememberable
      t.datetime :remember_created_at

      # Devise: trackable
      t.integer :sign_in_count, default: 0, null: false
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.string :current_sign_in_ip
      t.string :last_sign_in_ip

      # Devise: lockable
      t.integer :failed_attempts, default: 0, null: false
      t.string :unlock_token
      t.datetime :locked_at

      # Multi-tenant
      t.integer :customer_id, null: false

      # Profile
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.integer :role, default: 0, null: false
      t.integer :status, default: 0, null: false

      # 2FA / MFA (TOTP via rotp)
      t.string :otp_secret
      t.boolean :otp_required_for_login, default: false, null: false

      t.timestamps
    end

    add_index :users, [:customer_id, :email], unique: true
    add_index :users, :email
    add_index :users, :reset_password_token, unique: true
    add_index :users, :unlock_token, unique: true
    add_index :users, :customer_id
    add_index :users, :status

    add_foreign_key :users, :customers
  end
end
