# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityDefinitions::Persist do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other) { create(:customer) }
  let_it_be(:domain) { create(:entity_domain, customer: customer) }

  def apply(entities, replace: false)
    Current.with_customer(customer) do
      signal, (ctx, *) = described_class.call({ entities: entities, replace: replace, domain: domain })
      [signal.to_h[:semantic], ctx]
    end
  end

  # Limits are accepted before the subscription is created. Later catalog
  # edits deliberately cannot rewrite this customer's entitlement receipt.
  def accept_entity_limit(limit)
    plan = create(:billing_plan)
    Billing::AssignPlanLimits.call(plan: plan, limits: { "entity" => limit, "page" => 10, "member" => 1 })
    subscription = create(:billing_subscription, customer: customer, plan: plan)
    [plan, subscription]
  end

  it "creates a customer-owned entity from a definition" do
    semantic, ctx = apply([{ "name" => "Student", "display_label" => "Student",
                             "property_schema" => [{ "name" => "Email", "name_slug" => "email", "html_type" => "email" }] }])

    expect(semantic).to eq(:success)
    expect(ctx[:created]).to eq(["Student"])
    entity = Entity.find_by(customer_id: customer.id, name: "Student")
    expect(entity).to be_present
    expect(entity.customer_id).to eq(customer.id)
    expect(entity.property_schema_json.first["name_slug"]).to eq("email")
  end

  it "persists valid partial generator fields with derived slugs" do
    accept_entity_limit(1)
    semantic, ctx = apply([{
      "name" => "Student",
      "property_schema" => [{ "name" => "Email address", "html_type" => "email" }]
    }])
    expect(semantic).to eq(:success), ctx[:errors].inspect
    entity = Entity.find_by!(customer_id: customer.id, name: "Student")
    expect(entity.property_schema_json.first).to include("name" => "Email address", "name_slug" => "email_address")
    expect(entity).to be_valid
  end

  it "rejects explicit invalid slugs and rolls back the complete generated set" do
    accept_entity_limit(2)
    semantic, ctx = apply([
      { "name" => "ValidFirst", "property_schema" => [{ "name" => "Email", "html_type" => "email" }] },
      { "name" => "InvalidSecond", "property_schema" => [{ "name" => "Notes", "name_slug" => "notes.bad", "html_type" => "textarea" }] }
    ])
    expect(semantic).to eq(:failure)
    expect(ctx[:errors].join).to include(I18n.t("maint_core.errors.validations.property_schema_invalid_slugs", slugs: "notes.bad"))
    expect(Entity.where(customer_id: customer.id, name: %w[ValidFirst InvalidSecond])).not_to exist
  end

  it "enforces the accepted quota when the current catalog limit is increased" do
    plan, subscription = accept_entity_limit(1)
    Billing::AssignPlanLimits.call(plan: plan, limits: { "entity" => 10 })

    expect(apply([{ "name" => "First" }]).first).to eq(:success)
    semantic, ctx = apply([{ "name" => "Second" }])
    expect(semantic).to eq(:failure)
    expect(subscription.reload.plan_snapshot.dig("limits", "entity")).to eq(1)
    expect(ctx[:errors]).to eq([Billing::Quota::Guard.check(customer: customer, item_key: "entity").message])
    expect(Entity.where(customer_id: customer.id, name: "Second")).not_to exist
  end

  it "keeps accepted capacity when the current catalog limit is decreased" do
    plan, subscription = accept_entity_limit(2)
    Billing::AssignPlanLimits.call(plan: plan, limits: { "entity" => 0 })

    semantic, ctx = apply([{ "name" => "First" }, { "name" => "Second" }])
    expect(semantic).to eq(:success), ctx[:errors].inspect
    expect(subscription.reload.plan_snapshot.dig("limits", "entity")).to eq(2)
    expect(Entity.where(customer_id: customer.id, name: %w[First Second]).count).to eq(2)
    expect(apply([{ "name" => "Third" }]).first).to eq(:failure)
  end

  it "rolls back an entire set when a later identity fails inside an outer transaction" do
    create(:entity, customer: customer, name: "Inactive").soft_delete
    customer.with_lock do
      signal, (ctx, *) = described_class.call({
        entities: [{ "name" => "CreatedFirst" }, { "name" => "Inactive" }], customer: customer, domain: domain
      })
      expect(signal.to_h[:semantic]).to eq(:failure)
      expect(ctx[:created]).to be_empty
      expect(Entity.where(customer_id: customer.id, name: "CreatedFirst")).not_to exist
    end
  end

  it "creates a related set and a bridge with EntityReference participant fields" do
    semantic, ctx = apply([
      { "name" => "Student",
        "associations" => [{
          "associated_entity_name" => "Course",
          "display_field" => "title",
          "display_field_label" => "Title",
          "additional_attributes" => [{ "name" => "Score", "name_slug" => "score", "html_type" => "number" }]
        }] },
      { "name" => "Course", "property_schema" => [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }] }
    ])

    expect(semantic).to eq(:success)
    student = Entity.find_by!(customer_id: customer.id, name: "Student")
    course = Entity.find_by!(customer_id: customer.id, name: "Course")
    bridge = Entity.find_by!(customer_id: customer.id, name: "assoc_student_course")
    expect(bridge.bridge_entity?).to be true
    types = bridge.property_schema_json.map { |attr| attr["type"] }
    expect(types.first(2)).to eq([Entity::ENTITY_REFERENCE_TYPE, Entity::ENTITY_REFERENCE_TYPE])
    expect(bridge.property_schema_json.map { |attr| attr["name_slug"] }).to include("score")
    expect(student.associations_list.first["target_entity_id"]).to eq(course.id)
    expect(ctx[:bridges]).to include("assoc_student_course")
  end

  it "updates a live customer-owned entity when the name matches" do
    existing = create(:entity, customer: customer, name: "Student",
                      property_schema: [{ "name" => "Old", "name_slug" => "old", "html_type" => "text" }].to_json)

    semantic, ctx = apply([{ "name" => "Student",
                             "property_schema" => [{ "name" => "Email", "name_slug" => "email", "html_type" => "email" }] }])

    expect(semantic).to eq(:success)
    expect(ctx[:updated]).to eq(["Student"])
    expect(ctx[:created]).to eq([])
    existing.reload
    expect(existing.property_schema_json.map { |attr| attr["name_slug"] }).to eq(["old", "email"])
  end

  it "bases an update on the latest version instead of replacing the schema" do
    existing = create(:entity, customer: customer, name: "Student",
                      property_schema: [{ "name" => "Email", "name_slug" => "email", "html_type" => "email" }].to_json)
    head = existing.current_version

    semantic, ctx = apply([{ "name" => "Student",
                             "property_schema" => [{ "name" => "Notes", "name_slug" => "notes", "html_type" => "textarea" }] }])

    expect(semantic).to eq(:success)
    expect(ctx[:updated]).to eq(["Student"])
    existing.reload
    expect(existing.property_schema_json.map { |attr| attr["name_slug"] }).to eq(["email", "notes"])
    expect(existing.current_version.id).not_to eq(head.id)
    expect(existing.current_version.based_on_version_id).to eq(head.id)
  end

  it "persists LLM-supplied attribute groups on create" do
    semantic, ctx = apply([{
      "name" => "Student",
      "attribute_groups" => [
        { "id" => "g_identity", "name" => "Identity", "icon" => "user", "color" => "indigo" },
        { "id" => "g_contact", "name" => "Contact", "icon" => "mail", "color" => "sky" }
      ],
      "property_schema" => [
        { "name" => "First name", "name_slug" => "first_name", "html_type" => "text", "group_id" => "g_identity" },
        { "name" => "Last name", "name_slug" => "last_name", "html_type" => "text", "group_id" => "g_identity" },
        { "name" => "Email", "name_slug" => "email", "html_type" => "email", "group_id" => "g_contact" },
        { "name" => "Phone", "name_slug" => "phone", "html_type" => "tel", "group_id" => "g_contact" }
      ]
    }])

    expect(semantic).to eq(:success)
    expect(ctx[:created]).to eq(["Student"])
    entity = Entity.find_by!(customer_id: customer.id, name: "Student")
    expect(entity.attribute_groups_json.map { |row| row["id"] }).to eq(%w[g_identity g_contact])
    by_slug = entity.property_schema_json.index_by { |row| row["name_slug"] }
    expect(by_slug["first_name"]["group_id"]).to eq("g_identity")
    expect(by_slug["email"]["group_id"]).to eq("g_contact")
  end

  it "does not invent groups when the definition omitted them" do
    semantic, = apply([{
      "name" => "Student",
      "property_schema" => [
        { "name" => "First name", "name_slug" => "first_name", "html_type" => "text" },
        { "name" => "Email", "name_slug" => "email", "html_type" => "email" }
      ]
    }])

    expect(semantic).to eq(:success)
    entity = Entity.find_by!(customer_id: customer.id, name: "Student")
    expect(entity.attribute_groups_json).to eq([])
  end

  it "does not invent groups when an update only adds fields" do
    existing = create(:entity, customer: customer, name: "Student",
                      property_schema: [
                        { "name" => "First name", "name_slug" => "first_name", "html_type" => "text" },
                        { "name" => "Last name", "name_slug" => "last_name", "html_type" => "text" },
                        { "name" => "Email", "name_slug" => "email", "html_type" => "email" },
                        { "name" => "Phone", "name_slug" => "phone", "html_type" => "tel" }
                      ].to_json)

    semantic, = apply([{
      "name" => "Student",
      "property_schema" => [
        { "name" => "Street", "name_slug" => "street", "html_type" => "text" },
        { "name" => "City", "name_slug" => "city", "html_type" => "text" }
      ]
    }])

    expect(semantic).to eq(:success)
    existing.reload
    expect(existing.attribute_groups_json).to eq([])
    expect(existing.property_schema_json.map { |row| row["name_slug"] }).to eq(
      %w[first_name last_name email phone street city]
    )
    expect(existing.property_schema_json).to all(satisfy { |row| row["group_id"].blank? })
  end

  it "persists LLM grouping and group order from the full collected schema on update" do
    existing = create(:entity, customer: customer, name: "Student",
                      property_schema: [
                        { "name" => "First name", "name_slug" => "first_name", "html_type" => "text" },
                        { "name" => "Last name", "name_slug" => "last_name", "html_type" => "text" },
                        { "name" => "Email", "name_slug" => "email", "html_type" => "email" },
                        { "name" => "Phone", "name_slug" => "phone", "html_type" => "tel" }
                      ].to_json)

    semantic, = apply([{
      "name" => "Student",
      "attribute_groups" => [
        { "id" => "g_identity", "name" => "Identity", "icon" => "user", "color" => "indigo" },
        { "id" => "g_contact", "name" => "Contact", "icon" => "mail", "color" => "sky" },
        { "id" => "g_address", "name" => "Address", "icon" => "map-pin", "color" => "teal" }
      ],
      "property_schema" => [
        { "name" => "First name", "name_slug" => "first_name", "html_type" => "text", "group_id" => "g_identity" },
        { "name" => "Last name", "name_slug" => "last_name", "html_type" => "text", "group_id" => "g_identity" },
        { "name" => "Email", "name_slug" => "email", "html_type" => "email", "group_id" => "g_contact" },
        { "name" => "Phone", "name_slug" => "phone", "html_type" => "tel", "group_id" => "g_contact" },
        { "name" => "Street", "name_slug" => "street", "html_type" => "text", "group_id" => "g_address" },
        { "name" => "City", "name_slug" => "city", "html_type" => "text", "group_id" => "g_address" }
      ]
    }])

    expect(semantic).to eq(:success)
    existing.reload
    expect(existing.attribute_groups_json.map { |row| row["id"] }).to eq(%w[g_identity g_contact g_address])
    by_slug = existing.property_schema_json.index_by { |row| row["name_slug"] }
    expect(by_slug["first_name"]["group_id"]).to eq("g_identity")
    expect(by_slug["email"]["group_id"]).to eq("g_contact")
    expect(by_slug["street"]["group_id"]).to eq("g_address")
  end

  it "keeps catalog groups and applies a new attribute's group_id on update" do
    existing = create(:entity, customer: customer, name: "Student",
                      attribute_groups: [{ "id" => "g_contact", "name" => "Contact", "icon" => "mail", "color" => "sky" }],
                      property_schema: [{
                        "name" => "Email", "name_slug" => "email", "html_type" => "email", "group_id" => "g_contact"
                      }].to_json)

    semantic, ctx = apply([{
      "name" => "Student",
      "property_schema" => [{ "name" => "Phone", "name_slug" => "phone", "html_type" => "tel", "group_id" => "g_contact" }]
    }])

    expect(semantic).to eq(:success)
    expect(ctx[:updated]).to eq(["Student"])
    existing.reload
    expect(existing.attribute_groups_json.map { |row| row["id"] }).to eq(["g_contact"])
    expect(existing.property_schema_json.map { |row| [row["name_slug"], row["group_id"]] }).to eq(
      [["email", "g_contact"], ["phone", "g_contact"]]
    )
  end

  it "merges a new LLM group onto existing groups instead of replacing them" do
    existing = create(:entity, customer: customer, name: "Student",
                      attribute_groups: [{ "id" => "g_contact", "name" => "Contact", "icon" => "mail", "color" => "sky" }],
                      property_schema: [{
                        "name" => "Email", "name_slug" => "email", "html_type" => "email", "group_id" => "g_contact"
                      }].to_json)

    semantic, = apply([{
      "name" => "Student",
      "attribute_groups" => [{ "id" => "g_address", "name" => "Address", "icon" => "map-pin", "color" => "teal" }],
      "property_schema" => [{ "name" => "Street", "name_slug" => "street", "html_type" => "text", "group_id" => "g_address" }]
    }])

    expect(semantic).to eq(:success)
    existing.reload
    expect(existing.attribute_groups_json.map { |row| row["id"] }).to eq(%w[g_contact g_address])
    expect(existing.property_schema_json.find { |row| row["name_slug"] == "email" }["group_id"]).to eq("g_contact")
    expect(existing.property_schema_json.find { |row| row["name_slug"] == "street" }["group_id"]).to eq("g_address")
  end

  it "uses the LLM attribute_groups array as page order when an update restates groups" do
    existing = create(:entity, customer: customer, name: "Student",
                      attribute_groups: [
                        { "id" => "g_dates", "name" => "Dates", "icon" => "calendar", "color" => "amber" },
                        { "id" => "g_identity", "name" => "Identity", "icon" => "user", "color" => "indigo" }
                      ],
                      property_schema: [
                        { "name" => "Hire date", "name_slug" => "hire_date", "html_type" => "date", "group_id" => "g_dates" },
                        { "name" => "Full name", "name_slug" => "full_name", "html_type" => "text", "group_id" => "g_identity" }
                      ].to_json)

    semantic, = apply([{
      "name" => "Student",
      "attribute_groups" => [
        { "id" => "g_identity", "name" => "Identity", "icon" => "user", "color" => "indigo" },
        { "id" => "g_dates", "name" => "Dates", "icon" => "calendar", "color" => "amber" }
      ],
      "property_schema" => [
        { "name" => "Full name", "name_slug" => "full_name", "html_type" => "text", "group_id" => "g_identity" },
        { "name" => "Hire date", "name_slug" => "hire_date", "html_type" => "date", "group_id" => "g_dates" }
      ]
    }])

    expect(semantic).to eq(:success)
    existing.reload
    expect(existing.attribute_groups_json.map { |row| row["id"] }).to eq(%w[g_identity g_dates])
  end

  it "overlays a changed attribute onto the matching field of the latest version" do
    existing = create(:entity, customer: customer, name: "Student",
                      property_schema: [{
                        "name" => "Email",
                        "name_slug" => "email",
                        "html_type" => "email",
                        "validators" => [{ "type" => "format_email" }]
                      }].to_json)

    semantic, = apply([{ "name" => "Student",
                         "property_schema" => [{ "name" => "Email", "name_slug" => "email", "html_type" => "text" }] }])

    expect(semantic).to eq(:success)
    email = existing.reload.property_schema_json.find { |attr| attr["name_slug"] == "email" }
    expect(email["html_type"]).to eq("text")
    expect(email["validators"]).to eq([{ "type" => "format_email" }])
  end

  it "rolls back when an associated entity is missing" do
    semantic, ctx = apply([{
      "name" => "Student",
      "associations" => [{
        "associated_entity_name" => "MissingCourse",
        "display_field" => "name",
        "display_field_label" => "Name"
      }]
    }])

    expect(semantic).to eq(:failure)
    expect(ctx[:errors].join).to include("MissingCourse")
    expect(Entity.find_by(customer_id: customer.id, name: "Student")).to be_nil
  end

  it "rejects EntityReference attributes in a definition" do
    semantic, ctx = apply([{
      "name" => "Student",
      "property_schema" => [{ "name" => "Course", "type" => Entity::ENTITY_REFERENCE_TYPE, "html_type" => "number" }]
    }])

    expect(semantic).to eq(:failure)
    expect(ctx[:errors]).to eq([I18n.t("ai_assistant.assistant.apply_errors.forbidden_reference")])
    expect(Entity.find_by(customer_id: customer.id, name: "Student")).to be_nil
  end

  it "rejects a document that names the same entity twice, writing nothing" do
    create(:entity, customer: customer, name: "Student", description: "Before")

    semantic, ctx = apply([
      { "name" => "Student", "description" => "First" },
      { "name" => "Student", "description" => "Second" }
    ])

    expect(semantic).to eq(:failure)
    expect(ctx[:errors]).to eq([
      I18n.t("ai_assistant.assistant.apply_errors.duplicate_entity_name", names: "Student")
    ])
    expect(Entity.find_by(customer_id: customer.id, name: "Student").description).to eq("Before")
  end

  it "rejects smuggled entity_id on a data attribute" do
    semantic, = apply([{
      "name" => "Student",
      "property_schema" => [{ "name" => "Course", "html_type" => "number", "entity_id" => "1" }]
    }])

    expect(semantic).to eq(:failure)
    expect(Entity.find_by(customer_id: customer.id, name: "Student")).to be_nil
  end

  it "strips id from a definition and updates the live name match" do
    existing = create(:entity, customer: customer, name: "Student")

    semantic, ctx = apply([{ "id" => existing.id + 50, "name" => "Student", "description" => "From catalog echo" }])

    expect(semantic).to eq(:success)
    expect(ctx[:updated]).to eq(["Student"])
    expect(existing.reload.description).to eq("From catalog echo")
  end

  it "rejects customer_id on a definition" do
    semantic, ctx = apply([{ "name" => "Student", "customer_id" => other.id }])

    expect(semantic).to eq(:failure)
    expect(Entity.find_by(customer_id: customer.id, name: "Student")).to be_nil
    expect(Entity.find_by(customer_id: other.id, name: "Student")).to be_nil
  end

  it "rejects an extended_model that is not in the customer allowlist" do
    semantic, ctx = apply([{ "name" => "Account", "extended_model" => "User" }])

    expect(semantic).to eq(:failure)
    expect(ctx[:errors].join).to include("User")
    expect(Entity.find_by(customer_id: customer.id, name: "Account")).to be_nil
  end

  it "writes to the passed customer even when Current.customer is another tenant" do
    semantic, ctx = Current.with_customer(other) do
      signal, (inner, *) = described_class.call({ entities: [{ "name" => "Pinned" }], customer: customer, domain: domain })
      [signal.to_h[:semantic], inner]
    end

    expect(semantic).to eq(:success)
    expect(ctx[:created]).to eq(["Pinned"])
    expect(Entity.find_by(customer_id: customer.id, name: "Pinned")).to be_present
    expect(Entity.find_by(customer_id: other.id, name: "Pinned")).to be_nil
  end

  it "does not overwrite an inactive entity" do
    create(:entity, customer: customer, name: "Student").tap(&:soft_delete)

    semantic, ctx = apply([{ "name" => "Student" }])

    expect(semantic).to eq(:failure)
    expect(ctx[:errors].join).to include("inactive")
    expect(Entity.unscope(where: :status).find_by(customer_id: customer.id, name: "Student")).to be_inactive
  end

  it "creates when a trashed entity only collides on slug, not exact name" do
    create(:entity, customer: customer, name: "student").tap(&:soft_delete)

    semantic, ctx = apply([{ "name" => "Student",
                             "property_schema" => [{ "name" => "Email", "name_slug" => "email", "html_type" => "email" }] }])

    expect(semantic).to eq(:success)
    expect(ctx[:created]).to eq(["Student"])
    expect(Entity.find_by(customer_id: customer.id, name: "Student")).to be_active
    expect(Entity.unscope(where: :status).find_by(customer_id: customer.id, name: "student")).to be_inactive
  end

  it "does not write another tenant's entities" do
    apply([{ "name" => "Student" }])
    expect(Entity.find_by(customer_id: other.id, name: "Student")).to be_nil
    expect(Entity.find_by(customer_id: customer.id, name: "Student")).to be_present
  end

  it "resolves a computed onto the auto-created bridge in the same turn" do
    semantic, ctx = apply([
      {
        "name" => "Student",
        "property_schema" => [{
          "name" => "Course count",
          "name_slug" => "course_count",
          "type" => Entity::COMPUTED_TYPE,
          "html_type" => "number",
          "config" => { "target_entity_name" => "Course", "function" => "count", "bridge_role" => "source" }
        }],
        "associations" => [{
          "associated_entity_name" => "Course",
          "display_field" => "name",
          "display_field_label" => "Name"
        }]
      },
      { "name" => "Course", "property_schema" => [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }] }
    ])

    expect(semantic).to eq(:success)
    student = Entity.find_by!(customer_id: customer.id, name: "Student")
    computed = student.computed_fields.first
    expect(computed).to be_present
    expect(computed["config"]["bridge_entity_id"]).to eq(student.associations_list.first["bridge_entity_id"])
    expect(ctx[:bridges]).to include("assoc_student_course")
  end

  it "does not treat a shared entity as a name match" do
    create(:entity, :shared, name: "Catalog")

    semantic, ctx = apply([{ "name" => "Catalog" }])

    expect(semantic).to eq(:success)
    expect(ctx[:created]).to eq(["Catalog"])
    owned = Entity.find_by(customer_id: customer.id, name: "Catalog")
    expect(owned).to be_present
    expect(owned.shared?).to be false
  end

  describe "replace mode" do
    it "removes attributes that the incoming schema leaves out" do
      existing = create(:entity, customer: customer, name: "Student",
                        property_schema: [
                          { "name" => "Email", "name_slug" => "email", "html_type" => "email" },
                          { "name" => "Fax", "name_slug" => "fax", "html_type" => "tel" }
                        ].to_json)

      semantic, = apply([{
        "name" => "Student",
        "property_schema" => [{ "name" => "Email", "name_slug" => "email", "html_type" => "email" }]
      }], replace: true)

      expect(semantic).to eq(:success)
      expect(existing.reload.property_schema_json.map { |attr| attr["name_slug"] }).to eq(["email"])
    end

    it "rewrites attributes in the incoming order" do
      existing = create(:entity, customer: customer, name: "Student",
                        property_schema: [
                          { "name" => "Email", "name_slug" => "email", "html_type" => "email" },
                          { "name" => "Notes", "name_slug" => "notes", "html_type" => "textarea" }
                        ].to_json)

      semantic, = apply([{
        "name" => "Student",
        "property_schema" => [
          { "name" => "Notes", "name_slug" => "notes", "html_type" => "textarea" },
          { "name" => "Email", "name_slug" => "email", "html_type" => "email" }
        ]
      }], replace: true)

      expect(semantic).to eq(:success)
      expect(existing.reload.property_schema_json.map { |attr| attr["name_slug"] }).to eq(%w[notes email])
    end

    it "replaces groups wholesale instead of merging leftovers" do
      existing = create(:entity, customer: customer, name: "Student",
                        attribute_groups: [{ "id" => "g_contact", "name" => "Contact", "icon" => "mail", "color" => "sky" }],
                        property_schema: [{
                          "name" => "Email", "name_slug" => "email", "html_type" => "email", "group_id" => "g_contact"
                        }].to_json)

      semantic, = apply([{
        "name" => "Student",
        "attribute_groups" => [{ "id" => "g_identity", "name" => "Identity", "icon" => "user", "color" => "indigo" }],
        "property_schema" => [{
          "name" => "Full name", "name_slug" => "full_name", "html_type" => "text", "group_id" => "g_identity"
        }]
      }], replace: true)

      expect(semantic).to eq(:success)
      existing.reload
      expect(existing.attribute_groups_json.map { |row| row["id"] }).to eq(["g_identity"])
      expect(existing.property_schema_json.map { |row| row["name_slug"] }).to eq(["full_name"])
    end

    it "re-inserts a computed attribute at the authored index" do
      semantic, = apply([
        {
          "name" => "Student",
          "property_schema" => [
            { "name" => "Email", "name_slug" => "email", "html_type" => "email" },
            {
              "name" => "Course count",
              "name_slug" => "course_count",
              "type" => Entity::COMPUTED_TYPE,
              "html_type" => "number",
              "config" => { "target_entity_name" => "Course", "function" => "count", "bridge_role" => "source" }
            },
            { "name" => "Notes", "name_slug" => "notes", "html_type" => "textarea" }
          ],
          "associations" => [{
            "associated_entity_name" => "Course",
            "display_field" => "name",
            "display_field_label" => "Name"
          }]
        },
        { "name" => "Course", "property_schema" => [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }] }
      ], replace: true)

      expect(semantic).to eq(:success)
      student = Entity.find_by!(customer_id: customer.id, name: "Student")
      expect(student.property_schema_json.map { |attr| attr["name_slug"] }).to eq(%w[email course_count notes])
    end

    it "drops a removed association and its bridge" do
      apply([
        { "name" => "Student", "associations" => [{
          "associated_entity_name" => "Course", "display_field" => "name", "display_field_label" => "Name"
        }] },
        { "name" => "Course", "property_schema" => [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }] }
      ])
      expect(Entity.find_by(customer_id: customer.id, name: "assoc_student_course")).to be_present

      semantic, = apply([{ "name" => "Student", "associations" => [] }], replace: true)

      expect(semantic).to eq(:success)
      student = Entity.find_by!(customer_id: customer.id, name: "Student")
      expect(student.associations_list).to eq([])
      expect(Entity.unscope(where: :status).find_by(customer_id: customer.id, name: "assoc_student_course"))
        .to be_inactive
    end
  end

  it "resolves a computed in the target direction through the related entity's association" do
    semantic, = apply([
      {
        "name" => "Student",
        "associations" => [{
          "associated_entity_name" => "Course",
          "display_field" => "name",
          "display_field_label" => "Name"
        }]
      },
      {
        "name" => "Course",
        "property_schema" => [{
          "name" => "Name", "name_slug" => "name", "html_type" => "text"
        }, {
          "name" => "Enrollment count",
          "name_slug" => "enrollment_count",
          "type" => Entity::COMPUTED_TYPE,
          "html_type" => "number",
          "config" => { "target_entity_name" => "Student", "function" => "count", "bridge_role" => "target" }
        }]
      }
    ])

    expect(semantic).to eq(:success)
    student = Entity.find_by!(customer_id: customer.id, name: "Student")
    course = Entity.find_by!(customer_id: customer.id, name: "Course")
    computed = course.computed_fields.first
    expect(computed.dig("config", "bridge_entity_id")).to eq(student.associations_list.first["bridge_entity_id"])
    expect(computed.dig("config", "bridge_role")).to eq("target")
  end
end
