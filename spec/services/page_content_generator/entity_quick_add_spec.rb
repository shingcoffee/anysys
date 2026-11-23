# frozen_string_literal: true

require "rails_helper"

# Entity-backed dropdowns (dynamic_options.options_source == "entity_entries")
# pass a runtime quick_add option, resolved by PageEntityQuickAddHelper, and
# list only the referenced entity's entries.
RSpec.describe PageContentGenerator, "entity quick add" do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name_slug" => "student", "type" => "String", "html_type" => "select" },
      { "name_slug" => "mentor", "type" => "String", "html_type" => "radio" },
      { "name_slug" => "peers", "type" => "String", "html_type" => "multi-select" }
    ].to_json)
  end

  def field(slug, html_type, label_field: "student_number")
    { "id" => "f_#{slug}", "property_slug" => slug, "html_type" => html_type, "label" => slug.titleize,
      "dynamic_options" => { "options_source" => "entity_entries", "entity_id" => "59", "label_field" => label_field } }
  end

  def generate(fields, bound: true)
    page = create(:page, customer: customer, entity: entity, configuration_json: {
      "metadata" => bound ? { "entity_id" => entity.id } : {},
      "pages" => [{ "id" => "p1", "fields" => fields }]
    })
    allow(page).to receive(:entity).and_return(nil) unless bound
    described_class.new(page).generate
  end

  it "passes quick_add to a single select" do
    content = generate([field("student", "select")])
    expect(content).to include('quick_add: page_entity_quick_add(59, "student_number")')
  end

  it "keeps a hostile label field inside a Ruby string literal" do
    hostile = 'x") + system("id") + ("'
    content = generate([field("student", "select", label_field: hostile)])
    expect(content).to include("page_entity_quick_add(59, #{hostile.inspect})")
  end

  it "does not offer quick add on radios or multi-selects" do
    content = generate([field("mentor", "radio"), field("peers", "multi-select")])
    expect(content).not_to include("page_entity_quick_add")
  end

  it "does not offer quick add on read-only previews" do
    content = generate([field("student", "select")], bound: false)
    expect(content).not_to include("page_entity_quick_add")
  end

  it "lists only the referenced entity's entries" do
    content = generate([field("student", "select")])
    expect(content).to include("Entities::ReferenceOptions.call(entity_id: 59, label_field: \"student_number\"")
    expect(content).to include("viewer: Current.user")
  end
end
