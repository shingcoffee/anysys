# frozen_string_literal: true

require "rails_helper"

RSpec.describe Website, type: :model do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  before { Current.customer = customer }
  after  { Current.customer = nil }

  it "is valid with required attributes" do
    expect(build(:website, customer: customer)).to be_valid
  end

  it "requires customer_id" do
    Current.customer = nil
    site = Website.new(name: "Studio", skeleton_key: "presence")
    expect(site).not_to be_valid
    expect(site.errors[:customer_id]).to be_present
  end

  it "scopes to the current customer" do
    mine = create(:website, customer: customer)
    create(:website, customer: other_customer)

    expect(described_class.for_current_customer).to contain_exactly(mine)
    Current.customer = other_customer
    expect(described_class.for_current_customer).not_to include(mine)
  end

  it "returns none when Current.customer is unset" do
    create(:website, customer: customer)
    Current.customer = nil
    expect(described_class.for_current_customer).to be_empty
  end

  it "stores theme as a Hash rather than a JSON string" do
    site = create(:website, customer: customer, theme: { "appearance" => "dark" })
    expect(site.reload.theme).to be_a(Hash)
    expect(site.theme["appearance"]).to eq("dark")
    expect(site.theme).not_to be_a(String)
  end

  describe "#home_page" do
    it "returns the home page for the site" do
      site = create(:website, customer: customer)
      create(:website_page, website: site, customer: customer, slug: "about")
      home = create(:website_page, :home, website: site, customer: customer)

      expect(site.home_page).to eq(home)
    end
  end

  it "orders pages by position" do
    site = create(:website, customer: customer)
    second = create(:website_page, website: site, customer: customer, position: 2, slug: "two")
    first = create(:website_page, website: site, customer: customer, position: 1, slug: "one")

    expect(site.pages).to eq([ first, second ])
  end

  it "destroys pages with the site" do
    site = create(:website, customer: customer)
    create(:website_page, :home, website: site, customer: customer)

    expect { site.destroy! }.to change(WebsitePage, :count).by(-1)
  end
end
