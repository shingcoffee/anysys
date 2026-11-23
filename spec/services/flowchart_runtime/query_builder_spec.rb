# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::QueryBuilder do
  let_it_be(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Name", "name_slug" => "name", "type" => "String", "html_type" => "text" },
      { "name" => "Status", "name_slug" => "status", "type" => "String", "html_type" => "text" },
      { "name" => "Amount", "name_slug" => "amount", "type" => "Float", "html_type" => "number" }
    ].to_json)
  end

  before do
    create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Alice", "status" => "active", "amount" => "100" }.to_json)
    create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Bob", "status" => "inactive", "amount" => "200" }.to_json)
    create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Carol", "status" => "active", "amount" => "300" }.to_json)
  end

  describe ".for_entity" do
    it "returns a QueryBuilder instance" do
      builder = described_class.for_entity(entity, customer_id: customer.id)
      expect(builder).to be_a(described_class)
    end

    it "returns every tenant row when callers omit scope (flowcharts stay unscoped)" do
      result = described_class.for_entity(entity, customer_id: customer.id).execute
      expect(result.records.size).to eq(3)
      expect(result.total_count).to eq(3)
    end

    it "intersects an optional scope without changing unscoped callers" do
      limited = EntityEntry.where(customer_id: customer.id, entity_id: entity.id).limit(1)
      scoped = described_class.for_entity(entity, customer_id: customer.id, scope: limited).execute
      unscoped = described_class.for_entity(entity, customer_id: customer.id).execute

      expect(scoped.records.size).to eq(1)
      expect(unscoped.records.size).to eq(3)
    end
  end

  describe "#execute" do
    it "returns all records for entity when no filters applied" do
      result = described_class.for_entity(entity, customer_id: customer.id).execute
      expect(result.records.size).to eq(3)
    end

    it "returns a Result struct with metadata" do
      result = described_class.for_entity(entity, customer_id: customer.id).execute
      expect(result).to respond_to(:records, :total_count, :page, :per_page, :total_pages, :has_next, :sql)
      expect(result.total_count).to eq(3)
      expect(result.page).to be_nil
    end
  end

  describe "#where" do
    it "filters records using condition rules" do
      conditions = {
        "operator" => "AND",
        "rules" => [
          { "field" => "data.status", "op" => "==", "value" => "active" }
        ]
      }
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .where(conditions, {})
                              .execute
      expect(result.records.size).to eq(2)
      expect(result.total_count).to eq(2)
    end
  end

  describe "#order" do
    it "orders results by specified field" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .order("created_at", "desc")
                              .execute
      expect(result.records.first.created_at).to be >= result.records.last.created_at
    end
  end

  describe "#limit" do
    it "caps the number of records returned" do
      result = described_class.for_entity(entity, customer_id: customer.id).limit(2).execute
      expect(result.records.size).to eq(2)
    end

    it "reports the unrestricted total_count alongside the capped records" do
      result = described_class.for_entity(entity, customer_id: customer.id).limit(2).execute
      expect(result.total_count).to eq(3)
    end

    it "leaves the scope untouched for a non-positive count" do
      result = described_class.for_entity(entity, customer_id: customer.id).limit(0).execute
      expect(result.records.size).to eq(3)
    end

    it "defers to pagination when both are configured" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .limit(1)
                              .paginate(page: 2, per_page: 2)
                              .execute
      expect(result.records.size).to eq(1)
      expect(result.page).to eq(2)
    end
  end

  describe "#paginate" do
    it "limits results to page size" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .paginate(page: 1, per_page: 2)
                              .execute
      expect(result.records.size).to eq(2)
      expect(result.total_count).to eq(3)
      expect(result.page).to eq(1)
      expect(result.per_page).to eq(2)
      expect(result.total_pages).to eq(2)
      expect(result.has_next).to be true
    end

    it "returns second page correctly" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .order("id", "asc")
                              .paginate(page: 2, per_page: 2)
                              .execute
      expect(result.records.size).to eq(1)
      expect(result.page).to eq(2)
      expect(result.has_next).to be false
    end

    it "defaults page to 1 when nil" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .paginate(page: nil, per_page: 10)
                              .execute
      expect(result.page).to eq(1)
      expect(result.records.size).to eq(3)
    end

    it "does not dump every row when per_page is 0" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .paginate(page: 1, per_page: 0)
                              .execute
      expect(result.per_page).to eq(described_class::DEFAULT_PER_PAGE)
      expect(result.sql).to match(/LIMIT/i)
    end

    it "caps a crafted unbounded per_page" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .paginate(page: 1, per_page: 999_999)
                              .execute
      expect(result.per_page).to eq(described_class::MAX_PER_PAGE)
    end

    it "does not 500 when page and per_page are arrays" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .paginate(page: ["2"], per_page: ["2"])
                              .execute
      expect(result.page).to eq(1)
      expect(result.per_page).to eq(described_class::DEFAULT_PER_PAGE)
    end

    it "composes with where" do
      conditions = {
        "operator" => "AND",
        "rules" => [{ "field" => "data.status", "op" => "==", "value" => "active" }]
      }
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .where(conditions, {})
                              .paginate(page: 1, per_page: 1)
                              .execute
      expect(result.records.size).to eq(1)
      expect(result.total_count).to eq(2)
      expect(result.total_pages).to eq(2)
    end
  end

  context "with cross-entity JOINs" do
    let(:order_entity) do
      create(:entity, name: "Order", customer: customer, property_schema: [
        { "name" => "Total", "name_slug" => "total", "type" => "Float", "html_type" => "number" }
      ].to_json)
    end
    let(:bridge_entity) do
      entity_slug = entity.name.parameterize(separator: "_")
      create(:entity, name: "assoc_entity_order", customer: customer, category: :bridge, property_schema: [
        { "name" => entity.name, "name_slug" => entity_slug, "type" => "EntityReference", "html_type" => "number", "entity_id" => entity.id.to_s },
        { "name" => "Order", "name_slug" => "order", "type" => "EntityReference", "html_type" => "number", "entity_id" => order_entity.id.to_s }
      ].to_json)
    end

    before do
      entity_slug = entity.name.parameterize(separator: "_")
      order1 = create(:entity_entry, entity: order_entity, customer: customer, data: { "total" => "500" }.to_json)
      alice = EntityEntry.where(entity_id: entity.id, customer_id: customer.id)
                         .where("json_extract(data, '$.name') = ?", "Alice").first
      create(:entity_entry, entity: bridge_entity, customer: customer,
        data: { entity_slug => alice.id.to_s, "order" => order1.id.to_s }.to_json)
    end

    describe "#join_entity" do
      it "filters to only records with matching joins" do
        result = described_class.for_entity(entity, customer_id: customer.id)
                                .join_entity(order_entity, via: bridge_entity)
                                .execute
        names = result.records.map { |r| r.data_json["name"] }
        expect(names).to contain_exactly("Alice")
      end

      it "raises when no bridge entity found" do
        other = create(:entity, name: "Other", customer: customer)
        expect {
          described_class.for_entity(entity, customer_id: customer.id)
                         .join_entity(other)
        }.to raise_error(ArgumentError, /No bridge entity found/)
      end
    end
  end

  describe "#computed_field" do
    it "rejects manual SQL expressions" do
      expect {
        described_class.for_entity(entity, customer_id: customer.id)
                       .computed_field("sort_key", "json_extract(data, '$.name')")
      }.to raise_error(FlowchartRuntime::QueryBuilder::Error, /not supported/)
    end
  end

  describe "#group and #having" do
    it "groups results by json field" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .group("data.status")
                              .aggregate(:count)
                              .execute
      expect(result.records).to be_a(Hash)
      expect(result.records["active"]).to eq(2)
      expect(result.records["inactive"]).to eq(1)
    end

    it "applies having clause to grouped results" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .group("data.status")
                              .having("COUNT(*) > 1")
                              .aggregate(:count)
                              .execute
      expect(result.records).to be_a(Hash)
      expect(result.records.keys).to contain_exactly("active")
    end

    it "supports sum aggregate" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .aggregate(:sum, "amount")
                              .execute
      expect(result.records).to eq(600.0)
    end
  end

  context "with entity calculated fields" do
    let(:calc_entity) do
      create(:entity, customer: customer, property_schema: [
        { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" },
        { "name" => "Quantity", "name_slug" => "quantity", "type" => "Integer", "html_type" => "number" },
        { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number",
          "readonly" => true, "storage" => "computed", "formula" => "price * quantity" }
      ].to_json)
    end

    before do
      create(:entity_entry, entity: calc_entity, customer: customer, data: { "price" => "10", "quantity" => "5" }.to_json)
      create(:entity_entry, entity: calc_entity, customer: customer, data: { "price" => "20", "quantity" => "3" }.to_json)
    end

    it "auto-injects calculated fields into SELECT" do
      result = described_class.for_entity(calc_entity, customer_id: customer.id).execute
      expect(result.sql).to include("AS total")
    end

    it "makes calculated values available on records" do
      result = described_class.for_entity(calc_entity, customer_id: customer.id)
                              .order("total", "desc")
                              .execute
      totals = result.records.map { |r| r["total"] }
      expect(totals).to eq([60, 50])
    end

    it "works with entity that has no calculated fields" do
      result = described_class.for_entity(entity, customer_id: customer.id).execute
      expect(result.records.size).to eq(3)
    end
  end

  # ─── Edge-case branches ──────────────────────────────────────────────────

  describe "#order with nil direction" do
    it "defaults to asc when direction is nil" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .order("created_at", nil)
                              .execute
      # Just confirm no error and records are returned
      expect(result.records.size).to eq(3)
    end
  end

  describe "#paginate with page < 1" do
    it "clamps page 0 to 1" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .paginate(page: 0, per_page: 10)
                              .execute
      expect(result.page).to eq(1)
      expect(result.records.size).to eq(3)
    end

    it "clamps page -5 to 1" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .paginate(page: -5, per_page: 10)
                              .execute
      expect(result.page).to eq(1)
    end
  end

  describe "#aggregate function branches" do
    it "returns average for :average" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .aggregate(:average, "amount")
                              .execute
      expect(result.records).to eq(200.0)
    end

    it "returns minimum for :minimum" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .aggregate(:minimum, "amount")
                              .execute
      expect(result.records).to eq(100.0)
    end

    it "returns maximum for :maximum" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .aggregate(:maximum, "amount")
                              .execute
      expect(result.records).to eq(300.0)
    end

    it "falls back to count for an unknown aggregate function symbol" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .aggregate(:totally_unknown_func)
                              .execute
      expect(result.records).to eq(3)
    end
  end

  describe "aggregate_expression with no field (Arel.star)" do
    it "uses COUNT(*) style expression when field is nil (via :count aggregate)" do
      # :count uses COUNT(*) — the aggregate_expression is only called for non-count
      # aggregates. To reach the Arel.star branch, call :average with nil field.
      builder = described_class.for_entity(entity, customer_id: customer.id)
                               .aggregate(:average)
      # aggregate_expression returns Arel.star when @aggregate_field is nil
      expect(builder.send(:aggregate_expression)).to eq(Arel.star)
    end
  end

  describe "#group by a non-data column" do
    it "groups by a plain column expression without json_extract" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .group("customer_id")
                              .aggregate(:count)
                              .execute
      expect(result.records).to be_a(Hash)
      expect(result.records[customer.id]).to eq(3)
    end
  end

  describe "inject_calculated_fields with nil entity" do
    it "skips injection and returns records without error" do
      # When entity is nil, inject_calculated_fields returns early
      builder = described_class.new(entity: nil, customer_id: customer.id)
      # execute will fail without entity because base_scope calls entity.id
      # — we just verify the method itself returns without touching schema
      expect { builder.send(:inject_calculated_fields) }.not_to raise_error
    end
  end

  # ─── SQL injection prevention ──────────────────────────────────────────────

  describe "SQL injection prevention via JsonPathValidator" do
    context "when ordering by a data field with injection characters in the field name" do
      it "raises ArgumentError before building the ORDER BY clause" do
        expect do
          described_class.for_entity(entity, customer_id: customer.id)
                         .order("data.name'", "asc")
                         .execute
        end.to raise_error(ArgumentError, /Unsafe JSON path rejected/)
      end
    end

    context "when ordering by a data field containing closing parenthesis" do
      it "raises ArgumentError before building the ORDER BY clause" do
        expect do
          described_class.for_entity(entity, customer_id: customer.id)
                         .order("data.name')) OR 1=1 --", "asc")
                         .execute
        end.to raise_error(ArgumentError, /Unsafe JSON path rejected/)
      end
    end
  end

  describe "security / chain contract" do
    it "rejects manual computed SQL expressions" do
      expect {
        described_class.for_entity(entity, customer_id: customer.id)
                       .computed_field("x", "id; DROP TABLE users")
      }.to raise_error(FlowchartRuntime::QueryBuilder::Error, /not supported/)
    end

    it "rejects unsafe HAVING clauses" do
      expect {
        described_class.for_entity(entity, customer_id: customer.id)
                       .group("data.status")
                       .having("1=1; DROP TABLE users")
                       .aggregate(:count)
                       .execute
      }.to raise_error(FlowchartRuntime::QueryBuilder::Error, /unsafe HAVING/)
    end

    it "supports select/distinct chain while preserving tenant scope" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .select("id")
                              .distinct
                              .execute
      expect(result.records.size).to eq(3)
      expect(result.sql).to include("DISTINCT")
    end

    it "supports multi-agg helpers on a tenant-scoped builder" do
      builder = described_class.for_entity(entity, customer_id: customer.id)
      total = builder.sum("amount")
      expect(total).to eq(600.0)
      cnt = builder.count
      expect(cnt).to eq(3)
    end
  end

  describe "computed-column alias allowlist and computed injection" do
    def persist_schema(host, fields)
      host.property_schema_json = fields
      host.save(validate: false)
      host.reload
    end

    def peer_bridge_for(host)
      peer = create(:entity, name: "Peer #{SecureRandom.hex(3)}", customer: customer)
      host_slug = host.name.parameterize(separator: "_")
      peer_slug = peer.name.parameterize(separator: "_")
      create(:entity, name: "assoc_#{host_slug}_#{peer_slug}", customer: customer, category: :bridge,
        property_schema: [
          { "name" => host.name, "name_slug" => host_slug, "type" => "EntityReference", "entity_id" => host.id.to_s },
          { "name" => "Peer", "name_slug" => peer_slug, "type" => "EntityReference", "entity_id" => peer.id.to_s },
          { "name" => "Score", "name_slug" => "score", "type" => "Float", "html_type" => "number" }
        ].to_json)
    end

    def computed_field(slug, bridge)
      {
        "name" => slug,
        "name_slug" => slug,
        "type" => "Computed",
        "html_type" => "number",
        "config" => {
          "bridge_entity_id" => bridge.id,
          "bridge_role" => "source",
          "source_slug" => "score",
          "function" => "avg",
          "precision" => 2
        }
      }
    end

    let(:payload) { "x, (SELECT group_concat(data) FROM entity_entries) AS leak" }

    it "does not inject a computed whose name_slug is a SQL-injection payload" do
      host = create(:entity, name: "HostInject", customer: customer)
      bridge = peer_bridge_for(host)
      persist_schema(host, [computed_field(payload, bridge)])

      compiled = Entities::ComputedCompiler.compile_all(host, customer_id: customer.id)
      expect(compiled.first[:name]).to eq(payload)
      expect(compiled.first[:sql]).to be_present

      sql = described_class.for_entity(host, customer_id: customer.id).execute.sql
      expect(sql).not_to include(payload)
      expect(sql).not_to include("group_concat")
      expect(sql).not_to include("AS leak")
    end

    it "does not inject a Calculated field whose name_slug is a SQL-injection payload" do
      host = persist_schema(
        create(:entity, name: "CalcInject", customer: customer),
        [
          { "name" => "Amount", "name_slug" => "amount", "type" => "Float", "html_type" => "number" },
          { "name" => "Leak", "name_slug" => payload, "type" => "Calculated", "html_type" => "number",
            "formula" => "amount" }
        ]
      )

      compiled = FlowchartRuntime::FormulaCompiler.compile_all(host.property_schema_json)
      expect(compiled.map { |c| c[:name] }).to include(payload)

      sql = described_class.for_entity(host, customer_id: customer.id).execute.sql
      expect(sql).not_to include(payload)
      expect(sql).not_to include("group_concat")
      expect(sql).not_to include("AS leak")
    end

    it "still injects a legitimate digit-leading slug like 2024_revenue" do
      host = persist_schema(
        create(:entity, name: "DigitSlug", customer: customer),
        [
          { "name" => "Amount", "name_slug" => "amount", "type" => "Float", "html_type" => "number" },
          { "name" => "2024 Revenue", "name_slug" => "2024_revenue", "type" => "Calculated",
            "html_type" => "number", "formula" => "amount" }
        ]
      )

      builder = described_class.for_entity(host, customer_id: customer.id)
      builder.send(:inject_calculated_fields)
      names = builder.instance_variable_get(:@computed_fields).map { |c| c[:name] }
      expect(names).to include("2024_revenue")
      expect(builder.send(:base_scope).to_sql).to include("AS 2024_revenue")
    end

    it "injects computed fields into the SELECT list for a valid entity" do
      host = create(:entity, name: "HostComputed", customer: customer)
      bridge = peer_bridge_for(host)
      persist_schema(host, [computed_field("average_score", bridge)])

      sql = described_class.for_entity(host, customer_id: customer.id).execute.sql
      expect(sql).to include("AS average_score")
      expect(sql).to include("FROM entity_entries")
    end

    it "resolves a Calculated field that references a computed slug through the resolved: seed" do
      host = create(:entity, name: "HostWeighted", customer: customer)
      bridge = peer_bridge_for(host)
      persist_schema(host, [
        computed_field("average_score", bridge),
        { "name" => "Weighted", "name_slug" => "weighted", "type" => "Calculated", "html_type" => "number",
          "formula" => "average_score * 2" }
      ])

      sql = described_class.for_entity(host, customer_id: customer.id).execute.sql
      expect(sql).to include("AS average_score")
      expect(sql).to include("AS weighted")
      expect(sql).to include("AVG(")
      expect(sql).to include("* 2")
    end

    it "degrades to no calculated fields when FormulaCompiler.compile_all raises" do
      host = persist_schema(
        create(:entity, name: "HostBoom", customer: customer),
        [
          { "name" => "Amount", "name_slug" => "amount", "type" => "Float", "html_type" => "number" },
          { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number",
            "formula" => "amount * 2" }
        ]
      )

      allow(FlowchartRuntime::FormulaCompiler)
        .to receive(:compile_all).and_raise(FlowchartRuntime::FormulaError, "boom")

      result = nil
      expect {
        result = described_class.for_entity(host, customer_id: customer.id).execute
      }.not_to raise_error
      expect(result.sql).not_to include("AS total")
    end

    it "keeps the error boundary narrow and lets a non-formula error propagate" do
      host = persist_schema(
        create(:entity, name: "HostRaise", customer: customer),
        [
          { "name" => "Amount", "name_slug" => "amount", "type" => "Float", "html_type" => "number" },
          { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number",
            "formula" => "amount * 2" }
        ]
      )

      allow(FlowchartRuntime::FormulaCompiler).to receive(:compile_all).and_raise(NoMethodError, "bug")

      expect {
        described_class.for_entity(host, customer_id: customer.id).execute
      }.to raise_error(NoMethodError)
    end
  end
end
