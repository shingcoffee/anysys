# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Pages::BrowseScope do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }

  def browse(**options)
    described_class.call(customer_id: customer.id, **options)
  end

  it "uses the customer's effective shared-page binding for both lists and badges" do
    a = create(:entity, :shared, name: "GlobalA")
    b = create(:entity, :shared, name: "GlobalB")
    page = create(:page, :shared, entity: a)
    global_head = page.current_version_id
    Current.with_customer(customer) do
      loaded = Page.find(page.id)
      loaded.entity_id = b.id
      loaded.save!
    end
    Current.with_customer(other) do
      expect(browse(entity_ids: [a.id])).not_to include(page)
      expect(browse(entity_ids: [b.id])).to include(page)
      counts = Admin::Pages::BindingCounts.call(customer_id: customer.id)
      expect(counts[a.id].total).to eq(browse(entity_ids: [a.id]).count)
      expect(counts[b.id].total).to eq(browse(entity_ids: [b.id]).count)
      expect(described_class.call(customer_id: other.id, entity_ids: [a.id])).to include(page)
    end
    expect(page.reload.current_version_id).to eq(global_head)
  end

  it "classifies bridge-bound and stale pages as unbound in both lists and counts" do
    bridge = create(:entity, customer: customer, category: :bridge)
    page = create(:page, customer: customer, entity: bridge)
    stale = create(:page, customer: customer)
    stale.entity_id = 99999999
    stale.save!(validate: false)
    headless = create(:page, customer: customer)
    headless.update_column(:current_version_id, nil)
    foreign = create(:page, customer: other)

    expect(browse(unbound: true)).to contain_exactly(page, stale, headless)
    expect(browse(entity_ids: [bridge.id])).to be_empty
    expect(browse).not_to include(foreign)
    counts = Admin::Pages::BindingCounts.call(customer_id: customer.id)
    expect(counts[nil].total).to eq(browse(unbound: true).count)
    expect(counts.values.sum(&:total)).to eq(browse.count)
  end

  it "uses a stale effective override instead of the valid global binding" do
    entity = create(:entity, :shared)
    page = create(:page, :shared, entity: entity)
    Current.with_customer(customer) do
      loaded = Page.find(page.id)
      loaded.entity_id = 99999999
      loaded.save!(validate: false)
    end
    expect(browse(unbound: true)).to include(page)
    expect(browse(entity_ids: [entity.id])).not_to include(page)
    expect(described_class.call(customer_id: other.id, entity_ids: [entity.id])).to include(page)
  end

  it "normalizes digit ids identically for lists and counts without accepting partial ids" do
    entity = create(:entity, customer: customer)
    padded = create(:page, customer: customer, entity: entity)
    config = padded.configuration_json
    config["metadata"]["entity_id"] = " 00#{entity.id} "
    padded.configuration_json = config
    padded.save!(validate: false)
    malformed = create(:page, customer: customer, entity: entity)
    config = malformed.configuration_json
    config["metadata"]["entity_id"] = "#{entity.id}junk"
    malformed.configuration_json = config
    malformed.save!(validate: false)
    expect(browse(entity_ids: [entity.id])).to contain_exactly(padded)
    expect(browse(unbound: true)).to contain_exactly(malformed)
    counts = Admin::Pages::BindingCounts.call(customer_id: customer.id)
    expect(counts[entity.id].total).to eq(1)
    expect(counts[nil].total).to eq(1)
  end

  it "combines entity ids with unbound pages, ignoring unknown and bridge ids" do
    first = create(:entity, customer: customer)
    second = create(:entity, customer: customer)
    bridge = create(:entity, customer: customer, category: :bridge)
    first_page = create(:page, customer: customer, entity: first)
    second_page = create(:page, customer: customer, entity: second)
    orphan = create(:page, customer: customer, entity: second)
    orphan.entity_id = nil
    orphan.save!(validate: false)

    expect(browse(entity_ids: [first.id, second.id])).to contain_exactly(first_page, second_page)
    expect(browse(entity_ids: [first.id], unbound: true)).to contain_exactly(first_page, orphan)
    expect(browse(entity_ids: [bridge.id, 99_999_999])).to be_empty
    expect(browse(entity_ids: [])).to be_empty
    expect(browse).to include(first_page, second_page, orphan)
  end
end
