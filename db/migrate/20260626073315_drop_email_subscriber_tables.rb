# frozen_string_literal: true

class DropEmailSubscriberTables < ActiveRecord::Migration[8.1]
  def up
    drop_table :email_list_subscribers
    drop_table :email_subscribers
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
