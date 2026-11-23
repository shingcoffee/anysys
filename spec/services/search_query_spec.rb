# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchQuery do
  let_it_be(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer, role: :admin) }

  it "returns an empty array for a blank query" do
    expect(described_class.call(customer: customer, query: "", user: user)).to eq([])
  end

  it "returns an empty array for a single-character query" do
    expect(described_class.call(customer: customer, query: "a", user: user)).to eq([])
  end

  it "omits groups that have no results" do
    create(:page, customer: customer, name: "Checkout")
    groups = described_class.call(customer: customer, query: "Checkout", user: user)
    expect(groups.map { |g| g[:key] }).to eq([:pages])
  end

  it "returns pages, entities, and modules groups when all match" do
    create(:page, customer: customer, name: "alpha page")
    create(:entity, customer: customer, name: "alpha entity")
    enable_module!("alpha_mod", customer, name: "Alpha Module")

    groups = described_class.call(customer: customer, query: "alpha", user: user)
    expect(groups.map { |g| g[:key] }).to contain_exactly(:pages, :entities, :modules)
  end

  it "includes shared pages and entities the tenant can open" do
    create(:page, :shared, name: "Shared Checkout")
    create(:entity, :shared, name: "Shared Contact")

    groups = described_class.call(customer: customer, query: "shared", user: user)
    expect(groups.map { |g| g[:key] }).to contain_exactly(:pages, :entities)
    page_labels = groups.find { |g| g[:key] == :pages }[:items].map { |i| i[:label] }
    entity_labels = groups.find { |g| g[:key] == :entities }[:items].map { |i| i[:label] }
    expect(page_labels).to include("Shared Checkout")
    expect(entity_labels).to include("Shared Contact")
  end
end
