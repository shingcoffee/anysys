# frozen_string_literal: true

require "rails_helper"

RSpec.describe People::PendingClaim, type: :model do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other) { create(:customer) }

  it "uses the people_pending_claims table" do
    expect(described_class.table_name).to eq("people_pending_claims")
  end

  it "belongs to a customer, a user, and an optional entity entry" do
    user = create(:user, :member, customer: customer)
    entry = create(:entity_entry, customer: customer)
    record = create(:people_pending_claim, customer: customer, user: user, entity_entry: entry)

    expect(record.customer).to eq(customer)
    expect(record.user).to eq(user)
    expect(record.entity_entry).to eq(entry)
  end

  it "scopes by tenant" do
    mine = create(:people_pending_claim, customer: customer, user: create(:user, customer: customer))
    create(:people_pending_claim, customer: other, user: create(:user, customer: other))

    expect(described_class.for_customer(customer.id)).to contain_exactly(mine)
    expect(described_class.for_customer(customer.id).map(&:customer_id).uniq).to eq([customer.id])
  end

  it "exposes expired rows through .expired" do
    stale = create(:people_pending_claim, customer: customer, user: create(:user, customer: customer),
                   expires_at: 1.minute.ago)
    fresh = create(:people_pending_claim, customer: customer, user: create(:user, customer: customer),
                   expires_at: 1.day.from_now)

    expect(described_class.expired).to include(stale)
    expect(described_class.expired).not_to include(fresh)
  end
end
