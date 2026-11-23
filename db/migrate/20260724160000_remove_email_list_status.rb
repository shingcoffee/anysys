# frozen_string_literal: true

class RemoveEmailListStatus < ActiveRecord::Migration[8.1]
  def change
    remove_index :email_lists, name: "index_email_lists_on_customer_id_and_status", if_exists: true
    remove_column :email_lists, :status, :string, default: "active", null: false
  end
end
