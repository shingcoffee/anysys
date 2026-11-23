# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::ComputedDefinition do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  let!(:student) { create(:entity, name: "Student", customer: customer) }
  let!(:klass) { create(:entity, name: "Class", customer: customer) }
  let!(:bridge) do
    create(:entity, name: "assoc_student_class", customer: customer, category: :bridge,
      property_schema: [
        { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "entity_id" => student.id.to_s },
        { "name" => "Class", "name_slug" => "class", "type" => "EntityReference", "entity_id" => klass.id.to_s },
        { "name" => "Score", "name_slug" => "score", "type" => "Float", "html_type" => "number" },
        { "name" => "Weight", "name_slug" => "weight", "type" => "Float", "html_type" => "range" },
        { "name" => "Status", "name_slug" => "status", "type" => "String", "html_type" => "text" }
      ].to_json)
  end

  def field(overrides = {})
    {
      "name" => "Average Score",
      "name_slug" => "average_score",
      "type" => "Computed",
      "config" => {
        "bridge_entity_id" => bridge.id,
        "bridge_role" => "source",
        "source_slug" => "score",
        "function" => "avg",
        "precision" => 2
      }.merge(overrides.delete("config") || {})
    }.merge(overrides.except("config"))
  end

  def resolve(overrides = {})
    described_class.resolve(field(overrides), student, customer_id: customer.id)
  end

  describe ".resolve" do
    it "uses bridge schema index 0 as the join slug when bridge_role is source" do
      definition = resolve
      expect(definition).to be_a(described_class)
      expect(definition.join_slug).to eq("student")
      expect(definition.source_slug).to eq("score")
      expect(definition.function).to eq("avg")
      expect(definition.bridge).to eq(bridge)
    end

    it "uses bridge schema index 1 as the join slug when bridge_role is target" do
      definition = resolve("config" => { "bridge_role" => "target" })
      expect(definition.join_slug).to eq("class")
    end

    it "returns nil for an unknown bridge_role" do
      expect(resolve("config" => { "bridge_role" => "both" })).to be_nil
    end

    it "returns nil when the bridge is missing" do
      expect(resolve("config" => { "bridge_entity_id" => 0 })).to be_nil
    end

    it "returns nil when the bridge belongs to another tenant" do
      foreign = create(:entity, name: "assoc_student_class", customer: other_customer, category: :bridge,
        property_schema: bridge.property_schema)
      expect(resolve("config" => { "bridge_entity_id" => foreign.id })).to be_nil
    end

    it "returns nil when the bridge is soft-deleted" do
      bridge.soft_delete
      expect(resolve).to be_nil
    end

    it "returns nil when config is not a Hash" do
      expect(described_class.resolve({ "name_slug" => "average_score", "config" => "nope" }, student, customer_id: customer.id)).to be_nil
      expect(described_class.resolve({ "name_slug" => "average_score" }, student, customer_id: customer.id)).to be_nil
      expect(described_class.resolve("not-a-hash", student, customer_id: customer.id)).to be_nil
    end

    it "returns nil for an unknown function" do
      expect(resolve("config" => { "function" => "median" })).to be_nil
    end

    it "clamps precision to 0..6" do
      expect(resolve("config" => { "precision" => 99 }).precision).to eq(6)
      expect(resolve("config" => { "precision" => -4 }).precision).to eq(0)
      expect(resolve("config" => { "precision" => 3 }).precision).to eq(3)
    end

    it "leaves precision nil when omitted" do
      config = field["config"].except("precision")
      definition = described_class.resolve(field.merge("config" => config), student, customer_id: customer.id)
      expect(definition.precision).to be_nil
    end

    it "drops an invalid filter and still resolves the computed" do
      definition = resolve("config" => { "filter" => { "slug" => "status", "op" => "LIKE", "value" => "done" } })
      expect(definition).to be_a(described_class)
      expect(definition.filter).to be_nil
    end

    it "drops a filter whose slug is not on the bridge and still resolves" do
      definition = resolve("config" => { "filter" => { "slug" => "missing", "op" => "=", "value" => "x" } })
      expect(definition).to be_a(described_class)
      expect(definition.filter).to be_nil
    end

    it "keeps a valid filter" do
      definition = resolve("config" => { "filter" => { "slug" => "status", "op" => "=", "value" => "completed" } })
      expect(definition.filter).to eq(slug: "status", op: "=", value: "completed", numeric: false)
    end
  end

  describe "#empty_default" do
    it "is nil for avg, min, and max" do
      %w[avg min max].each do |function|
        expect(resolve("config" => { "function" => function }).empty_default).to be_nil
      end
    end

    it "is 0 for sum and count" do
      expect(resolve("config" => { "function" => "sum" }).empty_default).to eq(0)
      expect(resolve("config" => { "function" => "count", "source_slug" => nil }).empty_default).to eq(0)
    end
  end

  describe "table_alias allowlist" do
    let(:definition) { resolve }
    let(:hostile) { "b; DROP TABLE entity_entries;--" }

    it "neutralizes a hostile alias in subquery_sql to b0" do
      sql = definition.subquery_sql(hostile)
      expect(sql).to include("entity_entries b0")
      expect(sql).to include("b0.entity_id")
      expect(sql).not_to include("DROP")
      expect(sql).not_to include(hostile)
    end

    it "neutralizes a hostile alias in aggregate_sql to b0" do
      sql = definition.aggregate_sql(hostile)
      expect(sql).to include("b0.data")
      expect(sql).not_to include("DROP")
      expect(sql).not_to include(hostile)
    end
  end

  describe "filter SQL" do
    def sql_for(filter)
      resolve("config" => { "filter" => filter })
    end

    it "emits CAST(... AS NUMERIC) and an unquoted numeric literal for a number attribute" do
      definition = sql_for({ "slug" => "score", "op" => ">", "value" => 50 })
      expect(definition.filter[:numeric]).to be true

      subquery = definition.subquery_sql("b0")
      [subquery].each do |sql|
        expect(sql).to include("CAST(json_extract(b0.data, '$.score') AS NUMERIC) > 50.0")
        expect(sql).not_to include("'50")
      end
    end

    it "emits the quoted-text form with no CAST for a text attribute" do
      definition = sql_for({ "slug" => "status", "op" => "=", "value" => "completed" })
      expect(definition.filter[:numeric]).to be false

      subquery = definition.subquery_sql("b0")
      expect(subquery).to include("json_extract(b0.data, '$.status') = 'completed'")
      expect(subquery).not_to include("CAST(json_extract(b0.data, '$.status')")
    end

    it "treats a range attribute as numeric" do
      definition = sql_for({ "slug" => "weight", "op" => ">=", "value" => "1.5" })
      expect(definition.filter[:numeric]).to be true
      expect(definition.subquery_sql("b0")).to include("CAST(json_extract(b0.data, '$.weight') AS NUMERIC) >= 1.5")
    end

    it "coerces a non-numeric value on a numeric attribute via to_f rather than injecting" do
      definition = sql_for({ "slug" => "score", "op" => ">", "value" => "50-injected; DROP TABLE entity_entries" })
      sql = definition.subquery_sql("b0")
      expect(sql).to include("CAST(json_extract(b0.data, '$.score') AS NUMERIC) > 50.0")
      expect(sql).not_to include("DROP")
      expect(sql).not_to include("injected")
    end

    it "never lets a hostile filter value escape the literal on either branch" do
      hostile = "1' OR '1'='1"

      numeric_sql = sql_for({ "slug" => "score", "op" => ">", "value" => hostile }).subquery_sql("b0")
      expect(numeric_sql).to include("CAST(json_extract(b0.data, '$.score') AS NUMERIC) > 1.0")
      expect(numeric_sql).not_to include("OR")

      text_sql = sql_for({ "slug" => "status", "op" => "=", "value" => hostile }).subquery_sql("b0")
      expect(text_sql).to include(ActiveRecord::Base.connection.quote(hostile))
      expect(text_sql).not_to include("= '1' OR '1'='1'")
    end

    it "drops the filter and keeps the computed for an unknown slug or an operator outside FILTER_OPS" do
      unknown = resolve("config" => { "filter" => { "slug" => "missing", "op" => "=", "value" => 1 } })
      expect(unknown).to be_a(described_class)
      expect(unknown.filter).to be_nil
      expect(unknown.subquery_sql("b0")).to include("CAST(entity_entries.id AS TEXT)")
      expect(unknown.subquery_sql("b0")).not_to include("'$.missing'")

      bad_op = resolve("config" => { "filter" => { "slug" => "score", "op" => "LIKE", "value" => 50 } })
      expect(bad_op).to be_a(described_class)
      expect(bad_op.filter).to be_nil
      expect(bad_op.subquery_sql("b0")).not_to include("LIKE")
    end
  end
end
