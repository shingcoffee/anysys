class AddUniqueIndexToEmailMessageEvents < ActiveRecord::Migration[7.1]
  def change
    add_index :email_message_events, [:message_id, :event_type], unique: true, where: "event_type = 'open'"
  end
end
