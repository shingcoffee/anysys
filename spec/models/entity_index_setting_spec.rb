# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityIndexSetting, type: :model do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:entity) { create(:entity, customer: customer) }

  describe ".for" do
    it "returns an unsaved record when none exists" do
      setting = described_class.for(customer_id: customer.id, entity_id: entity.id)
      expect(setting).to be_new_record
      expect(setting.customer_id).to eq(customer.id)
      expect(setting.entity_id).to eq(entity.id)
    end

    it "returns the existing row" do
      existing = described_class.create!(customer_id: customer.id, entity_id: entity.id, config: {})
      expect(described_class.for(customer_id: customer.id, entity_id: entity.id)).to eq(existing)
    end
  end

  describe "#visible_column_keys" do
    it "returns nil when the key is absent (defaults)" do
      setting = described_class.new(config: {}.to_json)
      expect(setting.visible_column_keys).to be_nil
    end

    it "returns [] when the key is explicitly empty" do
      setting = described_class.new(config: { "visible_column_keys" => [] }.to_json)
      expect(setting.visible_column_keys).to eq([])
    end

    it "returns symbols when keys are present" do
      setting = described_class.new(config: { "visible_column_keys" => %w[title status] }.to_json)
      expect(setting.visible_column_keys).to eq(%i[title status])
    end
  end

  describe "#write_overlay" do
    it "persists string keys including empty array" do
      setting = described_class.for(customer_id: customer.id, entity_id: entity.id)
      setting.write_overlay(visible_column_keys: [])
      setting.save!
      expect(setting.reload.visible_column_keys).to eq([])
    end
  end

  describe "#per_page" do
    it "returns nil when the key is absent (defaults)" do
      setting = described_class.new(config: {}.to_json)
      expect(setting.per_page).to be_nil
    end

    it "returns an integer when the key is present" do
      setting = described_class.new(config: { "per_page" => 50 }.to_json)
      expect(setting.per_page).to eq(50)
    end

    it "returns nil for an out-of-range stored value" do
      setting = described_class.new(config: { "per_page" => 999_999 }.to_json)
      expect(setting.per_page).to be_nil
    end
  end

  describe "#density" do
    it "returns nil when the key is absent (defaults)" do
      setting = described_class.new(config: {}.to_json)
      expect(setting.density).to be_nil
    end

    it "returns the stored string when present" do
      setting = described_class.new(config: { "density" => "compact" }.to_json)
      expect(setting.density).to eq("compact")
    end
  end

  describe "#write_list_prefs" do
    it "persists per_page and density" do
      setting = described_class.for(customer_id: customer.id, entity_id: entity.id)
      setting.write_list_prefs(per_page: 25, density: "comfortable")
      setting.save!
      setting.reload
      expect(setting.per_page).to eq(25)
      expect(setting.density).to eq("comfortable")
    end

    it "writes only provided keys" do
      setting = described_class.for(customer_id: customer.id, entity_id: entity.id)
      setting.write_list_prefs(per_page: 10, density: "compact")
      setting.save!
      setting.write_list_prefs(per_page: 50)
      setting.save!
      expect(setting.reload.per_page).to eq(50)
      expect(setting.density).to eq("compact")
    end

    it "does not touch visible_column_keys" do
      setting = described_class.for(customer_id: customer.id, entity_id: entity.id)
      setting.write_overlay(visible_column_keys: %i[title status])
      setting.write_list_prefs(per_page: 25, density: "compact")
      setting.save!
      expect(setting.reload.visible_column_keys).to eq(%i[title status])
    end

    it "ignores an unbounded per_page and an unknown density" do
      setting = described_class.for(customer_id: customer.id, entity_id: entity.id)
      setting.write_list_prefs(per_page: 25, density: "compact")
      setting.write_list_prefs(per_page: 999_999, density: "huge")
      setting.save!
      expect(setting.reload.per_page).to eq(25)
      expect(setting.density).to eq("compact")
    end
  end

  it "enforces uniqueness on [customer_id, entity_id]" do
    described_class.create!(customer_id: customer.id, entity_id: entity.id, config: {})
    dup = described_class.new(customer_id: customer.id, entity_id: entity.id, config: {})
    expect(dup).not_to be_valid
  end
end
