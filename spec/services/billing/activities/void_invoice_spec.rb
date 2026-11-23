# frozen_string_literal: true
require "rails_helper"
require_relative "../partition_b_helpers"

RSpec.describe Billing::Activities::VoidInvoice do
  include BillingPartitionBHelpers

  it "voids only a safe invoice and preserves its immutable financial identity" do
    aggregate = billing_aggregate
    invoice = aggregate.fetch(:invoice)
    number = invoice.number
    expect(described_class.call(invoice: invoice).status).to eq(:voided)
    expect(described_class.call(invoice: invoice).status).to eq(:unchanged)
    expect(invoice.reload.number).to eq(number)
  end

  %w[unknown pending succeeded].each do |state|
    it "refuses void with a #{state} payment" do
      aggregate = billing_aggregate
      billing_payment(aggregate, state: state)
      expect(described_class.call(invoice: aggregate.fetch(:invoice)).status).to eq(:conflict)
      expect(aggregate.fetch(:invoice).reload.status).to eq("open")
    end
  end
end
