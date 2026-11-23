# frozen_string_literal: true

class CreateMemberSurfaceSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :member_surface_settings do |t|
      t.references :customer, null: false, foreign_key: true, type: :bigint
      t.string  :surface_key, null: false
      t.boolean :enabled,     null: false, default: true
      t.integer :position,    null: false, default: 0
      t.text    :config,      null: false, default: "{}"
      t.timestamps
    end

    add_index :member_surface_settings, %i[customer_id surface_key], unique: true,
              name: "idx_member_surface_settings_on_customer_and_key"
  end
end
