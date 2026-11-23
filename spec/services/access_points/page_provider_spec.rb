# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessPoints::PageProvider do
  subject(:provider) { described_class.new }

  let(:customer)        { create(:customer) }
  let(:other_customer)  { create(:customer) }

  it "yields one descriptor per page scoped to the customer" do
    p1 = create(:page, customer: customer)
    create(:page, customer: other_customer)
    results = provider.call(customer_id: customer.id)
    expect(results.map(&:subject_id)).to contain_exactly(p1.id)
  end

  it "search filters by name (LIKE)" do
    create(:page, customer: customer, name: "Onboarding")
    create(:page, customer: customer, name: "Checkout")
    results = provider.search(customer_id: customer.id, query: "onboard")
    expect(results.map(&:label)).to contain_exactly("Onboarding")
  end
end
