# frozen_string_literal: true
require "rails_helper"

RSpec.describe Billing::Countable::Registry do
  it "publishes only authoritative core quotas" do
    expect(described_class.keys).to eq(%w[page entity member])
    expect { described_class.count_for("storage", create(:customer)) }.to raise_error(ArgumentError)
  end

  it "counts member-role users and excludes tenant admins and other tenants" do
    customer = create(:customer)
    baseline = described_class.count_for("member", customer)
    create(:user, :member, customer: customer)
    create(:user, :admin, customer: customer)
    create(:user, :member, customer: customer, status: :trashed)
    create(:user, :member, customer: create(:customer))
    expect(described_class.count_for("member", customer)).to eq(baseline + 1)
  end

  it "counts pages/entities within the requested tenant regardless of Current" do
    customer = create(:customer)
    other = create(:customer)
    baseline = %w[page entity].to_h { |key| [key, described_class.count_for(key, customer)] }
    create(:page, customer: customer)
    # The page factory also creates its backing entity in this tenant.
    entity_count = described_class.count_for("entity", customer)
    create(:entity, customer: other)
    Current.set(customer: other) do
      expect(described_class.count_for("page", customer)).to eq(baseline["page"] + 1)
      expect(described_class.count_for("entity", customer)).to eq(entity_count)
    end
  end
end
