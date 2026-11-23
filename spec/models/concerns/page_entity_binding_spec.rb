# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageEntityBinding do
  describe ".preload_entities" do
    let(:customer) { create(:customer) }
    let(:other) { create(:customer) }

    def page_on(entity, customer: self.customer)
      create(:page, customer: customer, entity: entity)
    end

    it "resolves every page's entity without a query per page" do
      pages = [page_on(create(:entity, customer: customer)), page_on(create(:entity, customer: customer))]
      reloaded = Page.where(id: pages.map(&:id)).to_a

      Page.preload_entities(reloaded)
      queries = 0
      counter = ->(*) { queries += 1 }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { reloaded.each(&:entity) }

      expect(queries).to eq(0)
      expect(reloaded.map(&:entity)).to match_array(pages.map(&:entity))
    end

    it "keeps shared entities and hides another tenant's entity" do
      shared = create(:entity, customer: nil)
      foreign = create(:entity, customer: other)
      shared_page = page_on(shared)
      forged = page_on(create(:entity, customer: customer))
      reloaded = Page.where(id: [shared_page.id, forged.id]).index_by(&:id)
      allow(reloaded[forged.id]).to receive(:metadata).and_return("entity_id" => foreign.id)

      Page.preload_entities(reloaded.values)

      expect(reloaded[shared_page.id].entity).to eq(shared)
      expect(reloaded[forged.id].entity).to be_nil
    end
  end
end
