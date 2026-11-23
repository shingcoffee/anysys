# frozen_string_literal: true

class DropRoleFromUsers < ActiveRecord::Migration[8.1]
  def up
    remove_column :users, :role
  end

  def down
    add_column :users, :role, :integer, null: false, default: 0
  end
end
