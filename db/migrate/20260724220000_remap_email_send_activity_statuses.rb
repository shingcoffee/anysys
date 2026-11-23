# frozen_string_literal: true

class RemapEmailSendActivityStatuses < ActiveRecord::Migration[8.1]
  def up
    say_with_time "remap email_send_activities.status to pending/processing/succeed" do
      execute <<~SQL.squish
        UPDATE email_send_activities SET status = 'pending'
        WHERE status IN ('draft', 'scheduled')
      SQL
      execute <<~SQL.squish
        UPDATE email_send_activities SET status = 'processing'
        WHERE status = 'sending'
      SQL
      # Paused campaigns are no longer a product status. Return them to pending
      # with a cleared claim so the reaper cannot dead-letter a long-paused row.
      execute <<~SQL.squish
        UPDATE email_send_activities
        SET status = 'pending', started_at = NULL, claimed_at = NULL
        WHERE status = 'paused'
      SQL
      execute <<~SQL.squish
        UPDATE email_send_activities SET status = 'succeed'
        WHERE status = 'sent'
      SQL
    end

    change_column_default :email_send_activities, :status, from: "draft", to: "pending"
  end

  def down
    change_column_default :email_send_activities, :status, from: "pending", to: "draft"

    say_with_time "restore legacy email_send_activities.status values" do
      execute <<~SQL.squish
        UPDATE email_send_activities SET status = 'sent'
        WHERE status = 'succeed'
      SQL
      execute <<~SQL.squish
        UPDATE email_send_activities SET status = 'sending'
        WHERE status = 'processing'
      SQL
      execute <<~SQL.squish
        UPDATE email_send_activities SET status = 'scheduled'
        WHERE status = 'pending' AND scheduled_at IS NOT NULL
      SQL
      execute <<~SQL.squish
        UPDATE email_send_activities SET status = 'draft'
        WHERE status = 'pending'
      SQL
    end
  end
end
