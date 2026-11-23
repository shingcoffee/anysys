# frozen_string_literal: true
require "rails_helper"
require_relative "../../services/billing/partition_b_helpers"

RSpec.describe Billing::Invoice, type: :model do
  include BillingPartitionBHelpers

  it "rejects changes to issued financial terms while allowing collection state changes" do
    invoice = billing_aggregate.fetch(:invoice)
    invoice.total_cents = 1
    expect(invoice).not_to be_valid
    invoice.reload
    invoice.update!(collection_state: "blocked", failure_code: "no_payment_method")
    expect(invoice.total_cents).to eq(10_000)
  end

  it "cannot destroy issued financial history" do
    invoice = billing_aggregate.fetch(:invoice)
    expect { invoice.destroy! }.to raise_error(ActiveRecord::ActiveRecordError)
    expect(described_class.exists?(invoice.id)).to be(true)
  end

  it "retains the original policy when an owner authorizes outstanding collection" do
    aggregate = billing_aggregate(mode: "manual")
    invoice = aggregate.fetch(:invoice)
    snapshot = invoice.terms_snapshot.deep_dup
    result = Billing::Activities::AuthorizeInvoiceCollection.call(invoice: invoice, actor: find_or_create_platform_owner, mode: :gateway, note: "Owner recovery")
    expect(result.status).to eq(:authorized)
    expect(invoice.reload.effective_collection_mode).to eq("gateway")
    expect(invoice.terms_snapshot).to eq(snapshot)
    expect(invoice.collection_mode).to eq("manual")
  end

  it "distinguishes a zero-grace initial request deadline from its unpaid-access grace" do
    invoice = billing_aggregate(grace: 0).fetch(:invoice)
    expect(invoice.collection_deadline).to eq(Billing::PlanChangePolicy.request_deadline(invoice))
    expect(invoice.collection_deadline).to eq(invoice.period_end)
    expect(Billing::PlanChangePolicy.grace_deadline(invoice)).to eq(invoice.due_at)
  end
end
