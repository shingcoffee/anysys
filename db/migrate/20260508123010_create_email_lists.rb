class CreateEmailLists < ActiveRecord::Migration[8.1]
  def change
    create_table :email_lists do |t|
      t.integer :customer_id, null: false
      t.string :name, null: false
      t.text :description
      t.string :list_type, null: false, default: "static"
      t.json :segment_rules, null: false, default: {}
      t.string :status, null: false, default: "active"
      t.timestamps
    end

    add_index :email_lists, [:customer_id, :status]
    add_index :email_lists, :customer_id
  end
end
