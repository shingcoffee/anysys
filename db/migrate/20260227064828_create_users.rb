class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :gender
      t.string :email, null: false
      t.references :customer, null: false, foreign_key: true

      # Soft delete support
      t.integer :status, default: 0, null: false

      t.timestamps
    end

    # Indexes for performance
    add_index :users, :email
    add_index :users, [:customer_id, :email], unique: true
    add_index :users, :status
  end
end
