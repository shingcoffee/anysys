# frozen_string_literal: true

require "rails_helper"

RSpec.describe ModuleEntriesResolver do
  let_it_be(:customer) { create(:customer) }
  let(:columns) do
    [
      { key: :name, label: "Name", sortable: true, searchable: true },
      { key: :id,   label: "ID",   sortable: true }
    ]
  end
  let(:entity)   { create(:entity, customer: customer, name: "E") }

  before do
    @p1 = create(:page, customer: customer, entity: entity, name: "Alpha")
    @p2 = create(:page, customer: customer, entity: entity, name: "Beta")
    @p3 = create(:page, customer: customer, entity: entity, name: "Gamma")
  end


  it "paginates" do
    scope = Page.for_customer(customer.id).order(:name)
    result = described_class.call(scope: scope, columns: columns, params: { page: 1, per_page: 2 })
    expect(result[:rows].size).to eq(2)
    expect(result[:pagination]).to include(page: 1, per_page: 2, total: 3, total_pages: 2)
  end

  it "applies search over searchable columns" do
    scope = Page.for_customer(customer.id)
    result = described_class.call(scope: scope, columns: columns, params: { q: "alph" })
    expect(result[:rows].map(&:name)).to eq(["Alpha"])
  end

  it "does not 500 when q is an array" do
    scope = Page.for_customer(customer.id)
    result = described_class.call(scope: scope, columns: columns, params: { q: ["alph"] })
    expect(result[:rows].map(&:name)).to eq(["Alpha"])
  end

  it "sorts" do
    scope = Page.for_customer(customer.id)
    result = described_class.call(scope: scope, columns: columns, params: { sort: "name", dir: "desc" })
    expect(result[:rows].map(&:name)).to eq(%w[Gamma Beta Alpha])
  end

  it "ignores unknown sort column" do
    scope = Page.for_customer(customer.id).order(:name)
    result = described_class.call(scope: scope, columns: columns, params: { sort: "nope", dir: "asc" })
    expect(result[:rows].map(&:name)).to eq(%w[Alpha Beta Gamma])
  end

  describe "filters" do
    let(:filter_columns) do
      [
        { key: :name,   label: "Name",   sortable: true, searchable: true },
        { key: :status, label: "Status", sortable: true }
      ]
    end

    before do
      # Use unscoped to work around SoftDeletable default scope; destroy_all (not
      # delete_all) so dependent page_versions are removed — their FK to the page
      # would otherwise block the delete.
      Page.unscoped.where(customer_id: customer.id).destroy_all
      @f1 = create(:page, customer: customer, entity: entity, name: "FilterAlpha", status: :active)
      @f2 = create(:page, customer: customer, entity: entity, name: "FilterBeta",  status: :inactive)
      @f3 = create(:page, customer: customer, entity: entity, name: "FilterGamma", status: :active)
    end

    it "applies a simple filter { key, column, value }" do
      scope = Page.unscoped.where(customer_id: customer.id)
      result = described_class.call(
        scope: scope, columns: filter_columns,
        filters: [{ key: :status, column: :status }],
        params: { status: "active" }
      )
      expect(result[:rows].map(&:id)).to contain_exactly(@f1.id, @f3.id)
    end

    it "applies a custom-scope filter" do
      scope = Page.unscoped.where(customer_id: customer.id)
      result = described_class.call(
        scope: scope, columns: filter_columns,
        filters: [{ key: :only_named, scope: ->(rel, v) { v.present? ? rel.where(name: v) : rel } }],
        params: { only_named: "FilterBeta" }
      )
      expect(result[:rows].map(&:id)).to eq([@f2.id])
    end

    it "ignores unknown filter keys" do
      scope = Page.unscoped.where(customer_id: customer.id)
      result = described_class.call(
        scope: scope, columns: filter_columns, filters: [{ key: :status, column: :status }],
        params: { unknown: "xx" }
      )
      expect(result[:rows].size).to eq(3)
    end

    it "preserves existing behavior when filters: is omitted (no regression)" do
      scope = Page.unscoped.where(customer_id: customer.id)
      result = described_class.call(scope: scope, columns: filter_columns, params: {})
      expect(result[:rows].size).to eq(3)
    end

    it "honors per_page default argument" do
      scope = Page.unscoped.where(customer_id: customer.id)
      result = described_class.call(scope: scope, columns: filter_columns, params: {}, per_page: 1)
      expect(result[:rows].size).to eq(1)
      expect(result[:pagination][:per_page]).to eq(1)
    end

    it "params[:per_page] overrides the default" do
      scope = Page.unscoped.where(customer_id: customer.id)
      result = described_class.call(scope: scope, columns: filter_columns, params: { per_page: 2 }, per_page: 1)
      expect(result[:rows].size).to eq(2)
      expect(result[:pagination][:per_page]).to eq(2)
    end

    it "caps a crafted unbounded per_page" do
      scope = Page.unscoped.where(customer_id: customer.id)
      result = described_class.call(
        scope: scope, columns: filter_columns, params: { per_page: 999_999 }
      )
      expect(result[:pagination][:per_page]).to eq(described_class::MAX_PER_PAGE)
    end

    it "does not 500 when page and per_page are arrays" do
      scope = Page.unscoped.where(customer_id: customer.id)
      result = described_class.call(
        scope: scope, columns: filter_columns, params: { page: ["2"], per_page: ["2"] }
      )
      expect(result[:pagination][:page]).to eq(1)
      expect(result[:pagination][:per_page]).to eq(described_class::DEFAULT_PER_PAGE)
      expect(result[:rows].size).to eq(3)
    end

    it "allows CSV-sized pages when max_per_page is raised" do
      scope = Page.unscoped.where(customer_id: customer.id)
      result = described_class.call(
        scope: scope, columns: filter_columns,
        params: { per_page: 100_000 }, max_per_page: 100_000
      )
      expect(result[:pagination][:per_page]).to eq(100_000)
      expect(result[:rows].size).to eq(3)
    end
  end

  describe "sql: expression columns" do
    let_it_be(:entity_for_entries) do
      create(:entity,
        customer: customer,
        property_schema: [
          { "name" => "First name", "name_slug" => "first_name", "type" => "String", "html_type" => "text" },
          { "name" => "Age", "name_slug" => "age", "type" => "String", "html_type" => "text" }
        ].to_json)
    end

    def create_entry!(data)
      create(:entity_entry, customer: customer, entity: entity_for_entries, data: data.to_json)
    end

    let(:sql_columns) do
      [
        {
          key: :first_name,
          label: "First name",
          sortable: true,
          searchable: true,
          sql: "json_extract(entity_entries.data, '$.first_name')"
        },
        {
          key: :age,
          label: "Age",
          type: :number,
          sortable: true,
          searchable: false,
          sql: "json_extract(entity_entries.data, '$.age')"
        }
      ]
    end

    before do
      EntityEntry.where(customer_id: customer.id, entity_id: entity_for_entries.id).delete_all
      @a = create_entry!("first_name" => "Alice", "age" => "10")
      @b = create_entry!("first_name" => "Bob", "age" => "9")
      @c = create_entry!("first_name" => "Carol", "age" => "11")
    end

    def scope
      EntityEntry.where(customer_id: customer.id, entity_id: entity_for_entries.id)
    end

    it "searches via col[:sql]" do
      result = described_class.call(scope: scope, columns: sql_columns, params: { q: "ali" })
      expect(result[:rows].map(&:id)).to eq([@a.id])
    end

    it "sorts via col[:sql]" do
      result = described_class.call(scope: scope, columns: sql_columns, params: { sort: "first_name", dir: "desc" })
      expect(result[:rows].map { |r| r["first_name"] }).to eq(%w[Carol Bob Alice])
    end

    it "CAST()s :number columns so 9 < 10" do
      result = described_class.call(scope: scope, columns: sql_columns, params: { sort: "age", dir: "asc" })
      expect(result[:rows].map { |r| r["age"] }).to eq(%w[9 10 11])
    end

    it "keeps bare-column SQL when :sql is absent (regression)" do
      pages = Page.for_customer(customer.id)
      result = described_class.call(
        scope: pages,
        columns: [{ key: :name, label: "Name", sortable: true, searchable: true }],
        params: { q: "alph" }
      )
      expect(result[:rows].map(&:name)).to eq(["Alpha"])
    end
  end
end
