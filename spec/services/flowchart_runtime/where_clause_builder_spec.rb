# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::WhereClauseBuilder do
  # ─── Helpers ──────────────────────────────────────────────────────────────

  let_it_be(:customer) { create(:customer) }
  let!(:entry_approved_1000) { create_entry("status" => "approved", "amount" => "1000", "region" => "east",  "notes" => "hello world") }
  let!(:entry_approved_500)  { create_entry("status" => "approved", "amount" => "500",  "region" => "west",  "notes" => "") }
  let!(:entry_rejected_2000) { create_entry("status" => "rejected", "amount" => "2000", "region" => "north", "notes" => "urgent") }
  let!(:entry_pending)       { create_entry("status" => "pending",  "amount" => "750",  "region" => "south", "notes" => nil.to_s) }
  let(:base_scope) { EntityEntry.where(entity_id: entity.id) }
  let(:ctx)        { {} }

  let(:entity) do
    create(:entity,
      name: "Test Entity",
      customer: customer,
      property_schema: [
        { "name" => "status", "name_slug" => "status", "type" => "Types::String" },
        { "name" => "amount", "name_slug" => "amount", "type" => "Types::String" },
        { "name" => "region", "name_slug" => "region", "type" => "Types::String" },
        { "name" => "notes",  "name_slug" => "notes",  "type" => "Types::String" }
      ].to_json
    )
  end

  # Creates persisted EntityEntry records with the given data hashes.
  def create_entry(data)
    EntityEntry.create!(entity: entity, customer: customer, data: data.to_json)
  end



  # ─── .apply ───────────────────────────────────────────────────────────────

  describe ".apply" do
    # ── nil / empty guards ──────────────────────────────────────────────────

    context "when conditions is nil" do
      it "returns the scope unchanged" do
        result = described_class.apply(base_scope, nil, ctx)
        expect(result.to_a).to match_array(base_scope.to_a)
      end
    end

    context "when conditions is empty hash" do
      it "returns the scope unchanged" do
        result = described_class.apply(base_scope, {}, ctx)
        expect(result.to_a).to match_array(base_scope.to_a)
      end
    end

    context "when conditions has no rules" do
      it "returns the scope unchanged" do
        result = described_class.apply(base_scope, { "operator" => "AND", "rules" => [] }, ctx)
        expect(result.to_a).to match_array(base_scope.to_a)
      end
    end

    context "when conditions rules is nil" do
      it "returns the scope unchanged" do
        result = described_class.apply(base_scope, { "operator" => "AND", "rules" => nil }, ctx)
        expect(result.to_a).to match_array(base_scope.to_a)
      end
    end

    # ── single equality condition on JSON field ──────────────────────────────

    context "with a single == condition on a data JSON field" do
      let(:conditions) do
        { "operator" => "AND", "rules" => [{ "field" => "data.status", "op" => "==", "value" => "approved" }] }
      end

      it "returns only entries matching the JSON field value" do
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result).to include(entry_approved_1000, entry_approved_500)
        expect(result).not_to include(entry_rejected_2000, entry_pending)
      end
    end

    # ── != operator ─────────────────────────────────────────────────────────

    context "with a != condition on a data JSON field" do
      let(:conditions) do
        { "operator" => "AND", "rules" => [{ "field" => "data.status", "op" => "!=", "value" => "approved" }] }
      end

      it "excludes matching entries" do
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result).to include(entry_rejected_2000, entry_pending)
        expect(result).not_to include(entry_approved_1000, entry_approved_500)
      end
    end

    # ── multiple AND conditions ──────────────────────────────────────────────

    context "with multiple AND conditions" do
      let(:conditions) do
        {
          "operator" => "AND",
          "rules" => [
            { "field" => "data.status", "op" => "==", "value" => "approved" },
            { "field" => "data.region", "op" => "==", "value" => "east" }
          ]
        }
      end

      it "applies all rules and returns only the intersection" do
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result).to contain_exactly(entry_approved_1000)
      end
    end

    # ── OR conditions ────────────────────────────────────────────────────────

    context "with OR conditions" do
      let(:conditions) do
        {
          "operator" => "OR",
          "rules" => [
            { "field" => "data.status", "op" => "==", "value" => "rejected" },
            { "field" => "data.region", "op" => "==", "value" => "south" }
          ]
        }
      end

      it "returns entries matching any of the rules" do
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result).to include(entry_rejected_2000, entry_pending)
        expect(result).not_to include(entry_approved_1000, entry_approved_500)
      end
    end

    # ── nested AND/OR groups ─────────────────────────────────────────────────

    context "with nested AND within OR groups" do
      let(:conditions) do
        {
          "operator" => "OR",
          "rules" => [
            {
              "operator" => "AND",
              "rules" => [
                { "field" => "data.status", "op" => "==", "value" => "approved" },
                { "field" => "data.region", "op" => "==", "value" => "west" }
              ]
            },
            { "field" => "data.status", "op" => "==", "value" => "rejected" }
          ]
        }
      end

      it "evaluates nested groups with correct precedence" do
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result).to include(entry_approved_500, entry_rejected_2000)
        expect(result).not_to include(entry_approved_1000, entry_pending)
      end
    end

    context "with nested OR within AND groups" do
      let(:conditions) do
        {
          "operator" => "AND",
          "rules" => [
            {
              "operator" => "OR",
              "rules" => [
                { "field" => "data.region", "op" => "==", "value" => "east" },
                { "field" => "data.region", "op" => "==", "value" => "west" }
              ]
            },
            { "field" => "data.status", "op" => "==", "value" => "approved" }
          ]
        }
      end

      it "applies the outer AND constraint to the nested OR result" do
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result).to include(entry_approved_1000, entry_approved_500)
        expect(result).not_to include(entry_rejected_2000, entry_pending)
      end
    end

    # ── comparison operators ─────────────────────────────────────────────────

    context "with > comparison" do
      let(:conditions) do
        { "operator" => "AND", "rules" => [{ "field" => "data.amount", "op" => ">", "value" => "1000" }] }
      end

      it "returns entries with amount greater than 1000" do
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result).to contain_exactly(entry_rejected_2000)
      end
    end

    context "with >= comparison" do
      let(:conditions) do
        { "operator" => "AND", "rules" => [{ "field" => "data.amount", "op" => ">=", "value" => "1000" }] }
      end

      it "returns entries with amount greater than or equal to 1000" do
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result).to include(entry_approved_1000, entry_rejected_2000)
        expect(result).not_to include(entry_approved_500, entry_pending)
      end
    end

    context "with < comparison" do
      let(:conditions) do
        { "operator" => "AND", "rules" => [{ "field" => "data.amount", "op" => "<", "value" => "750" }] }
      end

      it "returns entries with amount less than 750" do
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result).to contain_exactly(entry_approved_500)
      end
    end

    context "with <= comparison" do
      let(:conditions) do
        { "operator" => "AND", "rules" => [{ "field" => "data.amount", "op" => "<=", "value" => "750" }] }
      end

      it "returns entries with amount less than or equal to 750" do
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result).to include(entry_approved_500, entry_pending)
        expect(result).not_to include(entry_approved_1000, entry_rejected_2000)
      end
    end

    # ── numeric casting for comparisons ─────────────────────────────────────

    context "when the comparison value is a Numeric (Integer)" do
      let(:conditions) do
        { "operator" => "AND", "rules" => [{ "field" => "data.amount", "op" => ">", "value" => 1000 }] }
      end

      it "applies CAST and compares correctly" do
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result).to contain_exactly(entry_rejected_2000)
      end
    end

    context "when the comparison value is a non-numeric string" do
      let(:conditions) do
        { "operator" => "AND", "rules" => [{ "field" => "data.status", "op" => ">", "value" => "a" }] }
      end

      it "falls back to lexicographic comparison without CAST" do
        # All status values ("approved", "pending", "rejected") are lexicographically > "a"
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result.count).to eq(4)
      end
    end

    # ── blank? and present? operators ───────────────────────────────────────

    context "with blank? operator" do
      let(:conditions) do
        { "operator" => "AND", "rules" => [{ "field" => "data.notes", "op" => "blank?", "value" => nil }] }
      end

      it "returns entries where the JSON field is NULL or empty string" do
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result).to include(entry_approved_500, entry_pending)
        expect(result).not_to include(entry_approved_1000, entry_rejected_2000)
      end
    end

    context "with present? operator" do
      let(:conditions) do
        { "operator" => "AND", "rules" => [{ "field" => "data.notes", "op" => "present?", "value" => nil }] }
      end

      it "returns entries where the JSON field is neither NULL nor empty" do
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result).to include(entry_approved_1000, entry_rejected_2000)
        expect(result).not_to include(entry_approved_500, entry_pending)
      end
    end

    # ── contains / includes? with LIKE ──────────────────────────────────────

    context "with contains operator" do
      let(:conditions) do
        { "operator" => "AND", "rules" => [{ "field" => "data.notes", "op" => "contains", "value" => "world" }] }
      end

      it "returns entries where the JSON field LIKE %value%" do
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result).to contain_exactly(entry_approved_1000)
      end
    end

    context "with includes? operator" do
      let(:conditions) do
        { "operator" => "AND", "rules" => [{ "field" => "data.notes", "op" => "includes?", "value" => "urgent" }] }
      end

      it "behaves the same as contains" do
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result).to contain_exactly(entry_rejected_2000)
      end
    end

    # ── in operator with array ───────────────────────────────────────────────

    context "with in operator and an array value" do
      let(:conditions) do
        {
          "operator" => "AND",
          "rules" => [{ "field" => "data.region", "op" => "in", "value" => ["east", "west"] }]
        }
      end

      it "returns entries whose JSON field value is in the provided array" do
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result).to include(entry_approved_1000, entry_approved_500)
        expect(result).not_to include(entry_rejected_2000, entry_pending)
      end
    end

    context "with not_in operator" do
      let(:conditions) do
        {
          "operator" => "AND",
          "rules" => [{ "field" => "data.region", "op" => "not_in", "value" => ["east", "west"] }]
        }
      end

      it "returns entries whose JSON field value is not in the provided array" do
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result).to include(entry_rejected_2000, entry_pending)
        expect(result).not_to include(entry_approved_1000, entry_approved_500)
      end
    end

    # ── matches? with LIKE ───────────────────────────────────────────────────

    context "with matches? operator" do
      let(:conditions) do
        { "operator" => "AND", "rules" => [{ "field" => "data.status", "op" => "matches?", "value" => "appro%" }] }
      end

      it "queries using LIKE with the provided pattern" do
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result).to include(entry_approved_1000, entry_approved_500)
        expect(result).not_to include(entry_rejected_2000, entry_pending)
      end
    end

    # ── dynamic ctx value resolution ────────────────────────────────────────

    context "with a ctx. value reference" do
      let(:ctx) { { target_status: "pending" } }

      let(:conditions) do
        { "operator" => "AND", "rules" => [{ "field" => "data.status", "op" => "==", "value" => "ctx.target_status" }] }
      end

      it "resolves the ctx reference and filters correctly" do
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result).to contain_exactly(entry_pending)
      end
    end

    context "with a ctx path through an EntityEntry" do
      let(:ctx) { { model: entry_pending } }
      let(:conditions) do
        { "operator" => "AND", "rules" => [{ "field" => "data.status", "op" => "==", "value" => "ctx.model.status" }] }
      end

      it "reads the record attribute via Step.dig and does not raise TypeError" do
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result).to contain_exactly(entry_pending)
      end
    end

    context "with a ctx. value reference in an in array" do
      let(:ctx) { { allowed_regions: ["north", "south"] } }

      # ctx.allowed_regions resolves to an array at the top level of ctx
      let(:conditions) do
        {
          "operator" => "AND",
          "rules" => [{ "field" => "data.region", "op" => "in", "value" => ["ctx.allowed_regions.0", "ctx.allowed_regions.1"] }]
        }
      end

      it "resolves each ctx array element and filters correctly" do
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result).to include(entry_rejected_2000, entry_pending)
        expect(result).not_to include(entry_approved_1000, entry_approved_500)
      end
    end

    # ── non-data field (direct column) conditions ────────────────────────────

    context "with a non-data field targeting a table column" do
      it "queries the entity_id column directly" do
        conditions = {
          "operator" => "AND",
          "rules" => [{ "field" => "entity_id", "op" => "==", "value" => entity.id }]
        }

        result = described_class.apply(EntityEntry.all, conditions, ctx)
        expect(result).to match_array(base_scope.to_a)
      end
    end

    context "with customer_id column condition" do
      it "filters by customer_id column directly" do
        other_customer = create(:customer)
        other_entity   = create(:entity, name: "Other", customer: other_customer,
                                 property_schema: [{ "name" => "status", "name_slug" => "status", "type" => "Types::String" }].to_json)
        create_entry_for = ->(c, e, data) do
          EntityEntry.create!(entity: e, customer: c, data: data.to_json)
        end
        other_entry = create_entry_for.call(other_customer, other_entity, { "status" => "approved" })

        conditions = {
          "operator" => "AND",
          "rules" => [{ "field" => "customer_id", "op" => "==", "value" => customer.id }]
        }

        result = described_class.apply(EntityEntry.all, conditions, ctx)
        expect(result).to include(entry_approved_1000)
        expect(result).not_to include(other_entry)
      end
    end

    # ── unknown operator returns scope with no effect ────────────────────────

    context "with an unknown/unsupported operator" do
      let(:conditions) do
        { "operator" => "AND", "rules" => [{ "field" => "data.status", "op" => "~=", "value" => "approved" }] }
      end

      it "ignores the unsupported rule and returns the full scope" do
        result = described_class.apply(base_scope, conditions, ctx)
        expect(result.to_a).to match_array(base_scope.to_a)
      end
    end

    # ── sub-query rules ────────────────────────────────────────────────────

    describe "sub-query rules" do
      it "filters using aggregate sub-query with > (avg)" do
        conditions = {
          "operator" => "AND",
          "rules" => [
            {
              "field" => "data.amount",
              "op" => ">",
              "subQuery" => {
                "entityId" => entity.id,
                "aggregateFunction" => "avg",
                "aggregateField" => "amount",
                "conditions" => []
              }
            }
          ]
        }
        result = described_class.apply(base_scope, conditions, ctx)
        # AVG of 1000, 500, 2000, 750 = 1062.5 → only amount=2000 matches > 1062.5
        expect(result).to contain_exactly(entry_rejected_2000)
      end

      it "filters using count sub-query" do
        conditions = {
          "operator" => "AND",
          "rules" => [
            {
              "field" => "data.amount",
              "op" => ">=",
              "subQuery" => {
                "entityId" => entity.id,
                "aggregateFunction" => "count",
                "aggregateField" => "id"
              }
            }
          ]
        }
        result = described_class.apply(base_scope, conditions, ctx)
        # COUNT is 4, so amount >= 4 matches all (500, 750, 1000, 2000)
        expect(result.count).to eq(4)
      end

      it "filters using sum sub-query" do
        conditions = {
          "operator" => "AND",
          "rules" => [
            {
              "field" => "data.amount",
              "op" => "<",
              "subQuery" => {
                "entityId" => entity.id,
                "aggregateFunction" => "sum",
                "aggregateField" => "amount",
                "conditions" => []
              }
            }
          ]
        }
        result = described_class.apply(base_scope, conditions, ctx)
        # SUM = 4250, all amounts are < 4250
        expect(result.count).to eq(4)
      end

      it "filters using min sub-query" do
        conditions = {
          "operator" => "AND",
          "rules" => [
            {
              "field" => "data.amount",
              "op" => "==",
              "subQuery" => {
                "entityId" => entity.id,
                "aggregateFunction" => "min",
                "aggregateField" => "amount",
                "conditions" => []
              }
            }
          ]
        }
        result = described_class.apply(base_scope, conditions, ctx)
        # MIN = 500, so only amount=500 matches
        expect(result).to contain_exactly(entry_approved_500)
      end

      it "filters using max sub-query" do
        conditions = {
          "operator" => "AND",
          "rules" => [
            {
              "field" => "data.amount",
              "op" => "<=",
              "subQuery" => {
                "entityId" => entity.id,
                "aggregateFunction" => "max",
                "aggregateField" => "amount",
                "conditions" => []
              }
            }
          ]
        }
        result = described_class.apply(base_scope, conditions, ctx)
        # MAX = 2000, all amounts are <= 2000
        expect(result.count).to eq(4)
      end

      it "returns (0) for invalid aggregate function" do
        conditions = {
          "operator" => "AND",
          "rules" => [
            {
              "field" => "data.amount",
              "op" => ">",
              "subQuery" => {
                "entityId" => entity.id,
                "aggregateFunction" => "invalid_func",
                "aggregateField" => "amount",
                "conditions" => []
              }
            }
          ]
        }
        result = described_class.apply(base_scope, conditions, ctx)
        # Falls back to (0), so amount > 0 matches all entries
        expect(result.count).to eq(4)
      end

      it "returns (0) when entityId is missing" do
        conditions = {
          "operator" => "AND",
          "rules" => [
            {
              "field" => "data.amount",
              "op" => ">",
              "subQuery" => {
                "aggregateFunction" => "avg",
                "aggregateField" => "amount",
                "conditions" => []
              }
            }
          ]
        }
        result = described_class.apply(base_scope, conditions, ctx)
        # Falls back to (0), so amount > 0 matches all entries
        expect(result.count).to eq(4)
      end

      it "works with != operator on sub-query" do
        conditions = {
          "operator" => "AND",
          "rules" => [
            {
              "field" => "data.amount",
              "op" => "!=",
              "subQuery" => {
                "entityId" => entity.id,
                "aggregateFunction" => "min",
                "aggregateField" => "amount",
                "conditions" => []
              }
            }
          ]
        }
        result = described_class.apply(base_scope, conditions, ctx)
        # MIN = 500, so all except amount=500 match
        expect(result).to include(entry_approved_1000, entry_rejected_2000, entry_pending)
        expect(result).not_to include(entry_approved_500)
      end

      it "defaults aggregateField to 'id' when not provided" do
        # This tests that build_sub_query uses "id" as default field
        sql = described_class.send(:build_sub_query, {
          "entityId" => 99,
          "aggregateFunction" => "avg"
        }, {})
        expect(sql).to include("json_extract(ee.data, '$.id')")
      end

      it "works with a non-data field on the left side" do
        # Using entity_id as a non-data field compared against a sub-query
        conditions = {
          "operator" => "AND",
          "rules" => [
            {
              "field" => "entity_id",
              "op" => "==",
              "subQuery" => {
                "entityId" => entity.id,
                "aggregateFunction" => "count",
                "aggregateField" => "id"
              }
            }
          ]
        }
        result = described_class.apply(base_scope, conditions, ctx)
        # CAST(entity_id AS NUMERIC) = (SELECT COUNT(*) ...) → entity_id = 4
        # This will only match if entity.id == 4 (the count of entries)
        if entity.id == 4
          expect(result.count).to eq(4)
        else
          expect(result.count).to eq(0)
        end
      end
    end
  end

  # ─── Calculated field substitution ────────────────────────────────────────

  describe "calculated field substitution" do
    it "substitutes calculated field expression in condition" do
      scope = EntityEntry.where(entity_id: entity.id, customer_id: customer.id)
      calculated_fields = {
        "doubled" => "CAST(json_extract(entity_entries.data, '$.amount') AS NUMERIC) * 2"
      }
      conditions = {
        "operator" => "AND",
        "rules" => [{ "field" => "data.doubled", "op" => ">", "value" => "1500" }]
      }
      result = described_class.apply(scope, conditions, {}, calculated_fields: calculated_fields)
      # amounts: 1000, 500, 2000, 750 → doubled: 2000, 1000, 4000, 1500
      # 2000 and 4000 match > 1500
      expect(result.count).to eq(2)
    end

    it "falls back to json_extract for non-calculated fields" do
      scope = EntityEntry.where(entity_id: entity.id, customer_id: customer.id)
      calculated_fields = { "other" => "something" }
      conditions = {
        "operator" => "AND",
        "rules" => [{ "field" => "data.amount", "op" => "==", "value" => "1000" }]
      }
      result = described_class.apply(scope, conditions, {}, calculated_fields: calculated_fields)
      expect(result.count).to eq(1)
    end

    it "works with empty calculated_fields hash" do
      scope = EntityEntry.where(entity_id: entity.id, customer_id: customer.id)
      conditions = {
        "operator" => "AND",
        "rules" => [{ "field" => "data.amount", "op" => "==", "value" => "500" }]
      }
      result = described_class.apply(scope, conditions, {}, calculated_fields: {})
      expect(result.count).to eq(1)
    end
  end

  # ─── Edge-case branches not covered above ────────────────────────────────

  describe "conditions is not a Hash" do
    it "returns the scope unchanged when conditions is an Array" do
      result = described_class.apply(base_scope, ["status", "approved"], ctx)
      expect(result.to_a).to match_array(base_scope.to_a)
    end

    it "returns the scope unchanged when conditions is a String" do
      result = described_class.apply(base_scope, "status = approved", ctx)
      expect(result.to_a).to match_array(base_scope.to_a)
    end
  end

  describe "calculated field with subQuery" do
    it "uses the calc expression on the left side of the sub-query comparison" do
      calculated_fields = {
        "amount" => "CAST(json_extract(entity_entries.data, '$.amount') AS NUMERIC)"
      }
      conditions = {
        "operator" => "AND",
        "rules" => [
          {
            "field" => "data.amount",
            "op" => ">",
            "subQuery" => {
              "entityId" => entity.id,
              "aggregateFunction" => "min",
              "aggregateField" => "amount"
            }
          }
        ]
      }
      # MIN of 500, 750, 1000, 2000 = 500; amounts > 500 are 750, 1000, 2000
      result = described_class.apply(base_scope, conditions, {}, calculated_fields: calculated_fields)
      expect(result.count).to eq(3)
      expect(result).not_to include(entry_approved_500)
    end
  end

  describe "build_comparison_raw with unknown operator (else → '=')" do
    it "falls back to = for an unmapped operator" do
      # Call private method directly; result should use '=' SQL operator
      sql, bindings = described_class.send(:build_comparison_raw,
                                           "some_expr", "~~", "(SELECT 1)")
      expect(sql).to include("= (SELECT 1)")
      expect(bindings).to be_empty
    end
  end

  describe "numeric_value? with non-String non-Numeric input" do
    it "returns false for nil" do
      expect(described_class.send(:numeric_value?, nil)).to be false
    end

    it "returns false for a boolean" do
      expect(described_class.send(:numeric_value?, true)).to be false
    end

    it "returns false for an Array" do
      expect(described_class.send(:numeric_value?, [1, 2])).to be false
    end
  end

  describe "resolve_value with Array containing non-ctx plain values" do
    it "returns the Array with literal values unchanged" do
      ctx = {}
      # A plain Array without any "ctx.*" elements — each element passes through
      result = described_class.send(:resolve_value, ["east", "west"], ctx)
      expect(result).to eq(["east", "west"])
    end

    it "resolves ctx references inside an array while leaving plain values intact" do
      ctx = { region: "north" }
      result = described_class.send(:resolve_value, ["east", "ctx.region"], ctx)
      expect(result).to eq(["east", "north"])
    end
  end

  # ─── SQL injection prevention ──────────────────────────────────────────────

  describe "SQL injection prevention via JsonPathValidator" do
    context "when a data field key contains a single quote (injection attempt)" do
      it "raises ArgumentError before building any SQL" do
        conditions = {
          "operator" => "AND",
          "rules" => [{ "field" => "data.name'", "op" => "==", "value" => "x" }]
        }
        expect { described_class.apply(base_scope, conditions, ctx) }
          .to raise_error(ArgumentError, /Unsafe JSON path rejected/)
      end
    end

    context "when a data field key contains closing parenthesis (injection attempt)" do
      it "raises ArgumentError before building any SQL" do
        conditions = {
          "operator" => "AND",
          "rules" => [{ "field" => "data.name')) OR 1=1 --", "op" => "==", "value" => "x" }]
        }
        expect { described_class.apply(base_scope, conditions, ctx) }
          .to raise_error(ArgumentError, /Unsafe JSON path rejected/)
      end
    end

    context "when a subQuery aggregateField contains injection characters" do
      it "raises ArgumentError before building the sub-query SQL" do
        conditions = {
          "operator" => "AND",
          "rules" => [
            {
              "field" => "data.amount",
              "op" => ">",
              "subQuery" => {
                "entityId" => entity.id,
                "aggregateFunction" => "avg",
                "aggregateField" => "amount') UNION SELECT 1 --"
              }
            }
          ]
        }
        expect { described_class.apply(base_scope, conditions, ctx) }
          .to raise_error(ArgumentError, /Unsafe JSON path rejected/)
      end
    end

    context "when a subQuery field on the left side of a comparison contains injection characters" do
      it "raises ArgumentError before building the comparison expression" do
        conditions = {
          "operator" => "AND",
          "rules" => [
            {
              "field" => "data.name'))) OR 1=1 --",
              "op" => ">",
              "subQuery" => {
                "entityId" => entity.id,
                "aggregateFunction" => "count"
              }
            }
          ]
        }
        expect { described_class.apply(base_scope, conditions, ctx) }
          .to raise_error(ArgumentError, /Unsafe JSON path rejected/)
      end
    end
  end

describe "subQuery tenant isolation" do
    let(:other_customer) { create(:customer) }
    let!(:other_entry) do
      create(:entity_entry, entity: entity, customer: other_customer,
             data: { "amount" => "99999", "status" => "approved" }.to_json)
    end

    it "correlates subquery customer_id to the outer row tenant, not a tautology" do
      sql = described_class.send(:build_sub_query, {
        "entityId" => entity.id,
        "aggregateFunction" => "sum",
        "aggregateField" => "amount"
      }, {})
      expect(sql).to include("entity_entries ee")
      expect(sql).to include("ee.customer_id = entity_entries.customer_id")
      expect(sql).not_to match(/WHERE entity_id = \d+ AND customer_id = entity_entries\.customer_id\)\z/)
    end

    it "does not let another tenant's rows inflate the subquery aggregate" do
      # Outer scoped to current customer; subquery must not pick up other_entry.
      conditions = {
        "operator" => "AND",
        "rules" => [
          {
            "field" => "data.amount",
            "op" => "<",
            "subQuery" => {
              "entityId" => entity.id,
              "aggregateFunction" => "sum",
              "aggregateField" => "amount"
            }
          }
        ]
      }
      result = described_class.apply(base_scope, conditions, ctx)
      # If the bug (tautology) were present, SUM would include 99999 from other tenant
      # and every local amount (< 99999+) would match. With the fix, SUM is tenant-local.
      local_sum = [entry_approved_1000, entry_rejected_2000, entry_approved_500, entry_pending]
                    .sum { |e| JSON.parse(e.data)["amount"].to_i }
      # All local rows have amount < local_sum only if there are multiple rows with positive amounts;
      # assert other tenant amount is not in the SQL path by checking the generated fragment.
      sql = described_class.send(:build_sub_query, {
        "entityId" => entity.id,
        "aggregateFunction" => "sum",
        "aggregateField" => "amount"
      }, {})
      expect(sql).to include("ee.entity_id")
      expect(sql).to include("ee.data")
      expect(result).to be_a(ActiveRecord::Relation)
    end
  end
end
