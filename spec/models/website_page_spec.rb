# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebsitePage, type: :model do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  let(:website) { create(:website, customer: customer) }

  before { Current.customer = customer }
  after  { Current.customer = nil }

  it "is valid with required attributes" do
    expect(build(:website_page, website: website, customer: customer)).to be_valid
  end

  it "requires customer_id" do
    Current.customer = nil
    page = WebsitePage.new(website: website, title: "About", slug: "about")
    expect(page).not_to be_valid
    expect(page.errors[:customer_id]).to be_present
  end

  it "scopes to the current customer" do
    mine = create(:website_page, website: website, customer: customer)
    other_site = create(:website, customer: other_customer)
    create(:website_page, website: other_site, customer: other_customer)

    expect(described_class.for_current_customer).to contain_exactly(mine)
  end

  it "enforces one home page per website" do
    create(:website_page, :home, website: website, customer: customer)
    second = build(:website_page, website: website, customer: customer, home: true, slug: "about")

    expect(second).not_to be_valid
    expect(second.errors[:home]).to be_present
  end

  it "enforces slug uniqueness per website" do
    create(:website_page, website: website, customer: customer, slug: "about")
    duplicate = build(:website_page, website: website, customer: customer, slug: "about")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:slug]).to be_present
  end

  it "allows the same slug on a different website" do
    create(:website_page, website: website, customer: customer, slug: "about")
    other_site = create(:website, customer: other_customer)
    other = build(:website_page, website: other_site, customer: other_customer, slug: "about")

    expect(other).to be_valid
  end

  it "rejects reserved slugs" do
    described_class::RESERVED_SLUGS.each do |slug|
      page = build(:website_page, website: website, customer: customer, slug: slug)
      expect(page).not_to be_valid
      expect(page.errors[:slug]).to include(I18n.t("website.errors.reserved_slug"))
    end
  end

  it "allows a blank slug on the home page" do
    page = build(:website_page, :home, website: website, customer: customer)
    expect(page).to be_valid
  end

  it "exposes published and in_nav scopes" do
    nav = create(:website_page, :published, website: website, customer: customer, nav_visible: true, slug: "shown")
    hidden = create(:website_page, website: website, customer: customer, published: false, nav_visible: false, slug: "hidden")

    expect(described_class.published).to contain_exactly(nav)
    expect(described_class.in_nav).to contain_exactly(nav)
    expect(described_class.published.in_nav).not_to include(hidden)
  end
end
