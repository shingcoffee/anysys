# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::ComputedCompiler do
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
        { "name" => "Status", "name_slug" => "status", "type" => "String", "html_type" => "text" }
      ].to_json)
  end

  def field(function:, role: "source", source_slug: "score", precision: 2, filter: nil, **extra)
    config = {
      "bridge_entity_id" => bridge.id,
      "bridge_role" => role,
      "source_slug" => source_slug,
      "function" => function,
      "precision" => precision
    }.merge(extra)
    config["filter"] = filter if filter
    {
      "name" => function.titleize,
      "name_slug" => function,
      "type" => "Computed",
      "config" => config
    }
  end

  def compile(computed_field, **kwargs)
    described_class.compile(computed_field, student, customer_id: customer.id, **kwargs)
  end

  def join_predicate(table_alias, slug)
    "json_extract(#{table_alias}.data, '$.#{slug}') = CAST(entity_entries.id AS TEXT)"
  end

  describe ".compile" do
    it "emits golden SQL for avg" do
      sql = compile(field(function: "avg"))
      expect(sql).to eq(
        "(SELECT ROUND(AVG(CAST(json_extract(b0.data, '$.score') AS NUMERIC)), 2) " \
        "FROM entity_entries b0 " \
        "WHERE b0.entity_id = #{bridge.id} " \
        "AND b0.customer_id = #{customer.id} " \
        "AND #{join_predicate('b0', 'student')} )"
      )
    end

    it "emits golden SQL for sum with COALESCE" do
      sql = compile(field(function: "sum"))
      expect(sql).to include("COALESCE(SUM(CAST(json_extract(b0.data, '$.score') AS NUMERIC)), 0)")
      expect(sql).to include("ROUND(")
      expect(sql).to include("b0.customer_id = #{customer.id}")
    end

    it "emits golden SQL for min" do
      sql = compile(field(function: "min"))
      expect(sql).to include("ROUND(MIN(CAST(json_extract(b0.data, '$.score') AS NUMERIC)), 2)")
    end

    it "emits golden SQL for max" do
      sql = compile(field(function: "max"))
      expect(sql).to include("ROUND(MAX(CAST(json_extract(b0.data, '$.score') AS NUMERIC)), 2)")
    end

    it "emits COUNT(json_extract) when count has a source_slug" do
      sql = compile(field(function: "count", source_slug: "score"))
      expect(sql).to include("COUNT(json_extract(b0.data, '$.score'))")
      expect(sql).not_to include("ROUND(")
    end

    it "emits COUNT(*) when count has a blank source_slug" do
      sql = compile(field(function: "count", source_slug: ""))
      expect(sql).to include("COUNT(*)")
      expect(sql).not_to include("ROUND(")
    end

    it "never wraps count in ROUND even when precision is present" do
      sql = compile(field(function: "count", source_slug: "", precision: 4))
      expect(sql).not_to include("ROUND(")
    end

    it "applies ROUND for avg/sum/min/max and never for count" do
      %w[avg sum min max].each do |function|
        expect(compile(field(function: function))).to include("ROUND(")
      end
      expect(compile(field(function: "count", source_slug: ""))).not_to include("ROUND(")
    end

    it "joins on the source slug when bridge_role is source" do
      sql = compile(field(function: "avg", role: "source"))
      expect(sql).to include(join_predicate("b0", "student"))
      expect(sql).not_to include("'$.class'")
    end

    it "joins on the target slug when bridge_role is target" do
      sql = compile(field(function: "avg", role: "target"))
      expect(sql).to include(join_predicate("b0", "class"))
      expect(sql).not_to include("'$.student'")
    end

    it "uses the exact join predicate shape" do
      sql = compile(field(function: "avg"))
      expect(sql).to include("json_extract(b0.data, '$.student') = CAST(entity_entries.id AS TEXT)")
    end

    it "includes customer_id in every emitted subquery" do
      %w[avg sum count min max].each do |function|
        sql = compile(field(function: function, source_slug: function == "count" ? "" : "score"))
        expect(sql).to include("b0.customer_id = #{customer.id}")
      end
    end

    it "applies a valid filter as a bound/quoted predicate" do
      sql = compile(field(function: "avg", filter: { "slug" => "status", "op" => "=", "value" => "completed" }))
      expect(sql).to include("AND json_extract(b0.data, '$.status') = 'completed'")
    end

    it "drops an invalid filter and still emits the computed" do
      sql = compile(field(function: "avg", filter: { "slug" => "status", "op" => "LIKE", "value" => "done" }))
      expect(sql).to be_present
      expect(sql).not_to include("LIKE")
      expect(sql).to include(join_predicate("b0", "student"))
    end

    it "quotes a hostile filter value instead of interpolating it" do
      sql = compile(field(function: "avg", filter: { "slug" => "status", "op" => "=", "value" => "' OR 1=1 --" }))
      expect(sql).to include(ActiveRecord::Base.connection.quote("' OR 1=1 --"))
      expect(sql).not_to include("= ' OR 1=1 --")
    end

    it "returns nil and never raises for injection attempts in slugs, role, and function" do
      hostile = [
        field(function: "avg); DROP TABLE entity_entries;--"),
        field(function: "avg", role: "source; DROP"),
        field(function: "avg", source_slug: "score'); DROP TABLE entity_entries;--"),
        { "config" => "not-a-hash" },
        { "config" => { "function" => "avg" } },
        nil,
        "nope"
      ]

      hostile.each do |computed_field|
        sql = nil
        expect { sql = compile(computed_field) }.not_to raise_error
        expect(sql).to be_nil
      end
    end

    it "drops a hostile filter and still emits the computed without raising" do
      sql = nil
      expect {
        sql = compile(field(function: "avg", filter: { "slug" => "status'); DROP", "op" => "=", "value" => "x" }))
      }.not_to raise_error
      expect(sql).to include(join_predicate("b0", "student"))
      expect(sql).not_to include("DROP")

      expect {
        sql = compile(field(function: "avg", filter: { "slug" => "status", "op" => "=; DROP", "value" => "x" }))
      }.not_to raise_error
      expect(sql).to include(join_predicate("b0", "student"))
      expect(sql).not_to include("DROP")
    end

    it "returns nil for a missing, soft-deleted, or cross-tenant bridge and never raises" do
      missing = compile(field(function: "avg", "bridge_entity_id" => 0))
      expect(missing).to be_nil

      foreign = create(:entity, name: "assoc_student_class", customer: other_customer, category: :bridge,
        property_schema: bridge.property_schema)
      expect { expect(compile(field(function: "avg", "bridge_entity_id" => foreign.id))).to be_nil }.not_to raise_error

      bridge.soft_delete
      expect { expect(compile(field(function: "avg"))).to be_nil }.not_to raise_error
    end
  end

  describe ".compile_all" do
    it "assigns unique table aliases b0, b1 when an entity has two computed fields" do
      student.property_schema_json = [
        field(function: "avg").merge("name_slug" => "average_score"),
        field(function: "sum").merge("name_slug" => "total_score")
      ]
      student.save(validate: false)

      result = described_class.compile_all(student, customer_id: customer.id)
      expect(result.map { |r| r[:name] }).to eq(%w[average_score total_score])
      expect(result[0][:sql]).to include("entity_entries b0")
      expect(result[0][:sql]).to include(join_predicate("b0", "student"))
      expect(result[1][:sql]).to include("entity_entries b1")
      expect(result[1][:sql]).to include(join_predicate("b1", "student"))
      expect(result[0][:sql]).not_to include("entity_entries b1")
      expect(result[1][:sql]).not_to include("entity_entries b0")
      result.each { |row| expect(row[:sql]).to include("customer_id = #{customer.id}") }
    end

    it "never raises for a nil entity or malformed fields" do
      expect { described_class.compile_all(nil, customer_id: customer.id) }.not_to raise_error
      expect(described_class.compile_all(nil, customer_id: customer.id)).to eq([])

      student.property_schema_json = [
        { "name_slug" => "broken", "type" => "Computed", "config" => "nope" },
        field(function: "avg").merge("name_slug" => "average_score")
      ]
      student.save(validate: false)

      result = nil
      expect { result = described_class.compile_all(student, customer_id: customer.id) }.not_to raise_error
      expect(result).to contain_exactly(
        { name: "broken", sql: nil, definition: nil },
        hash_including(name: "average_score")
      )
      expect(result.find { |r| r[:name] == "average_score" }[:sql]).to include("b1")
    end
  end
end
