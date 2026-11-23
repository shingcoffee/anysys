# frozen_string_literal: true

class AddSignInTokenToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :sign_in_token, :string
    add_column :users, :sign_in_token_sent_at, :datetime
    add_index :users, :sign_in_token, unique: true
  end
end
