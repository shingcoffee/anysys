class CreateEmailMessageEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :email_message_events do |t|
      t.integer :message_id, null: false
      t.string :event_type, null: false
      t.string :url
      t.string :ip
      t.string :user_agent
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :email_message_events, :message_id
  end
end
