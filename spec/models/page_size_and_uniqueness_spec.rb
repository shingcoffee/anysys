# frozen_string_literal: true

require "rails_helper"

RSpec.describe Page, "size cap, name uniqueness, and entity_id coercion" do
  let_it_be(:customer) { create(:customer) }
  let(:entity)   { create(:entity, customer: customer) }

  let(:minimal_configuration) do
    {
      "pages"    => [{ "id" => "page_1", "name" => "Page 1", "order" => 1, "fields" => [] }],
      "metadata" => { "entity_id" => entity.id, "entity_name" => entity.name }
    }.to_json
  end

  # ---------------------------------------------------------------------------
  # Bug 2 — configuration size cap
  # ---------------------------------------------------------------------------
  describe "configuration size cap (2 MB)" do
    it "rejects a configuration that exceeds 2 MB" do
      page = build(:page, customer: customer, entity: entity)
      page.configuration = "x" * (2.megabytes + 1)
      page.valid?
      expect(page.errors[:configuration]).to include("exceeds 2 MB limit")
    end

    it "does not raise a size error for a configuration within 2 MB" do
      page = build(:page, customer: customer, entity: entity)
      # configuration is well under 2 MB
      expect(page.errors[:configuration]).not_to include("exceeds 2 MB limit")
    end
  end

  # ---------------------------------------------------------------------------
  # Duplicate page names allowed
  # ---------------------------------------------------------------------------
  describe "duplicate page names" do
    it "allows two active pages with the same name under the same customer" do
      described_class.create!(name: "My Form", configuration: minimal_configuration, customer: customer)
      duplicate = build(:page, customer: customer, entity: entity, name: "My Form", configuration: minimal_configuration)
      expect(duplicate).to be_valid
      expect { duplicate.save! }.not_to raise_error
    end

    it "allows two active shared pages with the same name" do
      shared_entity = create(:entity, :shared)
      shared_config = {
        "pages"    => [{ "id" => "page_1", "name" => "Page 1", "order" => 1, "fields" => [] }],
        "metadata" => { "entity_id" => shared_entity.id, "entity_name" => shared_entity.name }
      }.to_json

      described_class.create!(name: "Shared Form", configuration: shared_config, customer_id: nil)
      duplicate = described_class.new(name: "Shared Form", configuration: shared_config, customer_id: nil)
      expect(duplicate).to be_valid
      expect { duplicate.save! }.not_to raise_error
    end

    it "allows the same name under a different customer" do
      other_customer = create(:customer)
      other_entity   = create(:entity, customer: other_customer)
      other_config   = {
        "pages"    => [{ "id" => "page_1", "name" => "Page 1", "order" => 1, "fields" => [] }],
        "metadata" => { "entity_id" => other_entity.id, "entity_name" => other_entity.name }
      }.to_json

      described_class.create!(name: "Shared Name", configuration: minimal_configuration, customer: customer)
      other_page = build(:page, customer: other_customer)
      other_page.name = "Shared Name"
      other_page.configuration = other_config
      expect(other_page).to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Bug 3 — entity_id= writer
  # ---------------------------------------------------------------------------
  describe "entity_id= writer coercion" do
    it "stores nil (not 0) when assigned a non-numeric string" do
      page = described_class.new(name: "Coerce Test", customer: customer)
      page.entity_id = "abc"
      expect(page.entity_id).to be_nil
    end

    it "stores nil when assigned an empty string" do
      page = described_class.new(name: "Coerce Empty", customer: customer)
      page.entity_id = ""
      expect(page.entity_id).to be_nil
    end

    it "stores the integer when assigned a valid numeric string" do
      page = described_class.new(name: "Coerce Valid", customer: customer)
      page.entity_id = entity.id.to_s
      expect(page.entity_id).to eq(entity.id)
    end

    it "stores the integer when assigned an Integer directly" do
      page = described_class.new(name: "Coerce Int", customer: customer)
      page.entity_id = entity.id
      expect(page.entity_id).to eq(entity.id)
    end
  end

  # ---------------------------------------------------------------------------
  # Bug 1 — configuration_must_be_valid_json TypeError guard
  # ---------------------------------------------------------------------------
  describe "configuration_must_be_valid_json non-String guard" do
    it "adds a clean validation error when configuration returns a non-String" do
      # Simulate a non-String reaching the validator by stubbing the
      # configuration attribute reader to return a Hash (which JSON.parse
      # raises TypeError on). AR type-casting normally prevents this but
      # an explicitly assigned non-String via allow_any_instance_of covers
      # the defensive guard.
      page = described_class.new(name: "Hash Config", customer: customer)
      allow(page).to receive(:configuration).and_return({ "pages" => [] })
      page.valid?
      expect(page.errors[:configuration]).to include("must be a JSON string")
    end

    it "still catches ordinary invalid JSON strings" do
      page = build(:page, customer: customer, entity: entity)
      page.configuration = "not { valid json"
      page.valid?
      expect(page.errors[:configuration].first).to match(/must be valid JSON:/)
    end
  end
end
