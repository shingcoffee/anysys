# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::Submission::Input do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Title", "name_slug" => "title", "html_type" => "text" },
      { "name" => "Pin", "name_slug" => "pin", "html_type" => "password" },
      { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "html_type" => "select",
        "entity_id" => student_entity.id }
    ].to_json)
  end
  let(:student_entity) do
    create(:entity, customer: customer, name: "Student",
           property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
  end
  let(:page) do
    Current.set(customer: customer) do
      create(:page, :for_public, customer: customer, entity: entity, launched: true,
                    configuration: {
                      form_settings: { modes: ["create"], inputs: [{ field: "student", entity_id: student_entity.id }] },
                      metadata: { entity_id: entity.id, entity_name: entity.name },
                      pages: [{ "id" => "p1", "fields" => [
                        { "id" => "f_title", "property_slug" => "title", "source" => "entity", "html_type" => "text" },
                        { "id" => "f_pin", "property_slug" => "pin", "source" => "entity", "html_type" => "password" },
                        { "id" => "f_student", "property_slug" => "student", "source" => "entity", "html_type" => "select" }
                      ] }]
                    }.to_json)
    end
  end

  def permit(params:, bindings: {}, audience: EntityAttributeAudience::PUBLIC, viewer: nil)
    described_class.permit(page: page, entity: page.entity, params: params.with_indifferent_access,
                           bindings: bindings, audience: audience, viewer: viewer, customer_id: customer.id)
  end

  it "keeps locked input bindings over a forged posted value" do
    own = create(:entity_entry, :with_data, customer: customer, entity: student_entity, entry_data: { "name" => "Ada" })
    other = create(:entity_entry, :with_data, customer: customer, entity: student_entity, entry_data: { "name" => "Bob" })

    input = permit(params: { "entity" => { "title" => "Essay", "student" => other.id.to_s } },
                   bindings: { "student" => own.id.to_s },
                   audience: EntityAttributeAudience::ADMIN,
                   viewer: create(:user, :admin, customer: customer))

    expect(input).not_to be_rejected
    expect(input.values["student"]).to eq(own.id.to_s)
    expect(input.values["title"]).to eq("Essay")
  end

  context "when the locked input names a record only its owner reaches" do
    let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
    let(:member) { create(:user, :member, customer: customer) }
    let(:learner) do
      create(:entity, customer: customer, name: "Learner", extended_model: person_model,
                      property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    end
    let(:cart_entity) do
      create(:entity, customer: customer, name: "Cart", property_schema: [
        { "name" => "Learner", "name_slug" => "learner", "html_type" => "select", "type" => "EntityReference",
          "entity_id" => learner.id.to_s }
      ].to_json)
    end
    let(:item_entity) do
      create(:entity, customer: customer, name: "Item", property_schema: [
        { "name" => "Cart", "name_slug" => "cart", "html_type" => "select", "type" => "EntityReference",
          "entity_id" => cart_entity.id.to_s },
        { "name" => "Quantity", "name_slug" => "quantity", "html_type" => "number" }
      ].to_json)
    end
    let(:item_page) do
      Current.set(customer: customer) do
        create(:page, :member_only, customer: customer, entity: item_entity, launched: true,
                                    configuration: {
                                      form_settings: { modes: %w[create update], inputs: [{ field: "cart", entity_id: cart_entity.id }] },
                                      pages: [{ "id" => "p1", "fields" => [
                                        { "id" => "f_cart", "property_slug" => "cart", "source" => "entity", "html_type" => "select" },
                                        { "id" => "f_qty", "property_slug" => "quantity", "source" => "entity", "html_type" => "number" }
                                      ] }]
                                    }.to_json)
      end
    end

    before { enable_module!("authentication", customer).set_extendable_model!(person_model, true) }

    def cart_of(user)
      person = create(:entity_entry, customer: customer, entity: learner, user: user)
      create(:entity_entry, :with_data, customer: customer, entity: cart_entity, entry_data: { "learner" => person.id.to_s })
    end

    def permit_item(posted, bindings:)
      described_class.permit(page: item_page, entity: item_entity, params: { "entity" => posted }.with_indifferent_access,
                             bindings: bindings, audience: EntityAttributeAudience::MEMBER, viewer: member,
                             customer_id: customer.id)
    end

    it "ignores a posted record the member cannot reach, keeping the binding" do
      own = cart_of(member)
      peer = cart_of(create(:user, :member, customer: customer))

      input = permit_item({ "cart" => peer.id.to_s, "quantity" => "4" }, bindings: { "cart" => own.id.to_s })

      expect(input).not_to be_rejected
      expect(input.values).to eq("cart" => own.id.to_s, "quantity" => "4")
    end

    it "checks a value posted for an unbound locked input, whose field the form shows" do
      own = cart_of(member)
      peer = cart_of(create(:user, :member, customer: customer))

      expect(permit_item({ "cart" => own.id.to_s }, bindings: {}).values).to eq("cart" => own.id.to_s)
      expect(permit_item({ "cart" => peer.id.to_s }, bindings: {}).error).to eq("Cart: you can't choose this record.")
    end
  end

  it "rejects a public submit on an owned entity" do
    person_model = EntityDefinitions::Capabilities::PERSON_MODEL
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    learner = create(:entity, customer: customer, name: "Learner", extended_model: person_model,
                     property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    owned = create(:entity, customer: customer, name: "Homework", property_schema: [
      { "name" => "Title", "name_slug" => "title", "html_type" => "text" },
      { "name" => "Student", "name_slug" => "student", "html_type" => "select", "owner" => true,
        "config" => { "options_source" => "entity_entries", "entity_id" => learner.id.to_s, "label_field" => "name" } }
    ].to_json)
    owned_page = Current.set(customer: customer) do
      create(:page, :for_member, :for_public, customer: customer, entity: owned, launched: true,
                    configuration: {
                      form_settings: { modes: ["create"] },
                      metadata: { entity_id: owned.id },
                      pages: [{ "id" => "p1", "fields" => [
                        { "id" => "title", "property_slug" => "title", "html_type" => "text" }
                      ] }]
                    }.to_json)
    end

    input = described_class.permit(page: owned_page, entity: owned,
                                   params: { "entity" => { "title" => "Essay" } }.with_indifferent_access,
                                   bindings: {}, audience: EntityAttributeAudience::PUBLIC, viewer: nil,
                                   customer_id: customer.id)

    expect(input).to be_rejected
    expect(input.error).to eq(I18n.t("common.errors.dynamic.sign_in_required"))
  end

  describe "a new record's starting values" do
    let(:entity) do
      create(:entity, customer: customer, property_schema: [
        { "name" => "Title", "name_slug" => "title", "html_type" => "text" },
        { "name" => "Status", "name_slug" => "status", "html_type" => "select",
          "editable" => { "admin" => true, "member" => true, "public" => false },
          "config" => { "options" => [{ "label" => "Open", "value" => "Open", "default" => true }] } },
        { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "html_type" => "select",
          "entity_id" => student_entity.id }
      ].to_json, default_properties: { "title" => "Untitled", "student" => "1" }.to_json)
    end

    it "starts what the visitor cannot set at its default on create, under typed values and bindings" do
      student = create(:entity_entry, customer: customer, entity: student_entity)
      input = described_class.permit(page: page, entity: page.entity, params: { "entity" => { "title" => "Essay" } }.with_indifferent_access,
                                     bindings: { "student" => student.id.to_s }, audience: EntityAttributeAudience::PUBLIC,
                                     viewer: nil, customer_id: customer.id, create: true)

      expect(input.values).to eq("status" => "Open", "title" => "Essay", "student" => student.id.to_s)
      expect(input.retry_values).to eq("title" => "Essay")
    end

    it "starts nothing on update" do
      expect(permit(params: { "entity" => { "title" => "Essay" } }).values).to eq("title" => "Essay")
    end
  end

  it "omits passwords from retry_values" do
    input = permit(params: { "entity" => { "title" => "Hello", "pin" => "1234" } })

    expect(input.retry_values).to eq("title" => "Hello")
    expect(input.retry_values).not_to have_key("pin")
  end
end
