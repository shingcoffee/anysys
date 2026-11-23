# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageContentGenerator, "hidden sections" do
  let_it_be(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name_slug" => "name", "name" => "Name" },
      { "name_slug" => "grade", "name" => "Grade", "visibility" => { "public" => false } },
      { "name_slug" => "notes", "name" => "Notes", "visibility" => { "public" => false } }
    ].to_json)
  end

  def render_for(fields)
    config = { "pages" => [{ "id" => "p1", "fields" => fields }] }
    page = double(configuration: config.to_json, configuration_json: config, customer_id: customer.id, entity: entity, id: 7)
    html = Current.set(customer: customer, user: nil) do
      source = described_class.new(page).generate
      ApplicationController.render(inline: source, layout: false, assigns: { page: page, form_action: "/submit" })
    end
    Nokogiri::HTML.fragment(html)
  end

  def section(id, label) = { "id" => id, "field_type" => "section", "property_type" => "layout", "label" => label, "content" => "" }
  def divider(id, label: nil) = { "id" => id, "field_type" => "divider", "property_type" => "layout", "label" => label }
  def paragraph(id, text) = { "id" => id, "field_type" => "paragraph", "property_type" => "layout", "content" => text }
  # No source: the input renders as name="<slug>" while still reading the
  # bound entity's attribute visibility.
  def input(slug) = { "id" => slug, "property_slug" => slug, "html_type" => "text", "label" => slug.titleize }

  it "drops a section whose inputs the viewer can see none of, with its divider and layout elements" do
    doc = render_for([
      section("s_main", "Main"), input("name"),
      divider("d_staff"),
      section("s_staff", "Staff only"), paragraph("p_staff", "Graded by staff"), input("grade"), input("notes")
    ])

    expect(doc.at_css('[data-field-id="s_main"]')).to be_present
    expect(doc.at_css('input[name="name"]')).to be_present
    %w[d_staff s_staff p_staff].each { |id| expect(doc.at_css(%([data-field-id="#{id}"]))).to be_nil }
    expect(doc.text).not_to include("Staff only", "Graded by staff")
  end

  it "counts inputs inside columns as the section's inputs" do
    columns = { "id" => "cols", "field_type" => "columns", "property_type" => "layout",
                "columns" => [{ "fields" => [input("grade")] }, { "fields" => [input("notes")] }] }
    doc = render_for([section("s_main", "Main"), input("name"), section("s_staff", "Staff only"), columns])

    expect(doc.at_css('[data-field-id="s_staff"]')).to be_nil
    expect(doc.at_css('[data-field-id="cols"]')).to be_nil
  end

  it "keeps a content-only section and a section with one visible input" do
    doc = render_for([
      section("s_intro", "Welcome"), paragraph("p_intro", "Please fill in"),
      section("s_mixed", "Mixed"), input("name"), input("grade")
    ])

    expect(doc.at_css('[data-field-id="s_intro"]')).to be_present
    expect(doc.at_css('[data-field-id="s_mixed"]')).to be_present
    expect(doc.at_css('input[name="name"]')).to be_present
    expect(doc.at_css('input[name="grade"]')).to be_nil
  end

  it "renders a generated divider without its default label in any locale" do
    doc = render_for([
      input("name"),
      divider("d_en", label: "Divider"), divider("d_zh", label: "分隔线"), divider("d_named", label: "Contact")
    ])

    expect(doc.text).not_to include("Divider", "分隔线")
    expect(doc.text).to include("Contact")
  end
end
