# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartAuditEvent, type: :model do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other) { create(:customer) }

  it "belongs to a customer" do
    record = build(:flowchart_audit_event, customer: customer)
    expect(record.customer).to eq(customer)
  end

  it "requires customer_id and event_type" do
    record = described_class.new
    expect(record).not_to be_valid
    expect(record.errors[:customer_id]).to be_present
    expect(record.errors[:event_type]).to be_present
  end

  it "scopes by tenant" do
    mine = create(:flowchart_audit_event, customer: customer, event_type: "login")
    create(:flowchart_audit_event, customer: other, event_type: "login")

    expect(described_class.for_customer(customer.id)).to contain_exactly(mine)
    expect(described_class.for_customer(customer.id).map(&:customer_id).uniq).to eq([customer.id])
  end

  it "optionally belongs to an actor user of the same tenant" do
    user = create(:user, :admin, customer: customer)
    record = create(:flowchart_audit_event, customer: customer, flowchart_id: 99, actor_user: user)

    expect(record.flowchart_id).to eq(99)
    expect(record.actor_user).to eq(user)
  end
end
