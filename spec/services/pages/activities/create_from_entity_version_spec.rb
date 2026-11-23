# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::Activities::CreateFromEntityVersion do
  let_it_be(:customer) { create(:customer) }

  def create_from(entity, version, shared: false)
    Current.with_customer(customer) do
      described_class.call(entity: entity, version: version, customer: customer, shared: shared)
    end
  end

  it "creates a page named after the entity and bound to the version" do
    entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    version = entity.current_version

    expect { create_from(entity, version) }.to change(Page, :count).by(1)

    page = Page.order(:id).last
    expect(page.name).to eq("Student")
    expect(page.customer_id).to eq(customer.id)
    expect(page).to have_attributes(launched: false)
    expect(page.visible_audiences).to eq(%w[admin])
    expect(page.entity_version_id).to eq(version.id)
    expect(page.entity_id).to eq(entity.id)
    expect(page.configuration_json["form_settings"].to_h.keys.grep(/flowchart/)).to be_empty
    slugs = page.configuration_json["pages"].flat_map { |p| p["fields"] }.map { |f| f["property_slug"] }
    expect(slugs).to include("name", "status")
  end

  it "uses the selected version snapshot rather than the live head" do
    entity = create(:entity, customer: customer, name: "Student", property_schema: [
      { "name" => "Name", "name_slug" => "name", "html_type" => "text" }
    ].to_json)
    v1 = entity.current_version
    entity.property_schema_json = [
      { "name" => "Name", "name_slug" => "name", "html_type" => "text" },
      { "name" => "Email", "name_slug" => "email", "html_type" => "email" }
    ]
    entity.save!

    result = create_from(entity, v1)
    expect(result).to be_success
    slugs = result.page.configuration_json["pages"].flat_map { |p| p["fields"] }.map { |f| f["property_slug"] }
    expect(slugs).to include("name")
    expect(slugs).not_to include("email")
  end

  it "leaves associated entities out of the page" do
    student = create(:entity, customer: customer, name: "Student", property_schema: [
      { "name" => "Name", "name_slug" => "name", "html_type" => "text" }
    ].to_json)
    course = create(:entity, customer: customer, name: "Course", property_schema: [
      { "name" => "Title", "name_slug" => "title", "html_type" => "text" }
    ].to_json)
    bridge = create(:entity, customer: customer, category: :bridge, name: "Enrollment", property_schema: [
      { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "entity_id" => student.id },
      { "name" => "Course", "name_slug" => "course", "type" => "EntityReference", "entity_id" => course.id },
      { "name" => "Grade", "name_slug" => "grade", "html_type" => "text" }
    ].to_json)
    student.associations_json = [{
      "target_entity_id" => course.id,
      "target_entity_name" => course.name,
      "bridge_entity_id" => bridge.id,
      "bridge_entity_name" => bridge.name,
      "association_type" => "has_many",
      "display_field" => "title",
      "display_field_label" => "Title"
    }]
    student.save!

    result = create_from(student, student.current_version)

    expect(result).to be_success
    steps = result.page.configuration_json["pages"]
    expect(steps.map { |step| step["name"] }).to eq(["Student"])
    fields = steps.flat_map { |step| step["fields"] }.reject { |field| field["property_type"] == "layout" }
    expect(fields.map { |field| field["property_slug"] }).to eq(["name"])
    expect(fields.map { |field| field["source"] }.uniq).to eq(["entity"])
  end

  it "creates the page when a version names a missing or another tenant's associated entity" do
    entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    foreign = create(:entity, customer: create(:customer), name: "Foreign")
    payload = Entities::VersionHydrator.snapshot_hash(entity.current_version)
    payload["associations"] = [foreign.id, 0].map do |id|
      { "target_entity_id" => id, "bridge_entity_id" => id, "bridge_entity_name" => "Gone", "association_type" => "has_many" }
    end
    content = entity.content_class.store!(customer_id: entity.customer_id, payload: payload)
    version = entity.commit_version!(content: content)

    result = create_from(entity, version)

    expect(result).to be_success
    expect(result.page.configuration_json["pages"].size).to eq(1)
  end

  it "generates a page for a bridge entity version" do
    student = create(:entity, customer: customer, name: "Student")
    bridge = create(:entity, customer: customer, category: :bridge, name: "Enrollment", property_schema: [
      { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "entity_id" => student.id },
      { "name" => "Grade", "name_slug" => "grade", "html_type" => "text" }
    ].to_json)

    result = create_from(bridge, bridge.current_version)

    expect(result).to be_success
    expect(result.page).to have_attributes(entity_id: bridge.id, entity_version_id: bridge.current_version.id)
    slugs = result.page.configuration_json["pages"].flat_map { |p| p["fields"] }.map { |f| f["property_slug"] }
    expect(slugs).to include("grade")
  end

  it "fails when a generated page already exists for this version" do
    entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    first = create_from(entity, entity.current_version)
    expect(first).to be_success
    second = create_from(entity, entity.current_version)
    expect(second).not_to be_success
    expect(second.error_code).to eq(:page_exists)
  end

  it "still creates a page from a different version of the same entity" do
    entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    v1 = entity.current_version
    content = entity.content_class.store!(customer_id: entity.customer_id, payload: { "_marker" => SecureRandom.hex(8) })
    v2 = entity.commit_version!(content: content)
    first = create_from(entity, v1)
    expect(first).to be_success
    second = create_from(entity, v2)
    expect(second).to be_success
    expect(second.page.id).not_to eq(first.page.id)
    expect(second.page.entity_version_id).to eq(v2.id)
    expect(second.page.name).to eq("Student v#{v2.version_number}")
  end

  it "reuses a soft-deleted page with the same name so create can run again" do
    entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    first = create_from(entity, entity.current_version)
    expect(first).to be_success
    first.page.soft_delete
    second = create_from(entity, entity.current_version)
    expect(second).to be_success
    expect(second.page.id).to eq(first.page.id)
    expect(second.page).to be_active
  end

  it "appends the version number when the entity name is already used" do
    entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    create(:page, customer: customer, name: "Student")
    result = create_from(entity, entity.current_version)
    expect(result).to be_success
    expect(result.page.name).to eq("Student v#{entity.current_version.version_number}")
  end

  it "fails when page quota is exceeded" do
    entity = create(:entity, :with_name_status_schema, customer: customer)
    allow(Billing::Quota::Guard).to receive(:check).and_return(
      Billing::Quota::Guard::Result.new(allowed: false, item_key: "page", limit: 1, label: "pages")
    )
    result = create_from(entity, entity.current_version)
    expect(result).not_to be_success
    expect(result.error_code).to eq(:quota)
  end

  it "maps a uniqueness race to page_exists" do
    entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    allow_any_instance_of(Page).to receive(:save).and_raise(ActiveRecord::RecordNotUnique)
    result = create_from(entity, entity.current_version)
    expect(result.error_code).to eq(:page_exists)
  end

  it "creates a shared page when shared: true" do
    entity = create(:entity, :shared, :with_name_status_schema, name: "GlobalStudent")
    result = described_class.call(
      entity: entity,
      version: entity.current_version,
      customer: customer,
      shared: true
    )
    expect(result).to be_success
    expect(result.page.customer_id).to be_nil
    expect(result.page.name).to eq("GlobalStudent")
  end
end
