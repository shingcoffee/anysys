# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::FormulaCompiler do
  let(:schema_fields) do
    [
      { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" },
      { "name" => "Quantity", "name_slug" => "quantity", "type" => "Integer", "html_type" => "number" },
      { "name" => "Name", "name_slug" => "name", "type" => "String", "html_type" => "text" },
      { "name" => "Email", "name_slug" => "email", "type" => "String", "html_type" => "email" }
    ]
  end

  describe ".compile" do
    context "field references" do
      it "translates numeric field to CAST json_extract" do
        sql = described_class.compile("price", schema_fields)
        expect(sql).to eq("CAST(json_extract(entity_entries.data, '$.price') AS NUMERIC)")
      end

      it "translates string field to plain json_extract" do
        sql = described_class.compile("name", schema_fields)
        expect(sql).to eq("json_extract(entity_entries.data, '$.name')")
      end
    end

    context "arithmetic" do
      it "compiles multiplication" do
        sql = described_class.compile("price * quantity", schema_fields)
        expect(sql).to include("*")
        expect(sql).to include("json_extract(entity_entries.data, '$.price')")
        expect(sql).to include("json_extract(entity_entries.data, '$.quantity')")
      end

      it "compiles addition with literal" do
        sql = described_class.compile("price + 10", schema_fields)
        expect(sql).to include("+")
        expect(sql).to include("10")
      end

      it "compiles subtraction" do
        sql = described_class.compile("price - 5", schema_fields)
        expect(sql).to include("-")
        expect(sql).to include("5")
      end

      it "compiles parenthesized expressions" do
        sql = described_class.compile("(price + 5) * quantity", schema_fields)
        expect(sql).to include("(")
        expect(sql).to include(")")
      end
    end

    context "string concatenation" do
      it "compiles string field addition with + operator" do
        sql = described_class.compile("name + email", schema_fields)
        expect(sql).to include("+")
        expect(sql).to include("json_extract(entity_entries.data, '$.name')")
        expect(sql).to include("json_extract(entity_entries.data, '$.email')")
      end
    end

    context "literals" do
      it "passes through integer literals" do
        sql = described_class.compile("42", schema_fields)
        expect(sql).to eq("42")
      end

      it "passes through float literals" do
        sql = described_class.compile("3.14", schema_fields)
        expect(sql).to eq("3.14")
      end

      it "converts double-quoted strings to single-quoted SQL strings" do
        sql = described_class.compile("\"hello\"", schema_fields)
        expect(sql).to eq("'hello'")
      end
    end

    context "functions" do
      it("compiles ROUND") { expect(described_class.compile("ROUND(price, 2)", schema_fields)).to include("ROUND(") }
      it("compiles ABS") { expect(described_class.compile("ABS(price)", schema_fields)).to include("ABS(") }
      it("compiles COALESCE") { expect(described_class.compile("COALESCE(price, 0)", schema_fields)).to include("COALESCE(") }
      it("compiles UPPER") { expect(described_class.compile("UPPER(name)", schema_fields)).to include("UPPER(") }
      it("compiles LOWER") { expect(described_class.compile("LOWER(name)", schema_fields)).to include("LOWER(") }
      it("compiles LENGTH") { expect(described_class.compile("LENGTH(name)", schema_fields)).to include("LENGTH(") }
    end

    context "error handling" do
      it "raises FormulaError for unknown field" do
        expect { described_class.compile("unknown * 2", schema_fields) }.to raise_error(FlowchartRuntime::FormulaError, /Unknown field/)
      end

      it "returns nil for nil formula" do
        expect(described_class.compile(nil, schema_fields)).to be_nil
      end

      it "returns nil for blank formula" do
        expect(described_class.compile("", schema_fields)).to be_nil
      end
    end
  end

  describe ".compile_all" do
    let(:chained_schema) do
      [
        { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" },
        { "name" => "Quantity", "name_slug" => "quantity", "type" => "Integer", "html_type" => "number" },
        { "name" => "Subtotal", "name_slug" => "subtotal", "type" => "Calculated", "html_type" => "number",
          "readonly" => true, "storage" => "computed", "formula" => "price * quantity" },
        { "name" => "Tax", "name_slug" => "tax", "type" => "Calculated", "html_type" => "number",
          "readonly" => true, "storage" => "computed", "formula" => "subtotal * 0.1" },
        { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number",
          "readonly" => true, "storage" => "computed", "formula" => "subtotal + tax" }
      ]
    end

    it "compiles in dependency order" do
      result = described_class.compile_all(chained_schema)
      expect(result.map { |r| r[:name] }).to eq(%w[subtotal tax total])
    end

    it "resolves chained references" do
      result = described_class.compile_all(chained_schema)
      tax_sql = result.find { |r| r[:name] == "tax" }[:sql]
      expect(tax_sql).to include("json_extract")
      expect(tax_sql).to include("0.1")
    end

    it "returns empty array when no calculated fields" do
      expect(described_class.compile_all([{ "name" => "X", "name_slug" => "x", "type" => "Float", "html_type" => "number" }])).to eq([])
    end

    it "detects circular dependencies" do
      circular = [
        { "name" => "A", "name_slug" => "a", "type" => "Calculated", "html_type" => "number", "formula" => "b + 1" },
        { "name" => "B", "name_slug" => "b", "type" => "Calculated", "html_type" => "number", "formula" => "a + 1" }
      ]
      expect { described_class.compile_all(circular) }.to raise_error(FlowchartRuntime::FormulaError, /Circular dependency/)
    end

    it "detects a direct self-cycle" do
      self_cycle = [
        { "name" => "A", "name_slug" => "a", "type" => "Calculated", "html_type" => "number", "formula" => "a + 1" }
      ]

      expect { described_class.compile_all(self_cycle) }
        .to raise_error(FlowchartRuntime::FormulaError, /Circular dependency/)
    end

    it "nests a computed subquery when compile_all is seeded with resolved:" do
      subquery = "(SELECT ROUND(AVG(CAST(json_extract(b0.data, '$.score') AS NUMERIC)), 2) FROM entity_entries b0 WHERE b0.entity_id = 15)"
      schema = [
        { "name" => "Average Score", "name_slug" => "average_score", "type" => "Computed", "html_type" => "number" },
        { "name" => "Weighted", "name_slug" => "weighted", "type" => "Calculated", "html_type" => "number",
          "formula" => "average_score * 2" }
      ]

      result = described_class.compile_all(schema, resolved: { "average_score" => subquery })
      expect(result.map { |r| r[:name] }).to eq(["weighted"])
      expect(result.first[:sql]).to include(subquery)
    end

    it "emits byte-identical SQL when resolved defaults to {}" do
      expect(described_class.compile_all(chained_schema, resolved: {})).to eq(described_class.compile_all(chained_schema))
    end
  end
end
