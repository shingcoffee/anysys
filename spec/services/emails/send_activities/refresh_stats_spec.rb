# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::SendActivities::RefreshStats do
  it "counts accepted send states separately from materialization, failures and queue state" do
    customer = create(:customer)
    campaign = create(:email_send_activity, customer: customer, stats: { "failure_reason" => "retained" })
    %w[pending queued sent delivered bounced complained failed suppressed].each do |status|
      create(:email_message, customer: customer, email_send_activity_id: campaign.id, status: status)
    end
    other = create(:email_send_activity, customer: customer)
    create(:email_message, customer: customer, email_send_activity_id: other.id, status: "sent")

    described_class.call(campaign)

    expect(campaign.reload.stats).to include(
      "sent_count" => 4, "materialized_count" => 8, "pending_count" => 1, "queued_count" => 1,
      "failed_count" => 1, "suppressed_count" => 1, "failure_reason" => "retained"
    )
  end
end
