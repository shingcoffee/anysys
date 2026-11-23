class DropVestigialEmailMessageColumns < ActiveRecord::Migration[7.1]
  def up
    remove_column :email_messages, :builder_data, if_exists: true
    remove_column :email_messages, :scheduled_at, if_exists: true
  end

  def down
    add_column :email_messages, :builder_data, :json, default: {} unless column_exists?(:email_messages, :builder_data)
    add_column :email_messages, :scheduled_at, :datetime unless column_exists?(:email_messages, :scheduled_at)
  end
end
