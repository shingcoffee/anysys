# frozen_string_literal: true

# Hardens Email Campaigns delivery integrity:
#   - email_campaigns.claimed_at backs the scheduler's atomic claim + the reaper
#     TTL (mirrors payments charge_due_subscriptions.claimed_at).
#   - email_messages.email_campaign_id is an indexed FK so campaign metrics and
#     the per-recipient dedup check are indexed lookups, not JSON scans.
class HardenEmailCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :email_campaigns, :claimed_at, :datetime

    add_column :email_messages, :email_campaign_id, :integer
    add_index  :email_messages, %i[email_campaign_id created_at]

    # Backfill the FK for existing campaign messages from the metadata blob.
    up_only do
      execute <<~SQL.squish
        UPDATE email_messages
           SET email_campaign_id = CAST(json_extract(metadata, '$.campaign_id') AS INTEGER)
         WHERE message_type = 'campaign'
           AND json_extract(metadata, '$.campaign_id') IS NOT NULL
      SQL
    end
  end
end
