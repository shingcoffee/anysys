# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartSequence, type: :model do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other) { create(:customer) }

  it "belongs to a customer" do
    record = build(:flowchart_sequence, customer: customer)
    expect(record.customer).to eq(customer)
  end

  it "requires customer_id, name, and period" do
    record = described_class.new(last_value: 0)
    expect(record).not_to be_valid
    expect(record.errors[:customer_id]).to be_present
    expect(record.errors[:name]).to be_present
    expect(record.errors[:period]).to be_present
  end

  it "scopes by tenant" do
    mine = create(:flowchart_sequence, customer: customer, name: "order", period: "never")
    create(:flowchart_sequence, customer: other, name: "order", period: "never")

    expect(described_class.for_customer(customer.id)).to contain_exactly(mine)
    expect(described_class.for_customer(customer.id).map(&:customer_id).uniq).to eq([customer.id])
  end

  it "enforces uniqueness of name and period per tenant at the database layer" do
    create(:flowchart_sequence, customer: customer, name: "order", period: "never")
    expect {
      described_class.insert_all!([{ customer_id: customer.id, name: "order", period: "never", last_value: 0 }])
    }.to raise_error(ActiveRecord::RecordNotUnique)
    expect {
      create(:flowchart_sequence, customer: other, name: "order", period: "never")
    }.not_to raise_error
  end
end
