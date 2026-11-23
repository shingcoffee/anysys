# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::CodeGenerators::FormComponent, type: :component do
  let(:customer_id) { "81721200" }
  let(:collection_url) { "/#{customer_id}/admin/maintenance/platform/code_generators" }
  let(:form_data) { CodeGenerators::FormDataExtractor.new(category: "utility").default_form_data }

  def render_form(**opts)
    render_inline(described_class.new(form_data: form_data, customer_id: customer_id, **opts))
  end

  it "posts the new generator to the collection" do
    html = render_form
    expect(html.at_css("form")["action"]).to eq(collection_url)
    expect(html.css("input[name='_method']")).to be_empty
    expect(html.text).to include("New Generator", "Create Generator")
  end

  it "asks for the kind, file name, category and metadata" do
    html = render_form(kind: "element_type")

    expect(html.css("select[name='kind'] option").map { |option| option["value"] }).to eq(%w[step_action element_type])
    expect(html.css("option[selected]").map { |option| option["value"] }).to include("element_type")
    expect(html.css("input[name='file_name'], input[name='description'], input[name='registered_names']").size).to eq(3)
    expect(html.at_css("input[name='version']")["value"]).to eq("1.0.0")
  end

  it "offers one category per process directory, translated and preselected" do
    html = render_form
    options = html.css("select[name='category'] option")
    directories = Dir.children(described_class::PROCESS_DIR).sort

    expect(options.map { |option| option["value"] }).to eq(directories)
    expect(options.find { |option| option["value"] == "payments" }.text).to eq("Payments")
    expect(html.at_css("select[name='category'] option[selected]")["value"]).to eq("utility")
  end

  it "keeps an unknown submitted category selectable" do
    html = render_form(form_data: form_data.merge(category: "custom_area"))
    expect(html.at_css("option[value='custom_area'][selected]").text).to eq("custom_area")
  end

  it "labels the scaffold's uncategorized default in the current locale" do
    html = I18n.with_locale(:"zh-CN") { render_form(form_data: form_data.merge(category: "uncategorized")) }
    expect(html.at_css("option[value='uncategorized'][selected]").text).to eq("未分类")
  end

  it "edits the scaffolded class body in the source editor beside a preview and the helper reference" do
    html = render_form

    expect(html.at_css("textarea[name='methods_body']").text).to include("config_schema do", "def generate_body")
    expect(html.text).to include("Generated Source Preview", "Helpers")
    expect(html.at_css("form")["data-generator-form-preview-url-value"]).to eq("#{collection_url}/source_preview")
  end

  it "shows save errors" do
    expect(render_form(errors: ["File name is blank"]).text).to include("File name is blank")
  end

  it "links back to the list" do
    expect(render_form.css("a[href='#{collection_url}']").map { |link| link.text.squish }).to include("Cancel")
  end
end
