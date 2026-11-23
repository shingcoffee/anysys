# frozen_string_literal: true
require "rails_helper"
require_relative "../partition_b_helpers"

RSpec.describe Billing::Cron::TrialEndingNotices do
  include BillingPartitionBHelpers

  it "deduplicates repeated sweeps by the actual trial end" do
    aggregate = billing_aggregate
    subscription = aggregate.fetch(:subscription)
    subscription.update!(status: "trialing", trial_end: 2.days.from_now)
    2.times { described_class.perform }
    expect(Billing::Notice.where(kind: "trial_ending", billing_subscription_id: subscription.id).count).to eq(1)
  end
end
