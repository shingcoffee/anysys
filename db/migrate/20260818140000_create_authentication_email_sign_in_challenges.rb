# frozen_string_literal: true

class CreateAuthenticationEmailSignInChallenges < ActiveRecord::Migration[8.1]
  def change
    create_table :authentication_email_sign_in_challenges do |t|
      t.string :email_digest, null: false
      t.string :code_digest, null: false
      t.integer :user_id
      t.integer :customer_id
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.string :request_ip
      t.timestamps
    end

    add_index :authentication_email_sign_in_challenges, :email_digest,
              name: "idx_email_sign_in_challenges_on_email_digest"
    add_index :authentication_email_sign_in_challenges, [:email_digest, :consumed_at, :expires_at],
              name: "idx_email_sign_in_challenges_active_lookup"
  end
end
