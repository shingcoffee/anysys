# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entries::Save do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Title", "name_slug" => "title", "type" => "String", "html_type" => "text" },
      { "name" => "Notes", "name_slug" => "notes", "type" => "String", "html_type" => "text" }
    ].to_json)
  end

  def contract_for(model, input)
    EntityEntryContract.build_for(entity, audience: "admin", writable_slugs: input.keys).new(model)
                       .tap { |contract| expect(contract.validate(input)).to be(true) }
  end

  def new_entry = EntityEntry.build_for(entity).new(entity: entity, customer_id: customer.id)
  def count = EntityEntry.where(entity_id: entity.id).count

  it "persists a new entry from a validated contract" do
    result = described_class.call(contract: contract_for(new_entry, "title" => "Hi"), audience: "admin")

    expect(result).to be_ok
    expect(result.entry).to be_persisted
    expect(result.entry.reload.title).to eq("Hi")
    expect(result.errors).to eq([])
    expect(result.field_errors).to eq([])
  end

  it "updates an existing entry" do
    entry = new_entry.tap { |record| record.title = "A"; record.save! }
    persisted = EntityEntry.build_for(entity).find(entry.id)

    result = described_class.call(contract: contract_for(persisted, "title" => "B", "notes" => "Later"), audience: "admin")

    expect(result).to be_ok
    expect(result.entry.reload).to have_attributes(title: "B", notes: "Later")
  end

  it "persists a record already changed in place through Written" do
    entry = new_entry
    entry.title = "In place"

    result = described_class.call(contract: described_class::Written.new(entry), audience: "admin")

    expect(result).to be_ok
    expect(result.entry.reload.title).to eq("In place")
  end

  it "rolls back when the record cannot be saved and reports field errors" do
    model = new_entry
    contract = contract_for(model, "title" => "Hi")
    allow(model).to receive(:save) do
      model.errors.add(:title, :invalid)
      false
    end

    result = nil
    expect { result = described_class.call(contract: contract, audience: "admin") }.not_to(change { count })
    expect(result).not_to be_ok
    expect(result.entry).to be_nil
    expect(result.errors).to eq(model.errors.full_messages)
    expect(result.field_errors.map(&:field)).to include("title")
  end

  it "collects RecordInvalid messages without leaving a persisted row" do
    model = new_entry
    contract = contract_for(model, "title" => "Hi")
    allow(model).to receive(:save) do
      model.errors.add(:title, :invalid)
      raise ActiveRecord::RecordInvalid, model
    end

    result = nil
    expect { result = described_class.call(contract: contract, audience: "admin") }.not_to(change { count })
    expect(result).not_to be_ok
    expect(result.entry).to be_nil
    expect(result.errors).to eq(model.errors.full_messages)
  end

  it "requires a known audience" do
    expect { described_class.call(contract: described_class::Written.new(new_entry)) }.to raise_error(ArgumentError)
    expect { described_class.call(contract: described_class::Written.new(new_entry), audience: "guest") }
      .to raise_error(ArgumentError, /guest/)
  end

  context "with a status lifecycle" do
    let(:entity) do
      create(:entity, customer: customer, property_schema: [
        { "name" => "Title", "name_slug" => "title", "type" => "String", "html_type" => "text" },
        { "name" => "Status", "name_slug" => "status", "type" => "String", "html_type" => "select",
          "config" => { "source" => "manual", "options" => [
            { "label" => "Draft", "value" => "draft", "default" => true },
            { "label" => "Submitted", "value" => "submitted" },
            { "label" => "Approved", "value" => "approved" }
          ] },
          "lifecycle" => { "transitions" => [
            { "from" => "draft", "to" => "submitted", "by" => %w[member public] },
            { "from" => "submitted", "to" => "approved", "by" => %w[admin] }
          ] } }
      ].to_json)
    end

    def saved(status)
      entry = new_entry.tap { |record| record.title = "T"; record.status = status; record.save! }
      EntityEntry.build_for(entity).find(entry.id)
    end

    def write(entry, status, audience)
      entry.status = status
      described_class.call(contract: described_class::Written.new(entry), audience: audience)
    end

    it "creates a record at the initial state for any audience" do
      expect(write(new_entry, "draft", "system")).to be_ok
    end

    it "lets the submit that creates a record take one allowed step" do
      result = write(new_entry, "submitted", "public")

      expect(result).to be_ok
      expect(result.entry.reload.data_json["status"]).to eq("submitted")
    end

    it "refuses creating a record further along than one allowed step" do
      result = nil
      expect { result = write(new_entry, "approved", "admin") }.not_to(change { count })

      expect(result).not_to be_ok
      expect(result.errors).to eq(["Status can't move from Draft to Approved"])
      expect(result.field_errors.map { |error| [error.field, error.message] })
        .to eq([["status", "can't move from Draft to Approved"]])
    end

    it "saves a change the audience may make" do
      entry = saved("submitted")

      expect(write(entry, "approved", "admin")).to be_ok
      expect(entry.reload.data_json["status"]).to eq("approved")
    end

    it "refuses the same change for another audience and leaves the stored value" do
      entry = saved("submitted")
      result = write(entry, "approved", "member")

      expect(result).not_to be_ok
      expect(result.entry).to be_nil
      expect(result.field_errors.map(&:field)).to eq(["status"])
      expect(EntityEntry.build_for(entity).find(entry.id).data_json["status"]).to eq("submitted")
    end

    it "moves a legacy record without a status off the initial state" do
      entry = saved(nil)

      expect(write(entry, "submitted", "member")).to be_ok
    end

    it "saves other fields while the status stays put" do
      entry = saved("approved")
      entry.title = "Renamed"

      expect(described_class.call(contract: described_class::Written.new(entry), audience: "public")).to be_ok
    end

    it "refuses clearing the status" do
      result = write(saved("submitted"), "", "admin")

      expect(result.field_errors.map(&:message)).to eq(["can't be cleared once it is Submitted"])
    end
  end
end
