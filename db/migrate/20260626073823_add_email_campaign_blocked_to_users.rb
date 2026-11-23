# frozen_string_literal: true

class AddEmailCampaignBlockedToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email_campaign_blocked, :boolean, null: false, default: false
    add_column :users, :email_campaign_blocked_at, :datetime
    add_index  :users, [:customer_id, :email_campaign_blocked]
  end
end
