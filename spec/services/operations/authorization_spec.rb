# frozen_string_literal: true

require "rails_helper"

RSpec.describe Operations::Authorization do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other) { create(:customer) }
  let_it_be(:owner) { find_or_create_platform_owner }
  let_it_be(:admin) { create(:user, :admin, customer: customer) }
  let_it_be(:foreign_admin) { create(:user, :admin, customer: other) }
  let_it_be(:member) { create(:user, :member, customer: customer) }
  let_it_be(:inactive) { create(:user, :admin, :inactive, customer: customer) }

  it "allows the platform owner across tenants" do
    expect(described_class.allowed?(actor: owner, customer: customer)).to be(true)
    expect(described_class.allowed?(actor: owner, customer: other)).to be(true)
  end

  it "allows an admin only for their own customer" do
    expect(described_class.allowed?(actor: admin, customer: customer)).to be(true)
    expect(described_class.allowed?(actor: admin, customer: other)).to be(false)
    expect(described_class.allowed?(actor: foreign_admin, customer: customer)).to be(false)
  end

  it "refuses members, inactive users, and a missing actor" do
    expect(described_class.allowed?(actor: member, customer: customer)).to be(false)
    expect(described_class.allowed?(actor: inactive, customer: customer)).to be(false)
    expect(described_class.allowed?(actor: nil, customer: customer)).to be(false)
  end
end
