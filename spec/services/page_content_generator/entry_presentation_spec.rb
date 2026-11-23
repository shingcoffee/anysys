# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageContentGenerator, "entry presentation" do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, name: "Student", property_schema: [
      { "name" => "Name", "name_slug" => "name", "html_type" => "text" },
      { "name" => "Status", "name_slug" => "status", "html_type" => "select",
        "config" => { "options" => [{ "label" => "Applicant", "value" => "applicant", "default" => true },
                                    { "label" => "Enrolled", "value" => "enrolled" }] } },
      { "name" => "Notes", "name_slug" => "notes", "html_type" => "textarea" },
      { "name" => "Photo", "name_slug" => "photo", "html_type" => "file" },
      { "name" => "Agree", "name_slug" => "agree", "html_type" => "checkbox" },
      { "name" => "Mentor", "name_slug" => "mentor", "html_type" => "select" },
      { "name" => "Nickname", "name_slug" => "nickname", "html_type" => "text" }
    ].to_json)
  end

  def section(label, content: nil)
    { "id" => "s_#{label.parameterize}", "field_type" => "section", "property_type" => "layout", "label" => label, "content" => content }
  end

  def divider = { "id" => "d_#{SecureRandom.hex(2)}", "field_type" => "divider", "property_type" => "layout" }

  def input(slug, html_type = "text", **extra)
    { "id" => "f_#{slug}", "property_slug" => slug, "html_type" => html_type, "field_type" => html_type,
      "property_type" => "string", "label" => slug.titleize, "source" => "entity", "width" => "half" }.merge(extra.stringify_keys)
  end

  def options(*values) = values.map { |value| { "label" => value.titleize, "value" => value } }

  def generate(steps, presentation: :entry, settings: {})
    page = create(:page, customer: customer, entity: entity, configuration_json: {
      "metadata" => { "entity_id" => entity.id }, "form_settings" => settings, "pages" => steps
    })
    described_class.new(page, presentation: presentation).generate
  end

  let(:student_step) do
    { "id" => "page_1", "name" => "Student",
      "fields" => [section("Identity", content: "Who the student is"), input("name"),
                   input("status", "select", options: options("applicant", "enrolled")),
                   divider, section("Notes"), input("notes", "textarea")] }
  end

  it "lays the form out as the entry form, with one group per section and the entry form's action bar" do
    content = generate([student_step])

    expect(content).to include("Admin::Pages::FormComponent.new(", "**page_form_options", "submit_text: nil")
    expect(content).not_to include("FormFields::PageComponent", "FormFields::FormComponent", "FormFields::WizardComponent",
                                   "FormFields::DividerElementComponent", "FormFields::SectionElementComponent")
    expect(content.scan("Admin::Entities::EntryGroupComponent.new").size).to eq(2)
    expect(content).to include('label: "Identity", separated: false, description: "Who the student is"')
    expect(content).to include('label: "Notes", separated: true')
    expect(content).to include("hidden_field_tag :_page_id, @page.id")
  end

  it "names, ids and spans each input as the page submission and the entry grid expect" do
    content = generate([student_step])

    expect(content).to include('field_name: "entity[name]"', 'id: "f_name"', 'html_type: "text"')
    expect(content).to include(%(<div data-field-id="f_name" class="min-w-0">))
    expect(content).to include(%(<div data-field-id="f_notes" class="min-w-0 md:col-span-2">))
  end

  it "starts a field without a prefill at the entity's default option" do
    content = generate([student_step])

    expect(content).to include('value: page_prefill_value("status", default: "applicant")')
    expect(content).to include('value: page_prefill_value("name")')
    expect(content).to include('options: [["Applicant", "applicant"], ["Enrolled", "enrolled"]]')
  end

  it "prefers the entity's configured default value" do
    entity.default_properties_json = { "name" => "Ada" }
    entity.save!
    content = generate([{ "id" => "page_1", "fields" => [input("name")] }])

    expect(content).to include('value: page_prefill_value("name", default: "Ada")')
  end

  it "joins every step into the one form, naming a section-less step's group after the step" do
    content = generate([student_step, { "id" => "page_2", "name" => "Extra", "fields" => [input("nickname")] }])

    expect(content.scan("Admin::Pages::FormComponent.new").size).to eq(1)
    expect(content).to include('label: "Extra", separated: true')
  end

  it "drops a group whose inputs the viewer can see none of" do
    content = generate([{ "id" => "page_1", "fields" => [input("unbound")] }, student_step])

    expect(content.scan("Admin::Entities::EntryGroupComponent.new").size).to eq(2)
    expect(content).to include('label: "Identity", separated: false')
  end

  it "leaves a single-step page's section-less group for the entry form's fallback title" do
    content = generate([{ "id" => "page_1", "name" => "Student", "fields" => [input("name")] }])

    expect(content).to include('label: "", separated: false')
  end

  it "passes the page's own submit text and placeholder through" do
    content = generate([{ "id" => "page_1", "fields" => [input("name", placeholder: "Full name")] }],
                       settings: { "submit_button_text" => "Enrol" })

    expect(content).to include('submit_text: "Enrol"', 'placeholder: "Full name"')
  end

  it "keeps the page control for a type the entry form has no control for" do
    content = generate([{ "id" => "page_1", "fields" => [input("photo", "file"), input("agree", "checkbox", options: [{ "label" => "A", "value" => "a" }])] }])

    expect(content).not_to include("Admin::Pages::FormFieldComponent")
    expect(content).to include("FormFields::FileUploadFieldComponent", "FormFields::CheckboxFieldComponent")
    expect(content).to include(%(<div class="min-w-0 md:col-span-2">))
  end

  it "lists an entity-backed dropdown's records at render time with + Add New" do
    reference = input("mentor", "select", dynamic_options: { "options_source" => "entity_entries", "entity_id" => "59", "label_field" => "name" })
    content = generate([{ "id" => "page_1", "fields" => [reference] }])

    expect(content).to include("_dyn_opts_f_mentor = Entities::ReferenceOptions.call(entity_id: 59")
    expect(content).to include("options: _dyn_opts_f_mentor", 'quick_add: page_entity_quick_add(59, "name")')
  end

  it "hides a locked input's cell, records query included, when the run binds it" do
    reference = input("mentor", "select", dynamic_options: { "options_source" => "entity_entries", "entity_id" => "59", "label_field" => "name" })
    page = build(:page, customer: customer, entity: entity, configuration_json: {
      "metadata" => { "entity_id" => entity.id }, "pages" => [{ "id" => "page_1", "fields" => [input("name"), reference] }],
      "form_settings" => { "inputs" => [{ "field" => "mentor", "entity_id" => "59" }] }
    })
    content = described_class.new(page, presentation: :entry).generate

    guarded = content[/<% unless page_input_bound\?\("mentor"\) %>(.*?)<% end %>/m, 1]
    expect(guarded).to include("_dyn_opts_f_mentor = Entities::ReferenceOptions.call", 'data-field-id="f_mentor"')
    expect(content.scan("page_input_bound?").size).to eq(1)
    expect(content).to include("render Pages::LockedInputsComponent", "hidden_field_tag :_run")
  end

  it "shows a refused submission's errors under the page's own fields only, in both presentations" do
    steps = [{ "id" => "page_1", "fields" => [input("name"), input("nickname", source: "base_model")] }]
    entry = generate(steps)
    themed = generate(steps, presentation: :themed)

    expect(entry).to include('errors: page_field_errors("name")')
    expect(entry).not_to include('page_field_errors("nickname")')
    expect(themed).to include('page_field_error("name")')
    expect(themed).not_to include('page_field_error("nickname")')
  end

  it "keeps hostile labels and section titles inside Ruby string literals" do
    hostile = 'x") + system("id") + (" <%= 1 %>'
    content = generate([{ "id" => "page_1", "fields" => [section(hostile), input("name", label: hostile)] }])

    expect(content).not_to include('") + system("id")', "<%= 1 %>")
  end

  it "leaves content-only pages and the themed presentation unchanged" do
    content_only = [{ "id" => "page_1", "fields" => [section("Intro")] }]
    expect(generate(content_only)).to eq(generate(content_only, presentation: :themed))
    expect(generate([student_step], presentation: :themed)).to include("FormFields::FormComponent")
  end

  it "rejects an unknown presentation" do
    expect { described_class.new(build(:page), presentation: :fancy) }.to raise_error(ArgumentError, /fancy/)
  end
end
