# frozen_string_literal: true

class RemoveNameSlugAndNameUniquenessFromPages < ActiveRecord::Migration[8.1]
  def change
    remove_column :pages, :name_slug, :string
    remove_index :pages, column: %i[customer_id name], name: "index_pages_on_customer_id_and_name", unique: true
    remove_index :pages, column: :name, name: "index_pages_on_shared_active_name", unique: true,
                         where: "customer_id IS NULL AND status = 0"
  end
end
