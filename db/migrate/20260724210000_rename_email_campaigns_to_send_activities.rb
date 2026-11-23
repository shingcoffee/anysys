# frozen_string_literal: true

class RenameEmailCampaignsToSendActivities < ActiveRecord::Migration[8.1]
  def up
    rename_table :email_campaigns, :email_send_activities if table_exists?(:email_campaigns)

    {
      "index_email_campaigns_on_customer_id_and_status" => "index_email_send_activities_on_customer_id_and_status",
      "index_email_campaigns_on_email_list_id" => "index_email_send_activities_on_email_list_id",
      "index_email_campaigns_on_email_template_id" => "index_email_send_activities_on_email_template_id",
      "index_email_campaigns_on_status_and_claimed_at" => "index_email_send_activities_on_status_and_claimed_at",
      "index_email_campaigns_on_status_and_scheduled_at" => "index_email_send_activities_on_status_and_scheduled_at"
    }.each do |from, to|
      rename_index :email_send_activities, from, to if index_name_exists?(:email_send_activities, from)
    end

    if column_exists?(:email_messages, :email_campaign_id)
      rename_column :email_messages, :email_campaign_id, :email_send_activity_id
    end

    if index_name_exists?(:email_messages, "index_email_messages_on_email_campaign_id_and_created_at")
      rename_index :email_messages,
                   "index_email_messages_on_email_campaign_id_and_created_at",
                   "index_email_messages_on_email_send_activity_id_and_created_at"
    end
  end

  def down
    if index_name_exists?(:email_messages, "index_email_messages_on_email_send_activity_id_and_created_at")
      rename_index :email_messages,
                   "index_email_messages_on_email_send_activity_id_and_created_at",
                   "index_email_messages_on_email_campaign_id_and_created_at"
    end

    if column_exists?(:email_messages, :email_send_activity_id)
      rename_column :email_messages, :email_send_activity_id, :email_campaign_id
    end

    {
      "index_email_send_activities_on_customer_id_and_status" => "index_email_campaigns_on_customer_id_and_status",
      "index_email_send_activities_on_email_list_id" => "index_email_campaigns_on_email_list_id",
      "index_email_send_activities_on_email_template_id" => "index_email_campaigns_on_email_template_id",
      "index_email_send_activities_on_status_and_claimed_at" => "index_email_campaigns_on_status_and_claimed_at",
      "index_email_send_activities_on_status_and_scheduled_at" => "index_email_campaigns_on_status_and_scheduled_at"
    }.each do |from, to|
      rename_index :email_send_activities, from, to if index_name_exists?(:email_send_activities, from)
    end

    rename_table :email_send_activities, :email_campaigns if table_exists?(:email_send_activities)
  end
end
