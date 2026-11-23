# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageContentGenerator, "composite layout" do
  let_it_be(:customer) { create(:customer) }
  around { |example| Current.set(customer: customer, user: nil, shared_resources_mode: false) { example.run } }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Name", "name_slug" => "name", "type" => "String", "html_type" => "text" },
      { "name" => "Secret", "name_slug" => "secret", "type" => "String",
        "visibility" => { "public" => false, "member" => false, "admin" => true } }
    ].to_json)
  end

  before do
    create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Alice", "secret" => "Admin-only value" }.to_json)
  end

  let(:composite_configuration) do
    {
      "layout" => "composite",
      "modules" => [
        { "id" => "mod_1", "module_type" => "list", "title" => "Items",
          "entity_id" => entity.id, "width" => "full",
          "config" => { "columns" => %w[name secret], "pageSize" => 10 } }
      ],
      "metadata" => { "entity_id" => entity.id },
      "rules" => [], "calculations" => []
    }
  end

  def generate(configuration)
    page = create(:page, customer: customer, configuration: configuration.to_json)
    described_class.new(page).generate
  end

  it "generates composite layout with list module" do
    content = generate(composite_configuration)

    expect(content).to include("composite-page")
    expect(content).to include("Items")
    expect(content).to include("Alice")
    expect(content).not_to include("Admin-only value", ">Secret<")
  end

  it "uses the actual same-tenant admin audience for visible schema columns" do
    admin = create(:user, :admin, customer: customer)
    content = Current.set(user: admin) { generate(composite_configuration) }

    expect(content).to include("Alice", "Admin-only value")
  end

  it "does not read the page tenant's entity when the active render tenant is different" do
    other = create(:customer)
    admin = create(:user, :admin, customer: other)
    content = Current.set(customer: other, user: admin) { generate(composite_configuration) }

    expect(content).to include(I18n.t("public_views.composite.no_records"))
    expect(content).not_to include("Alice", "Admin-only value")
  end

  it "adds a trailing row-action column when the tile configures a row action" do
    entry = EntityEntry.find_by!(entity: entity, customer: customer)
    composite_configuration["modules"][0]["config"]["row_action"] = {
      "action_key" => "enroll", "field" => "course", "label" => "Enroll"
    }
    content = generate(composite_configuration)
    href = Pages::ActionLink.path(
      customer_id: customer.id, action_key: "enroll", prefill: { "course" => entry.id }
    )

    expect(content).to include("list-module#rowAction")
    expect(content).to include(href)
    expect(content).to include("Enroll")
    expect(content).to include("sr-only")
  end

  it "does not add a row-action column without a configured row action" do
    content = generate(composite_configuration)

    expect(content).not_to include("list-module#rowAction")
  end

  it "never turns stored record data into a row-action link" do
    EntityEntry.find_by!(entity: entity, customer: customer)
               .update_column(:data, { "name" => "Alice", "row_action_path" => "https://phish.example" }.to_json)
    content = generate(composite_configuration)

    expect(content).not_to include("list-module#rowAction")
    expect(content).not_to include(%(href="https://phish.example"))
  end

  it "does not add a row-action column on an empty list" do
    html = PageContentGenerator::CompositeRenderer.new.render_module(
      id: "mod_1", module_type: "list", title: "Items", width: "full",
      visibility: {}, events: {},
      config: { "row_action" => { "action_key" => "enroll", "field" => "course" } },
      columns: [{ slug: "name", name: "Name" }],
      records: [],
      pagination: { total_count: 0 }
    )

    expect(html).to include(I18n.t("public_views.composite.no_records"))
    expect(html).not_to include("list-module#rowAction")
  end

  it "escapes a hostile row-action path and uses the default label" do
    hostile = %(/x/actions/enroll?prefill[course]=7" onclick=alert(1))
    record = Struct.new(:id, :data_json).new(7, { "name" => "Alice" })
    html = PageContentGenerator::CompositeRenderer.new.render_module(
      id: "mod_1", module_type: "list", title: "Items", width: "full",
      visibility: {}, events: {}, config: {},
      columns: [{ slug: "name", name: "Name" }],
      records: [record],
      row_action_paths: { 7 => hostile },
      pagination: { total_count: 1 }
    )

    expect(html).to include(ERB::Util.html_escape(hostile))
    expect(html).not_to include(%(href="#{hostile}"))
    expect(html).to include(I18n.t("public_views.composite.row_action_default"))
  end

  it "falls back to standard rendering for non-composite" do
    content = generate(
      "pages" => [{ "id" => "page_1", "name" => "Test", "order" => 1, "fields" => [
        { "id" => "f1", "field_type" => "text", "label" => "Name", "property_slug" => "name",
          "property_type" => "string", "html_type" => "text", "width" => "full" }
      ] }],
      "metadata" => { "entity_id" => entity.id },
      "rules" => [], "calculations" => []
    )

    expect(content).not_to include("composite-page")
  end
end
