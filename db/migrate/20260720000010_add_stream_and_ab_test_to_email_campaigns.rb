# frozen_string_literal: true

class AddStreamAndAbTestToEmailCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_reference :email_campaigns, :email_stream, foreign_key: true, index: true
    add_reference :email_campaigns, :email_segment, foreign_key: true, index: true
    add_column :email_campaigns, :ab_test_config, :json, null: false, default: {}
    add_column :email_campaigns, :ab_test_winner_variant, :string
    add_column :email_campaigns, :ab_test_completed_at, :datetime

    # Wizard drafts are created incrementally across steps, so the list and
    # template are only required once the user reaches the review step.
    change_column_null :email_campaigns, :email_template_id, true
    change_column_null :email_campaigns, :email_list_id, true
  end
end
