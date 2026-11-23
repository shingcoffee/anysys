# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Activities::DestroyPage do
  let_it_be(:customer) { create(:customer) }
  let(:site) { create(:website, customer: customer) }

  before { Current.customer = customer }
  after  { Current.customer = nil }

  it "refuses to destroy the home page" do
    home = create(:website_page, :home, website: site, customer: customer)
    result = described_class.call(page: home)

    expect(result.success?).to be(false)
    expect(result.errors).to include(I18n.t("website.errors.home_required"))
    expect(WebsitePage.find_by(id: home.id)).to eq(home)
  end

  it "destroys a non-home page" do
    create(:website_page, :home, website: site, customer: customer)
    page = create(:website_page, website: site, customer: customer, slug: "about")

    expect { described_class.call(page: page) }.to change(WebsitePage, :count).by(-1)
  end
end
