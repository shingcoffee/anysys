# frozen_string_literal: true

require "rails_helper"

# File and Image inputs take whether they accept several files, and which
# types, from the bound attribute, the shape its Active Storage attachment has.
RSpec.describe PageContentGenerator, "file fields" do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name_slug" => "contract", "type" => "String", "html_type" => "file",
        "config" => { "accept" => ".pdf,.docx", "multiple" => false } },
      { "name_slug" => "scans", "type" => "String", "html_type" => "file", "config" => { "multiple" => true } },
      { "name_slug" => "photo", "type" => "String", "html_type" => "image" }
    ].to_json)
  end

  def field(slug, html_type, **extra)
    { "id" => "f_#{slug}", "property_slug" => slug, "html_type" => html_type, "label" => slug.titleize,
      "source" => "entity" }.merge(extra.stringify_keys)
  end

  def generate(fields)
    page = create(:page, customer: customer, entity: entity, configuration_json: {
      "metadata" => { "entity_id" => entity.id }, "pages" => [{ "id" => "p1", "fields" => fields }]
    })
    described_class.new(page).generate
  end

  def render_call(content, slug)
    content.split("<%=").find { |chunk| chunk.include?("FileUploadFieldComponent") && chunk.include?("entity[#{slug}]") }.to_s
  end

  it "passes the attribute's accepted types and file count, not the page field's" do
    content = generate([field("contract", "file", multiple: true), field("scans", "file")])

    expect(render_call(content, "contract")).to include('accept: ".pdf,.docx"')
    expect(render_call(content, "contract")).not_to include("multiple: true")
    expect(render_call(content, "scans")).to include("multiple: true")
  end

  it "offers images on an Image field without its own accepted types" do
    expect(render_call(generate([field("photo", "image")]), "photo")).to include('accept: "image/*"')
  end
end
