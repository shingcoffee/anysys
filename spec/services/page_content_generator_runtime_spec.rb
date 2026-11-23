# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageContentGenerator, "runtime boundaries" do
  let_it_be(:customer) { create(:customer) }

  def generate_and_render(config, entity: nil)
    page = double(configuration: config.to_json, configuration_json: config, customer_id: customer.id, entity: entity, id: 7)
    Current.set(customer: customer, user: nil) do
      source = described_class.new(page).generate
      ApplicationController.render(inline: source, layout: false, assigns: { page: page, form_action: "/submit" })
    end
  end

  it "keeps hostile wizard ids and ERB terminators inert through template compilation" do
    payload = 'step"; raise "INJECTED"; #%><% raise "INJECTED" %>#{raise "INJECTED"}'
    html = generate_and_render({ "pages" => [
      { "id" => payload, "fields" => [{ "id" => "name", "property_slug" => "name", "html_type" => "text", "label" => payload }] },
      { "id" => "second", "fields" => [{ "id" => "email", "property_slug" => "email", "html_type" => "email" }] }
    ], "form_settings" => { "submit_button_text" => payload } })
    document = Nokogiri::HTML.fragment(html)
    expect(document.at_css('[data-step-id]')["data-step-id"]).to eq(payload)
    expect(document.at_css('button[type="submit"]').text.strip).to eq(payload)
    expect(html).not_to include('<% raise "INJECTED"')
  end

  it "uses native password, hidden and multi-select semantics in generated forms" do
    entity = create(:entity, customer: customer, property_schema: %w[password reference choices].map { |slug|
      { "name_slug" => slug, "type" => "String" }
    }.to_json)
    html = generate_and_render({ "pages" => [{ "id" => "first", "fields" => [
      { "id" => "password", "property_slug" => "password", "html_type" => "password", "source" => "entity" },
      { "id" => "reference", "property_slug" => "reference", "html_type" => "hidden", "source" => "entity" },
      { "id" => "choices", "property_slug" => "choices", "html_type" => "multi-select", "source" => "entity",
        "options" => [{ "label" => "Choice", "value" => "1" }] }
    ] }] }, entity: entity)
    document = Nokogiri::HTML.fragment(html)
    expect(document.at_css('input[type="password"]')["name"]).to eq("entity[password]")
    expect(document.at_css('input[type="hidden"][name="entity[reference]"]')).to be_present
    expect(document.at_css('select[multiple]')["name"]).to eq("entity[choices][]")
    expect(document.at_css("form")["enctype"]).to eq("multipart/form-data")
    expect(document.css('fieldset[disabled]')).to be_empty
  end

  it "renders an unbound UI control as read-only without permitting its value" do
    config = { "pages" => [{ "fields" => [{ "id" => "preview", "property_slug" => "preview", "html_type" => "text" }] }] }
    html = generate_and_render(config)
    expect(Nokogiri::HTML.fragment(html).at_css('fieldset[disabled] input[name="preview"][disabled]')).to be_present
    page = double(customer_id: customer.id, configuration_json: config)
    expect(Pages::FormParams.permit(page: page, entity: nil, params: ActionController::Parameters.new(preview: "forged"), audience: "public")).to eq({})
  end

  it "does not treat an unresolved entity binding or entity-sourced field as an unbound preview" do
    field = { "id" => "forbidden", "property_slug" => "forbidden", "html_type" => "text", "label" => "Forbidden label" }
    unresolved = { "metadata" => { "entity_id" => -1 }, "pages" => [{ "fields" => [field] }] }
    explicit = { "pages" => [{ "fields" => [field.merge("source" => "entity")] }] }
    expect(generate_and_render(unresolved)).not_to include("Forbidden label")
    expect(generate_and_render(explicit)).not_to include("Forbidden label")
  end

  it "omits unknown schema slugs even when marked computed" do
    entity = create(:entity, customer: customer, property_schema: [{ "name_slug" => "known", "type" => "String" }].to_json)
    html = generate_and_render({ "pages" => [{ "fields" => [
      { "id" => "unknown", "property_slug" => "unknown", "html_type" => "text", "storage" => "computed", "label" => "Unknown data" },
      { "id" => "known", "property_slug" => "known", "html_type" => "text" }
    ] }] }, entity: entity)
    expect(html).not_to include("Unknown data")
    expect(Nokogiri::HTML.fragment(html).at_css('input[name="known"]')).to be_present
  end

  it "preserves hashrocket syntax while neutralizing condition ERB terminators" do
    payload = '"; raise "INJECTED"; #%><% raise "INJECTED" %>#{raise "INJECTED"}'
    html = generate_and_render({ "pages" => [{ "fields" => [
      { "id" => "preview", "property_slug" => "preview", "html_type" => "text",
        "conditions" => [{ "field" => "other", "operator" => "equals", "value" => payload }] }
    ] }] })
    input = Nokogiri::HTML.fragment(html).at_css('input[name="preview"]')
    expect(JSON.parse(input["data-conditions"]).first["value"]).to eq(payload)
  end

  it "escapes composite module/listen attributes before compiling the generated ERB" do
    entity = create(:entity, customer: customer, property_schema: [{ "name_slug" => "name", "name" => "Name" }].to_json)
    create(:entity_entry, customer: customer, entity: entity, data: { "name" => "Alice" }.to_json)
    payload = 'module" onmouseover="bad()%><% raise "INJECTED" %>'
    html = generate_and_render({ "layout" => "composite", "modules" => [
      { "id" => payload, "module_type" => "list", "entity_id" => entity.id, "events" => { "listen" => [payload] }, "config" => { "columns" => ["name"] } }
    ] })
    document = Nokogiri::HTML.fragment(html)
    expect(document.at_css('[data-module-id]')["data-module-id"]).to eq(payload)
    expect(document.at_css('[data-listen-events]')["data-listen-events"]).to eq(payload)
    expect(document.at_css('[data-list-module-module-id-value]')["data-list-module-module-id-value"]).to eq(payload)
    expect(document.css('[onmouseover]')).to be_empty
  end

  it "omits audience-hidden fields even when nested in columns" do
    entity = create(:entity, customer: customer, property_schema: [
      { "name_slug" => "secret", "visibility" => { "public" => false } }, { "name_slug" => "name" }
    ].to_json)
    config = { "pages" => [{ "fields" => [
      { "id" => "columns", "field_type" => "columns", "property_type" => "layout", "columns" => [{ "fields" => [
        { "id" => "secret", "property_slug" => "secret", "html_type" => "text", "label" => "Secret label" },
        { "id" => "name", "property_slug" => "name", "html_type" => "text", "label" => "Name" }
      ] }] }
    ] }] }
    html = generate_and_render(config, entity: entity)
    expect(html).not_to include("Secret label", 'name="secret"')
    expect(html).to include('name="name"')
  end

  %w[query entity_entries].each do |source|
    it "does not expose hidden entity attributes in #{source} dropdown labels" do
      entity = create(:entity, customer: customer, property_schema: [
        { "name_slug" => "secret", "visibility" => { "public" => false } }
      ].to_json)
      create(:entity_entry, customer: customer, entity: entity, data: { "secret" => "hidden-data-value" }.to_json)
      html = generate_and_render({ "pages" => [{ "fields" => [
        { "id" => "choice", "property_slug" => "choice", "html_type" => "select", "dynamic_options" => {
          "options_source" => source, "entity_id" => entity.id, "label_field" => "secret"
        } }
      ] }] })
      document = Nokogiri::HTML.fragment(html)
      expect(document.at_css("select")).to be_present
      expect(html).not_to include("hidden-data-value")
      expect(document.css('option:not([value=""])')).to be_empty
    end
  end

  it "labels entity_entries choices with the display field, Untitled and numbered repeats" do
    entity = create(:entity, customer: customer, property_schema: [
      { "name" => "Title", "name_slug" => "title", "html_type" => "text" }
    ].to_json)
    first = create(:entity_entry, customer: customer, entity: entity, data: { "title" => "Intro" }.to_json)
    second = create(:entity_entry, customer: customer, entity: entity, data: { "title" => "Intro" }.to_json)
    blank = create(:entity_entry, customer: customer, entity: entity, data: {}.to_json)

    html = generate_and_render({ "pages" => [{ "fields" => [
      { "id" => "choice", "property_slug" => "choice", "html_type" => "select", "dynamic_options" => {
        "options_source" => "entity_entries", "entity_id" => entity.id, "label_field" => "title"
      } }
    ] }] })
    options = Nokogiri::HTML.fragment(html).css('option:not([value=""])').to_h { |option| [option["value"], option.text.strip] }

    expect(options).to eq(
      blank.id.to_s => "Untitled (##{blank.id})",
      first.id.to_s => "Intro (##{first.id})",
      second.id.to_s => "Intro (##{second.id})"
    )
  end
end
