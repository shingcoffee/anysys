# frozen_string_literal: true
require "rails_helper"

RSpec.describe Billing::Countable::CatalogSync do
  it "keeps an enabled non-core item and preserves explicit core labels" do
    storage = Billing::CountableItem.create!(key: "storage", label: "Storage", enabled: true)
    described_class.call
    page = Billing::CountableItem.find_by!(key: "page")
    page.update!(label: "Custom page label")
    described_class.call
    expect(storage.reload.enabled).to be(true)
    expect(page.reload.label).to eq("Custom page label")
    expect(Billing::CountableItem.where(key: Billing::Countable::Registry.keys).count).to eq(3)
  end
end
