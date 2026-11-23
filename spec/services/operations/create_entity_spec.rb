# frozen_string_literal: true

require "rails_helper"

RSpec.describe Operations::CreateEntity do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other) { create(:customer) }
  let_it_be(:admin) { create(:user, :admin, customer: customer) }
  let_it_be(:foreign_admin) { create(:user, :admin, customer: other) }
  let_it_be(:domain) { create(:entity_domain, customer: customer, name: "Academics") }
  let(:context) { Operations::Context.new(customer: customer, actor: admin, channel: "assistant") }
  let(:mapper) { EntityDefinitions::Api::Mapper.new(customer: customer) }
  let!(:constant) { create(:constant, :with_status, :customer_specific, customer: customer) }

  def run(input, ctx: context)
    Operations::Activities::Execute.call(operation: "create_entity", input: input, context: ctx)
  end

  def domain_of(entity)
    EntityDomainMembership.for_customer(customer.id).find_by(entity_id: entity.id)&.entity_domain_id
  end

  def full_payload
    {
      "domain" => domain.name,
      "entities" => [
        {
          "name" => "Course",
          "attribute_groups" => [{ "key" => "basics", "name" => "Basics", "icon" => "folder", "color" => "indigo" }],
          "attributes" => [
            { "name" => "Title", "group" => "basics", "rules" => [{ "type" => "presence" }] },
            {
              "name" => "Level",
              "html_type" => "select",
              "group" => "basics",
              "options" => { "source" => "static", "values" => %w[Beginner Advanced] }
            },
            {
              "name" => "Enrollment count",
              "kind" => "computed",
              "aggregate" => { "related_entity" => "Student", "function" => "count", "direction" => "target" }
            }
          ]
        },
        {
          "name" => "Student",
          "display_label" => "Learner",
          "description" => "Enrolled people",
          "settings" => { "icon" => "custom", "color" => "#0f766e", "default_values" => { "email" => "a@b.c" } },
          "attribute_groups" => [{ "key" => "contact", "name" => "Contact", "icon" => "mail", "color" => "sky" }],
          "attributes" => [
            {
              "name" => "Email",
              "html_type" => "email",
              "group" => "contact",
              "rules" => [{ "type" => "presence" }, { "type" => "format_email" }],
              "access" => { "visible_to" => { "admin" => true, "member" => true, "public" => false } }
            },
            {
              "name" => "Status",
              "html_type" => "select",
              "group" => "contact",
              "options" => { "source" => "constant", "constant" => constant.name }
            },
            {
              "name" => "Favorite course",
              "html_type" => "select",
              "options" => { "source" => "entity_entries", "entity" => "Course", "label_field" => "title" }
            },
            { "name" => "Resume", "html_type" => "file", "file" => { "accept" => ".pdf", "multiple" => false } },
            { "name" => "Hours", "html_type" => "number" },
            { "name" => "Rate", "html_type" => "number" },
            { "name" => "Total", "kind" => "calculated", "html_type" => "number", "formula" => "hours * rate" },
            { "name" => "Course count", "kind" => "computed", "aggregate" => { "related_entity" => "Course", "function" => "count", "direction" => "source" } },
            {
              "name" => "Average score",
              "kind" => "computed",
              "aggregate" => {
                "related_entity" => "Course",
                "function" => "avg",
                "source_attribute" => "score",
                "precision" => 1,
                "direction" => "source"
              }
            }
          ],
          "associations" => [{
            "related_entity" => "Course",
            "display_field" => "title",
            "bridge_attributes" => [
              { "name" => "Enrolled On", "html_type" => "date" },
              { "name" => "Score", "html_type" => "number" }
            ]
          }]
        }
      ]
    }
  end

  it "creates a related set covering every attribute kind and returns slugs, versions, and bridges" do
    outcome = run(full_payload)

    expect(outcome.status).to eq("succeeded"), Array(outcome.violations).map(&:as_json).inspect
    expect(outcome.data["created"].map { |row| row["name"] }).to match_array(%w[Course Student])
    expect(outcome.data["domain"]).to eq(domain.name)
    expect(outcome.data["bridges"]).to include("assoc_student_course")
    expect(outcome.effects).to include(hash_including("kind" => "entity", "action" => "created", "name" => "Student"))

    student = Entity.find_by!(customer_id: customer.id, name: "Student")
    row = outcome.data["created"].find { |item| item["name"] == "Student" }
    expect(row).not_to have_key("slug")
    expect(row["version"]).to eq(student.display_current_version.version_number)
    expect(row["attributes"].map { |attr| attr["slug"] }).to include("email", "total", "course_count")

    by_slug = student.property_schema_json.index_by { |attr| attr["name_slug"] }
    expect(by_slug["email"]["html_type"]).to eq("email")
    expect(by_slug["email"]["visibility"]).to include("public" => false)
    expect(by_slug["status"]["config"]).to include("source" => "constant", "constant_name" => constant.name)
    course = Entity.find_by!(customer_id: customer.id, name: "Course")
    expect(by_slug["favorite_course"]["config"]).to eq("options_source" => "entity_entries", "entity_id" => course.id.to_s, "label_field" => "title")
    expect(by_slug["resume"]["config"]).to eq("accept" => ".pdf", "multiple" => false)
    expect(by_slug["total"]).to include("type" => "Calculated", "formula" => "hours * rate")
    expect(by_slug["course_count"]["type"]).to eq(Entity::COMPUTED_TYPE)
    expect(by_slug["course_count"]["config"]).to include("bridge_role" => "source")

    email_public = {
      "name" => "Email",
      "html_type" => "email",
      "group" => "contact",
      "rules" => [{ "type" => "presence" }, { "type" => "format_email" }],
      "access" => { "visible_to" => { "admin" => true, "member" => true, "public" => false } }
    }
    expect(by_slug["email"]).to include(mapper.attribute_to_stored(email_public).except("display_label", "name_slug"))

    expect(course.computed_fields.first.dig("config", "bridge_role")).to eq("target")

    bridge = Entity.find_by!(customer_id: customer.id, name: "assoc_student_course")
    expect(domain_of(student)).to eq(domain.id)
    expect(domain_of(course)).to eq(domain.id)
    expect(domain_of(bridge)).to eq(domain.id)
  end

  it "creates a person entity and an entity whose owner reference targets it in one call" do
    person_model = EntityDefinitions::Capabilities::PERSON_MODEL
    enable_module!("authentication", customer, name: "Authentication").set_extendable_model!(person_model, true)

    outcome = run({
      "domain" => domain.name,
      "entities" => [
        { "name" => "Learner", "extends" => person_model,
          "attributes" => [{ "name" => "Learner ID", "slug" => "learner_id", "html_type" => "text" }] },
        { "name" => "Assignment",
          "attributes" => [
            { "name" => "Title", "slug" => "title" },
            { "name" => "Learner", "slug" => "learner", "html_type" => "select", "owner" => true,
              "options" => { "source" => "entity_entries", "entity" => "Learner", "label_field" => "learner_id" } }
          ] }
      ]
    })

    expect(outcome.status).to eq("succeeded")
    assignment = Entity.find_by!(customer_id: customer.id, name: "Assignment")
    expect(People::Ownership.owner_reference(assignment)).to have_attributes(slug: "learner")
  end

  it "forbids an admin of another customer and does not write" do
    ctx = Operations::Context.new(customer: customer, actor: foreign_admin, channel: "assistant")
    outcome = run({ "domain" => domain.name, "entities" => [{ "name" => "X" }] }, ctx: ctx)

    expect(outcome.status).to eq("forbidden")
    expect(Entity.find_by(customer_id: customer.id, name: "X")).to be_nil
  end

  it "returns pointed semantic violations without writing" do
    create(:entity, customer: customer, name: "Course")
    outcome = run({ "domain" => domain.name, "entities" => [{ "name" => "Course" }, { "name" => "assoc_nope" }] })

    expect(outcome.status).to eq("invalid")
    expect(outcome.violations.map(&:code)).to include("entity.already_exists", "entity.name_reserved")
    expect(outcome.violations.map(&:pointer)).to include("/entities/0/name", "/entities/1/name")
    expect(Entity.find_by(customer_id: customer.id, name: "assoc_nope")).to be_nil
  end

  # Validation runs before the customer lock. A name another writer takes in
  # between must be refused under the lock, never merged into.
  it "refuses, rather than merges into, an entity created after validation" do
    existing = create(:entity, customer: customer, name: "Course",
                               property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
    allow(EntityDefinitions::Api::SemanticValidator).to receive(:for_create).and_return([])

    outcome = run({
      "domain" => domain.name,
      "entities" => [{ "name" => "Course", "attributes" => [{ "name" => "Phone", "html_type" => "tel" }] }]
    })

    expect(outcome.status).to eq("invalid")
    expect(outcome.violations.map { |violation| [violation.code, violation.pointer] })
      .to eq([["entity.already_exists", "/entities/0/name"]])
    expect(existing.reload.property_schema_json.map { |attr| attr["name_slug"] }).to eq(["title"])
  end

  it "never lets Persist update an existing entity in create-only mode" do
    create(:entity, customer: customer, name: "Course")
    _signal, (ctx, *) = EntityDefinitions::Persist.call(
      { customer: customer, entities: [{ "name" => "Course", "description" => "X" }], create_only: true }
    )

    expect(ctx[:errors]).to include(I18n.t("operations.violations.entity.already_exists", name: "Course"))
    expect(Entity.find_by!(customer_id: customer.id, name: "Course").description).not_to eq("X")
  end

  it "caps the length of a format_custom pattern" do
    outcome = run({ "domain" => domain.name, "entities" => [{ "name" => "Course", "attributes" => [
      { "name" => "Code", "rules" => [{ "type" => "format_custom", "pattern" => "a" * 501 }] }
    ] }] })

    expect(outcome.violations.map(&:code)).to include("schema.max_length")
  end

  it "requires label_field on an entity_entries options list" do
    outcome = run({
      "domain" => domain.name,
      "entities" => [
        { "name" => "Course" },
        {
          "name" => "Application",
          "attributes" => [{
            "name" => "Course",
            "html_type" => "select",
            "options" => { "source" => "entity_entries", "entity" => "Course" }
          }]
        }
      ]
    })

    expect(outcome.violations.map(&:code)).to include("schema.required")
  end

  it "rejects value_field on an entity_entries options list" do
    outcome = run({
      "domain" => domain.name,
      "entities" => [
        { "name" => "Course" },
        {
          "name" => "Application",
          "attributes" => [{
            "name" => "Course",
            "html_type" => "select",
            "options" => { "source" => "entity_entries", "entity" => "Course", "label_field" => "title", "value_field" => "code" }
          }]
        }
      ]
    })

    expect(outcome.violations.map(&:code)).to include("schema.unknown_property")
  end

  it "requires domain" do
    outcome = run({ "entities" => [{ "name" => "Course" }] })

    expect(outcome.status).to eq("invalid")
    expect(outcome.violations.map(&:code)).to include("schema.required")
    expect(Entity.find_by(customer_id: customer.id, name: "Course")).to be_nil
  end

  it "returns not_found when the domain is missing" do
    outcome = run({ "domain" => "Missing", "entities" => [{ "name" => "Course" }] })

    expect(outcome.status).to eq("invalid")
    expect(outcome.violations.map { |violation| [violation.code, violation.pointer] })
      .to eq([["entity_domain.not_found", "/domain"]])
    expect(outcome.violations.first.details["name"]).to eq("Missing")
    expect(Entity.find_by(customer_id: customer.id, name: "Course")).to be_nil
  end

  it "does not find another tenant's domain" do
    create(:entity_domain, customer: other, name: "Foreign")
    outcome = run({ "domain" => "Foreign", "entities" => [{ "name" => "Course" }] })

    expect(outcome.status).to eq("invalid")
    expect(outcome.violations.map(&:code)).to eq(["entity_domain.not_found"])
    expect(Entity.find_by(customer_id: customer.id, name: "Course")).to be_nil
  end
end
