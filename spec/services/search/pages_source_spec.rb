# frozen_string_literal: true

require "rails_helper"

RSpec.describe Search::PagesSource do
  let(:customer)       { create(:customer) }
  let(:other_customer) { create(:customer) }
  let(:user)           { create(:user, customer: customer, role: :admin) }

  def build(query)
    described_class.new(customer: customer, query: query, user: user).to_group
  end

  it "returns pages for the customer whose name matches the query (case insensitive)" do
    create(:page, customer: customer, name: "Checkout Form")
    create(:page, customer: customer, name: "Onboarding")
    group = build("CHECK")
    expect(group[:key]).to eq(:pages)
    expect(group[:label]).to eq("Pages")
    expect(group[:items].map { |i| i[:label] }).to eq(["Checkout Form"])
    page = Page.find_by!(customer_id: customer.id, name: "Checkout Form")
    expect(group[:items].first[:path]).to eq("/#{customer.id}/admin/maintenance/pages/#{page.id}")
    expect(group[:items].first[:type]).to eq(:page)
  end

  it "excludes pages belonging to other customers" do
    create(:page, customer: other_customer, name: "Checkout Form")
    expect(build("Checkout")[:items]).to be_empty
  end

  it "caps results at 5" do
    7.times { |i| create(:page, customer: customer, name: "Match #{i}") }
    expect(build("Match")[:items].size).to eq(5)
  end

  it "returns an empty group when the query is blank" do
    create(:page, customer: customer, name: "Anything")
    expect(build("")[:items]).to be_empty
  end

  it "safely handles special LIKE characters" do
    create(:page, customer: customer, name: "100% Good")
    # '%' should be treated literally, not as wildcard
    expect(build("100%")[:items].map { |i| i[:label] }).to eq(["100% Good"])
  end
end
