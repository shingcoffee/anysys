# frozen_string_literal: true

class CreateEmailSendActivityLists < ActiveRecord::Migration[8.1]
  class MigrationSendActivity < ActiveRecord::Base
    self.table_name = "email_send_activities"
  end

  class MigrationSendActivityList < ActiveRecord::Base
    self.table_name = "email_send_activity_lists"
  end

  def up
    create_table :email_send_activity_lists do |t|
      t.references :email_send_activity, null: false, foreign_key: true
      t.references :email_list, null: false, foreign_key: true
      t.timestamps
    end
    add_index :email_send_activity_lists, %i[email_send_activity_id email_list_id],
              unique: true

    MigrationSendActivity.where.not(email_list_id: nil).find_each do |activity|
      MigrationSendActivityList.create!(
        email_send_activity_id: activity.id,
        email_list_id: activity.email_list_id
      )
    end
  end

  def down
    drop_table :email_send_activity_lists
  end
end
