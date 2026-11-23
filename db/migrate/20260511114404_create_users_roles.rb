# frozen_string_literal: true

class CreateUsersRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :users_roles do |t|
      t.references :user, null: false, foreign_key: { to_table: :users }, type: :bigint
      t.references :role, null: false, foreign_key: true, type: :bigint
      t.timestamps
    end

    add_index :users_roles, %i[user_id role_id], unique: true
  end
end
