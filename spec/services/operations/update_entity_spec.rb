# frozen_string_literal: true

require "rails_helper"

RSpec.describe Operations::UpdateEntity do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other) { create(:customer) }
  let_it_be(:admin) { create(:user, :admin, customer: customer) }
  let_it_be(:foreign_admin) { create(:user, :admin, customer: other) }
  let_it_be(:domain) { create(:entity_domain, customer: customer, name: "Academics") }
  let(:context) { Operations::Context.new(customer: customer, actor: admin, channel: "assistant") }

  def execute(input, ctx: context)
    Operations::Activities::Execute.call(operation: "update_entity", input: input, context: ctx)
  end

  def confirm(invocation, ctx: context)
    Operations::Activities::Confirm.call(invocation: invocation, context: ctx)
  end

  def seed_student!
    create(:entity, customer: customer, name: "Course",
           property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
    Operations::Activities::Execute.call(
      operation: "create_entity",
      input: {
        "domain" => domain.name,
        "entities" => [{
          "name" => "Student",
          "attribute_groups" => [
            { "key" => "basics", "name" => "Basics", "icon" => "folder", "color" => "indigo" },
            { "key" => "extra", "name" => "Extra", "icon" => "tag", "color" => "amber" }
          ],
          "attributes" => [
            { "name" => "Email", "html_type" => "email", "group" => "basics", "rules" => [{ "type" => "presence" }] },
            { "name" => "Fax", "html_type" => "tel", "group" => "extra" }
          ],
          "associations" => [{
            "related_entity" => "Course",
            "display_field" => "title",
            "bridge_attributes" => [{ "name" => "Seat", "html_type" => "number" }]
          }]
        }]
      },
      context: context
    )
    Entity.find_by!(customer_id: customer.id, name: "Student")
  end

  def all_ops(student)
    {
      "updates" => [{
        "entity" => "Student",
        "expected_version" => student.display_current_version.version_number,
        "changes" => [
          { "op" => "set_details", "display_label" => "Learner", "description" => "Enrolled" },
          { "op" => "set_settings", "icon" => "user", "color" => "#111827", "default_values" => { "email" => "a@b.c" } },
          { "op" => "add_attribute", "attribute" => { "name" => "Phone", "html_type" => "tel" }, "position" => { "after" => "email" } },
          { "op" => "update_attribute", "slug" => "email", "set" => { "access" => { "visible_to" => { "public" => false } } } },
          { "op" => "remove_attribute", "slug" => "fax" },
          { "op" => "add_group", "group" => { "key" => "schedule", "name" => "Schedule", "icon" => "calendar", "color" => "sky" } },
          { "op" => "update_group", "key" => "basics", "set" => { "name" => "Overview" } },
          { "op" => "move_attribute", "slug" => "phone", "to_group" => "schedule" },
          { "op" => "remove_group", "key" => "extra", "move_attributes_to" => "basics" },
          { "op" => "reorder_groups", "order" => %w[schedule basics] },
          { "op" => "update_association", "related_entity" => "Course", "set" => { "display_field_label" => "Course title" } },
          { "op" => "add_bridge_attribute", "related_entity" => "Course", "attribute" => { "name" => "Note", "html_type" => "text" } },
          { "op" => "update_bridge_attribute", "related_entity" => "Course", "slug" => "seat", "set" => { "display_label" => "Seat no" } },
          { "op" => "remove_bridge_attribute", "related_entity" => "Course", "slug" => "note" },
          { "op" => "add_association", "association" => { "related_entity" => "Campus", "display_field" => "name" } },
          { "op" => "remove_association", "related_entity" => "Campus" }
        ]
      }]
    }
  end

  it "parks a plan covering all 16 ops and applies it on confirm" do
    create(:entity, customer: customer, name: "Campus",
           property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    student = seed_student!
    bridge_id = student.associations_list.first["bridge_entity_id"]
    expect(bridge_id).to be_present
    parked = execute(all_ops(student))

    expect(parked.status).to eq("confirmation_required"), Array(parked.violations).map(&:as_json).inspect
    expect(parked.plan).to be_present
    expect(Entity.find_by!(customer_id: customer.id, name: "Student").property_schema_json.map { |attr| attr["name_slug"] }).to include("fax")

    applied = confirm(parked.invocation)
    expect(applied.status).to eq("succeeded"), Array(applied.violations).map(&:as_json).inspect
    expect(applied.data["updated"].first).to include("name" => "Student")
    expect(applied.data["updated"].first).not_to have_key("slug")
    expect(applied.effects).to include(hash_including("action" => "updated", "name" => "Student"))

    student.reload
    expect(student.display_label).to eq("Learner")
    expect(student.icon).to eq("user")
    slugs = student.property_schema_json.map { |attr| attr["name_slug"] }
    expect(slugs).to include("email", "phone")
    expect(slugs).not_to include("fax")
    expect(student.attribute_groups_json.map { |group| group["id"] }).to eq(%w[schedule basics])
    expect(student.associations_list.map { |assoc| assoc["target_entity_name"] }).to eq(["Course"])
    extras = student.associations_list.first["additional_attributes"]
    expect(extras.map { |attr| attr["name_slug"] }).to include("seat")
    expect(extras.map { |attr| attr["name_slug"] }).not_to include("note")
    expect(extras.find { |attr| attr["name_slug"] == "seat" }["display_label"]).to eq("Seat no")
    expect(student.associations_list.first["bridge_entity_id"].to_s).to eq(bridge_id.to_s)
    expect(Entity.where(customer_id: customer.id, category: :bridge).pluck(:id).map(&:to_s)).to eq([bridge_id.to_s])
  end

  it "returns conflict when the entity changes between proposal and apply" do
    student = seed_student!
    parked = execute({
      "updates" => [{
        "entity" => "Student",
        "changes" => [{ "op" => "set_details", "description" => "Proposed" }]
      }]
    })
    expect(parked.status).to eq("confirmation_required")

    EntityDefinitions::Persist.call(
      { customer: customer, entities: [{ "name" => "Student", "description" => "Changed outside" }], replace: false }
    )

    outcome = confirm(parked.invocation)
    expect(outcome.status).to eq("conflict")
    expect(outcome.violations.first.code).to eq("conflict.version_changed")
    expect(student.reload.description).to eq("Changed outside")
  end

  it "returns conflict (not invalid) on approval when expected_version no longer matches" do
    student = seed_student!
    parked = execute({
      "updates" => [{
        "entity" => "Student",
        "expected_version" => student.display_current_version.version_number,
        "changes" => [{ "op" => "set_details", "description" => "Proposed" }]
      }]
    })
    EntityDefinitions::Persist.call(
      { customer: customer, entities: [{ "name" => "Student", "description" => "Changed outside" }], replace: false }
    )

    expect(confirm(parked.invocation).status).to eq("conflict")
  end

  it "reports conflict, not invalid, when the entity moved so a parked change no longer applies" do
    seed_student!
    parked = execute({ "updates" => [{ "entity" => "Student", "changes" => [{ "op" => "remove_attribute", "slug" => "fax" }] }] })
    expect(parked.status).to eq("confirmation_required")

    document = EntityDefinitions::Catalog.document_for(customer.id, "Student")
    document["property_schema"].reject! { |attr| attr["name_slug"] == "fax" }
    EntityDefinitions::Persist.call({ customer: customer, entities: [document], replace: true })

    outcome = confirm(parked.invocation)
    expect(outcome.status).to eq("conflict")
    expect(parked.invocation.reload).to be_conflict
  end

  it "never fills schema defaults into a patch" do
    student = seed_student!
    EntityDefinitions::Persist.call(
      { customer: customer, entities: [{ "name" => "Student", "icon" => "user", "color" => "#111827" }], replace: false }
    )
    Operations::Activities::Execute.call(
      operation: "update_entity",
      input: {
        "updates" => [{ "entity" => "Student", "changes" => [
          { "op" => "add_attribute", "attribute" => { "name" => "Photo", "html_type" => "image", "file" => { "accept" => "image/*", "multiple" => true } } }
        ] }]
      },
      context: context
    ).then { |parked| confirm(parked.invocation) }

    parked = execute({
      "updates" => [{ "entity" => "Student", "changes" => [
        { "op" => "update_attribute", "slug" => "photo", "set" => { "file" => { "accept" => "image/png" } } },
        { "op" => "update_attribute", "slug" => "email", "set" => { "access" => { "visible_to" => { "public" => false } } } },
        { "op" => "set_settings", "default_values" => { "email" => "x@y.z" } }
      ] }]
    })
    expect(confirm(parked.invocation).status).to eq("succeeded")

    student.reload
    photo = student.property_schema_json.find { |attr| attr["name_slug"] == "photo" }
    email = student.property_schema_json.find { |attr| attr["name_slug"] == "email" }
    expect(photo["config"]).to eq("accept" => "image/png", "multiple" => true)
    expect(email["visibility"]).to eq("admin" => true, "member" => true, "public" => false)
    expect([student.icon, student.color]).to eq(["user", "#111827"])
  end

  it "sets and clears the owner flag on a reference through update_attribute" do
    person_model = EntityDefinitions::Capabilities::PERSON_MODEL
    enable_module!("authentication", customer, name: "Authentication").set_extendable_model!(person_model, true)
    created = Operations::Activities::Execute.call(operation: "create_entity", context: context, input: {
      "domain" => domain.name,
      "entities" => [
        { "name" => "Learner", "extends" => person_model,
          "attributes" => [{ "name" => "Learner ID", "slug" => "learner_id", "html_type" => "text" }] },
        { "name" => "Assignment",
          "attributes" => [
            { "name" => "Title", "slug" => "title" },
            { "name" => "Learner", "slug" => "learner", "html_type" => "select",
              "options" => { "source" => "entity_entries", "entity" => "Learner", "label_field" => "learner_id" } }
          ] }
      ]
    })
    expect(created.status).to eq("succeeded")
    assignment = Entity.find_by!(customer_id: customer.id, name: "Assignment")

    flag = lambda do |value|
      parked = execute({ "updates" => [{ "entity" => "Assignment", "changes" => [
        { "op" => "update_attribute", "slug" => "learner", "set" => { "owner" => value } }
      ] }] })
      expect(parked.status).to eq("confirmation_required")
      applied = confirm(parked.invocation)
      expect(applied.status).to eq("succeeded")
      assignment.reload.property_schema_json.find { |attr| attr["name_slug"] == "learner" }
    end

    expect(flag.call(true)["owner"]).to be(true)
    expect(People::Ownership.owner_reference(assignment.reload).slug).to eq("learner")
    expect(flag.call(false)).not_to have_key("owner")
  end

  it "rejects an update that names the same entity twice" do
    seed_student!
    outcome = execute({
      "updates" => [
        { "entity" => "Student", "changes" => [{ "op" => "set_details", "description" => "One" }] },
        { "entity" => "Student", "changes" => [{ "op" => "set_details", "description" => "Two" }] }
      ]
    })

    expect(outcome.status).to eq("invalid")
    expect(outcome.violations.map { |violation| [violation.code, violation.pointer] })
      .to eq([["entity.duplicate_in_request", "/updates/1/entity"]])
  end

  it "rejects a stale expected_version before parking" do
    student = seed_student!
    outcome = execute({
      "updates" => [{
        "entity" => "Student",
        "expected_version" => student.display_current_version.version_number + 9,
        "changes" => [{ "op" => "set_details", "description" => "Nope" }]
      }]
    })

    expect(outcome.status).to eq("invalid")
    expect(outcome.violations.first.code).to eq("conflict.version_changed")
    expect(outcome.violations.first.resolution).to eq("refresh")
  end

  it "isolates tenants and forbids a foreign admin" do
    seed_student!
    create(:entity, customer: other, name: "Foreign")

    expect(execute({
      "updates" => [{ "entity" => "Foreign", "changes" => [{ "op" => "set_details", "description" => "X" }] }]
    }).violations.first.code).to eq("entity.not_found")

    ctx = Operations::Context.new(customer: customer, actor: foreign_admin, channel: "assistant")
    expect(execute({
      "updates" => [{ "entity" => "Student", "changes" => [{ "op" => "set_details", "description" => "X" }] }]
    }, ctx: ctx).status).to eq("forbidden")
  end

  it "reports missing attributes with pointers and does not park a write" do
    seed_student!
    outcome = execute({
      "updates" => [{
        "entity" => "Student",
        "changes" => [{ "op" => "remove_attribute", "slug" => "missing" }]
      }]
    })

    expect(outcome.status).to eq("invalid")
    expect(outcome.violations.first.code).to eq("attribute.not_found")
    expect(outcome.violations.first.pointer).to eq("/updates/0/changes/0/slug")
  end

  it "rejects retyping a display field other entities still list" do
    course = create(:entity, customer: customer, name: "Course",
                    property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
    create(:entity, customer: customer, name: "Application",
           property_schema: [{
             "name" => "Course", "name_slug" => "course", "html_type" => "select",
             "config" => { "options_source" => "entity_entries", "entity_id" => course.id.to_s, "label_field" => "title" }
           }].to_json)

    outcome = execute({
      "updates" => [{
        "entity" => "Course",
        "expected_version" => course.display_current_version.version_number,
        "changes" => [{ "op" => "update_attribute", "slug" => "title", "set" => { "html_type" => "textarea" } }]
      }]
    })

    expect(outcome.violations.map(&:code)).to include("attribute.display_field_in_use")
    expect(outcome.violations.find { |violation| violation.code == "attribute.display_field_in_use" }.details["fields"])
      .to eq("Application › Course")
  end

  it "rejects hiding a display field from a launched form audience" do
    course = create(:entity, customer: customer, name: "Course",
                    property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
    page = create(:page, :for_member, :for_public, customer: customer, launched: true, name: "Apply", entity: course,
                  configuration_json: { "metadata" => {}, "pages" => [{ "fields" => [
                    { "id" => "f1", "label" => "Course", "html_type" => "select",
                      "dynamic_options" => { "options_source" => "entity_entries", "entity_id" => course.id.to_s, "label_field" => "title" } }
                  ] }] })

    outcome = execute({
      "updates" => [{
        "entity" => "Course",
        "expected_version" => course.display_current_version.version_number,
        "changes" => [{ "op" => "update_attribute", "slug" => "title",
                        "set" => { "access" => { "visible_to" => { "public" => false } } } }]
      }]
    })

    hidden = outcome.violations.find { |violation| violation.code == "attribute.display_field_hidden" }
    expect(hidden).to be_present
    expect(hidden.details).to include("slug" => "title", "audience" => "public", "form" => page.name)
  end

  describe "status lifecycle" do
    let(:lifecycle) do
      { "transitions" => [{ "from" => "draft", "to" => "submitted", "by" => %w[member] },
                          { "from" => "submitted", "to" => "approved", "by" => %w[admin] }] }
    end
    let(:values) do
      [{ "label" => "Draft", "value" => "draft", "default" => true },
       { "label" => "Submitted", "value" => "submitted" }, { "label" => "Approved", "value" => "approved" }]
    end

    def seed_application!
      created = Operations::Activities::Execute.call(
        operation: "create_entity",
        input: { "domain" => domain.name, "entities" => [{ "name" => "Application", "attributes" => [
          { "name" => "Status", "html_type" => "select", "options" => { "source" => "static", "values" => values },
            "lifecycle" => lifecycle }
        ] }] },
        context: context
      )
      expect(created.status).to eq("succeeded"), Array(created.violations).map(&:as_json).inspect
      Entity.find_by!(customer_id: customer.id, name: "Application")
    end

    def stored_status(entity) = entity.reload.property_schema_json.find { |attr| attr["name_slug"] == "status" }

    def update_status(set)
      execute({ "updates" => [{ "entity" => "Application",
                                "changes" => [{ "op" => "update_attribute", "slug" => "status", "set" => set }] }] })
    end

    it "is created, read back by get_entity, kept by an unrelated patch and cleared by null" do
      application = seed_application!
      expect(stored_status(application)["lifecycle"]).to eq(lifecycle)

      read = Operations::Activities::Execute.call(operation: "get_entity", input: { "entity" => "Application" }, context: context)
      expect(read.data["entity"]["attributes"].find { |attr| attr["slug"] == "status" }["lifecycle"]).to eq(lifecycle)

      relabelled = confirm(update_status({ "display_label" => "State" }).invocation)
      expect(relabelled.status).to eq("succeeded"), Array(relabelled.violations).map(&:as_json).inspect
      expect(stored_status(application)).to include("display_label" => "State", "lifecycle" => lifecycle)

      cleared = confirm(update_status({ "lifecycle" => nil }).invocation)
      expect(cleared.status).to eq("succeeded"), Array(cleared.violations).map(&:as_json).inspect
      expect(stored_status(application)).not_to have_key("lifecycle")
    end

    it "refuses an options change that drops a state the lifecycle names" do
      application = seed_application!
      outcome = update_status({ "options" => { "source" => "static", "values" => values.first(2) } })

      expect(outcome.status).to eq("invalid")
      expect(outcome.violations.map { |violation| [violation.code, violation.details["state"]] })
        .to include(["entity.lifecycle_unknown_state", "approved"])
      expect(stored_status(application)["lifecycle"]).to eq(lifecycle)
    end

    it "refuses a lifecycle added to a text field" do
      seed_application!
      outcome = execute({ "updates" => [{ "entity" => "Application", "changes" => [
        { "op" => "add_attribute", "attribute" => { "name" => "Notes", "lifecycle" => lifecycle } }
      ] }] })

      expect(outcome.status).to eq("invalid")
      expect(outcome.violations.map(&:code)).to include("entity.lifecycle_not_choice")
    end
  end
end
