# frozen_string_literal: true

class DropDefinitionSharingTypeColumns < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE constants SET customer_id = NULL WHERE constant_type = 'shared'"
    execute "UPDATE entities SET customer_id = NULL WHERE type = 1"
    execute "UPDATE flowcharts SET customer_id = NULL WHERE type = 1"
    execute "UPDATE pages SET customer_id = NULL WHERE type = 1"

    remove_index :constants, name: "index_constants_on_constant_type"
    remove_column :constants, :constant_type

    remove_index :entities, :type
    remove_column :entities, :type

    remove_index :flowcharts, :type
    remove_column :flowcharts, :type

    remove_index :pages, :type
    remove_column :pages, :type
  end

  def down
    add_column :constants, :constant_type, :string, null: false, default: "customer_specific"
    add_index :constants, :constant_type
    execute "UPDATE constants SET constant_type = 'shared' WHERE customer_id IS NULL"

    add_column :entities, :type, :integer, default: 0, null: false
    add_index :entities, :type
    execute "UPDATE entities SET type = 1 WHERE customer_id IS NULL"

    add_column :flowcharts, :type, :integer, default: 0, null: false
    add_index :flowcharts, :type
    execute "UPDATE flowcharts SET type = 1 WHERE customer_id IS NULL"

    add_column :pages, :type, :integer, default: 0, null: false
    add_index :pages, :type
    execute "UPDATE pages SET type = 1 WHERE customer_id IS NULL"
  end
end
