# frozen_string_literal: true

# Composite index tuned for the reaper's stalled_sending(status, claimed_at)
# scope (status='sending' + a claimed_at range).
class IndexEmailCampaignsClaimedAt < ActiveRecord::Migration[8.1]
  def change
    add_index :email_campaigns, %i[status claimed_at], name: "index_email_campaigns_on_status_and_claimed_at"
  end
end
