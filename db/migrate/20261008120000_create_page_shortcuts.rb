# frozen_string_literal: true

class CreatePageShortcuts < ActiveRecord::Migration[8.1]
  def change
    create_table :page_shortcuts do |t|
      t.references :customer, type: :bigint, null: false, foreign_key: { on_delete: :cascade }
      t.string :path, null: false
      t.string :target_type, null: false
      t.bigint :target_id, null: false
      t.timestamps
    end

    add_index :page_shortcuts, [:customer_id, :path], unique: true
    add_index :page_shortcuts, [:target_type, :target_id]
    add_check_constraint :page_shortcuts, "target_type IN ('WebsitePage', 'Page')",
                         name: "page_shortcuts_target_type"
    add_check_constraint :page_shortcuts, "substr(path, 1, 1) = '/'",
                         name: "page_shortcuts_absolute_path"
  end
end
