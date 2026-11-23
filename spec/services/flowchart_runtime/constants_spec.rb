# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Constants do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }
  let(:shared) { create(:constant, :shared, options: %w[Open Closed]) }
  let(:owned) { create(:constant, :customer_specific, customer: customer, options: %w[Red Blue]) }

  before do
    ConstantCustomerOverride.create!(constant: shared, customer_id: customer.id, options: %w[Draft Live])
  end

  it "resolves the customer override and never Current or another tenant" do
    Current.customer = other

    expect(described_class.options({ customer_id: customer.id }, shared.id)).to eq(%w[Draft Live])
    expect(described_class.options({ customer_id: other.id }, shared.id)).to eq(%w[Open Closed])
    expect(described_class.label({ customer_id: customer.id }, shared.id, "Draft")).to eq("Draft")
    expect(described_class.label({ customer_id: other.id }, shared.id, "Open")).to eq("Open")
    expect(described_class.label({ customer_id: other.id }, shared.id, "Draft")).to be_nil
    expect(described_class.label({ customer_id: other.id }, shared.id, "Draft", default: "Unknown")).to eq("Unknown")
  end

  it "resolves a shared constant by name using this customer's override" do
    expect(described_class.options({ customer_id: customer.id }, shared.name)).to eq(%w[Draft Live])
    expect(described_class.label({ customer_id: customer.id }, shared.name, "Draft")).to eq("Draft")
  end

  it "reads a customer-owned constant only for that customer" do
    expect(described_class.options({ customer_id: customer.id }, owned.id)).to eq(%w[Red Blue])
    expect {
      described_class.options({ customer_id: other.id }, owned.id)
    }.to raise_error(described_class::Error, "constant is not accessible")
  end

  it "rejects a missing customer or constant" do
    expect { described_class.options({}, shared.id) }.to raise_error(described_class::Error, "customer is required")
    expect { described_class.options({ customer_id: customer.id }, nil) }
      .to raise_error(described_class::Error, "constant is required")
    expect { described_class.options({ customer_id: customer.id }, 0) }
      .to raise_error(described_class::Error, "constant is not accessible")
  end
end
