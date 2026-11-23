# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Website::Registration do
  it_behaves_like "a feature module registration",
                  key: "website", name: "Website", inactive: true, required: false

  it "uses the locked module description" do
    expect(described_class.module_description).to eq(
      "Customer introduction and marketing website — static pages, no forms"
    )
  end

  describe ".sidebar_contributions" do
    it "points entries at pages and settings at the site" do
      contributions = described_class.sidebar_contributions(double("controller"))
      pages = contributions[:entries].find { |item| item.entry_key == "pages" }
      site = contributions[:settings].find { |item| item.entry_key == "site" }

      expect(pages.path.call(42)).to eq("/42/admin/modules/website")
      expect(site.path.call(42)).to eq("/42/admin/settings/modules/website")
    end
  end

  describe ".entries_for" do
    let_it_be(:customer) { create(:customer) }

    around { |example| Current.set(customer: customer) { example.run } }

    it "returns tenant-scoped WebsitePage rows ordered by position" do
      site = create(:website, customer: customer)
      later = create(:website_page, website: site, customer: customer, position: 2, slug: "later")
      earlier = create(:website_page, website: site, customer: customer, position: 1, slug: "earlier")
      other = create(:website)
      create(:website_page, website: other, customer: other.customer, slug: "foreign")

      config = described_class.entries_for(entry_key: "pages", params: {})
      expect(config[:scope].to_a).to eq([ earlier, later ])
    end
  end

  describe ".entry_path_for" do
    it "returns the website module index" do
      customer = double(id: 99)
      expect(described_class.entry_path_for(customer)).to eq("/99/admin/modules/website")
    end
  end
end
