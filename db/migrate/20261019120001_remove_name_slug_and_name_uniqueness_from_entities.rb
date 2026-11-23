# frozen_string_literal: true

class RemoveNameSlugAndNameUniquenessFromEntities < ActiveRecord::Migration[8.1]
  def change
    remove_column :entities, :name_slug, :string
    remove_index :entities, column: %i[customer_id name], name: "index_entities_on_customer_id_and_name", unique: true
  end
end
