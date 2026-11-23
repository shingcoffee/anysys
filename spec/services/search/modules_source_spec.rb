# frozen_string_literal: true

require "rails_helper"

RSpec.describe Search::ModulesSource do
  let_it_be(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer, role: :admin) }

  def enable(key:, name:)
    enable_module!(key, customer, name: name)
  end

  def build(query)
    described_class.new(customer: customer, query: query, user: user).to_group
  end

  it "returns enabled modules for the customer matching the query" do
    enable(key: "payment", name: "Payments")
    enable(key: "sms",     name: "SMS Gateway")
    group = build("pay")
    expect(group[:key]).to eq(:modules)
    expect(group[:label]).to eq("Modules")
    expect(group[:items].map { |i| i[:label] }).to eq(["Payments"])
    # Payment's entry_path is a non-admin checkout URL, so search falls back
    # to the customer settings surface.
    expect(group[:items].first[:path]).to eq("/#{customer.id}/admin/settings/modules/payments")
    expect(group[:items].first[:type]).to eq(:module)
  end

  it "prefers an admin entry_path when the registration declares one" do
    enable(key: "email", name: "Email")
    group = build("email")
    expect(group[:items].map { |i| i[:label] }).to eq(["Email"])
    expect(group[:items].first[:path]).to eq("/#{customer.id}/admin/modules/emails/templates")
  end

  it "excludes modules not enabled for the customer" do
    find_or_create_feature_module!("payment", name: "Payments")
    expect(build("pay")[:items]).to be_empty
  end
end
