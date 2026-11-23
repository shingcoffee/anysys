# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::FormParams do
  let_it_be(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name_slug" => "name" },
      { "name_slug" => "email" }
    ].to_json)
  end
  let(:page) do
    Current.set(customer: customer) do
      create(:page, :for_member, :for_public,
             customer: customer,
             entity: entity,
             launched: true,
             configuration: {
               metadata: { entity_id: entity.id, entity_name: entity.name },
               fields: []
             }.to_json)
    end
  end

  def params_hash(attrs)
    ActionController::Parameters.new(attrs)
  end

  describe ".permit" do
    it "returns empty hash when entity is nil" do
      expect(described_class.permit(page: page, entity: nil, params: params_hash(name: "A"))).to eq({})
    end

    it "allowlists schema field slugs and drops unknown keys" do
      result = described_class.permit(
        page: page,
        entity: entity,
        params: params_hash(name: "Alice", email: "a@example.com", secret_admin_flag: "1")
      )

      expect(result).to include("name" => "Alice", "email" => "a@example.com")
      expect(result).not_to have_key("secret_admin_flag")
    end

    it "unwraps nested entity[...] params from page forms" do
      result = described_class.permit(
        page: page,
        entity: entity,
        params: params_hash(
          entity: { name: "Alice", email: "a@example.com", secret_admin_flag: "1" },
          _page_id: "7"
        )
      )

      expect(result).to include("name" => "Alice", "email" => "a@example.com")
      expect(result).not_to have_key("secret_admin_flag")
      expect(result).not_to have_key("entity")
    end

    it "applies RulesEngine hidden-field filtering and calculations" do
      engine = instance_double(
        Pages::RulesEngine,
        apply: { "name" => "Alice", "total" => "10" }
      )
      allow(Pages::RulesEngine).to receive(:new).with(page).and_return(engine)

      result = described_class.permit(
        page: page,
        entity: entity,
        params: params_hash(name: "Alice", email: "a@example.com")
      )

      expect(Pages::RulesEngine).to have_received(:new).with(page)
      # Calculations cannot add a target outside the writable entity schema.
      expect(result).to eq("name" => "Alice")
    end
  end

  describe ".permit audience visibility" do
    let(:entity) do
      create(:entity, customer: customer, property_schema: [
        { "name_slug" => "name" },
        { "name_slug" => "internal_note",
          "visibility" => { "admin" => true, "member" => false, "public" => false } }
      ].to_json)
    end

    def permit_as(audience)
      described_class.permit(
        page: page,
        entity: entity,
        params: params_hash(name: "Alice", internal_note: "leaked"),
        audience: audience
      )
    end

    it "drops attributes hidden from the submitting audience" do
      expect(permit_as("public")).to eq("name" => "Alice")
      expect(permit_as("member")).to eq("name" => "Alice")
    end

    it "keeps attributes visible to the submitting audience" do
      expect(permit_as("admin")).to include("internal_note" => "leaked")
    end

    it "allows the whole schema for an unscoped run" do
      expect(permit_as(nil)).to include("internal_note" => "leaked")
    end
  end

  describe "fields an audience sees but cannot edit" do
    let(:entity) do
      create(:entity, customer: customer, property_schema: [
        { "name_slug" => "name" },
        { "name_slug" => "status", "validators" => [{ "type" => "presence" }],
          "editable" => { "admin" => true, "member" => false, "public" => false } }
      ].to_json)
    end

    def boundary(audience) = described_class.new(page: page, entity: entity, params: params_hash(name: "Alice", status: "Shipped"), audience: audience)

    it "ignores the posted value from that audience" do
      expect(boundary("member").permit).to eq("name" => "Alice")
      expect(boundary("admin").permit).to include("status" => "Shipped")
    end

    it "keeps the field visible but neither editable nor required for that audience" do
      field = { "property_slug" => "status" }

      expect(boundary("member").visible_field?(field)).to be true
      expect(boundary("member").editable_field?(field)).to be false
      expect(boundary("member").required_field?(field)).to be false
      expect(boundary("admin").editable_field?(field)).to be true
      expect(boundary("admin").required_field?(field)).to be true
    end
  end

  describe "#starting_values" do
    let(:entity) do
      member_locked = { "admin" => true, "member" => false, "public" => false }
      create(:entity, customer: customer, default_properties: { "source" => "web", "name" => "Anon", "total" => "9" }.to_json,
                      property_schema: [
                        { "name_slug" => "name" },
                        { "name_slug" => "status", "html_type" => "select", "editable" => member_locked,
                          "config" => { "options" => [{ "label" => "Open", "value" => "Open", "default" => true },
                                                      { "label" => "Closed", "value" => "Closed", "default" => false }] } },
                        { "name_slug" => "tags", "html_type" => "multi-select", "visibility" => member_locked,
                          "config" => { "options" => [{ "value" => "a", "default" => true }, { "value" => "b", "default" => true },
                                                      { "value" => "c" }] } },
                        { "name_slug" => "priority", "html_type" => "radio", "editable" => member_locked,
                          "config" => { "options" => [{ "value" => "x", "default" => true }, { "value" => "y", "default" => true }] } },
                        { "name_slug" => "source", "editable" => member_locked },
                        { "name_slug" => "total", "type" => "Calculated" }
                      ].to_json)
    end

    def starting(audience, on: page) = described_class.new(page: on, entity: entity, params: {}, audience: audience).starting_values

    it "starts the attributes that audience cannot set at the definition's defaults" do
      expect(starting("member")).to eq("status" => "Open", "tags" => %w[a b], "source" => "web")
    end

    it "leaves the attributes the page offers that audience to the form" do
      expect(starting("admin")).to eq({})
    end

    it "starts the attributes the page leaves off at their defaults too" do
      name_only = Current.set(customer: customer) do
        create(:page, :for_member, customer: customer, entity: entity, launched: true,
                                   configuration: { pages: [{ "id" => "p1", "fields" => [
                                     { "id" => "f_name", "property_slug" => "name", "source" => "entity" }
                                   ] }] }.to_json)
      end

      expect(starting("admin", on: name_only)).to eq("status" => "Open", "tags" => %w[a b], "source" => "web")
    end

    it "never starts the owner reference, which the server fills" do
      person_model = EntityDefinitions::Capabilities::PERSON_MODEL
      enable_module!("authentication", customer).set_extendable_model!(person_model, true)
      student = create(:entity, customer: customer, name: "Student", extended_model: person_model,
                                property_schema: [{ "name" => "Name", "name_slug" => "name" }].to_json)
      owned = create(:entity, customer: customer, default_properties: { "student" => "1" }.to_json, property_schema: [
        { "name" => "Student", "name_slug" => "student", "html_type" => "select", "owner" => true,
          "config" => { "options_source" => "entity_entries", "entity_id" => student.id.to_s, "label_field" => "name" } }
      ].to_json)

      expect(described_class.new(page: page, entity: owned, params: {}, audience: "member").starting_values).to eq({})
    end
  end

  describe "#required_field?" do
    it "follows a presence validator only for audiences it applies to" do
      record = create(:entity, customer: customer, property_schema: [
        { "name_slug" => "course_code", "validators" => [{ "type" => "presence" }],
          "validator_apply" => { "admin" => true, "member" => false, "public" => false } },
        { "name_slug" => "notes", "validators" => [{ "type" => "length_maximum", "config" => { "value" => 20 } }] },
        { "name_slug" => "total", "type" => "Calculated", "validators" => [{ "type" => "presence" }] }
      ].to_json)
      admin_boundary = described_class.new(page: page, entity: record, params: {}, audience: "admin")
      public_boundary = described_class.new(page: page, entity: record, params: {}, audience: "public")

      expect(admin_boundary.required_field?("property_slug" => "course_code")).to be true
      expect(public_boundary.required_field?("property_slug" => "course_code")).to be false
      expect(admin_boundary.required_field?("property_slug" => "notes")).to be false
      expect(admin_boundary.required_field?("property_slug" => "total")).to be false
      expect(admin_boundary.required_field?("property_slug" => "missing")).to be false
    end

    it "reads presence from the bridge entity named by the field" do
      bridge = create(:entity, customer: customer, name: "enrollment", property_schema: [
        { "name_slug" => "student", "validators" => [{ "type" => "presence" }] }
      ].to_json)
      record = create(:entity, customer: customer)
      allow(record).to receive(:associations_json).and_return([{ "bridge_entity_id" => bridge.id }])
      boundary = described_class.new(page: page, entity: record, params: {}, audience: "admin")
      field = { "property_slug" => "student", "source" => "bridge", "source_section" => bridge.name }

      expect(boundary.required_field?(field)).to be true
    end

    it "skips the owner reference for members because the server fills it" do
      person_model = EntityDefinitions::Capabilities::PERSON_MODEL
      enable_module!("authentication", customer).set_extendable_model!(person_model, true)
      student = create(:entity, customer: customer, name: "Student", extended_model: person_model,
                       property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
      owned = create(:entity, customer: customer, property_schema: [
        { "name" => "Student", "name_slug" => "student", "html_type" => "select",
          "owner" => true, "validators" => [{ "type" => "presence" }],
          "config" => { "options_source" => "entity_entries", "entity_id" => student.id.to_s,
                        "label_field" => "name" } },
        { "name" => "Title", "name_slug" => "title", "validators" => [{ "type" => "presence" }] }
      ].to_json)
      field = { "property_slug" => "student" }
      title = { "property_slug" => "title" }

      member_boundary = described_class.new(page: page, entity: owned, params: {}, audience: "member")
      admin_boundary = described_class.new(page: page, entity: owned, params: {}, audience: "admin")

      expect(member_boundary.required_field?(field)).to be false
      expect(member_boundary.required_field?(title)).to be true
      expect(admin_boundary.required_field?(field)).to be true
    end
  end

  describe "#visible_field?" do
    it "hides the owner reference from members and keeps it for admins" do
      person_model = EntityDefinitions::Capabilities::PERSON_MODEL
      enable_module!("authentication", customer).set_extendable_model!(person_model, true)
      student = create(:entity, customer: customer, name: "Student", extended_model: person_model,
                       property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
      owned = create(:entity, customer: customer, property_schema: [
        { "name" => "Student", "name_slug" => "student", "html_type" => "select",
          "owner" => true,
          "config" => { "options_source" => "entity_entries", "entity_id" => student.id.to_s,
                        "label_field" => "name" } },
        { "name" => "Title", "name_slug" => "title" }
      ].to_json)
      field = { "id" => "student", "property_slug" => "student" }
      title = { "id" => "title", "property_slug" => "title" }
      owned_page = Current.set(customer: customer) do
        create(:page, :for_member, customer: customer, entity: owned, launched: true)
      end

      expect(described_class.visible_field?(page: owned_page, field: field, audience: "member")).to be false
      expect(described_class.visible_field?(page: owned_page, field: title, audience: "member")).to be true
      expect(described_class.visible_field?(page: owned_page, field: field, audience: "admin")).to be true
    end
  end

  describe "identity fields" do
    let(:identity_payload) do
      {
        first_name: "Ada",
        last_name: "Lovelace",
        email: "ada@example.com",
        password: "secret"
      }
    end

    def identity_field(key)
      html = key == "email" ? "email" : "text"
      { "id" => "id_#{key}", "field_type" => html, "html_type" => html,
        "property_slug" => key, "source" => "identity", "label" => key.humanize }
    end

    let(:person_entity) do
      person_model = EntityDefinitions::Capabilities::PERSON_MODEL
      enable_module!("authentication", customer).set_extendable_model!(person_model, true)
      create(:entity, customer: customer, extended_model: person_model,
             property_schema: [{ "name_slug" => "name" }].to_json)
    end

    def person_page(keys = People::IDENTITY_KEYS)
      Current.set(customer: customer) do
        create(:page, :for_public, customer: customer, entity: person_entity, launched: true,
               configuration: { metadata: { entity_id: person_entity.id, entity_name: person_entity.name },
                                pages: [{ "id" => "p1", "fields" => keys.map { |key| identity_field(key) } }] }.to_json)
      end
    end

    def permit_identity_as(audience, attrs = identity_payload, on: person_page)
      described_class.permit_identity(
        page: on,
        entity: on.entity,
        params: params_hash(entity: { name: "Ada", email: "forged@example.com" }, identity: attrs),
        audience: audience
      )
    end

    it "permits only the identity keys the page places" do
      expect(permit_identity_as("public", identity_payload, on: person_page(%w[email])))
        .to eq("email" => "ada@example.com")
      expect(permit_identity_as("public", identity_payload, on: person_page([]))).to eq({})
    end

    it "accepts no identity on a page whose entity is not a person entity" do
      expect(permit_identity_as("public", identity_payload, on: page)).to eq({})
    end

    it "recognizes a page field whose source is identity and whose key is reserved" do
      expect(described_class.identity_field?(identity_field("email"))).to be true
      expect(described_class.identity_field?(identity_field("first_name"))).to be true
      expect(described_class.identity_field?("property_slug" => "email", "source" => "entity")).to be false
      expect(described_class.identity_field?(identity_field("password"))).to be false
    end

    it "permits the three identity keys as scalar strings for public and admin" do
      expected = { "first_name" => "Ada", "last_name" => "Lovelace", "email" => "ada@example.com" }

      expect(permit_identity_as("public")).to eq(expected)
      expect(permit_identity_as("admin")).to eq(expected)
    end

    it "drops identity entirely for the member audience" do
      expect(permit_identity_as("member")).to eq({})
    end

    it "drops unknown identity keys and non-string values" do
      result = permit_identity_as("public", {
        email: "ada@example.com",
        password: "secret",
        first_name: { value: "Ada" },
        last_name: ["Lovelace"]
      })

      expect(result).to eq("email" => "ada@example.com")
      expect(result).not_to have_key("password")
    end

    it "never mixes identity into the entity input" do
      params = params_hash(
        entity: { name: "Ada", email: "forged@example.com" },
        identity: identity_payload
      )

      expect(described_class.permit(page: page, entity: entity, params: params, audience: "public"))
        .to eq("name" => "Ada", "email" => "forged@example.com")
      expect(described_class.permit_parts(page: page, entity: entity, params: params, audience: "public"))
        .to eq([{ "name" => "Ada", "email" => "forged@example.com" }, {}])
    end

    it "shows identity fields to public and admin and hides them from members" do
      field = identity_field("email")

      expect(described_class.visible_field?(page: page, field: field, audience: "public")).to be true
      expect(described_class.visible_field?(page: page, field: field, audience: "admin")).to be true
      expect(described_class.visible_field?(page: page, field: field, audience: "member")).to be false
    end
  end

  describe "file fields" do
    let(:entity) do
      create(:entity, customer: customer, property_schema: [
        { "name_slug" => "name" },
        { "name_slug" => "contract", "html_type" => "file" },
        { "name_slug" => "scans", "html_type" => "file", "config" => { "multiple" => true } }
      ].to_json)
    end
    let(:upload) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/note.txt"), "text/plain") }
    let(:other) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test.png"), "image/png") }

    def permit(attrs) = described_class.permit(page: page, entity: entity, params: params_hash(attrs))

    it "keeps only uploaded files, never a string Active Storage would read as a stored blob's signed id" do
      expect(permit(contract: "eyJfcmFpbHMiOnsiZGF0YSI6MX19--abc", scans: ["signed-id", ""])).not_to include("contract", "scans")
      expect(permit(contract: "")).not_to have_key("contract")
      expect(permit(contract: upload)["contract"]).to eq(upload)
    end

    it "shapes the files by the attribute: one for a single-file field, all for a multiple one" do
      result = permit(contract: [upload, other], scans: [upload, "", other])

      expect(result["contract"]).to eq(other)
      expect(result["scans"]).to eq([upload, other])
      expect(permit(scans: upload)["scans"]).to eq([upload])
    end

    it "answers the File or Image attribute a field is bound to" do
      boundary = described_class.new(page: page, entity: entity, params: {}, audience: "admin")

      expect(boundary.file_attribute({ "property_slug" => "contract", "source" => "entity" })).to include("name_slug" => "contract")
      expect(boundary.file_attribute({ "property_slug" => "name", "source" => "entity" })).to be_nil
    end
  end
end
