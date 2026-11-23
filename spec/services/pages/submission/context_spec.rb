# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::Submission::Context do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Title", "name_slug" => "title", "html_type" => "text" }
    ].to_json)
  end
  let(:page) do
    Current.set(customer: customer) do
      create(:page, :for_public, customer: customer, entity: entity, launched: true,
                    configuration: {
                      form_settings: { modes: %w[create update] },
                      metadata: { entity_id: entity.id, entity_name: entity.name },
                      pages: [{ "id" => "p1", "fields" => [
                        { "id" => "f_title", "property_slug" => "title", "source" => "entity", "html_type" => "text" }
                      ] }]
                    }.to_json)
    end
  end

  def build_context(viewer: nil, entry_id: nil, params: { "entity" => { "title" => "Hello" } })
    params = params.with_indifferent_access
    audience = EntityAttributeAudience.for_user(viewer, customer_id: customer.id)
    target = Pages::Submission::Target.resolve(
      page: page, entity: page.entity, entry_id: entry_id, audience: audience,
      viewer: viewer, customer_id: customer.id
    )
    input = Pages::Submission::Input.permit(
      page: page, entity: page.entity, params: params, bindings: {},
      audience: audience, viewer: viewer, customer_id: customer.id
    )
    described_class.new(
      page: page, target: target, input: input, audience: audience, viewer: viewer,
      authentication: :auth, continuation: { "action_key" => "enroll" },
      journey: { "key" => "join", "step" => "start" },
      request: { request_ip: "127.0.0.1", user_agent: "RSpec", locale: "en",
                 request_id: "spec", device_type: "desktop" }
    )
  end

  it "seeds the flowchart ctx with the page record, bound entity and permitted params" do
    ctx = build_context.to_ctx

    expect(ctx[:model]).to be_a(EntityEntry)
    expect(ctx[:page_record]).to eq(ctx[:model])
    expect(ctx[:bound_entity]).to eq(entity)
    expect(ctx[:customer_id]).to eq(customer.id)
    expect(ctx[:mode]).to eq("create")
    expect(ctx[:params]).to include("title" => "Hello")
    expect(ctx[:params]).not_to have_key("id")
    expect(ctx[:writable_slugs]).to include("title")
    expect(ctx[:source]).to include("surface" => "page", "page_id" => page.id)
    expect(ctx[:journey]).to eq("key" => "join", "step" => "start")
    expect(ctx[:authentication]).to eq(:auth)
    expect(ctx[:current_person_ids]).to eq({})
  end

  it "adds the persisted record id on update" do
    admin = create(:user, :admin, customer: customer)
    page.update!(audience_admin: true)
    entry = EntityEntry.build_for(entity).create!(entity: entity, customer_id: customer.id, data: { "title" => "A" }.to_json)

    ctx = build_context(viewer: admin, entry_id: entry.id.to_s).to_ctx

    expect(ctx[:mode]).to eq("update")
    expect(ctx[:params]).to include("id" => entry.id.to_s, "title" => "Hello")
    expect(ctx[:model].id).to eq(entry.id)
    expect(ctx[:page_record].id).to eq(entry.id)
  end

  it "does not put another tenant's person records into current_person_ids" do
    person_model = EntityDefinitions::Capabilities::PERSON_MODEL
    enable_module!("authentication", other).set_extendable_model!(person_model, true)
    foreign_student = create(:entity, customer: other, name: "Student", extended_model: person_model)
    stranger = create(:user, :member, customer: other)
    create(:entity_entry, entity: foreign_student, customer: other, user: stranger)

    ctx = build_context(viewer: stranger).to_ctx

    expect(ctx[:audience]).to eq(EntityAttributeAudience::PUBLIC)
    expect(ctx[:current_user_id]).to eq(stranger.id)
    expect(ctx[:current_person_ids]).to eq({})
  end

  it "includes the same-tenant member's person ids" do
    person_model = EntityDefinitions::Capabilities::PERSON_MODEL
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    student = create(:entity, customer: customer, name: "Student", extended_model: person_model)
    member = create(:user, :member, customer: customer)
    own = create(:entity_entry, entity: student, customer: customer, user: member)
    page.update!(audience_member: true)

    ctx = build_context(viewer: member).to_ctx

    expect(ctx[:audience]).to eq(EntityAttributeAudience::MEMBER)
    expect(ctx[:current_person_ids]).to eq(student.id.to_s => own.id)
  end
end
