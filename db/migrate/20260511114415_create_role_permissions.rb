# frozen_string_literal: true

class CreateRolePermissions < ActiveRecord::Migration[8.1]
  def change
    create_table :role_permissions do |t|
      t.references :role, null: false, foreign_key: true, type: :bigint
      t.string  :subject_type, null: false
      t.string  :subject_key
      t.bigint  :subject_id
      t.string  :action,       null: false
      t.timestamps
    end

    add_index :role_permissions, %i[role_id subject_type subject_key]
    add_index :role_permissions, %i[role_id subject_type subject_id]
    add_check_constraint :role_permissions,
      "subject_key IS NOT NULL OR subject_id IS NOT NULL",
      name: "role_permissions_subject_present"
  end
end
