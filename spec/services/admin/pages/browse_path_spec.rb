# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Pages::BrowsePath do
  let(:customer) { create(:customer) }
  let(:entity) { create(:entity, customer: customer, name: "Student", display_label: "Learners") }

  def browse(page) = described_class.new(page, customer_id: customer.id)

  it "leads a bound form to its entity's Forms tab" do
    page = create(:page, customer: customer, entity: entity)

    expect(described_class.for(page, customer_id: customer.id)).to eq("/#{customer.id}/admin/entities/#{entity.id}/pages")
    expect(browse(page).crumb).to eq(described_class::Crumb.new(label: "Learners", path: "/#{customer.id}/admin/entities/#{entity.id}/pages"))
  end

  it "leads unbound, bridge-bound and stale forms to the ungrouped domain's Forms tab" do
    bridge = create(:entity, customer: customer, category: :bridge)
    stale = create(:page, customer: customer, entity: entity)
    stale.entity_id = 99_999_999
    stale.save!(validate: false)
    unbound = create(:page, customer: customer, entity: entity)
    unbound.entity_id = nil
    unbound.save!(validate: false)
    pages = [unbound, create(:page, customer: customer, entity: bridge), stale]

    pages.each do |page|
      expect(browse(page).crumb)
        .to eq(described_class::Crumb.new(label: "Other", path: "/#{customer.id}/admin/domains/ungrouped/pages"))
    end
  end
end
