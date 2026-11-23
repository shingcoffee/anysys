# spec/models/page_entity_grouping_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Page, "entity grouping", type: :model do
  let_it_be(:customer) { create(:customer) }
  let(:entity_a) { create(:entity, customer: customer) }
  let(:entity_b) { create(:entity, customer: customer) }

  let!(:a1) { create(:page, customer: customer, entity: entity_a) }
  let!(:a2) { create(:page, customer: customer, entity: entity_a) }
  let!(:b1) { create(:page, customer: customer, entity: entity_b) }

  describe ".for_entity" do
    it "returns only pages bound to that entity via metadata.entity_id" do
      expect(described_class.for_customer(customer.id).for_entity(entity_a.id)).to contain_exactly(a1, a2)
    end

    it "returns none for blank id" do
      expect(described_class.for_entity(nil)).to be_empty
    end
  end

  describe ".uncategorized_for" do
    let(:other_customer) { create(:customer) }
    let!(:other_tenant_page) { create(:page, customer: other_customer) }

    it "includes pages with nil entity_id" do
      orphan = create(:page, customer: customer, entity: entity_a)
      orphan.entity_id = nil
      orphan.save!(validate: false)

      expect(Page.uncategorized_for(customer.id)).to include(orphan)
    end

    it "includes pages bound to a missing/stale entity id" do
      stale = create(:page, customer: customer, entity: entity_a)
      stale.entity_id = 9_999_999
      stale.save!(validate: false)

      expect(Page.uncategorized_for(customer.id)).to include(stale)
    end

    it "excludes pages bound to a live customer entity" do
      expect(Page.uncategorized_for(customer.id)).not_to include(a1)
    end

    it "never returns another tenant's pages" do
      orphan = create(:page, customer: other_customer)
      orphan.entity_id = nil
      orphan.save!(validate: false)

      expect(Page.uncategorized_for(customer.id)).not_to include(other_tenant_page)
      expect(Page.uncategorized_for(customer.id)).not_to include(orphan)
    end
  end
end
