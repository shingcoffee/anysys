# frozen_string_literal: true

class AddSharedIdentityToPages < ActiveRecord::Migration[8.1]
  def change
    change_column_null :pages, :customer_id, true
    add_column :pages, :type, :integer, default: 0, null: false
    add_index :pages, :type
    add_index :pages, :name,
              unique: true,
              where: "customer_id IS NULL AND status = 0",
              name: "index_pages_on_shared_active_name"
  end
end
