# frozen_string_literal: true

class AddUserIdToPayments < ActiveRecord::Migration[8.1]
  def change
    add_reference :payments, :user, null: true, index: true, foreign_key: { to_table: :users }
  end
end
