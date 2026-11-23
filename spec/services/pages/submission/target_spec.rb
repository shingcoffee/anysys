# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::Submission::Target do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Title", "name_slug" => "title", "html_type" => "text" }
    ].to_json)
  end

  def launched_page(form_settings:, traits: %i[for_public], bound: entity)
    Current.set(customer: customer) do
      create(:page, *traits, customer: customer, entity: bound, launched: true,
                    configuration: {
                      form_settings: form_settings,
                      metadata: { entity_id: bound.id, entity_name: bound.name },
                      pages: [{ "id" => "p1", "fields" => [
                        { "id" => "f_title", "property_slug" => "title", "source" => "entity", "html_type" => "text" }
                      ] }]
                    }.to_json)
    end
  end

  def resolve(page, entry_id:, audience:, viewer:)
    described_class.resolve(page: page, entity: page.entity, entry_id: entry_id, audience: audience,
                            viewer: viewer, customer_id: customer.id)
  end

  it "creates a new record of this tenant's entity" do
    page = launched_page(form_settings: { "modes" => ["create"] })

    target = resolve(page, entry_id: nil, audience: EntityAttributeAudience::PUBLIC, viewer: nil)

    expect(target).to be_a(described_class)
    expect(target).to be_create
    expect(target.record).to be_a(EntityEntry)
    expect(target.record).not_to be_persisted
    expect(target.record.customer_id).to eq(customer.id)
    expect(target.record.entity_id).to eq(entity.id)
  end

  it "loads an admin-edited entry of this tenant and entity" do
    admin = create(:user, :admin, customer: customer)
    page = launched_page(form_settings: { "modes" => %w[create update] })
    page.update!(audience_admin: true)
    entry = EntityEntry.build_for(entity).create!(entity: entity, customer_id: customer.id, data: { "title" => "A" }.to_json)

    target = resolve(page, entry_id: entry.id.to_s, audience: EntityAttributeAudience::ADMIN, viewer: admin)

    expect(target.mode).to eq(:update)
    expect(target.record.id).to eq(entry.id)
    expect(target.record.customer_id).to eq(customer.id)
  end

  it "refuses another customer's entry_id" do
    admin = create(:user, :admin, customer: customer)
    page = launched_page(form_settings: { "modes" => ["update"] })
    page.update!(audience_admin: true)
    foreign_entity = create(:entity, customer: other)
    foreign = EntityEntry.build_for(foreign_entity).create!(entity: foreign_entity, customer_id: other.id)

    result = resolve(page, entry_id: foreign.id.to_s, audience: EntityAttributeAudience::ADMIN, viewer: admin)

    expect(result).to be_a(described_class::Refusal)
    expect(result.http_status).to eq(:not_found)
    expect(result.message_key).to eq("common.errors.dynamic.entry_unavailable")
  end

  it "refuses a member update that is not their own person record" do
    person_model = EntityDefinitions::Capabilities::PERSON_MODEL
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    student = create(:entity, customer: customer, name: "Student", extended_model: person_model,
                     property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    member = create(:user, :member, customer: customer)
    other_member = create(:user, :member, customer: customer)
    create(:entity_entry, entity: student, customer: customer, user: other_member)
    page = launched_page(form_settings: { "modes" => ["update"] }, traits: %i[for_member], bound: student)

    result = resolve(page, entry_id: nil, audience: EntityAttributeAudience::MEMBER, viewer: member)

    expect(result).to be_a(described_class::Refusal)
    expect(result.http_status).to eq(:method_not_allowed)
    expect(result.message_key).to eq("common.errors.dynamic.page_not_executable")
  end

  it "updates the signed-in member's own person record on an update-only page" do
    person_model = EntityDefinitions::Capabilities::PERSON_MODEL
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    student = create(:entity, customer: customer, name: "Student", extended_model: person_model,
                     property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    member = create(:user, :member, customer: customer)
    own = create(:entity_entry, entity: student, customer: customer, user: member)
    page = launched_page(form_settings: { "modes" => ["update"] }, traits: %i[for_member], bound: student)

    target = resolve(page, entry_id: nil, audience: EntityAttributeAudience::MEMBER, viewer: member)

    expect(target.mode).to eq(:update)
    expect(target.record.id).to eq(own.id)
    expect(target.record.user_id).to eq(member.id)
  end

  describe "a row a member manages from their own record" do
    let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
    let(:member) { create(:user, :member, customer: customer) }
    let(:student) do
      create(:entity, customer: customer, name: "Student", extended_model: person_model,
                      property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    end
    let(:cart) do
      create(:entity, customer: customer, name: "Cart", property_schema: [
        { "name" => "Student", "name_slug" => "student", "html_type" => "select", "type" => "EntityReference", "entity_id" => student.id.to_s }
      ].to_json)
    end
    let(:item) do
      create(:entity, customer: customer, name: "Item", property_schema: [
        { "name" => "Cart", "name_slug" => "cart", "html_type" => "select", "type" => "EntityReference", "entity_id" => cart.id.to_s },
        { "name" => "Title", "name_slug" => "title", "html_type" => "text" }
      ].to_json)
    end

    before { enable_module!("authentication", customer).set_extendable_model!(person_model, true) }

    def item_of(user)
      person = create(:entity_entry, entity: student, customer: customer, user: user)
      basket = create(:entity_entry, :with_data, entity: cart, customer: customer, entry_data: { "student" => person.id.to_s })
      create(:entity_entry, :with_data, entity: item, customer: customer, entry_data: { "cart" => basket.id.to_s })
    end

    def item_page(manage_rows:)
      launched_page(form_settings: { "modes" => %w[create update], "manage_rows" => manage_rows,
                                     "inputs" => [{ "field" => "cart", "entity_id" => cart.id.to_s }] },
                    traits: %i[member_only], bound: item)
    end

    def resolve_item(page, entry)
      resolve(page, entry_id: entry.id.to_s, audience: EntityAttributeAudience::MEMBER, viewer: member)
    end

    it "updates the member's own row on a page managing such rows" do
      own = item_of(member)

      target = resolve_item(item_page(manage_rows: true), own)

      expect(target.mode).to eq(:update)
      expect(target.record.id).to eq(own.id)
    end

    it "refuses another member's row, and any row on a page that does not manage them" do
      peer = item_of(create(:user, :member, customer: customer))

      expect(resolve_item(item_page(manage_rows: true), peer)).to be_a(described_class::Refusal)
      expect(resolve_item(item_page(manage_rows: false), item_of(member))).to have_attributes(http_status: :not_found)
    end
  end

  describe "the record a member's journey run is editing" do
    let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
    let(:member) { create(:user, :member, customer: customer) }
    let(:student) do
      create(:entity, customer: customer, name: "Student", extended_model: person_model,
                      property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    end
    let(:application) do
      create(:entity, customer: customer, name: "Application", property_schema: [
        { "name" => "Student", "name_slug" => "student", "html_type" => "select", "type" => "EntityReference", "entity_id" => student.id.to_s },
        { "name" => "Title", "name_slug" => "title", "html_type" => "text" }
      ].to_json)
    end
    let(:page) { launched_page(form_settings: { "modes" => ["update"] }, traits: %i[member_only], bound: application) }

    before { enable_module!("authentication", customer).set_extendable_model!(person_model, true) }

    def application_of(user, entry_customer: customer)
      person = (@people ||= {})[user.id] ||= create(:entity_entry, entity: student, customer: customer, user: user)
      create(:entity_entry, :with_data, entity: application, customer: entry_customer, entry_data: { "student" => person.id.to_s })
    end

    def resolve_for(entry, journey_record_id:)
      described_class.resolve(page: page, entity: application, entry_id: entry.id.to_s, audience: EntityAttributeAudience::MEMBER,
                              viewer: member, customer_id: customer.id, journey_record_id: journey_record_id)
    end

    it "updates it while the run's update step names it and the member reaches it" do
      own = application_of(member)

      target = resolve_for(own, journey_record_id: own.id.to_s)

      expect(target.mode).to eq(:update)
      expect(target.record.id).to eq(own.id)
    end

    it "refuses it without the run, and a record other than the one the run names" do
      own = application_of(member)
      second = application_of(member)

      expect(resolve_for(own, journey_record_id: nil)).to have_attributes(http_status: :not_found)
      expect(resolve_for(own, journey_record_id: "")).to have_attributes(http_status: :not_found)
      expect(resolve_for(second, journey_record_id: own.id.to_s)).to have_attributes(http_status: :not_found)
    end

    it "refuses another member's record and another tenant's, even when the run names it" do
      peer = application_of(create(:user, :member, customer: customer))
      foreign = application_of(member, entry_customer: other)

      expect(resolve_for(peer, journey_record_id: peer.id.to_s)).to have_attributes(http_status: :not_found)
      expect(resolve_for(foreign, journey_record_id: foreign.id.to_s)).to have_attributes(http_status: :not_found)
    end

    it "is only a member allowance" do
      own = application_of(member)

      result = described_class.resolve(page: page, entity: application, entry_id: own.id.to_s, audience: EntityAttributeAudience::PUBLIC,
                                       viewer: nil, customer_id: customer.id, journey_record_id: own.id.to_s)
      expect(result).to have_attributes(http_status: :not_found)
    end
  end
end
