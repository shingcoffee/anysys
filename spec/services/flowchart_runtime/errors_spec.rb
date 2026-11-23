# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Errors do
  def model_with(*messages)
    errors = instance_double(ActiveModel::Errors, full_messages: messages)
    Object.new.tap { |record| record.define_singleton_method(:errors) { errors } }
  end

  it "returns [] for an empty ctx" do
    expect(described_class.collect({})).to eq([])
  end

  it "keeps pre-existing ctx[:errors] first and de-duplicates later messages" do
    contract = model_with("Name can't be blank", "taken")
    ctx = { errors: ["taken", "child failed"], contract: contract }

    expect(described_class.collect(ctx)).to eq(["taken", "child failed", "Name can't be blank"])
  end

  it "collects Reform/AR full_messages from every top-level ctx value" do
    contract = model_with("Email can't be blank")
    record = model_with("Age is not a number")
    ctx = { contract: contract, model: record }

    expect(described_class.collect(ctx)).to eq(["Email can't be blank", "Age is not a number"])
  end

  it "does not copy a bare string diagnostic into the collected messages" do
    ctx = { diagnostic: "Kernel.raise leaked", errors: ["visible"] }

    expect(described_class.collect(ctx)).to eq(["visible"])
  end

  it "ignores values that do not expose errors.full_messages" do
    ctx = { token: "abc", count: 1, errors: nil }

    expect(described_class.collect(ctx)).to eq([])
  end

  it "drops blank and non-string entries of ctx[:errors]" do
    expect(described_class.collect(errors: ["kept", "", "  ", nil, 42])).to eq(["kept"])
  end

  describe ".fields" do
    let(:entity) do
      create(:entity, property_schema: [{ "name" => "Title", "name_slug" => "title", "validators" => [{ "type" => "presence" }] }].to_json)
    end

    it "keys a failed step's message by its field" do
      ctx = {}
      FlowchartRuntime::Step.fail_message(ctx, { "en" => "Pick another title" }, field: "title")
      FlowchartRuntime::Step.fail_message(ctx, { "en" => "Closed today" })

      expect(described_class.fields(ctx)).to eq([
        described_class::Field.new(field: "title", message: "Pick another title", full_message: "Pick another title")
      ])
    end

    it "keys a contract's errors by attribute with their collected full message" do
      contract = EntityEntryContract.build_for(entity).new(EntityEntry.build_for(entity).new(entity: entity, data: "{}"))
      contract.validate("title" => "")

      expect(described_class.fields(contract: contract))
        .to eq([described_class::Field.new(field: "title", message: "can't be blank", full_message: "Title can't be blank")])
      expect(described_class.collect(contract: contract)).to eq(["Title can't be blank"])
    end

    it "never treats base errors as a field" do
      record = EntityEntry.new
      record.errors.add(:base, "Not allowed")

      expect(described_class.of(record.errors)).to eq([])
    end
  end
end
