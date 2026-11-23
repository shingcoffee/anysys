# frozen_string_literal: true

require "rails_helper"

RSpec.describe SharedIdentity, type: :concern do
  let(:customer) { create(:customer) }

  it "exposes shared? / customer_owned? from customer_id" do
    owned = create(:entity, customer: customer)
    shared = create(:entity, :shared)

    expect(owned).to be_customer_owned
    expect(owned).not_to be_shared
    expect(shared).to be_shared
    expect(shared).not_to be_customer_owned
  end

  it "scopes .shared, .customer_owned, and .accessible" do
    owned = create(:entity, customer: customer)
    other = create(:entity, customer: create(:customer))
    shared = create(:entity, :shared)

    expect(Entity.shared).to include(shared)
    expect(Entity.shared).not_to include(owned)
    expect(Entity.customer_owned).to include(owned, other)
    expect(Entity.customer_owned).not_to include(shared)

    Current.customer = customer
    accessible = Entity.accessible
    expect(accessible).to include(owned, shared)
    expect(accessible).not_to include(other)

    Current.reset
    expect(Entity.accessible).to contain_exactly(shared)
  ensure
    Current.reset
  end
end
