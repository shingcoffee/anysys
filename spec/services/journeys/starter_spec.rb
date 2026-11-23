# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::Starter do
  let(:customer) { create(:customer) }
  let(:start_page) { Page.new(action_key: "student_new") }

  describe ".for_page" do
    def for_page(page = start_page, audience: "admin", customer_id: customer.id)
      described_class.for_page(page: page, audience: audience, customer_id: customer_id)
    end

    it "finds the launched journey whose first step is the page's action, for the audience" do
      journey = create(:journey, :launched, customer: customer)

      expect(for_page).to eq(journey)
      expect(for_page(audience: "public")).to be_nil
    end

    it "ignores drafts, other tenants, later steps and pages without an action key" do
      create(:journey, customer: customer)
      create(:journey, :launched)

      expect(for_page).to be_nil

      create(:journey, :launched, customer: customer)
      expect(for_page(Page.new(action_key: "student_add_course"))).to be_nil
      expect(for_page(Page.new(action_key: nil))).to be_nil
    end
  end

  describe ".preview" do
    let!(:draft) { create(:journey, customer: customer) }
    let(:owner) { find_or_create_platform_owner }

    def preview(key: draft.key, page: start_page, viewer: owner, customer_id: customer.id)
      described_class.preview(key: key, page: page, customer_id: customer_id, viewer: viewer)
    end

    it "lets the platform owner start a draft from its first page" do
      expect(preview).to eq(draft)
    end

    it "refuses anyone else, other tenants' keys, blank keys and other pages" do
      expect(preview(viewer: create(:user, :admin, customer: customer))).to be_nil
      expect(preview(viewer: nil)).to be_nil
      expect(preview(customer_id: create(:customer).id)).to be_nil
      expect(preview(key: "")).to be_nil
      expect(preview(key: %w[array])).to be_nil
      expect(preview(page: Page.new(action_key: "student_add_course"))).to be_nil
    end
  end
end
