# frozen_string_literal: true

# `email_send_activity_lists` (see 20260725100000) has already been backfilled
# from this column, so this migration only drops it — no re-backfill needed.
class RemoveEmailListIdFromEmailSendActivities < ActiveRecord::Migration[8.1]
  class MigrationSendActivityList < ActiveRecord::Base
    self.table_name = "email_send_activity_lists"
  end

  def up
    remove_foreign_key :email_send_activities, :email_lists if foreign_key_exists?(:email_send_activities, :email_lists)
    remove_index :email_send_activities, :email_list_id if index_exists?(:email_send_activities, :email_list_id)
    remove_column :email_send_activities, :email_list_id, :integer
  end

  def down
    add_column :email_send_activities, :email_list_id, :integer
    add_index :email_send_activities, :email_list_id

    say_with_time "backfill email_send_activities.email_list_id from email_send_activity_lists" do
      MigrationSendActivityList.order(:id).group_by(&:email_send_activity_id).each do |activity_id, rows|
        execute ActiveRecord::Base.sanitize_sql_array([
          "UPDATE email_send_activities SET email_list_id = ? WHERE id = ?",
          rows.first.email_list_id, activity_id
        ])
      end
    end
  end
end
