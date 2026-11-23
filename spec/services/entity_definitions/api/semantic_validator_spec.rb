# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityDefinitions::Api::SemanticValidator do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other) { create(:customer) }

  def codes_for(specs)
    described_class.for_create(specs, customer: customer).map(&:code)
  end

  def create_violations(specs)
    described_class.for_create(specs, customer: customer)
  end

  it "locates editable, trashed, shared, bridge, and missing names" do
    live = create(:entity, customer: customer, name: "Student")
    trashed = create(:entity, customer: customer, name: "Alumni").tap(&:soft_delete)
    shared = create(:entity, :shared, name: "Catalog")
    bridge = create(:entity, customer: customer, name: "assoc_student_course", category: :bridge)

    expect(described_class.locate(customer: customer, name: "Student").status).to eq(:ok)
    expect(described_class.locate(customer: customer, name: "Alumni").status).to eq(:in_trash)
    expect(described_class.locate(customer: customer, name: "Catalog").status).to eq(:not_editable)
    expect(described_class.locate(customer: customer, name: "assoc_student_course").status).to eq(:not_editable)
    missing = described_class.locate(customer: customer, name: "Studnt")
    expect(missing.status).to eq(:not_found)
    expect(missing.candidates).to include("Student")
    expect(described_class.locate(customer: other, name: "Student").status).to eq(:not_found)
    expect(live).to be_present
    expect(trashed).to be_inactive
    expect(shared).to be_shared
    expect(bridge).to be_bridge_entity
  end

  it "rejects reserved names, duplicates, trash collisions, and assoc_ prefixes" do
    create(:entity, customer: customer, name: "Course")
    create(:entity, customer: customer, name: "Old").tap(&:soft_delete)

    expect(codes_for([{ "name" => "assoc_x" }])).to include("entity.name_reserved")
    expect(codes_for([{ "name" => "Course" }])).to include("entity.already_exists")
    expect(codes_for([{ "name" => "Old" }])).to include("entity.name_in_trash")
    dupes = create_violations([{ "name" => "A" }, { "name" => "A" }])
    expect(dupes.map(&:code)).to include("entity.duplicate_in_request")
    expect(dupes.first.pointer).to eq("/entities/0/name")
  end

  it "validates groups, attributes, rules, options, files, formulas, and associations" do
    violations = create_violations([{
      "name" => "Student",
      "extends" => "NotAModel",
      "settings" => { "default_values" => { "missing" => "x" } },
      "attribute_groups" => [
        { "key" => "a", "name" => "One" },
        { "key" => "a", "name" => "One" }
      ],
      "attributes" => [
        { "name" => "Title", "group" => "ghost" },
        { "name" => "Title" },
        { "name" => "Id", "slug" => "id" },
        { "name" => "Bio", "html_type" => "text", "rules" => [{ "type" => "numericality" }] },
        { "name" => "Score", "html_type" => "number", "rules" => [{ "type" => "length_in_range", "min" => 9, "max" => 1 }] },
        { "name" => "Code", "html_type" => "text", "rules" => [{ "type" => "format_custom", "pattern" => "(" }] },
        { "name" => "Notes", "html_type" => "textarea", "options" => { "source" => "static", "values" => %w[a a] } },
        { "name" => "Status", "html_type" => "select", "options" => { "source" => "constant", "constant" => "Nope" } },
        { "name" => "Photo", "html_type" => "text", "file" => { "accept" => ".png" } },
        { "name" => "Total", "kind" => "input", "formula" => "x + 1" },
        { "name" => "Calc", "kind" => "calculated", "formula" => "ghost * 2" }
      ],
      "associations" => [
        { "related_entity" => "Student", "display_field" => "title" },
        { "related_entity" => "Missing", "display_field" => "nope" }
      ]
    }])

    expect(violations.map(&:code)).to include(
      "extends.not_allowed",
      "settings.unknown_default_key",
      "group.duplicate_key",
      "group.duplicate_name",
      "attribute.unknown_group",
      "attribute.duplicate_name",
      "attribute.reserved_slug",
      "rule.not_allowed",
      "rule.invalid_range",
      "rule.invalid_pattern",
      "options.not_applicable",
      "options.duplicate_values",
      "options.constant_not_found",
      "file.not_applicable",
      "formula.not_applicable",
      "formula.unknown_reference",
      "association.self_reference",
      "association.target_not_found"
    )
    expect(violations.all? { |violation| violation.pointer.present? }).to be(true)
    expect(violations.find { |violation| violation.code == "options.constant_not_found" }.resolution).to eq("ask_user")
  end

  it "allows same-request entity references and reports missing aggregate associations" do
    violations = create_violations([
      {
        "name" => "Course",
        "attributes" => [{ "name" => "Title" }]
      },
      {
        "name" => "Student",
        "attributes" => [
          { "name" => "Email", "html_type" => "email" },
          { "name" => "Count", "kind" => "computed", "aggregate" => { "related_entity" => "Ghost", "function" => "count" } },
          { "name" => "Avg", "kind" => "computed",
            "aggregate" => { "related_entity" => "Course", "function" => "avg", "source_attribute" => "score" } }
        ],
        "associations" => [{
          "related_entity" => "Course",
          "display_field" => "title",
          "bridge_attributes" => [{ "name" => "Note", "html_type" => "text" }]
        }]
      }
    ])

    expect(violations.map(&:code)).to include(
      "aggregate.association_missing",
      "aggregate.source_not_found"
    )
    expect(violations.map(&:code)).not_to include("association.target_not_found")
  end

  describe "the person entity" do
    let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
    let(:course) { { "name" => "Course", "attributes" => [{ "name" => "Title", "slug" => "title" }] } }

    before do
      enable_module!("authentication", customer, name: "Authentication").set_extendable_model!(person_model, true)
    end

    def allow_person_attributes(*names)
      module_record = FeatureModules::Module.find_by!(key: "authentication")
      names.each do |name|
        module_record.set_extendable_attribute!(person_model, name, true, candidates: Authentication::User.column_names)
      end
    end

    def person(name, **extra)
      { "name" => name, "extends" => person_model, "attributes" => [{ "name" => "Member ID" }] }.merge(extra.stringify_keys)
    end

    it "accepts one person entity listed first that owns the call's associations" do
      student = person("Student", associations: [{ "related_entity" => "Course", "display_field" => "title" }])

      expect(create_violations([student, course])).to be_empty
    end

    it "rejects a second person entity in the same call" do
      violations = create_violations([person("Student"), person("Guardian")])
      violation = violations.find { |row| row.code == "extends.person_not_unique" }

      expect(violation.pointer).to eq("/entities/1/extends")
      expect(violation.details).to include("name" => "Guardian", "primary" => "Student")
      expect(violation.message).to include("Guardian", "Student")
    end

    it "requires the person entity to be listed first" do
      violation = create_violations([course, person("Student")]).find { |row| row.code == "entity.person_not_first" }

      expect(violation.pointer).to eq("/entities/1")
      expect(violation.resolution).to eq("fix_payload")
    end

    it "rejects another entity in the call associating back to the person entity" do
      linked = course.merge("associations" => [{ "related_entity" => "Student", "display_field" => "member_id" }])
      violation = create_violations([person("Student"), linked]).find { |row| row.code == "association.person_not_primary" }

      expect(violation.pointer).to eq("/entities/1/associations/0/related_entity")
      expect(violation.details).to include("name" => "Student", "entity" => "Course")
    end

    it "leaves calls without a person entity and links to an existing person entity alone" do
      create(:entity, customer: customer, name: "Student", extended_model: person_model)
      linked = course.merge("associations" => [{ "related_entity" => "Student", "display_field" => "id" }])

      expect(codes_for([linked])).not_to include("association.person_not_primary", "entity.person_not_first")
    end

    it "rejects attribute slugs the base model already holds" do
      allow_person_attributes("email", "status")
      spec = person("Student", attributes: [{ "name" => "Email", "html_type" => "email" },
                                            { "name" => "Status" }, { "name" => "Enrollment status" }])
      violations = create_violations([spec]).select { |row| row.code == "attribute.reserved_by_base_model" }

      expect(violations.map { |row| row.details["slug"] }).to contain_exactly("email", "status")
      expect(violations.first.pointer).to eq("/entities/0/attributes/0/slug")
      expect(violations.first.details["model"]).to eq(person_model)
    end

    it "rejects base model slugs added by an update" do
      allow_person_attributes("email")
      document = { "name" => "Student", "extended_model" => person_model,
                   "property_schema" => [{ "name" => "Email", "name_slug" => "email", "html_type" => "email" }] }
      violation = described_class.for_update([document], customer: customer)
                                 .find { |row| row.code == "attribute.reserved_by_base_model" }

      expect(violation.pointer).to start_with("/updates/0")
      expect(violation.details).to include("slug" => "email", "model" => person_model)
    end

    it "reserves user_id on every entity" do
      plain = { "name" => "Contact", "attributes" => [{ "name" => "User", "slug" => "user_id" }] }

      expect(codes_for([plain])).to include("attribute.reserved_slug")
    end

    it "rejects a slug the record itself answers to and suggests another" do
      plain = { "name" => "Order", "attributes" => [{ "name" => "Buyer", "slug" => "customer" }] }
      violation = create_violations([plain]).find { |row| row.code == "attribute.reserved_by_record" }

      expect(violation.details).to eq("slug" => "customer", "suggestion" => "customer_ref")
      expect(violation.pointer).to eq("/entities/0/attributes/0/slug")
      expect(I18n.t("operations.violations.attribute.reserved_by_record", **violation.details.symbolize_keys)).to include("customer_ref")
    end

    it "gives an attribute named after a reserved slug a slug of its own" do
      plain = { "name" => "Order", "attributes" => [{ "name" => "Customer" }, { "name" => "User" }] }

      expect(codes_for([plain])).to be_empty
    end

    it "lets a plain entity use base model column names" do
      plain = { "name" => "Contact", "attributes" => [{ "name" => "Email", "html_type" => "email" }] }

      expect(codes_for([plain])).to be_empty
    end
  end

  describe "reference display fields" do
    let(:course_spec) do
      { "name" => "Course", "attributes" => [
        { "name" => "Title", "slug" => "title", "html_type" => "text" },
        { "name" => "Summary", "slug" => "summary", "html_type" => "textarea" }
      ] }
    end

    def application_with(label_field)
      { "name" => "Application", "attributes" => [
        { "name" => "Course", "slug" => "course", "html_type" => "select",
          "options" => { "source" => "entity_entries", "entity" => "Course", "label_field" => label_field } }
      ] }
    end

    def codes(specs) = described_class.for_create(specs, customer: customer).map(&:code)

    it "rejects a label field that cannot label a choice, including id" do
      %w[summary id].each do |label_field|
        expect(codes([course_spec, application_with(label_field)])).to include("options.label_field_not_labelable")
      end
    end

    it "accepts a labelable label field and reports an unknown one as not found" do
      expect(codes([course_spec, application_with("title")]))
        .not_to include("options.label_field_not_labelable", "options.field_not_found")
      expect(codes([course_spec, application_with("nope")])).to include("options.field_not_found")
    end

    it "rejects an association display field that cannot label a record" do
      student = { "name" => "Student", "attributes" => [{ "name" => "Name", "slug" => "name", "html_type" => "text" }],
                  "associations" => [{ "related_entity" => "Course", "display_field" => "summary", "display_field_label" => "Summary" }] }

      expect(codes([course_spec, student])).to include("association.display_field_not_labelable")
    end
  end

  describe "owner flag" do
    let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }

    def person_student
      {
        "name" => "Student",
        "extends" => person_model,
        "attributes" => [{ "name" => "Student ID", "slug" => "student_id", "html_type" => "text" }]
      }
    end

    def student_ref(owner: true)
      {
        "name" => "Student",
        "slug" => "student",
        "html_type" => "select",
        "owner" => owner,
        "options" => { "source" => "entity_entries", "entity" => "Student", "label_field" => "student_id" }
      }
    end

    before do
      enable_module!("authentication", customer, name: "Authentication").set_extendable_model!(person_model, true)
    end

    it "accepts owner: true on a reference to a person entity" do
      assignment = {
        "name" => "Assignment",
        "attributes" => [
          { "name" => "Title", "slug" => "title" },
          student_ref
        ]
      }

      expect(create_violations([person_student, assignment])).to be_empty
    end

    it "accepts owner: false and a missing owner key on any attribute" do
      assignment = {
        "name" => "Assignment",
        "attributes" => [
          { "name" => "Title", "slug" => "title", "owner" => false },
          student_ref(owner: false)
        ]
      }

      expect(create_violations([person_student, assignment])).to be_empty
    end

    it "rejects owner: true on a non-reference attribute" do
      violation = create_violations([{
        "name" => "Assignment",
        "attributes" => [{ "name" => "Title", "slug" => "title", "owner" => true }]
      }]).find { |row| row.code == "attribute.owner_invalid" }

      expect(violation.details).to eq("slug" => "title")
      expect(violation.pointer).to eq("/entities/0/attributes/0/owner")
      expect(violation.message).to eq(
        "The attribute title can mark the record's owner only when it references a person entity."
      )
    end

    it "rejects owner: true on a reference to a non-person entity" do
      course = { "name" => "Course", "attributes" => [{ "name" => "Title", "slug" => "title", "html_type" => "text" }] }
      assignment = {
        "name" => "Assignment",
        "attributes" => [{
          "name" => "Course",
          "slug" => "course",
          "html_type" => "select",
          "owner" => true,
          "options" => { "source" => "entity_entries", "entity" => "Course", "label_field" => "title" }
        }]
      }
      violation = create_violations([course, assignment]).find { |row| row.code == "attribute.owner_invalid" }

      expect(violation.details).to eq("slug" => "course")
    end

    it "rejects owner: true on any attribute of a person entity" do
      spec = person_student.merge("attributes" => [
        { "name" => "Student ID", "slug" => "student_id", "html_type" => "text" },
        student_ref
      ])
      violation = create_violations([spec]).find { |row| row.code == "attribute.owner_invalid" }

      expect(violation.details).to eq("slug" => "student")
    end

    it "rejects owner: true on a bridge additional attribute" do
      course = { "name" => "Course", "attributes" => [{ "name" => "Title", "slug" => "title", "html_type" => "text" }] }
      assignment = {
        "name" => "Assignment",
        "attributes" => [{ "name" => "Title", "slug" => "title" }],
        "associations" => [{
          "related_entity" => "Course",
          "display_field" => "title",
          "bridge_attributes" => [student_ref]
        }]
      }
      violation = create_violations([person_student, course, assignment])
                    .find { |row| row.code == "attribute.owner_invalid" }

      expect(violation.details).to eq("slug" => "student")
      expect(violation.pointer).to eq("/entities/2/associations/0/bridge_attributes/0/owner")
    end

    it "rejects more than one owner flag on the same entity" do
      create(:entity, customer: customer, name: "Teacher",
             extended_model: person_model,
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
      assignment = {
        "name" => "Assignment",
        "attributes" => [
          student_ref,
          {
            "name" => "Teacher",
            "slug" => "teacher",
            "html_type" => "select",
            "owner" => true,
            "options" => { "source" => "entity_entries", "entity" => "Teacher", "label_field" => "name" }
          }
        ]
      }
      violation = create_violations([person_student, assignment])
                    .find { |row| row.code == "entity.owner_multiple" }

      expect(violation.details).to eq("name" => "Assignment")
      expect(violation.pointer).to eq("/entities/1")
      expect(violation.message).to eq(
        "The entity Assignment marks more than one attribute as the owner. Keep one."
      )
    end

    it "rejects an owner flag on an existing person entity during update" do
      document = {
        "name" => "Student",
        "extended_model" => person_model,
        "property_schema" => [{
          "name" => "Mentor",
          "name_slug" => "mentor",
          "html_type" => "select",
          "owner" => true,
          "config" => {
            "options_source" => "entity_entries",
            "options_entity_name" => "Student",
            "label_field" => "student_id"
          }
        }]
      }
      violation = described_class.for_update([document], customer: customer)
                                 .find { |row| row.code == "attribute.owner_invalid" }

      expect(violation.pointer).to start_with("/updates/0")
      expect(violation.details).to eq("slug" => "mentor")
    end
  end

  describe "status lifecycle" do
    let(:values) do
      [{ "label" => "Draft", "value" => "draft", "default" => true }, { "label" => "Submitted", "value" => "submitted" },
       { "label" => "Approved", "value" => "approved" }]
    end
    let(:transitions) do
      [{ "from" => "draft", "to" => "submitted", "by" => %w[member] },
       { "from" => "submitted", "to" => "approved", "by" => %w[admin] }]
    end

    def status(**overrides)
      { "name" => "Status", "slug" => "status", "html_type" => "select",
        "options" => { "source" => "static", "values" => values },
        "lifecycle" => { "transitions" => transitions } }.merge(overrides.stringify_keys)
    end

    def lifecycle_violations(attribute)
      create_violations([{ "name" => "Application", "attributes" => [attribute] }]).select { |row| row.code.start_with?("entity.lifecycle") }
    end

    def message(violation) = I18n.t("operations.violations.#{violation.code}", **violation.details.symbolize_keys)

    it "accepts a lifecycle on a select or radio with static options and one default" do
      expect(lifecycle_violations(status)).to be_empty
      expect(lifecycle_violations(status(html_type: "radio"))).to be_empty
    end

    it "refuses a lifecycle on anything but a static single choice input" do
      text = lifecycle_violations(status(html_type: "text", options: nil))
      constant = lifecycle_violations(status(options: { "source" => "constant", "constant" => "Levels" }))
      checkbox = lifecycle_violations(status(html_type: "checkbox"))

      [text, constant, checkbox].each { |found| expect(found.map(&:code)).to eq(["entity.lifecycle_not_choice"]) }
      expect(text.first.pointer).to eq("/entities/0/attributes/0/lifecycle")
      expect(message(text.first)).to include("status")
    end

    it "needs exactly one default option" do
      none = lifecycle_violations(status(options: { "source" => "static", "values" => values.map { |value| value.except("default") } }))
      plain = lifecycle_violations(status(options: { "source" => "static", "values" => %w[draft submitted approved] }))

      expect(none.map(&:code)).to eq(["entity.lifecycle_initial_missing"])
      expect(plain.map(&:code)).to eq(["entity.lifecycle_initial_missing"])
      expect(none.first.pointer).to eq("/entities/0/attributes/0/options/values")
    end

    it "names a state that is not an option value, with candidates" do
      found = lifecycle_violations(status(lifecycle: { "transitions" => [{ "from" => "draft", "to" => "aproved", "by" => %w[admin] }] }))

      expect(found.map(&:code)).to eq(["entity.lifecycle_unknown_state"])
      expect(found.first.pointer).to eq("/entities/0/attributes/0/lifecycle/transitions/0/to")
      expect(found.first.details).to include("slug" => "status", "state" => "aproved", "candidates" => include("approved"))
      expect(message(found.first)).to include("aproved")
    end

    it "refuses a pair listed twice and a change to the same state" do
      found = lifecycle_violations(status(lifecycle: { "transitions" => transitions + [
        { "from" => "draft", "to" => "submitted", "by" => %w[public] },
        { "from" => "approved", "to" => "approved", "by" => %w[admin] }
      ] }))

      expect(found.map(&:code)).to eq(%w[entity.lifecycle_duplicate_transition entity.lifecycle_self_transition])
      expect(found.first.details).to eq("slug" => "status", "from" => "draft", "to" => "submitted")
      expect(found.first.pointer).to eq("/entities/0/attributes/0/lifecycle/transitions/2")
      expect(found.map { |violation| message(violation) }).to all(be_present)
    end

    it "catches an update whose options no longer hold a state the lifecycle names" do
      document = {
        "name" => "Application",
        "property_schema" => [{
          "name" => "Status", "name_slug" => "status", "html_type" => "select",
          "config" => { "source" => "manual", "options" => values.first(2) },
          "lifecycle" => { "transitions" => transitions }
        }]
      }
      found = described_class.for_update([document], customer: customer).select { |row| row.code == "entity.lifecycle_unknown_state" }

      expect(found.map { |row| row.details["state"] }).to eq(["approved"])
      expect(found.first.pointer).to start_with("/updates/0")
    end
  end
end
