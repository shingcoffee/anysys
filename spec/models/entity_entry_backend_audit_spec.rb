# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityEntry, "backend audit", type: :model do
  let(:customer) { create(:customer) }

  ["{", "null", "[]", "true", '"text"'].each do |raw|
    it "rejects malformed data #{raw.inspect} through ordinary validation" do
      entry = build(:entity_entry, customer: customer, entity: create(:entity, customer: customer), data: raw)
      expect(entry).not_to be_valid
      expect(entry.errors[:data]).to be_present
      expect(entry.data).to eq(raw)
    end
  end

  it "stamps the resolved shared definition's version rather than the global head" do
    entity = create(:entity, :shared)
    entity.update!(description: "global second version")
    expect(entity.current_version.version_number).to eq(2)
    Current.with_customer(customer) do
      loaded = Entity.find(entity.id)
      loaded.update!(description: "first override")
      entry = create(:entity_entry, customer: customer, entity: loaded)
      expect(entry.entity_version_number).to eq(1)
    end
  end
end
