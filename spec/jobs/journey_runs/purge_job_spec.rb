# frozen_string_literal: true

require "rails_helper"

RSpec.describe JourneyRuns::PurgeJob do
  let(:customer) { create(:customer) }

  it "deletes runs that expired more than a week ago" do
    stale, = JourneyRun.issue!(customer_id: customer.id, user: nil, session: {})
    recent, = JourneyRun.issue!(customer_id: customer.id, user: nil, session: {})
    live, = JourneyRun.issue!(customer_id: customer.id, user: nil, session: {})
    stale.update_column(:expires_at, 8.days.ago)
    recent.update_column(:expires_at, 6.days.ago)

    described_class.perform_now

    expect(JourneyRun.pluck(:id)).to contain_exactly(recent.id, live.id)
  end
end
