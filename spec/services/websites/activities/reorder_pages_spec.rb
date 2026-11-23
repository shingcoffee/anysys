# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Activities::ReorderPages do
  let_it_be(:customer) { create(:customer) }
  let(:site) { create(:website, customer: customer) }

  before { Current.customer = customer }
  after  { Current.customer = nil }

  it "writes positions from the given id order" do
    a = create(:website_page, :home, website: site, customer: customer, position: 0)
    b = create(:website_page, website: site, customer: customer, slug: "about", position: 1)
    c = create(:website_page, website: site, customer: customer, slug: "team", position: 2)

    result = described_class.call(website: site, ordered_ids: [ c.id, a.id, b.id ])
    expect(result.success?).to be(true)
    expect(site.pages.reload.map(&:id)).to eq([ c.id, a.id, b.id ])
  end
end
