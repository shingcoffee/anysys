# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Collections do
  describe ".dig_item on records" do
    let(:customer) { create(:customer) }
    let(:entity) do
      create(:entity, customer: customer, property_schema: [
        { "name" => "Status", "name_slug" => "status", "data_type" => "string" },
        { "name" => "Meta", "name_slug" => "meta", "data_type" => "string" }
      ].to_json)
    end
    let(:records) do
      [{ "status" => "open", "meta" => { "tier" => "gold" } }, { "status" => "closed" }].map do |data|
        entry = create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: data)
        EntityEntry.build_for(entity).find(entry.id)
      end
    end

    it "reads entry data fields, id and nested values via flowchart_value without calling arbitrary methods" do
      expect(described_class.dig_item(records.first, "status")).to eq("open")
      expect(described_class.dig_item(records.first, "meta.tier")).to eq("gold")
      expect(described_class.dig_item(records.first, "id")).to eq(records.first.id)
      expect(described_class.dig_item(records.first, "destroy")).to be_nil
      expect(records.first).not_to be_destroyed
    end

    it "filters and sorts records by a data field" do
      expect(described_class.filter(records, returns: "items", field: "status", compare: "closed")).to eq([records.last])
      expect(described_class.sort(records, field: "status").map(&:status)).to eq(%w[closed open])
    end
  end

  describe ".filter" do
    let(:items) { [{ status: "active" }, { status: "draft" }, { status: "active" }] }

    it "returns matching items" do
      expect(described_class.filter(items, returns: "items", field: "status", compare: "active"))
        .to eq([items[0], items[2]])
    end

    it "splits matches from rejects" do
      expect(described_class.filter(items, returns: "split", field: "status", compare: "active"))
        .to eq([[items[0], items[2]], [items[1]]])
    end

    it "returns first, last, index, count, any, all, and none" do
      expect(described_class.filter(items, returns: "first", field: "status", compare: "active")).to eq(items[0])
      expect(described_class.filter(items, returns: "last", field: "status", compare: "active")).to eq(items[2])
      expect(described_class.filter(items, returns: "index", field: "status", compare: "draft")).to eq(1)
      expect(described_class.filter(items, returns: "count", field: "status", compare: "active")).to eq(2)
      expect(described_class.filter(items, returns: "any", field: "status", compare: "draft")).to eq(true)
      expect(described_class.filter(items, returns: "all", field: "status", compare: "active")).to eq(false)
      expect(described_class.filter(items, returns: "none", field: "status", compare: "gone")).to eq(true)
    end

    it "raises for an unknown returns value" do
      expect { described_class.filter([], returns: "bogus") }.to raise_error(described_class::Error)
    end

    it "limits matched items" do
      expect(described_class.filter(items, returns: "items", field: "status", compare: "active", limit: 1))
        .to eq([items[0]])
    end
  end

  describe ".aggregate" do
    let(:items) { [{ amount: 10 }, { amount: 4 }] }

    it "sums, counts, averages, and multiplies" do
      expect(described_class.aggregate(items, operation: "sum", field: "amount")).to eq(14)
      expect(described_class.aggregate(items, operation: "count")).to eq(2)
      expect(described_class.aggregate(items, operation: "avg", field: "amount")).to eq(7.0)
      expect(described_class.aggregate(items, operation: "product", field: "amount")).to eq(40)
    end

    it "returns zero for an empty collection" do
      expect(described_class.aggregate([], operation: "sum")).to eq(0)
    end
  end

  describe ".random" do
    it "returns a uuid string" do
      expect(described_class.random("uuid")).to match(/\A[0-9a-f-]{36}\z/)
    end

    it "raises for an unknown type" do
      expect { described_class.random("bogus") }.to raise_error(described_class::Error)
    end
  end

  describe ".first_present_from_ctx" do
    it "returns the first non-blank context path" do
      ctx = { preferred_name: "", name: "Ada" }
      expect(described_class.first_present_from_ctx(ctx, %w[preferred_name name], literals: ["Anonymous"]))
        .to eq("Ada")
    end
  end

  describe "manipulate helpers" do
    let(:items) { [{ name: "Ada", category: "a" }, { name: "Bob", category: "b" }] }

    it "maps, plucks, groups, sorts, uniques, chunks, flattens, and zips" do
      expect(described_class.map(items, mappings: { "name" => "label" }))
        .to eq([{ label: "Ada" }, { label: "Bob" }])
      expect(described_class.pluck(items, fields: { "name" => "name" }, flatten: true)).to eq(%w[Ada Bob])
      expect(described_class.group(items, field: "category").keys).to contain_exactly("a", "b")
      expect(described_class.sort(items, field: "name", direction: "desc").map { |row| row[:name] }).to eq(%w[Bob Ada])
      expect(described_class.unique(items + [items[0]], field: "name").map { |row| row[:name] }).to eq(%w[Ada Bob])
      expect(described_class.chunk(items, size: 1).size).to eq(2)
      expect(described_class.flatten([[1], [2]], depth: 1)).to eq([1, 2])
      expect(described_class.zip([[1, 2], %w[a b c]], strategy: "shortest")).to eq([[1, "a"], [2, "b"]])
    end
  end
end
