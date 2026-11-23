class DropUsers < ActiveRecord::Migration[8.1]
  def up
    drop_table :users
  end

  def down
    create_table :users do |t|
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :gender
      t.string :email, null: false
      t.integer :customer_id, null: false
      t.integer :status, default: 0, null: false
      t.timestamps
    end

    add_index :users, :email
    add_index :users, [:customer_id, :email], unique: true
    add_index :users, :customer_id
    add_index :users, :status
    add_foreign_key :users, :customers
  end
end
