class CreateEmailListSubscribers < ActiveRecord::Migration[8.1]
  def change
    create_table :email_list_subscribers do |t|
      t.integer :email_list_id, null: false
      t.integer :email_subscriber_id, null: false
      t.timestamps
    end

    add_index :email_list_subscribers, [:email_list_id, :email_subscriber_id], unique: true, name: "idx_email_list_subscribers_unique"
    add_index :email_list_subscribers, :email_subscriber_id
  end
end
