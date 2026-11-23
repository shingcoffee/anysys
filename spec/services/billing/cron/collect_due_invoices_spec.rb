# frozen_string_literal: true
require "rails_helper"
require_relative "../partition_b_helpers"

RSpec.describe Billing::Cron::CollectDueInvoices do
  include BillingPartitionBHelpers

  it "selects only ready initial collection and preserves the caller's Current" do
    aggregate = billing_aggregate
    ready = aggregate.fetch(:invoice)
    retrying = billing_aggregate.fetch(:invoice)
    retrying.update!(collection_state: "retry_wait", attempt_count: 1, next_attempt_at: Time.current)
    current = create(:customer)
    Current.set(customer: current) do
      allow(Billing::Activities::CollectInvoice).to receive(:call)
      described_class.perform
      expect(Billing::Activities::CollectInvoice).to have_received(:call).with(invoice: ready, trigger: :initial, at: kind_of(Time)).once
      expect(Billing::Activities::CollectInvoice).not_to have_received(:call).with(invoice: retrying, trigger: :initial, at: anything)
      expect(Current.customer).to eq(current)
    end
  end
end
