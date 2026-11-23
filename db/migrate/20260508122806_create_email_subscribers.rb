class CreateEmailSubscribers < ActiveRecord::Migration[8.1]
  def change
    create_table :email_subscribers do |t|
      t.integer :customer_id, null: false
      t.string :email, null: false
      t.string :first_name
      t.string :last_name
      t.string :status, null: false, default: "active"
      t.json :tags, null: false, default: []
      t.json :attributes_data, null: false, default: {}
      t.datetime :subscribed_at, null: false
      t.datetime :unsubscribed_at
      t.string :unsubscribe_token, null: false
      t.timestamps
    end

    add_index :email_subscribers, [:customer_id, :email], unique: true
    add_index :email_subscribers, [:customer_id, :status]
    add_index :email_subscribers, :unsubscribe_token, unique: true
  end
end
