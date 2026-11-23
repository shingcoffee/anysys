# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::Submit do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Title", "name_slug" => "title", "type" => "String", "html_type" => "text",
        "validators" => [{ "type" => "presence" }] },
      { "name" => "Note", "name_slug" => "note", "type" => "String", "html_type" => "text" }
    ].to_json)
  end
  let(:page) { launched_page }

  def launched_page(form_settings: { "modes" => ["create"] }, traits: %i[for_public], fields: nil)
    fields ||= [
      { "id" => "f_title", "property_slug" => "title", "source" => "entity", "html_type" => "text" },
      { "id" => "f_note", "property_slug" => "note", "source" => "entity", "html_type" => "text" }
    ]
    Current.set(customer: customer) do
      create(:page, *traits, customer: customer, entity: entity, launched: true,
                    configuration: {
                      form_settings: form_settings,
                      metadata: { entity_id: entity.id, entity_name: entity.name },
                      pages: [{ "id" => "p1", "fields" => fields }]
                    }.to_json)
    end
  end

  def submit(page, params: { "entity" => { "title" => "Hello" } }, viewer: nil, bindings: {}, journey: nil, session: {},
             journey_record_id: nil)
    described_class.call(
      page: page,
      params: params.with_indifferent_access,
      customer: customer,
      viewer: viewer,
      bindings: bindings,
      journey: journey,
      authentication: FlowchartRuntime::Authentication.from_request(nil),
      user_agent: "RSpec",
      session: session,
      journey_record_id: journey_record_id
    )
  end

  it "hands the record a journey run's update step edits to the target, so a member may change it" do
    allow(Pages::Submission::Target).to receive(:resolve).and_call_original
    member = create(:user, :member, customer: customer)
    page = launched_page(form_settings: { "modes" => ["update"] }, traits: %i[member_only])

    submit(page, params: { "entity" => { "title" => "B" }, "entry_id" => "12" }, viewer: member, journey_record_id: "12")
    submit(page, params: { "entity" => { "title" => "B" }, "entry_id" => "12" }, viewer: member)

    expect(Pages::Submission::Target).to have_received(:resolve).with(hash_including(entry_id: "12", journey_record_id: "12")).once
    expect(Pages::Submission::Target).to have_received(:resolve).with(hash_including(entry_id: "12", journey_record_id: nil)).once
  end

  it "refuses a create-only page when an admin names an entry to update" do
    admin = create(:user, :admin, customer: customer)
    entry = EntityEntry.build_for(entity).create!(entity: entity, customer_id: customer.id, data: { "title" => "A" }.to_json)
    page = launched_page(form_settings: { "modes" => ["create"] }, traits: %i[for_public for_member])
    page.update!(audience_admin: true)

    result = submit(page, params: { "entity" => { "title" => "B" }, "entry_id" => entry.id.to_s }, viewer: admin)

    expect(result.status).to eq(:refused)
    expect(result.http_status).to eq(:method_not_allowed)
    expect(result.message).to eq(I18n.t("common.errors.dynamic.page_not_executable"))
  end

  it "refuses another customer's entry_id before the flowchart runs" do
    admin = create(:user, :admin, customer: customer)
    other = create(:customer)
    foreign_entity = create(:entity, customer: other, property_schema: entity.property_schema)
    foreign = EntityEntry.build_for(foreign_entity).create!(entity: foreign_entity, customer_id: other.id,
                                                           data: { "title" => "X" }.to_json)
    page = launched_page(form_settings: { "modes" => ["update"] }, traits: %i[for_public])
    page.update!(audience_admin: true)

    result = submit(page, params: { "entity" => { "title" => "B" }, "entry_id" => foreign.id.to_s }, viewer: admin)

    expect(result.status).to eq(:refused)
    expect(result.http_status).to eq(:not_found)
    expect(result.message).to eq(I18n.t("common.errors.dynamic.entry_unavailable"))
    expect(foreign.reload.data_json["title"]).to eq("X")
  end

  it "rejects a public submit on an owned entity before the flowchart runs" do
    person_model = EntityDefinitions::Capabilities::PERSON_MODEL
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    student = create(:entity, customer: customer, name: "Student", extended_model: person_model,
                     property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    owned = create(:entity, customer: customer, name: "Assignment", property_schema: [
      { "name" => "Title", "name_slug" => "title", "html_type" => "text" },
      { "name" => "Student", "name_slug" => "student", "html_type" => "select", "owner" => true,
        "config" => { "options_source" => "entity_entries", "entity_id" => student.id.to_s, "label_field" => "name" } }
    ].to_json)
    owned_page = Current.set(customer: customer) do
      create(:page, :for_member, :for_public, customer: customer, entity: owned, launched: true,
                    configuration: {
                      form_settings: { modes: ["create"] },
                      metadata: { entity_id: owned.id, entity_name: owned.name },
                      pages: [{ "id" => "p1", "fields" => [
                        { "id" => "title", "property_slug" => "title", "html_type" => "text" }
                      ] }]
                    }.to_json)
    end

    result = submit(owned_page, params: { "entity" => { "title" => "Essay" } })

    expect(result.status).to eq(:rejected)
    expect(result.http_status).to eq(:unprocessable_entity)
    expect(result.message).to eq(I18n.t("common.errors.dynamic.sign_in_required"))
    expect(EntityEntry.where(entity_id: owned.id)).to be_empty
  end

  it "is offline when the page has no launched flowchart" do
    page.update_column(:flowchart_id, nil)

    result = submit(page)

    expect(result.status).to eq(:offline)
    expect(result.http_status).to eq(:service_unavailable)
    expect(result.message).to eq(I18n.t("maint_core.errors.page_launch.submission_process_offline"))
  end

  it "fails with field_errors for a Fail with error step that names a field on the page" do
    bind_page_flowchart(page, body: <<~RUBY)
      return FlowchartRuntime::Step.fail_message(ctx, { "en" => "Pick another title" }, field: "title")
    RUBY

    result = submit(page, params: { "entity" => { "title" => "Hello", "note" => "typed" } })

    expect(result.status).to eq(:failed)
    expect(result.field_errors).to eq("title" => ["Pick another title"])
    expect(result.message).to be_nil
    expect(result.values).to eq("title" => "Hello", "note" => "typed")
    expect(EntityEntry.where(entity_id: entity.id)).to be_empty
  end

  it "fails with a message when the error is not on a field the page shows" do
    bind_page_flowchart(page, body: <<~RUBY)
      return FlowchartRuntime::Step.fail_message(ctx, { "en" => "We're closed" })
    RUBY

    result = submit(page)

    expect(result.status).to eq(:failed)
    expect(result.field_errors).to eq({})
    expect(result.message).to eq("We're closed")
  end

  it "succeeds with the saved entry and the flowchart's outcome" do
    bind_page_flowchart(page, body: <<~RUBY)
      ctx[:model].data_json = ctx[:params]
      ctx[:model].save!
      ctx[:submission_outcome] = { "preset" => "saved" }
      true
    RUBY

    result = submit(page)

    expect(result.status).to eq(:success)
    expect(result).to be_success
    expect(result.entry).to be_a(EntityEntry)
    expect(result.entry).to be_persisted
    expect(result.entry.data_json["title"]).to eq("Hello")
    expect(result.outcome).to include("preset" => "saved")
    expect(result.handed_off).to be(false)
  end
end
