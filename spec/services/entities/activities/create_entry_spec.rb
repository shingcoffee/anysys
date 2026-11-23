# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::Activities::CreateEntry do
  let(:customer) { create(:customer) }
  let(:actor) { create(:user, :admin, customer: customer) }
  let(:schema) do
    [
      { "name" => "Title", "name_slug" => "title", "validators" => [{ "type" => "presence" }] },
      { "name" => "Credits", "name_slug" => "credits", "html_type" => "number", "validators" => [
        { "type" => "numericality" }, { "type" => "greater_than_or_equal_to", "config" => { "value" => 0 } }
      ] },
      { "name" => "Internal notes", "name_slug" => "notes", "html_type" => "textarea", "visibility" => { "public" => false } },
      { "name" => "Hidden", "name_slug" => "hidden", "visibility" => { "admin" => false }, "validators" => [{ "type" => "presence" }] },
      { "name" => "Locked", "name_slug" => "locked", "readonly" => true },
      { "name" => "Reference", "name_slug" => "reference", "type" => "EntityReference" },
      { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number", "storage" => "computed" }
    ]
  end
  let(:entity) do
    create(:entity, customer: customer, property_schema: schema.to_json,
           default_properties: { "credits" => 0, "hidden" => "secret", "locked" => "locked" }.to_json)
  end

  def run(params = {}, **arguments)
    described_class.call(customer: customer, actor: actor, entity: entity, params: params, **arguments)
  end

  it "saves one primary entry through the exact keyword API with authoritative tenant and provenance" do
    params = ActionController::Parameters.new(title: "Course", credits: "0", notes: "Admin note", hidden: "forged",
                                              total: 90, locked: "forged", reference: 1, customer_id: 1,
                                              entity_id: 1, entity_version_number: 999, id: 999, audience: "public")
    entity
    actor
    signal, ctx = nil
    expect { signal, ctx = run(params) }.to change(EntityEntry, :count).by(1)
    expect(signal.to_h[:semantic]).to eq(:success)
    expect(ctx[:form]).to be_a(Entities::EntryForm)
    expect(ctx[:contract]).to be_a(EntityEntryContract)
    expect(ctx[:contract].class.validation_audience).to eq("admin")
    expect(ctx[:errors]).to eq({})
    expect(ctx[:model]).to be_persisted
    entry = EntityEntry.find(ctx[:model].id)
    expect(entry.customer_id).to eq(customer.id)
    expect(entry.entity_id).to eq(entity.id)
    expect(entry.entity_version_number).to eq(entity.resolved_current_version.version_number)
    expect(entry.data_json).to eq("title" => "Course", "credits" => "0", "notes" => "Admin note")
  end

  it "retains the same attempted values and keyed Reform errors on validation failure" do
    signal, ctx = nil
    expect { signal, ctx = run({ "title" => "", "credits" => "-1" }) }.not_to change(EntityEntry, :count)
    expect(signal.to_h[:semantic]).to eq(:failure)
    expect(ctx[:model]).to be_new_record
    expect(ctx[:errors].keys).to contain_exactly("title", "credits")
    expect(ctx[:form].values).to eq("title" => "", "credits" => "-1")
    expect(ctx[:errors]).to equal(ctx[:form].errors)
  end

  it "keeps authoritative columns and associations intact even when the schema declares internal slugs" do
    internal = %w[id customer_id entity_id entity_version_number data entity customer]
    fields = schema + internal.map { |slug| { "name" => slug, "name_slug" => slug } }
    target = create(:entity, customer: customer, property_schema: fields.to_json,
                    default_properties: internal.index_with { "forged default" }.to_json)
    signal, ctx = run({ "title" => "Course", "credits" => 0 }.merge(internal.index_with { "forged input" }), entity: target)
    expect(signal.to_h[:semantic]).to eq(:success)
    entry = EntityEntry.find(ctx[:model].id)
    expect(entry.customer_id).to eq(customer.id)
    expect(entry.entity_id).to eq(target.id)
    expect(entry.entity_version_number).to eq(target.resolved_current_version.version_number)
    expect(entry.data_json.keys & internal).to be_empty
    expect(ctx[:form].values.keys & internal).to be_empty
  end

  it "rejects blank-only required multi-selections and persists only real choices" do
    target = create(:entity, customer: customer, property_schema: [{
      "name" => "Choices", "name_slug" => "choices", "html_type" => "multi-select",
      "validators" => [{ "type" => "presence" }], "config" => { "options" => [{ "label" => "A", "value" => "a" }] }
    }].to_json)
    [[" "], [nil], [], ["", "\t", nil]].each do |raw|
      signal, ctx = nil
      expect { signal, ctx = run({ "choices" => raw }, entity: target) }.not_to change(EntityEntry, :count)
      expect(signal.to_h[:semantic]).to eq(:failure)
      expect(ctx[:errors]["choices"]).to eq([I18n.t("errors.messages.blank")])
      expect(ctx[:form].value_for("choices")).to eq([])
    end
    signal, ctx = nil
    expect { signal, ctx = run({ "choices" => ["", "a"] }, entity: target) }.to change(EntityEntry, :count).by(1)
    expect(signal.to_h[:semantic]).to eq(:success)
    expect(ctx[:model].reload.data_json).to eq("choices" => ["a"])
  end

  it "retains valid non-native numeric literals after a failed POST without adding number errors" do
    signal, ctx = nil
    expect { signal, ctx = run({ "title" => "", "credits" => "+1" }) }.not_to change(EntityEntry, :count)
    expect(signal.to_h[:semantic]).to eq(:failure)
    expect(ctx[:errors].keys).to eq(["title"])
    expect(ctx[:form].value_for("credits")).to eq("+1")
    credits = ctx[:form].groups.flat_map(&:fields).find { |field| field.slug == "credits" }
    expect(credits).to have_attributes(html_type: "number", invalid_literal: true)
    expect(ctx[:contract].credits).to eq("+1")

    signal, ctx = run({ "title" => "Course", "credits" => "+1" })
    expect(signal.to_h[:semantic]).to eq(:success)
    expect(ctx[:model].reload.data_json["credits"]).to eq("+1")
    signal, ctx = run({ "title" => "", "credits" => "1." })
    expect(signal.to_h[:semantic]).to eq(:failure)
    expect(ctx[:form].value_for("credits")).to eq("1.")
    expect(ctx[:form].groups.flat_map(&:fields).find { |field| field.slug == "credits" }.invalid_literal).to be(true)
  end

  it "keeps checkbox and switch display values canonical on failed and successful submissions" do
    target = create(:entity, customer: customer, property_schema: (schema + [
      { "name" => "Checkbox", "name_slug" => "checkbox", "html_type" => "checkbox" },
      { "name" => "Switch", "name_slug" => "switch", "html_type" => "switch" }
    ]).to_json, default_properties: { "credits" => 0 }.to_json)
    signal, ctx = run({ "title" => "", "checkbox" => "on", "switch" => "on" }, entity: target)
    expect(signal.to_h[:semantic]).to eq(:failure)
    expect(ctx[:form].values.slice("checkbox", "switch")).to eq("checkbox" => "1", "switch" => "1")
    expect(ctx[:errors].keys).to eq(["title"])
    signal, ctx = run({ "title" => "Course", "checkbox" => "on", "switch" => "on" }, entity: target)
    expect(signal.to_h[:semantic]).to eq(:success)
    expect(ctx[:model].reload.data_json.slice("checkbox", "switch")).to eq("checkbox" => "1", "switch" => "1")
    expect(ctx[:form].values.slice("checkbox", "switch")).to eq("checkbox" => "1", "switch" => "1")
  end

  it "never calls the contract writer when the form already has boundary errors" do
    expect(EntityEntryContract).not_to receive(:build_for)
    signal, ctx = nil
    expect { signal, ctx = run({ "title" => { "nested" => "bad" }, "credits" => "oops" }) }.not_to change(EntityEntry, :count)
    expect(signal.to_h[:semantic]).to eq(:failure)
    expect(ctx[:errors].keys).to contain_exactly("title", "credits")
    expect(ctx[:form].value_for("credits")).to eq("oops")
  end

  it "refuses unsupported and empty forms before writing" do
    [[], [{ "name" => "File", "name_slug" => "file", "html_type" => "file" }]].each do |fields|
      target = create(:entity, customer: customer, property_schema: fields.to_json)
      signal, ctx = nil
      expect { signal, ctx = run({}, entity: target) }.not_to change(EntityEntry, :count)
      expect(signal.to_h[:semantic]).to eq(:failure)
      expect(ctx[:errors]["base"]).to be_present
    end
  end

  it "requires a submitted data object rather than treating nil as a GET-default submission" do
    target = create(:entity, customer: customer, property_schema: schema.to_json,
                    default_properties: { "title" => "Default", "credits" => 0 }.to_json)
    expect(EntityEntryContract).not_to receive(:build_for)
    signal, ctx = nil
    expect { signal, ctx = run(nil, entity: target) }.not_to change(EntityEntry, :count)
    expect(signal.to_h[:semantic]).to eq(:failure)
    expect(ctx[:errors]["base"]).to eq([I18n.t("admin_misc.entities.entry_form.errors.invalid_shape")])
  end

  it "keeps validators for excluded readonly and reference properties and shows nonrendered errors" do
    %w[locked reference].each do |slug|
      fields = schema.deep_dup
      fields.find { |field| field["name_slug"] == slug }["validators"] = [{ "type" => "presence" }]
      target = create(:entity, customer: customer, property_schema: fields.to_json)
      signal, ctx = nil
      expect { signal, ctx = run({ "title" => "Course", slug => "forged" }, entity: target) }.not_to change(EntityEntry, :count)
      expect(signal.to_h[:semantic]).to eq(:failure)
      expect(ctx[:errors][slug]).to be_present
      expect(ctx[:form].values).not_to have_key(slug)
    end
  end

  it "reports save failure without leaving a persisted entry" do
    allow(Entries::Save).to receive(:call) do |contract:, audience:|
      expect(contract).to be_present
      expect(audience).to eq("admin")
      Entries::Save::Result.new(
        entry: nil,
        errors: [I18n.t("admin_misc.entities.entry_form.errors.save_failed")],
        field_errors: []
      )
    end
    signal, ctx = nil
    expect { signal, ctx = run({ "title" => "Course" }) }.not_to change(EntityEntry, :count)
    expect(signal.to_h[:semantic]).to eq(:failure)
    expect(EntityEntry.find_by(id: ctx[:model].id)).to be_nil
    expect(ctx[:errors]["base"]).to eq([I18n.t("admin_misc.entities.entry_form.errors.save_failed")])
    expect(ctx[:form].value_for("title")).to eq("Course")
  end

  it "collects model save errors and handles expected save exceptions without leaking exception text" do
    runtime_class = EntityEntry.build_for(entity)
    allow(EntityEntry).to receive(:build_for).and_return(runtime_class)
    allow(runtime_class).to receive(:new).and_wrap_original do |build, **attributes|
      model = build.call(**attributes)
      allow(model).to receive(:save) do
        model.errors.add(:title, :invalid)
        raise ActiveRecord::RecordInvalid, model
      end
      model
    end
    signal, ctx = run({ "title" => "Course" })
    expect(signal.to_h[:semantic]).to eq(:failure)
    expect(ctx[:errors]["title"]).to eq([I18n.t("errors.messages.invalid")])
    expect(ctx[:model]).to be_new_record
  end

  it "rejects members, absent actors and foreign admins on direct calls" do
    member = create(:user, :member, customer: customer)
    foreign_admin = create(:user, :admin)
    [member, foreign_admin, nil].each do |user|
      signal, = run({ "title" => "Course" }, actor: user)
      expect(signal.to_h[:semantic]).to eq(:forbidden)
    end
    expect(EntityEntry.count).to eq(0)
  end

  it "rejects foreign, inactive, missing and bridge targets even for the platform owner" do
    foreign = create(:entity, property_schema: schema.to_json)
    inactive = create(:entity, customer: customer, status: :inactive, property_schema: schema.to_json)
    bridge = create(:entity, customer: customer, category: :bridge, property_schema: schema.to_json)
    owner = find_or_create_platform_owner
    [foreign, inactive, bridge, nil].each do |target|
      signal, = run({ "title" => "Course" }, entity: target, actor: owner)
      expect(signal.to_h[:semantic]).to eq(:forbidden)
    end
    expect(EntityEntry.count).to eq(0)
  end

  it "uses the URL customer's latest shared override for a cross-tenant pinned owner" do
    shared = create(:entity, :shared, property_schema: [{ "name" => "Global", "name_slug" => "global" }].to_json)
    Current.set(customer: customer, shared_resources_mode: false) do
      edited = Entity.find(shared.id)
      edited.update!(property_schema: schema.to_json, default_properties: { "credits" => 0 }.to_json)
      edited.update!(description: "Second tenant version")
    end
    owner = find_or_create_platform_owner
    Current.set(customer: owner.customer, shared_resources_mode: true) do
      signal, ctx = run({ "title" => "Course", "global" => "ignored" }, entity: shared, actor: owner)
      expect(signal.to_h[:semantic]).to eq(:success)
      expect(ctx[:model].customer_id).to eq(customer.id)
      expect(ctx[:model].entity_version_number).to eq(2)
      expect(ctx[:model].data_json).to eq("title" => "Course", "credits" => 0, "notes" => nil)
      expect(Current.customer).to eq(owner.customer)
      expect(Current.shared_resources_mode).to be(true)
    end
  end

  it "creates neither associated bridge entries nor extended base model records" do
    feature_module = FeatureModules::Module.find_by!(key: "authentication")
    feature_module.update!(extendable_models: ["Authentication::User"].to_json)
    target = create(:entity, customer: customer, extended_model: "Authentication::User", property_schema: schema.to_json)
    bridge = create(:entity, customer: customer, category: :bridge,
                    property_schema: [{ "name" => "Course", "name_slug" => "course", "type" => "EntityReference", "entity_id" => target.id.to_s }].to_json)
    actor
    user_count = Authentication::User.count
    signal, ctx = nil
    expect { signal, ctx = run({ "title" => "Course", "credits" => 0 }, entity: target) }.to change(EntityEntry, :count).by(1)
    expect(signal.to_h[:semantic]).to eq(:success)
    expect(ctx[:model].entity_id).to eq(target.id)
    expect(EntityEntry.where(entity_id: bridge.id)).to be_empty
    expect(Authentication::User.count).to eq(user_count)
  end
end
