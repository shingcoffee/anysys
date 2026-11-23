# frozen_string_literal: true
require "rails_helper"
require_relative "../partition_b_helpers"

RSpec.describe Billing::Cron::Dunning do
  include BillingPartitionBHelpers

  it "expires blocked pending enrollment by its original deadline without inventing payment attempts" do
    aggregate = billing_aggregate(grace: 2)
    invoice = aggregate.fetch(:invoice)
    invoice.update!(collection_state: "blocked", failure_code: "no_payment_method")
    Billing::Settings.current.update!(grace_period_days: 99)
    described_class.perform(at: invoice.due_at + 2.days)
    expect(aggregate.fetch(:subscription).reload.status).to eq("expired")
    expect(invoice.collection_attempts).to be_empty
  end

  it "does not mark a paid base subscription overdue for a failed proration" do
    aggregate = billing_aggregate(purpose: "proration")
    invoice = aggregate.fetch(:invoice)
    invoice.update!(status: "uncollectible", collection_state: "exhausted")
    described_class.perform(at: invoice.due_at + 1.day)
    expect(aggregate.fetch(:subscription).reload.status).to eq("active")
    expect(aggregate.fetch(:subscription).past_due_at).to be_nil
  end
end
