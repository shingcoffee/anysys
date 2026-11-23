# frozen_string_literal: true

require "rails_helper"

RSpec.describe LandingStats do
  let_it_be(:customer) { create(:customer) }
  let(:other)    { create(:customer) }

  it "counts customer-scoped resources only" do
    baseline_modules = FeatureModules::CustomerAssignment.where(customer_id: customer.id, status: :active).count
    baseline_active_users = Authentication::User.where(customer_id: customer.id, status: :active).count

    create(:entity, customer: customer, name: "A")
    create(:entity, customer: customer, name: "B_bridge", category: :bridge)
    create(:entity, customer: other, name: "Other")

    e = create(:entity, customer: customer, name: "EP")
    create(:page, customer: customer, entity: e, launched: true)
    create(:page, customer: customer, entity: e, launched: false)

    fm = create(:feature_module, key: "m1")
    create(:customer_feature_module, customer: customer, feature_module: fm, status: :active)

    create(:user, customer: customer)
    create(:user, :inactive, customer: customer)

    stats = described_class.for(customer).to_h
    expect(stats[:entities]).to eq(2)
    expect(stats[:pages]).to eq(total: 2, launched: 1, draft: 1)
    expect(stats[:modules_enabled]).to eq(baseline_modules + 1)
    expect(stats[:users]).to eq(baseline_active_users + 1)
  end
end
