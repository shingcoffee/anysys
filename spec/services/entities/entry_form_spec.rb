# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::EntryForm do
  let(:customer) { create(:customer) }

  def field(slug, **attributes)
    { "name" => slug.titleize, "name_slug" => slug, "type" => "String" }.merge(attributes.stringify_keys)
  end

  def entity_for(schema, defaults: {}, groups: [])
    create(:entity, customer: customer, property_schema: schema.to_json,
           default_properties: defaults.to_json, attribute_groups: groups)
  end

  def form_for(schema, params: nil, defaults: {})
    described_class.new(entity: entity_for(schema, defaults: defaults), customer: customer, params: params)
  end

  def error(key) = I18n.t("admin_misc.entities.entry_form.errors.#{key}")

  it "exposes ordered descriptors, admin visibility, applicable required flags and server constraints" do
    groups = %w[identity teaching capacity internal].map do |key|
      { "id" => key, "name" => key.titleize, "icon" => "folder", "color" => EntityAttributeGroupOptions::COLORS.first }
    end
    schema = [
      field("title", group_id: "identity", display_label: "Course title", description: "Help <text>",
            validators: [{ "type" => "presence" }, { "type" => "length_maximum", "config" => { "value" => 60 } }]),
      field("status", group_id: "teaching", html_type: "select",
            config: { "options" => [{ "label" => "Planning", "value" => "draft", "default" => true }] }),
      field("capacity", group_id: "capacity", html_type: "number", validators: [
        { "type" => "numericality_integer" }, { "type" => "greater_than", "config" => { "value" => 0 } }
      ]),
      field("notes", group_id: "internal", html_type: "textarea", visibility: { "member" => false, "public" => false },
            validators: [{ "type" => "presence" }], validator_apply: { "admin" => false }),
      field("other", display_label: ""),
      field("hidden", html_type: "file", visibility: { "admin" => false }),
      field("derived", type: "Calculated", html_type: "rich-text"),
      field("computed_storage", storage: "computed", html_type: "file"),
      field("locked", readonly: true, html_type: "file"),
      field("reference", type: "EntityReference"),
      field("customer_id"), field("entity_version_number")
    ]
    entity = entity_for(schema, groups: groups)
    form = described_class.new(entity: entity, customer: customer)

    expect(form.entity.id).to eq(entity.id)
    expect(form.groups.map(&:key)).to eq(%w[identity teaching capacity internal] + [nil])
    expect(form.groups.map(&:label)).to eq(%w[Identity Teaching Capacity Internal] + [nil])
    expect(form.writable_slugs).to eq(%w[title status capacity notes other])
    expect(form.writable_slugs).to be_frozen
    fields = form.groups.flat_map(&:fields)
    expect(fields.first).to have_attributes(label: "Course title", help_text: "Help <text>",
                                          html_type: "text", required: true, constraints: { maxlength: 60 })
    expect(fields[1].options).to eq([["Planning", "draft"]])
    expect(fields[2].constraints).to eq(step: 1)
    expect(fields[3]).to have_attributes(required: false, full_width: true)
    expect(fields.last.label).to eq("Other")
    expect(form).to be_available
    expect(form.errors).to be_empty
    expect(form.value_for(:status)).to eq("draft")
  end

  it "uses defaults by key presence and retains explicit blanks, false, zero and empty arrays" do
    schema = [field("text"), field("number", html_type: "number"), field("boolean", html_type: "checkbox"),
              field("tags", html_type: "multi-select", config: { "options" => [{ "label" => "One", "value" => "1" }] }),
              field("secret", visibility: { "admin" => false })]
    defaults = { "text" => "default", "number" => 0, "boolean" => false, "tags" => ["1"], "secret" => "hidden", "id" => 999 }
    entity = entity_for(schema, defaults: defaults)
    initial = described_class.new(entity: entity, customer: customer)
    expect(initial.values).to eq("text" => "default", "number" => 0, "boolean" => "0", "tags" => ["1"])
    expect(initial.filtered_input["boolean"]).to eq("0")

    empty_post = described_class.new(entity: entity, customer: customer, params: {})
    expect(empty_post.values).to eq(initial.values)
    form = described_class.new(entity: entity, customer: customer,
                              params: { text: "", number: 0, boolean: false, tags: [], secret: "forged", id: 2 })
    expect(form.values).to eq("text" => "", "number" => 0, "boolean" => "0", "tags" => [])
    expect(form.filtered_input).to eq("text" => "", "number" => 0, "boolean" => "0", "tags" => [])
    expect(form.errors).to be_empty
  end

  it "normalizes choice values without confusing labels, false defaults or multi-select sentinels" do
    options = [{ "label" => "Zero", "value" => 0 }, { "label" => "No", "value" => false, "default" => true }]
    schema = [field("single", html_type: "select", config: { "source" => "constant", "options" => options }),
              field("many", html_type: "multi-select", config: { "options" => options })]
    initial = form_for(schema)
    expect(initial.filtered_input).to eq("single" => "false", "many" => ["false"])
    form = form_for(schema, params: { "single" => 0, "many" => ["", 0, false] })
    expect(form.filtered_input).to eq("single" => "0", "many" => %w[0 false])
    expect(form.values).to eq("single" => 0, "many" => [0, false])
    expect(form.errors).to be_empty
    expect(form_for(schema, params: { "many" => [""] }).filtered_input["many"]).to eq([])
  end

  it "rejects choice values independently of configured inclusion validators and keeps scalar attempts" do
    %w[select radio multi-select].each do |type|
      raw = type == "multi-select" ? ["Label"] : "Label"
      form = form_for([field("choice", html_type: type, config: { "options" => [{ "label" => "Label", "value" => "value" }] })],
                      params: { "choice" => raw })
      expect(form.errors_for("choice")).to eq([error("invalid_choice")])
      expect(form.value_for("choice")).to eq(raw)
      expect(form.groups.first.fields.first.options).to eq([["Label", "value"]])
    end
  end

  it "removes nil and whitespace selection members while preserving false, zero and legitimate choices" do
    schema = [field("many", html_type: "multi-select", validators: [{ "type" => "presence" }], config: { "options" => [
      { "label" => "A", "value" => "a" }, { "label" => "Zero", "value" => 0 }, { "label" => "No", "value" => false }
    ] })]
    [[" "], [nil], [], ["", "\t\n", nil]].each do |raw|
      form = form_for(schema, params: { "many" => raw })
      expect(form.filtered_input["many"]).to eq([])
      expect(form.value_for("many")).to eq([])
      expect(form.errors).to be_empty
    end
    form = form_for(schema, params: { "many" => ["", "a", " ", nil, 0, false] })
    expect(form.filtered_input["many"]).to eq(%w[a 0 false])
    expect(form.value_for("many")).to eq(["a", 0, false])
    expect(form.errors).to be_empty
    expect(form_for(schema, defaults: { "many" => [nil, " "] }).filtered_input["many"]).to eq([])
  end

  it "rejects objects, nested arrays, uploads and wrong multi-select shapes without exposing them as values" do
    schema = [field("text"), field("many", html_type: "multi-select", config: { "options" => [] })]
    upload = ActionDispatch::Http::UploadedFile.new(tempfile: Tempfile.new("entry-upload"), filename: "input.txt")
    [[], {}, ActionController::Parameters.new(nested: "value"), upload].each do |raw|
      form = form_for(schema, params: { "text" => raw, "many" => [["nested"]] })
      expect(form.errors).to eq("text" => [error("invalid_shape")], "many" => [error("invalid_shape")])
      expect(form.values).to be_empty
      expect(form.filtered_input).to be_empty
    end
    expect(form_for(schema, params: { "many" => "value" }).errors_for("many")).to eq([error("invalid_shape")])
  ensure
    upload&.tempfile&.close!
  end

  it "reads unpermitted Parameters only through the write set and rejects malformed direct inputs" do
    params = ActionController::Parameters.new(text: false, customer_id: 1, audience: "public", unknown: {})
    form = form_for([field("text")], params: params)
    expect(form.filtered_input).to eq("text" => false)
    expect(params).not_to be_permitted
    ["text", [], false].each do |raw|
      expect(form_for([field("text")], params: raw).errors_for("base")).to eq([error("invalid_shape")])
    end
  end

  it "preserves number literals and leaves configured bounds to Reform" do
    schema = [field("number", html_type: "number", validators: [{ "type" => "greater_than" }])]
    [0, -1, 1.25, "-1.25", "1e3", "0", ""].each do |raw|
      form = form_for(schema, params: { "number" => raw })
      expect(form.filtered_input["number"]).to eq(raw)
      expect(form.errors).to be_empty
    end
    ["not a number", "NaN", "Infinity", "1e999", "0x10", false].each do |raw|
      form = form_for(schema, params: { "number" => raw })
      expect(form.value_for("number")).to eq(raw)
      expect(form.errors_for("number")).to eq([error("invalid_number")])
      expect(form.groups.first.fields.first.invalid_literal).to be(true)
    end
  end

  it "checks strict real ISO dates and keeps invalid dates for a text rerender" do
    schema = [field("date", html_type: "date")]
    ["2024-02-29", "", nil].each do |raw|
      expect(form_for(schema, params: { "date" => raw }).errors).to be_empty
    end
    ["2026-02-29", "2026-04-31", "2026-1-01", "2026-01-01T12:00", 0].each do |raw|
      form = form_for(schema, params: { "date" => raw })
      expect(form.value_for("date")).to eq(raw)
      expect(form.errors_for("date")).to eq([error("invalid_date")])
      expect(form.groups.first.fields.first.invalid_literal).to be(true)
    end
  end

  it "accepts datetime-local literals and keeps invalid ones for a text rerender" do
    schema = [field("opens_at", html_type: "datetime-local")]
    form = form_for(schema)
    expect(form).to be_available
    expect(form.blockers).to be_empty
    ["2024-02-29T08:30", "2026-10-23T23:59:59", "2026-10-23T00:00:00.500", "", nil].each do |raw|
      form = form_for(schema, params: { "opens_at" => raw })
      expect(form.errors).to be_empty
      expect(form.filtered_input["opens_at"]).to eq(raw)
    end
    ["2026-02-29T08:30", "2026-10-23", "2026-10-23T24:00", "2026-10-23T12:60", "2026-10-23T12:00:60",
     "2026-10-23 12:00", "2026-10-23T12:00Z", 0].each do |raw|
      form = form_for(schema, params: { "opens_at" => raw })
      expect(form.value_for("opens_at")).to eq(raw)
      expect(form.errors_for("opens_at")).to eq([error("invalid_datetime")])
      expect(form.groups.first.fields.first.invalid_literal).to be(true)
    end
  end

  it "flags browser-unrepresentable number defaults without changing their numeric field semantics" do
    schema = [field("number", html_type: "number", validators: [{ "type" => "numericality_integer" }])]
    form = form_for(schema, defaults: { "number" => "+1" })
    expect(form.value_for("number")).to eq("+1")
    expect(form.filtered_input["number"]).to eq("+1")
    expect(form.errors).to be_empty
    expect(form.groups.first.fields.first).to have_attributes(html_type: "number", invalid_literal: true, constraints: { step: 1 })
    ["1", "-1", ".5", "1.0", "1e+3"].each do |literal|
      expect(form_for(schema, defaults: { "number" => literal }).groups.first.fields.first.invalid_literal).to be(false)
    end
    trailing_decimal = form_for(schema, defaults: { "number" => "1." })
    expect(trailing_decimal.value_for("number")).to eq("1.")
    expect(trailing_decimal.groups.first.fields.first.invalid_literal).to be(true)
  end

  it "normalizes recognized booleans and rejects other literals instead of turning them into false" do
    schema = [field("boolean", html_type: "switch")]
    { true => "1", false => "0", 0 => "0", "on" => "1", "off" => "0", "true" => "1", "false" => "0" }.each do |raw, expected|
      form = form_for(schema, params: { "boolean" => raw })
      expect(form.filtered_input["boolean"]).to eq(expected)
      expect(form.value_for("boolean")).to eq(expected)
      expect(form.errors).to be_empty
    end
    ["unexpected", "", nil, 2].each do |raw|
      form = form_for(schema, params: { "boolean" => raw })
      expect(form.errors_for("boolean")).to eq([error("invalid_boolean")])
      expect(form.value_for("boolean")).to eq(raw)
    end
  end

  it "canonicalizes recognized checkbox and switch defaults for display" do
    schema = [field("checkbox", html_type: "checkbox"), field("switch", html_type: "switch")]
    form = form_for(schema, defaults: { "checkbox" => "on", "switch" => "true" })
    expect(form.values).to eq("checkbox" => "1", "switch" => "1")
    expect(form.filtered_input).to eq(form.values)
    expect(form.errors).to be_empty
    unchecked = form_for(schema, defaults: { "checkbox" => false, "switch" => "off" })
    expect(unchecked.values).to eq("checkbox" => "0", "switch" => "0")
  end

  it "blocks unsupported visible fields, dynamic bindings, option checkboxes and ambiguous defaults" do
    schema = [field("supported"), field("upload", html_type: "file"),
              field("query", html_type: "select", config: { "source" => "query", "options" => [] }),
              field("checks", html_type: "checkbox", config: { "options" => [{ "label" => "One", "value" => "1" }] }),
              field("ambiguous", html_type: "radio", config: { "options" => [
                { "label" => "A", "value" => "a", "default" => true }, { "label" => "B", "value" => "b", "default" => true }
              ] })]
    form = form_for(schema)
    expect(form).not_to be_available
    expect(form.writable_slugs).to eq(["supported"])
    expect(form.blockers.map(&:slug)).to eq(%w[upload query checks ambiguous])
    expect(form.errors_for("base")).to be_present
    expect(form_for([])).not_to be_available
  end

  describe "entity_entries references" do
    let(:course) do
      create(:entity, customer: customer, name: "Course", property_schema: [
        { "name" => "Title", "name_slug" => "title", "html_type" => "text" },
        { "name" => "Secret", "name_slug" => "secret", "html_type" => "text",
          "visibility" => { "admin" => false, "member" => false, "public" => false } }
      ].to_json)
    end

    def application_with(html_type: "select", label_field: "title", target: course)
      create(:entity, customer: customer, name: "Application", property_schema: [
        { "name" => "Course", "name_slug" => "course", "html_type" => html_type,
          "config" => { "options_source" => "entity_entries", "entity_id" => target.id.to_s, "label_field" => label_field } }
      ].to_json)
    end

    def blocker_slugs(entity) = described_class.new(entity: entity, customer: customer).blockers.map(&:slug)

    it "lists the target's records as choices and accepts any id for the contract to check" do
      biology = create(:entity_entry, customer: customer, entity: course, data: { title: "Biology" }.to_json)
      form = described_class.new(entity: application_with, customer: customer, params: { "course" => "999999" })

      field = form.groups.flat_map(&:fields).find { |item| item.slug == "course" }
      expect(field.reference).to eq(described_class::Reference.new(entity: course, label_field: "title"))
      expect(field.options).to eq([["Biology", biology.id.to_s]])
      expect(form.blockers).to be_empty
      expect(form.errors_for("course")).to be_empty
    end

    it "supports radio references" do
      expect(blocker_slugs(application_with(html_type: "radio"))).to be_empty
    end

    it "blocks a reference whose display field is hidden from admins" do
      expect(blocker_slugs(application_with(label_field: "secret"))).to eq(["course"])
    end

    it "names no target entity for a reference that cannot label its choices" do
      blocker = described_class.new(entity: application_with(label_field: "secret"), customer: customer).blockers.first
      expect(blocker.reference).to eq(described_class::Reference.new(entity: nil, label_field: "secret"))
    end

    it "blocks a reference to a trashed entity" do
      course.soft_delete
      expect(blocker_slugs(application_with)).to eq(["course"])
    end

    it "blocks a checkbox reference, which Create Entry would read as a boolean" do
      expect(blocker_slugs(application_with(html_type: "checkbox"))).to eq(["course"])
    end
  end

  it "checks defaults with the same shape rules and merges errors without rebuilding values" do
    form = form_for([field("text")], defaults: { "text" => {} })
    expect(form.errors_for(:text)).to eq([error("invalid_shape")])
    form = form_for([field("text")], params: { "text" => "attempt" }, defaults: { "text" => {} })
    expect(form.errors).to be_empty
    expect(form.add_errors!(text: ["validation error"], hidden: ["nonrendered error"])).to equal(form)
    expect(form.values).to eq("text" => "attempt")
    expect(form.errors).to eq("text" => ["validation error"], "hidden" => ["nonrendered error"])
  end

  it "reloads the requested customer's effective shared override despite stale or platform context" do
    shared = create(:entity, :shared, property_schema: [field("global")].to_json)
    Current.set(customer: customer, shared_resources_mode: false) do
      edited = Entity.find(shared.id)
      edited.update!(property_schema: [field("tenant")].to_json, default_properties: { "tenant" => "override" }.to_json)
    end
    other = create(:customer)
    Current.set(customer: other, shared_resources_mode: true) do
      form = described_class.new(entity: shared, customer: customer)
      expect(form.writable_slugs).to eq(["tenant"])
      expect(form.values).to eq("tenant" => "override")
      expect(Current.customer).to eq(other)
      expect(Current.shared_resources_mode).to be(true)
    end
  end

  describe "editing an existing entry" do
    let(:schema) do
      [
        field("title"),
        field("status", html_type: "select", config: { "options" => [
          { "label" => "Draft", "value" => "draft", "default" => true }, { "label" => "Live", "value" => "live" }
        ] }),
        field("tags", html_type: "multi-select", config: { "options" => [{ "label" => "A", "value" => "a" }] }),
        field("enabled", html_type: "checkbox"),
        field("credits", html_type: "number"),
        field("hidden", visibility: { "admin" => false })
      ]
    end
    let(:entity) { entity_for(schema, defaults: { "title" => "Default title", "credits" => 9 }) }

    def entry_with(data)
      create(:entity_entry, :with_data, customer: customer, entity: entity, entry_data: data)
    end

    it "prefills stored values instead of definition defaults and normalizes them for display" do
      entry = entry_with("title" => "Stored", "tags" => ["a"], "enabled" => true, "credits" => 4, "hidden" => "secret")
      form = described_class.new(entity: entity, customer: customer, entry: entry)
      expect(form).to be_persisted
      expect(form.entry).to eq(entry)
      expect(form.values).to eq("title" => "Stored", "tags" => ["a"], "enabled" => "1", "credits" => 4)
      expect(form.errors).to be_empty
    end

    it "leaves fields without a stored value blank and opens stale stored values without errors" do
      entry = entry_with("status" => "retired", "credits" => "abc", "tags" => nil)
      form = described_class.new(entity: entity, customer: customer, entry: entry)
      expect(form.values).to eq("status" => "retired", "credits" => "abc")
      expect(form.errors).to be_empty
      expect(form.groups.flat_map(&:fields).find { |item| item.slug == "credits" }.invalid_literal).to be(true)
    end

    it "keeps readiness errors on the prefill and judges submitted values" do
      blocked = entity_for([field("title"), field("file", html_type: "file")])
      entry = create(:entity_entry, :with_data, customer: customer, entity: blocked, entry_data: { "title" => "Stored" })
      form = described_class.new(entity: blocked, customer: customer, entry: entry)
      expect(form).not_to be_available
      expect(form.errors["base"]).to be_present

      entry = entry_with("title" => "Stored", "credits" => 4)
      form = described_class.new(entity: entity, customer: customer, entry: entry, params: { "status" => "retired" })
      expect(form.errors_for(:status)).to eq([error("invalid_choice")])
      expect(form.filtered_input).to include("title" => "Stored", "credits" => 4, "status" => "retired")
      expect(form.filtered_input).not_to have_key("hidden")
    end
  end

  describe "bridge row forms (links)" do
    let(:course) do
      create(:entity, customer: customer, name: "Course", property_schema: [field("code", html_type: "text")].to_json)
    end
    let!(:math) { create(:entity_entry, :with_data, customer: customer, entity: course, entry_data: { "code" => "MATH" }) }
    let(:bridge) do
      create(:entity, customer: customer, category: :bridge, property_schema: [
        field("student", type: "EntityReference", html_type: "number", entity_id: "1"),
        field("course", type: "EntityReference", html_type: "select", entity_id: course.id.to_s,
                        config: { "options_source" => "entity_entries", "entity_id" => course.id.to_s, "label_field" => "code" }),
        field("grade", html_type: "number")
      ].to_json)
    end

    def bridge_form(params: nil, links: { student: 5 })
      described_class.new(entity: bridge, customer: customer, params: params, links: links)
    end

    it "hides the linked reference, offers the other reference as a dropdown and always writes the link" do
      form = bridge_form(params: { "course" => math.id.to_s, "grade" => "90", "student" => "999" })

      expect(form.links).to eq("student" => 5)
      expect(form.groups.flat_map(&:fields).map(&:slug)).to eq(%w[course grade])
      expect(form.groups.flat_map(&:fields).first.options).to eq([["MATH", math.id.to_s]])
      expect(form.writable_slugs).to eq(%w[course grade student])
      expect(form.filtered_input).to eq("course" => math.id.to_s, "grade" => "90", "student" => 5)
      expect(form).to be_available
    end

    it "skips participant references entirely without links, as for any entry form" do
      form = bridge_form(links: {})

      expect(form.groups.flat_map(&:fields).map(&:slug)).to eq(%w[grade])
      expect(form.filtered_input).not_to have_key("student")
    end

    it "is unavailable when only the linked reference would be writable" do
      bridge.update!(property_schema: [field("student", type: "EntityReference", html_type: "number", entity_id: "1")].to_json)
      form = bridge_form

      expect(form).not_to be_available
      expect(form.errors["base"]).to eq([I18n.t("admin_misc.entities.entry_form.no_fields")])
    end
  end
end
