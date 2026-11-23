# frozen_string_literal: true

require "rails_helper"

RSpec.describe OperationInvocation, type: :model do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other) { create(:customer) }
  let_it_be(:admin) { create(:user, :admin, customer: customer) }

  it "exposes the locked status set and predicates" do
    expect(described_class::STATUSES).to eq(%w[
      awaiting_confirmation succeeded invalid conflict forbidden failed superseded declined
    ])
    record = build(:operation_invocation, customer: customer, user: admin, status: "awaiting_confirmation")
    expect(record).to be_awaiting_confirmation
    expect(record).not_to be_succeeded
    declined = build(:operation_invocation, customer: customer, user: admin, status: "declined")
    expect(declined).to be_declined
  end

  it "validates presence and inclusion" do
    record = described_class.new
    expect(record).not_to be_valid
    expect(record.errors[:operation]).to be_present
    expect(record.errors[:status]).to be_present

    record = build(:operation_invocation, customer: customer, user: admin, status: "nope", channel: "web")
    expect(record).not_to be_valid
    expect(record.errors[:status]).to be_present
    expect(record.errors[:channel]).to be_present
  end

  it "scopes by status and customer" do
    mine = create(:operation_invocation, customer: customer, user: admin, status: "succeeded")
    create(:operation_invocation, :awaiting_confirmation, customer: customer, user: admin)
    create(:operation_invocation, customer: other, user: create(:user, :admin, customer: other))

    expect(described_class.succeeded).to include(mine)
    expect(described_class.for_customer(customer.id)).to include(mine)
    expect(described_class.for_customer(customer.id).map(&:customer_id).uniq).to eq([customer.id])
    expect(described_class.awaiting_confirmation).to include(
      described_class.find_by!(customer_id: customer.id, status: "awaiting_confirmation")
    )
    declined = create(:operation_invocation, customer: customer, user: admin, status: "declined")
    expect(described_class.declined).to include(declined)
  end

  it "belongs to an Authentication::User actor and confirmer" do
    confirmer = create(:user, :admin, customer: customer)
    record = create(:operation_invocation, customer: customer, user: admin, confirmed_by: confirmer)

    expect(record.user).to eq(admin)
    expect(record.confirmed_by).to eq(confirmer)
  end
end
