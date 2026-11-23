# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::SurfaceSetting do
  let_it_be(:customer) { create(:customer) }

  before do
    Member::Surfaces::SourceRegistry.reset!
    klass = Class.new(Member::SurfaceSource) do
      def self.key ; :modules ; end
      def self.name ; "Modules" ; end
    end
    Member::Surfaces::SourceRegistry.register(klass)
  end

  after { Member::Surfaces::SourceRegistry.reset! }

  # A well-formed row for the default customer; override any attribute (or clear
  # one to nil) via a positional hash to exercise a specific validation.
  def new_setting(overrides = {})
    described_class.new({ customer: customer, surface_key: "payments", source_key: "modules" }.merge(overrides))
  end

  def create_setting(overrides = {})
    new_setting(overrides).tap(&:save!)
  end

  describe "validations" do
    it "requires surface_key" do
      record = new_setting(surface_key: nil)
      expect(record).not_to be_valid
      expect(record.errors[:surface_key]).to be_present
    end

    it "enforces uniqueness of [customer_id, surface_key]" do
      create_setting
      expect(new_setting).not_to be_valid
    end

    it "allows the same surface_key across different customers" do
      create_setting
      expect(new_setting(customer: create(:customer))).to be_valid
    end
  end

  describe "config JSON round-trip" do
    it "stores and reads label / icon / subtitle / per_page" do
      record = create_setting
      record.write_overlay(
        label: "Donations", icon: :heart, subtitle: "Past donations",
        per_page: 50,
        empty_headline: "No donations yet",
        empty_body:     "Once you donate it'll show up here."
      )
      record.save!
      record.reload

      expect(record.label_or("Payments")).to eq("Donations")
      expect(record.icon_or(:credit_card)).to eq(:heart)
      expect(record.subtitle_or("default")).to eq("Past donations")
      expect(record.per_page_or(20)).to eq(50)
      expect(record.empty_headline_or("default")).to eq("No donations yet")
      expect(record.empty_body_or("default")).to eq("Once you donate it'll show up here.")
    end

    it "falls back to defaults when not set" do
      record = create_setting
      expect(record.label_or("Payments")).to eq("Payments")
      expect(record.icon_or(:credit_card)).to eq(:credit_card)
      expect(record.per_page_or(20)).to eq(20)
    end

    it "stores and reads a row action overlay" do
      record = create_setting
      record.write_overlay(row_action_key: "enroll", row_action_field: "course", row_action_label: "Enroll")
      record.save!
      record.reload

      expect(record.row_action_or("Open")).to eq(
        action_key: "enroll", field: "course", label: "Enroll"
      )
    end

    it "falls back to the given default label when the overlay has no label" do
      record = create_setting
      record.write_overlay(row_action_key: "enroll", row_action_field: "course")
      record.save!

      expect(record.reload.row_action_or("Open")).to eq(
        action_key: "enroll", field: "course", label: "Open"
      )
    end

    it "returns nil from row_action_or when the pair is incomplete" do
      record = create_setting
      expect(record.row_action_or("Open")).to be_nil

      record.write_overlay(row_action_key: "enroll")
      record.save!
      expect(record.reload.row_action_or("Open")).to be_nil
    end

    it "stores visible_column_keys / visible_detail_row_keys / visible_section_keys as symbols" do
      record = create_setting
      record.write_overlay(
        visible_column_keys:     [:date, :amount],
        visible_detail_row_keys: [:amount, :vendor],
        visible_section_keys:    [:primary]
      )
      record.save!
      record.reload
      expect(record.visible_column_keys).to     eq([:date, :amount])
      expect(record.visible_detail_row_keys).to eq([:amount, :vendor])
      expect(record.visible_section_keys).to    eq([:primary])
    end

    it "distinguishes inheritance from hiding every optional column" do
      record = create_setting
      expect(record.visible_column_keys).to be_nil
      record.write_overlay(visible_column_keys: [])
      record.save!
      record.reload
      expect(record.visible_column_keys).to eq([])

      record.write_overlay(visible_column_keys: nil)
      record.save!
      expect(record.reload.visible_column_keys).to be_nil
      expect(record.config_json).not_to have_key("visible_column_keys")
    end

    it "keeps omitted overrides but removes explicitly blank display copy" do
      record = create_setting
      record.write_overlay(label: "Saved", subtitle: "Saved subtitle", empty_body: "Saved body")
      record.save!
      record.write_overlay(label: "", empty_body: nil)
      record.save!

      expect(record.reload.label_or("Default")).to eq("Default")
      expect(record.subtitle_or("Default")).to eq("Saved subtitle")
      expect(record.empty_body_or("Default")).to eq("Default")
      expect(record.config_json).not_to have_key("label")
      expect(record.config_json).not_to have_key("empty_body")
    end
  end

  describe "enabled_or" do
    it "inherits the given default when enabled is nil" do
      record = create_setting(enabled: nil)
      expect(record.enabled).to be_nil
      expect(record.enabled_or(true)).to be(true)
      expect(record.enabled_or(false)).to be(false)
    end

    it "returns a saved true or false instead of the default" do
      expect(create_setting(enabled: true).enabled_or(false)).to be(true)
      expect(create_setting(surface_key: "other", enabled: false).enabled_or(true)).to be(false)
    end
  end

  describe "position_or" do
    it "returns descriptor default when position is 0" do
      record = create_setting(position: 0)
      expect(record.position_or(30)).to eq(30)
    end

    it "returns the row's position when set" do
      record = create_setting(position: 50)
      expect(record.position_or(30)).to eq(50)
    end
  end

  describe ".for_customer_surface" do
    it "returns a new record when missing" do
      record = described_class.for_customer_surface(customer_id: customer.id, surface_key: :payments)
      expect(record).to be_new_record
      expect(record.customer_id).to eq(customer.id)
      expect(record.surface_key).to eq("payments")
    end

    it "returns existing record when present" do
      existing = create_setting
      found = described_class.for_customer_surface(customer_id: customer.id, surface_key: :payments)
      expect(found.id).to eq(existing.id)
    end
  end

  describe "source_key" do
    it "is valid when source_key matches a registered source" do
      expect(new_setting(source_key: "modules")).to be_valid
    end

    it "is invalid when source_key is not registered" do
      record = new_setting(source_key: "phantom")
      expect(record).not_to be_valid
      expect(record.errors[:source_key]).to be_present
    end

    it "is invalid when source_key is blank" do
      expect(new_setting(source_key: "")).not_to be_valid
    end
  end
end
