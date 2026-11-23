# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageProcessing do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }

  describe "default binding on create" do
    it "binds the platform default flowchart" do
      page = create(:page, customer: customer)

      expect(page.flowchart).to be_present
      expect(Flowcharts::DefaultPageFlowchart.default?(page.flowchart)).to be(true)
    end
  end

  describe "#bindable_flowcharts" do
    it "lists this owner's flowcharts and shared ones, never another tenant's" do
      page = create(:page, customer: customer)
      own = create(:flowchart, customer: customer)
      shared = create(:flowchart, :shared_type)
      foreign = create(:flowchart, customer: other)

      expect(page.bindable_flowcharts).to include(own, shared, page.flowchart)
      expect(page.bindable_flowcharts).not_to include(foreign)
    end
  end

  describe "#flowchart_belongs_to_page_owner" do
    it "rejects a flowchart owned by another tenant" do
      page = create(:page, customer: customer)
      page.flowchart = create(:flowchart, customer: other)

      expect(page).not_to be_valid
      expect(page.errors[:flowchart_id]).to include(I18n.t("maint_core.errors.validations.page_flowchart_unavailable"))
    end
  end

  describe "#hands_off?" do
    it "is false when the bound flowchart has no module handoff step" do
      page = create(:page, customer: customer)
      expect(page.hands_off?).to be(false)
    end

    it "is true when the bound flowchart has a hand_off_to_module step" do
      page = create(:page, customer: customer)
      bind_page_flowchart(page, steps: [{
        "action" => "hand_off_to_module",
        "config" => { "moduleKey" => "payment", "input" => [] }
      }])
      expect(page.reload.hands_off?).to be(true)
    end

    it "reads a tenant override of a shared flowchart" do
      shared = create_page_flowchart(customer: nil)
      page = create(:page, customer: customer)
      page.update_column(:flowchart_id, shared.id)
      expect(page.reload.hands_off?(for_customer: customer)).to be(false)

      handoff = create_page_flowchart(customer: customer, steps: [{
        "action" => "hand_off_to_module",
        "config" => { "moduleKey" => "payment", "input" => [] }
      }])
      Current.with_customer(customer) do
        loaded = Flowchart.find(shared.id)
        loaded.configuration = handoff.configuration
        loaded.save!
      end

      expect(page.reload.hands_off?(for_customer: customer)).to be(true)
      expect(page.hands_off?(for_customer: other)).to be(false)
    end
  end
end
