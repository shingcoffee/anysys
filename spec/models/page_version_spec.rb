# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageVersion, type: :model do
  let_it_be(:customer) { create(:customer) }
  let(:page)     { create(:page, customer: customer) }

  before { Current.customer = customer }

  def content_for(payload)
    PageConfigurationContent.store!(customer_id: customer.id, payload: payload)
  end

  describe "validations" do
    it "is valid with a content row and version_number" do
      version = page.page_versions.build(customer_id: customer.id, version_number: 99, content: content_for({ "a" => 1 }))
      expect(version).to be_valid
    end

    it "requires a content row" do
      version = page.page_versions.build(customer_id: customer.id, version_number: 99, content: nil)
      expect(version).not_to be_valid
      expect(version.errors[:content]).to be_present
    end

    it "requires version_number" do
      version = page.page_versions.build(customer_id: customer.id, version_number: nil, content: content_for({ "a" => 1 }))
      expect(version).not_to be_valid
      expect(version.errors[:version_number]).to include("can't be blank")
    end

    describe "version_number uniqueness scoped to page_id" do
      before { page.page_versions.create!(customer_id: customer.id, version_number: 5, content: content_for({ "a" => 1 })) }

      it "rejects a duplicate version_number for the same page" do
        duplicate = page.page_versions.build(customer_id: customer.id, version_number: 5, content: content_for({ "a" => 2 }))
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:version_number]).to include("has already been taken")
      end

      it "allows the same version_number for a different page" do
        other_page = create(:page, customer: customer)
        version = other_page.page_versions.build(customer_id: customer.id, version_number: 5, content: content_for({ "a" => 2 }))
        expect(version).to be_valid
      end
    end
  end

  describe "payload" do
    it "reads through the content row" do
      c = content_for({ "fields" => [] })
      v = page.page_versions.create!(customer_id: customer.id, version_number: 7, content: c)
      expect(v.payload).to eq(c.payload)
    end
  end

  describe "scopes" do
    # Page auto-creates v1 on save; add higher-numbered versions to avoid collision.
    let!(:v2) { page.page_versions.create!(customer_id: customer.id, version_number: 2, content: content_for({ "n" => 2 })) }
    let!(:v3) { page.page_versions.create!(customer_id: customer.id, version_number: 3, content: content_for({ "n" => 3 })) }

    describe ".ordered" do
      it "returns versions in descending version_number order" do
        expect(page.page_versions.ordered.pluck(:version_number)).to eq([3, 2, 1])
      end
    end

    describe ".recent" do
      it "returns at most 50 records in descending order" do
        result = page.page_versions.recent
        expect(result.count).to be <= 50
        expect(result.pluck(:version_number)).to eq(result.pluck(:version_number).sort.reverse)
      end
    end
  end
end
